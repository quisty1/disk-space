import AppKit
import SwiftUI

private enum FileMode: CaseIterable, Identifiable {
    case large, old

    var id: Self { self }
    var title: TextKey { self == .large ? .large : .old }
    var hint: TextKey { self == .large ? .largeHint : .oldHint }
}

struct FilesView: View {
    let model: AppModel
    @Environment(\.diskLanguage) private var language
    @State private var mode = FileMode.large
    @State private var personalOnly = false
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\ScannedFile.allocatedBytes, order: .reverse)]
    @State private var review: PendingCleanup?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 19)
                .padding(.bottom, 13)
            Divider()
            if model.results == nil {
                empty(icon: "doc.on.doc", title: .filesEmptyTitle, detail: .filesEmptyDetail)
            } else if rows.isEmpty {
                empty(icon: "doc.text.magnifyingglass", title: .noMatches, detail: .noMatchesDetail)
            } else {
                table
            }
            Divider()
            footer
                .padding(.horizontal, 17)
                .padding(.vertical, 11)
                .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: mode) { selection.removeAll() }
        .onChange(of: personalOnly) { selection.removeAll() }
        .onChange(of: model.results?.completedAt) { selection.removeAll() }
        .sheet(item: $review) { review in
            CleanupReview(model: model, entries: review.entries) {
                selection.removeAll()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text(.fileTitle))
                .font(.system(size: 32, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                Picker(language.text(.fileTitle), selection: $mode) {
                    ForEach(FileMode.allCases) { mode in
                        Text(language.text(mode.title)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Toggle(language.text(.personalOnly), isOn: $personalOnly)
                    .toggleStyle(.checkbox)
                    .help(language.text(.personalHelp))
            }

            Text(language.text(mode.hint))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var rows: [ScannedFile] {
        guard let result = model.results else { return [] }
        let entries: [ScannedFile]
        switch (mode, personalOnly) {
        case (.large, false): entries = result.large
        case (.old, false): entries = result.old
        case (.large, true): entries = result.personalLarge
        case (.old, true): entries = result.personalOld
        }
        return entries.filter { !model.removedPaths.contains($0.id) }
    }

    private var totalMatches: Int {
        guard let result = model.results else { return 0 }
        switch (mode, personalOnly) {
        case (.large, false): return result.largeCount
        case (.old, false): return result.oldCount
        case (.large, true): return result.personalLargeCount
        case (.old, true): return result.personalOldCount
        }
    }

    private var selectedRows: [ScannedFile] {
        rows.filter { selection.contains($0.id) }
    }

    private var table: some View {
        Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn(language.text(.filename), value: \.name) { row in
                HStack(spacing: 5) {
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !row.canTrash {
                        Image(systemName: "lock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help(language.text(.protectedFile))
                            .accessibilityLabel(language.text(.protectedFile))
                    }
                }
                .help(row.path)
            }
            .width(min: 128, ideal: 200)
            TableColumn(language.text(.size), value: \.allocatedBytes) { row in
                Text(language.bytes(row.allocatedBytes)).monospacedDigit().lineLimit(1)
            }
            .width(min: 78, ideal: 91, max: 115)
            TableColumn(language.text(.modified), value: \.modified) { row in
                Text(language.date(row.modified)).lineLimit(1)
            }
            .width(min: 100, ideal: 117, max: 150)
            TableColumn(language.text(.location), value: \.path) { row in
                Text(URL(fileURLWithPath: row.path).deletingLastPathComponent().path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.path)
            }
            .width(min: 100, ideal: 225)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                let entries = rows.filter { ids.contains($0.id) }
                Button(language.text(.showFinder)) { reveal(entries) }
                Button(language.text(.moveToTrash)) { askToMove(entries) }
                    .disabled(!canMove(entries))
            }
        } primaryAction: { ids in
            reveal(rows.filter { ids.contains($0.id) })
        }
    }

    private func empty(icon: String, title: TextKey, detail: TextKey) -> some View {
        VStack {
            Spacer(minLength: 0)
            DiskEmptyView(icon: icon, title: language.text(title), detail: language.text(detail))
            if model.results == nil {
                Button(language.text(.scan)) { model.startScan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScanning || model.isMoving)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        let selected = selectedRows
        return HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(footerTitle(selected))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if !selected.isEmpty && selected.contains(where: { !$0.canTrash }) {
                    Text(language.text(.viewOnlySelection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Button {
                reveal(selected)
            } label: {
                Label(language.text(.showFinder), systemImage: "arrow.up.forward.app")
            }
            .disabled(selected.isEmpty)
            Button {
                askToMove(selected)
            } label: {
                Label(language.text(.moveToTrash), systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!canMove(selected))
        }
    }

    private func footerTitle(_ entries: [ScannedFile]) -> String {
        if !entries.isEmpty {
            return language.text(.selectedSize, language.count(entries.count), language.bytes(entries.allocatedBytes))
        }
        if model.removedPaths.isEmpty && totalMatches > rows.count {
            return language.text(.cappedCount, language.count(rows.count), language.count(totalMatches))
        }
        return language.text(.matchCount, language.count(rows.count))
    }

    private func canMove(_ entries: [ScannedFile]) -> Bool {
        !entries.isEmpty && entries.allSatisfy(\.canTrash) && !model.isScanning && !model.isMoving
    }

    private func reveal(_ entries: [ScannedFile]) {
        guard !entries.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(entries.map { URL(fileURLWithPath: $0.path) })
    }

    private func askToMove(_ entries: [ScannedFile]) {
        guard canMove(entries) else { return }
        review = PendingCleanup(entries: entries)
    }
}

private struct PendingCleanup: Identifiable {
    let id = UUID()
    let entries: [ScannedFile]
}

private struct CleanupReview: View {
    let model: AppModel
    let entries: [ScannedFile]
    let onComplete: () -> Void

    @Environment(\.diskLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: TrashOutcome?
    @State private var showingTrashError = false
    @State private var submitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let outcome {
                Text(language.text(.trashResult)).font(.title2.weight(.semibold))
                Text(language.text(.trashMoved, language.count(outcome.moved.count)))
                if !outcome.issues.isEmpty {
                    Text(language.text(.trashSkipped, language.count(outcome.issues.count)))
                        .foregroundStyle(.secondary)
                    itemList {
                        ForEach(outcome.issues) { issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.path).font(.callout).lineLimit(1).truncationMode(.middle)
                                Text(language.text(issue.reason.title)).font(.caption).foregroundStyle(.secondary)
                            }
                            .help(issue.path)
                        }
                    }
                }
                if !outcome.moved.isEmpty {
                    Text(language.text(.reviewDetail)).foregroundStyle(.secondary)
                }
                HStack {
                    if !outcome.moved.isEmpty {
                        Button(language.text(.openTrash)) {
                            if !model.openTrash() { showingTrashError = true }
                        }
                    }
                    Spacer()
                    Button(language.text(.done)) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(language.text(.reviewTitle)).font(.title2.weight(.semibold))
                Text(language.text(.reviewCount, language.count(entries.count), language.bytes(entries.allocatedBytes)))
                itemList {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.path).lineLimit(1).truncationMode(.middle).help(entry.path)
                            Spacer()
                            Text(language.bytes(entry.allocatedBytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                Text(language.text(.reviewDetail)).foregroundStyle(.secondary)
                HStack {
                    if submitting {
                        ProgressView().controlSize(.small)
                        Text(language.text(.moving)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(language.text(.cancel)) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(submitting)
                    Button(language.text(.moveToTrash), role: .destructive) {
                        guard !submitting else { return }
                        submitting = true
                        Task {
                            outcome = await model.moveToTrash(entries)
                            submitting = false
                            onComplete()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(submitting || model.isScanning)
                }
            }
        }
        .padding(20)
        .frame(width: 530)
        .interactiveDismissDisabled(submitting)
        .alert(language.text(.trashUnavailable), isPresented: $showingTrashError) {
            Button(language.text(.done), role: .cancel) {}
        }
    }

    private func itemList<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .frame(height: 120)
    }
}

private extension TrashFailure {
    var title: TextKey {
        switch self {
        case .changed: .changed
        case .protected: .protected
        case .unavailable: .unavailable
        }
    }
}

private extension Array where Element == ScannedFile {
    var allocatedBytes: Int64 {
        reduce(0) { $0 + $1.allocatedBytes }
    }
}
