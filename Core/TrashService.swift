import FileProvider
import Foundation

enum TrashFailure: Sendable {
    case changed, protected, unavailable
}

struct TrashIssue: Identifiable, Sendable {
    let path: String
    let reason: TrashFailure

    var id: String { path }
}

struct TrashedFile: Sendable {
    let path: String
    let trashURL: URL?
}

struct TrashOutcome: Sendable {
    var moved: [TrashedFile] = []
    var issues: [TrashIssue] = []
}

struct TrashService: Sendable {
    let policy: CleanupPolicy

    func move(_ entries: [ScannedFile]) async -> TrashOutcome {
        var result = TrashOutcome()
        for entry in entries {
            do {
                guard entry.canTrash, policy.hasSafeParents(at: entry.path) else {
                    result.issues.append(TrashIssue(path: entry.path, reason: .protected))
                    continue
                }
                let current = try FileStamp.read(entry.path)
                guard current == entry.stamp else {
                    result.issues.append(TrashIssue(path: entry.path, reason: .changed))
                    continue
                }
                let url = URL(fileURLWithPath: entry.path)
                guard policy.allowsFile(current, at: entry.path),
                      await isOutsideFileProvider(url),
                      policy.hasSafeParents(at: entry.path) else {
                    result.issues.append(TrashIssue(path: entry.path, reason: .protected))
                    continue
                }
                var destination: NSURL?
                guard try FileStamp.read(entry.path) == entry.stamp else {
                    result.issues.append(TrashIssue(path: entry.path, reason: .changed))
                    continue
                }
                try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
                result.moved.append(TrashedFile(path: entry.path, trashURL: destination as URL?))
            } catch {
                result.issues.append(TrashIssue(path: entry.path, reason: .unavailable))
            }
        }
        return result
    }

    private func isOutsideFileProvider(_ url: URL) async -> Bool {
        do {
            _ = try await NSFileProviderManager.identifierForUserVisibleFile(at: url)
            return false
        } catch let error as CocoaError {
            return error.code == .fileNoSuchFile
        } catch {
            return false
        }
    }
}
