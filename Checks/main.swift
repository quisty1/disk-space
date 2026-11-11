import Darwin
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(message: message) }
}

struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func runChecks() async throws {
    let manager = FileManager.default
    let base = manager.temporaryDirectory.appendingPathComponent("DiskSpaceChecks-\(UUID().uuidString)")
    try manager.createDirectory(at: base, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: base) }

    func directory(_ relative: String) throws -> URL {
        let url = base.appendingPathComponent(relative, isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(_ relative: String, size: Int, old: Bool = false) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try Data(repeating: 0xA5, count: size).write(to: url)
        if old {
            try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100 * 86_400)],
                                      ofItemAtPath: url.path)
        }
        return url
    }

    _ = try directory("Personal")
    _ = try directory("Library/CloudStorage")
    _ = try directory("Personal/Custom sync folder/.dropbox.cache")
    _ = try directory("Archive.app/Contents")
    let denied = try directory("Denied")
    _ = try directory("Mounted")
    _ = try directory("System")
    let first = try file("Personal/first.bin", size: 131_072, old: true)
    let second = try file("Personal/second.bin", size: 65_536)
    _ = try file("Personal/.hidden.bin", size: 81_920)
    _ = try file("Archive.app/Contents/file.bin", size: 98_304)
    _ = try file("Library/CloudStorage/cloud.bin", size: 114_688, old: true)
    _ = try file("Personal/Custom sync folder/synced.bin", size: 16_384)
    _ = try file("Denied/denied.bin", size: 262_144)
    _ = try file("Mounted/mounted.bin", size: 262_144)
    _ = try file("System/system.bin", size: 32_768)
    try manager.createSymbolicLink(at: base.appendingPathComponent("Personal/link.bin"),
                                  withDestinationURL: first)
    try manager.linkItem(at: second, to: base.appendingPathComponent("Personal/second-alias.bin"))

    let policy = CleanupPolicy(home: base, protectedDirectories: [base.appendingPathComponent("System")])
    let scanner = DiskScanner(
        policy: policy, largeThreshold: 1, resultLimit: 25,
        mountPoint: { path, _ in path == base.appendingPathComponent("Mounted").path ? "other" : "test" },
        listDirectory: { path, descriptor in
            if path == denied.path { throw CocoaError(.fileReadNoPermission) }
            return try readDirectory(descriptor)
        }
    )
    let roots = [ScanRoot(path: base.path, title: nil, useStartupAliases: false)]
    let result = try scanner.scan(roots: roots)
    let large = result.large
    try expect(large.map(\.allocatedBytes) == large.map(\.allocatedBytes).sorted(by: >), "Files must be sorted by allocated size")
    try expect(large.first?.name == "first.bin", "Largest eligible file must be first")
    try expect(result.old.map(\.name) == ["first.bin", "cloud.bin"], "Old files must be selected by modification date")
    try expect(result.skippedCount == 1 && result.skippedPaths == [denied.path], "Unreadable folders must produce partial results")
    try expect(!large.contains { ["link.bin", "mounted.bin", "denied.bin", "file.bin"].contains($0.name) },
               "Symlinks, other mounts, unreadable folders, and package contents must stay out of file candidates")
    try expect(large.filter { ["second.bin", "second-alias.bin"].contains($0.name) }.count == 1, "Count hard links once")
    let package = result.folders.first { $0.name == "Archive.app" }
    try expect((package?.allocatedBytes ?? 0) >= 98_304, "Count package contents in storage totals")
    let personal = result.folders.first { $0.name == "Personal" }
    let expectedPersonal = try [first, second, base.appendingPathComponent("Personal/.hidden.bin"),
                                base.appendingPathComponent("Personal/Custom sync folder/synced.bin")].reduce(Int64(0)) { total, url in
        total + (try FileStamp.read(url.path)).allocatedBytes
    }
    try expect(personal?.allocatedBytes == expectedPersonal, "Folder totals must add allocated bytes without double-counting hard links")
    try expect(large.first { $0.name == "cloud.bin" }?.canTrash == false, "Cloud-managed files must be view-only")
    try expect(large.first { $0.name == "synced.bin" }?.canTrash == false, "Recognized legacy sync roots must be view-only")
    try expect(large.first { $0.name == ".hidden.bin" }?.canTrash == false, "Hidden files must be view-only")
    try expect(large.first { $0.name == "system.bin" }?.canTrash == false, "Protected files must be view-only")

    let limited = try DiskScanner(policy: policy, largeThreshold: 1, resultLimit: 1).scan(roots: roots)
    try expect(limited.large.count == 1 && limited.largeCount > 1, "Retain a bounded list and count all matches")
    do {
        _ = try scanner.scan(roots: roots, isCancelled: { true })
        throw CheckFailure(message: "Expected cancellation")
    } catch is CancellationError {}

    guard let original = large.first, let stale = result.old.first else {
        throw CheckFailure(message: "Missing test candidates")
    }
    try Data([1, 2, 3]).write(to: first, options: .atomic)
    let outcome = await TrashService(policy: policy).move([stale])
    try expect(outcome.moved.isEmpty && outcome.issues.first?.reason == .changed, "A replaced file must be skipped")
    try expect(manager.fileExists(atPath: first.path), "Changed file must still be on disk")
    try manager.removeItem(at: first)
    try manager.createSymbolicLink(at: first, withDestinationURL: second)
    let redirected = await TrashService(policy: policy).move([original])
    try expect(redirected.moved.isEmpty && manager.fileExists(atPath: second.path), "A symlink replacement must never move its target")

    let trashCandidate = try file("Personal/restore-me.bin", size: 16_384)
    let fresh = try scanner.scan(roots: roots)
    guard let entry = fresh.large.first(where: { $0.name == "restore-me.bin" }) else {
        throw CheckFailure(message: "Missing Trash test candidate")
    }
    let moved = await TrashService(policy: policy).move([entry])
    guard let trashURL = moved.moved.first?.trashURL else {
        throw CheckFailure(message: "Temporary file was not moved to Trash: \(moved.issues)")
    }
    defer {
        if manager.fileExists(atPath: trashURL.path) {
            try? manager.moveItem(at: trashURL, to: trashCandidate)
        }
    }
    try expect(!manager.fileExists(atPath: trashCandidate.path), "Original path must be gone after moving to Trash")
    try expect(manager.fileExists(atPath: trashURL.path), "Trash must contain the temporary file")
    print("Passed: allocated bytes, ranking, age, result limits, partial scans, mount boundaries, cancellation, cleanup scope, stale files, symlinks, and macOS Trash.")
}

try await runChecks()
