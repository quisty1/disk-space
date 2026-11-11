import Darwin
import Foundation

struct ScanRoot: Sendable {
    let path: String
    let title: String?
    let useStartupAliases: Bool

    static func startup() -> [ScanRoot] {
        let data = "/System/Volumes/Data"
        let system = ScanRoot(path: "/", title: "macOS", useStartupAliases: false)
        guard mountedAt(data) == data else {
            return [ScanRoot(path: "/", title: nil, useStartupAliases: false)]
        }
        return [ScanRoot(path: data, title: nil, useStartupAliases: true), system]
    }
}

struct ScannedFile: Identifiable, Sendable {
    let path: String
    let name: String
    let stamp: FileStamp
    let canTrash: Bool

    var id: String { path }
    var allocatedBytes: Int64 { stamp.allocatedBytes }
    var modified: Date { stamp.modified }
}

struct FolderUsage: Identifiable, Sendable {
    let path: String
    let name: String
    let allocatedBytes: Int64

    var id: String { path }
}

struct ScanProgress: Sendable {
    let inspectedCount: Int
    let path: String
}

struct ScanResult: Sendable {
    let large: [ScannedFile]
    let old: [ScannedFile]
    let personalLarge: [ScannedFile]
    let personalOld: [ScannedFile]
    let largeCount: Int
    let oldCount: Int
    let personalLargeCount: Int
    let personalOldCount: Int
    let folders: [FolderUsage]
    let inspectedCount: Int
    let skippedCount: Int
    let skippedPaths: [String]
    let completedAt: Date
}

struct DiskScanner: Sendable {
    let policy: CleanupPolicy
    let largeThreshold: Int64
    let resultLimit: Int
    let mountPoint: @Sendable (String, Int32) -> String?
    let listDirectory: @Sendable (String, Int32) throws -> [String]

    init(
        policy: CleanupPolicy = CleanupPolicy(), largeThreshold: Int64 = 100_000_000,
        resultLimit: Int = 500, mountPoint: @escaping @Sendable (String, Int32) -> String? = {
            mountedAt(descriptor: $1)
        },
        listDirectory: @escaping @Sendable (String, Int32) throws -> [String] = {
            try readDirectory($1)
        }
    ) {
        self.policy = policy
        self.largeThreshold = largeThreshold
        self.resultLimit = max(1, resultLimit)
        self.mountPoint = mountPoint
        self.listDirectory = listDirectory
    }

    func scan(
        roots: [ScanRoot],
        isCancelled: () -> Bool = { false },
        onProgress: (ScanProgress) -> Void = { _ in }
    ) throws -> ScanResult {
        var state = Traversal(scanner: self)
        for root in roots {
            try state.walk(root, isCancelled: isCancelled, onProgress: onProgress)
        }
        if isCancelled() { throw CancellationError() }
        return state.result()
    }
}

private struct Traversal {
    let scanner: DiskScanner
    let oldCutoff = Date().addingTimeInterval(-90 * 86_400)
    var inspectedCount = 0
    var skippedCount = 0
    var skippedPaths: [String] = []
    var large = RankedFiles()
    var old = RankedFiles()
    var personalLarge = RankedFiles()
    var personalOld = RankedFiles()
    var folders: [FolderUsage] = []
    var hardLinks: Set<HardLink> = []
    var lastProgress = ContinuousClock.now

    mutating func walk(
        _ root: ScanRoot, isCancelled: () -> Bool, onProgress: (ScanProgress) -> Void
    ) throws {
        if isCancelled() { throw CancellationError() }
        let bytes = try visit(
            name: root.path, parent: AT_FDCWD, path: root.path, displayPath: root.path,
            root: root, depth: 0, mount: nil,
            showFiles: true, allowCleanup: root.title == nil,
            isCancelled: isCancelled, onProgress: onProgress
        )
        if let title = root.title, bytes > 0 {
            folders.append(FolderUsage(path: root.path, name: title, allocatedBytes: bytes))
        }
    }

    mutating func visit(
        name: String, parent: Int32, path: String, displayPath: String, root: ScanRoot, depth: Int, mount: String?,
        showFiles: Bool, allowCleanup: Bool, isCancelled: () -> Bool, onProgress: (ScanProgress) -> Void
    ) throws -> Int64 {
        if isCancelled() { throw CancellationError() }
        inspectedCount += 1
        if inspectedCount.isMultiple(of: 256), lastProgress.duration(to: .now) >= .milliseconds(240) {
            lastProgress = .now
            onProgress(ScanProgress(inspectedCount: inspectedCount, path: displayPath))
        }

        let stamp: FileStamp
        do {
            stamp = try FileStamp.read(name, relativeTo: parent)
        } catch {
            noteSkipped(displayPath)
            return 0
        }

        if stamp.isDirectory {
            if root.title != nil && path == "/System/Volumes" { return 0 }
            guard !stamp.isDataless else {
                noteSkipped(displayPath)
                return 0
            }
            let descriptor = openat(parent, name, O_DIRECTORY | O_NOFOLLOW | O_RDONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
                noteSkipped(displayPath)
                return 0
            }
            defer { close(descriptor) }
            guard let openedStamp = try? FileStamp.read(descriptor: descriptor),
                  stamp.matchesIdentity(of: openedStamp), !openedStamp.isDataless,
                  let directoryMount = scanner.mountPoint(path, descriptor) else {
                noteSkipped(displayPath)
                return 0
            }
            if let mount, mount != directoryMount { return 0 }
            let names: [String]
            do {
                names = try scanner.listDirectory(path, descriptor)
            } catch {
                noteSkipped(displayPath)
                return 0
            }

            let folderURL = URL(fileURLWithPath: path, isDirectory: true)
            let package = showFiles && depth > 0 && isPackage(folderURL)
            let isTrash = folderURL.lastPathComponent == ".Trash" || folderURL.lastPathComponent == ".Trashes"
            let showChildren = showFiles && !package && !isTrash
            let cleanChildren = allowCleanup && !package && !openedStamp.isRestricted
                && !names.contains(where: CleanupPolicy.syncMarkers.contains)
            var bytes: Int64 = 0

            for name in names {
                let child = childPath(path, name)
                let visiblePath = root.useStartupAliases && depth == 0
                    ? startupAlias(name, for: child, mount: directoryMount)
                    : childPath(displayPath, name)
                bytes += try visit(
                    name: name, parent: descriptor, path: child, displayPath: visiblePath,
                    root: root, depth: depth + 1, mount: directoryMount,
                    showFiles: showChildren, allowCleanup: cleanChildren,
                    isCancelled: isCancelled, onProgress: onProgress
                )
            }

            if bytes > 0 && root.title == nil && (depth == 1 || parentPath(displayPath) == scanner.policy.home) {
                folders.append(FolderUsage(path: displayPath, name: folderURL.lastPathComponent, allocatedBytes: bytes))
            }
            return bytes
        }

        guard stamp.isFile, let mount else { return 0 }
        if stamp.linkCount > 1 {
            let identity = HardLink(mount: mount, inode: stamp.inode)
            guard hardLinks.insert(identity).inserted else { return 0 }
        }
        if showFiles && stamp.allocatedBytes > 0 {
            record(stamp, at: displayPath, allowCleanup: allowCleanup)
        }
        return stamp.allocatedBytes
    }

    mutating func record(_ stamp: FileStamp, at path: String, allowCleanup: Bool) {
        let isLarge = stamp.allocatedBytes >= scanner.largeThreshold
        let isOld = stamp.modified <= oldCutoff
        guard isLarge || isOld else { return }

        let canTrash = allowCleanup && scanner.policy.allowsPath(path)
            && scanner.policy.allowsFile(stamp, at: path)
        let entry = ScannedFile(
            path: path, name: path.split(separator: "/").last.map(String.init) ?? path,
            stamp: stamp, canTrash: canTrash
        )
        if isLarge {
            large.record(entry, limit: scanner.resultLimit)
            if canTrash { personalLarge.record(entry, limit: scanner.resultLimit) }
        }
        if isOld {
            old.record(entry, limit: scanner.resultLimit)
            if canTrash { personalOld.record(entry, limit: scanner.resultLimit) }
        }
    }

    mutating func noteSkipped(_ path: String) {
        skippedCount += 1
        if skippedPaths.count < 40 { skippedPaths.append(path) }
    }

    func startupAlias(_ name: String, for path: String, mount: String) -> String {
        let alias = "/" + name
        guard mountedAt(alias) == mount,
              let canonical = try? FileStamp.read(path), let visible = try? FileStamp.read(alias),
              canonical.matchesIdentity(of: visible) else { return path }
        return alias
    }

    func parentPath(_ path: String) -> String {
        guard let separator = path.lastIndex(of: "/") else { return path }
        return separator == path.startIndex ? "/" : String(path[..<separator])
    }

    func result() -> ScanResult {
        ScanResult(
            large: large.results(limit: scanner.resultLimit), old: old.results(limit: scanner.resultLimit),
            personalLarge: personalLarge.results(limit: scanner.resultLimit),
            personalOld: personalOld.results(limit: scanner.resultLimit),
            largeCount: large.count, oldCount: old.count,
            personalLargeCount: personalLarge.count, personalOldCount: personalOld.count,
            folders: Array(folders.sorted {
                $0.allocatedBytes == $1.allocatedBytes ? $0.path < $1.path : $0.allocatedBytes > $1.allocatedBytes
            }.prefix(8)),
            inspectedCount: inspectedCount, skippedCount: skippedCount,
            skippedPaths: skippedPaths, completedAt: Date()
        )
    }
}

private struct HardLink: Hashable {
    let mount: String
    let inode: UInt64
}

private struct RankedFiles {
    var count = 0
    var entries: [ScannedFile] = []
    var minimumBytes: Int64 = 0

    mutating func record(_ entry: ScannedFile, limit: Int) {
        count += 1
        guard entry.allocatedBytes >= minimumBytes else { return }
        entries.append(entry)
        if entries.count >= limit * 2 {
            entries = results(limit: limit)
            minimumBytes = entries.last?.allocatedBytes ?? 0
        }
    }

    func results(limit: Int) -> [ScannedFile] {
        Array(entries.sorted {
            $0.allocatedBytes == $1.allocatedBytes ? $0.path < $1.path : $0.allocatedBytes > $1.allocatedBytes
        }.prefix(limit))
    }
}
