import AppKit
import Observation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: TextKey {
        switch self {
        case .system: .systemTheme
        case .light: .lightTheme
        case .dark: .darkTheme
        }
    }

    @MainActor var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor @Observable
final class AppModel {
    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    private(set) var capacity: DiskCapacity?
    private(set) var results: ScanResult?
    private(set) var scanID: UUID?
    private(set) var progress: ScanProgress?
    private(set) var isCancelling = false
    private(set) var wasCancelled = false
    private(set) var isMoving = false
    private(set) var removedPaths: Set<String> = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    var isScanning: Bool { scanID != nil }

    init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? .initial
        theme = defaults.string(forKey: "theme").flatMap(AppTheme.init(rawValue:)) ?? .system
        refreshCapacity()
    }

    func applyTheme() {
        NSApp?.appearance = theme.appearance
    }

    func refreshCapacity() {
        capacity = DiskCapacity.readStartup()
    }

    func startScan() {
        guard !isScanning, !isMoving else { return }
        refreshCapacity()
        let id = UUID()
        scanID = id
        progress = nil
        wasCancelled = false
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            let result = try? DiskScanner().scan(
                roots: ScanRoot.startup(), isCancelled: { Task.isCancelled },
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in self?.record(progress, for: id) }
                }
            )
            await self?.finishScan(id, result: result, cancelled: Task.isCancelled)
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        isCancelling = true
        worker?.cancel()
    }

    func moveToTrash(_ entries: [ScannedFile]) async -> TrashOutcome {
        guard !entries.isEmpty, !isScanning, !isMoving else { return TrashOutcome() }
        isMoving = true
        let outcome = await Task.detached(priority: .userInitiated) {
            await TrashService(policy: CleanupPolicy()).move(entries)
        }.value
        removedPaths.formUnion(outcome.moved.map(\.path))
        isMoving = false
        refreshCapacity()
        return outcome
    }

    func openTrash() -> Bool {
        let manager = FileManager.default
        let trash = (try? manager.url(for: .trashDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: false))
            ?? manager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        return NSWorkspace.shared.open(trash)
    }

    private func record(_ progress: ScanProgress, for id: UUID) {
        guard scanID == id, progress.inspectedCount > (self.progress?.inspectedCount ?? 0) else { return }
        self.progress = progress
    }

    private func finishScan(_ id: UUID, result: ScanResult?, cancelled: Bool) {
        guard scanID == id else { return }
        let stopped = cancelled || isCancelling
        scanID = nil
        worker = nil
        isCancelling = false
        wasCancelled = stopped
        if !stopped, let result {
            results = result
            removedPaths.removeAll()
        }
        refreshCapacity()
    }
}
