import Darwin
import Foundation

struct FileStamp: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let owner: uid_t
    let mode: mode_t
    let flags: UInt32
    let linkCount: nlink_t
    let modified: Date
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int
    let allocatedBytes: Int64
    let logicalBytes: Int64

    var isDirectory: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFDIR) }
    var isFile: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFREG) }
    var isDataless: Bool { flags & UInt32(SF_DATALESS) != 0 }
    var isRestricted: Bool {
        flags & UInt32(SF_RESTRICTED | SF_DATALESS | SF_IMMUTABLE | UF_IMMUTABLE | UF_HIDDEN) != 0
    }

    static func read(_ path: String, relativeTo parent: Int32 = AT_FDCWD) throws -> FileStamp {
        var metadata = stat()
        guard fstatat(parent, path, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw fileSystemError() }
        return FileStamp(metadata)
    }

    static func read(descriptor: Int32) throws -> FileStamp {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw fileSystemError() }
        return FileStamp(metadata)
    }

    private init(_ metadata: stat) {
        device = metadata.st_dev
        inode = metadata.st_ino
        owner = metadata.st_uid
        mode = metadata.st_mode
        flags = metadata.st_flags
        linkCount = metadata.st_nlink
        modified = Date(timeIntervalSince1970: Double(metadata.st_mtimespec.tv_sec))
        modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
        changedSeconds = metadata.st_ctimespec.tv_sec
        changedNanoseconds = metadata.st_ctimespec.tv_nsec
        allocatedBytes = max(0, metadata.st_blocks) * 512
        logicalBytes = max(0, metadata.st_size)
    }

    func matchesIdentity(of other: FileStamp) -> Bool {
        device == other.device && inode == other.inode
    }
}

func fileSystemError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}

func readDirectory(_ descriptor: Int32) throws -> [String] {
    let copy = dup(descriptor)
    guard copy >= 0 else { throw fileSystemError() }
    guard let stream = fdopendir(copy) else {
        let error = fileSystemError()
        close(copy)
        throw error
    }
    defer { closedir(stream) }

    var names: [String] = []
    while true {
        errno = 0
        guard let entry = readdir(stream) else {
            if errno != 0 { throw fileSystemError() }
            return names
        }
        let length = Int(entry.pointee.d_namlen)
        let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
            String(decoding: bytes.prefix(length), as: UTF8.self)
        }
        if name != "." && name != ".." { names.append(name) }
    }
}

func mountedAt(_ path: String) -> String? {
    var volume = statfs()
    guard statfs(path, &volume) == 0 else { return nil }
    return mountName(volume)
}

func mountedAt(descriptor: Int32) -> String? {
    var volume = statfs()
    guard fstatfs(descriptor, &volume) == 0 else { return nil }
    return mountName(volume)
}

private func mountName(_ volume: statfs) -> String {
    return withUnsafeBytes(of: volume.f_mntonname) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

func childPath(_ parent: String, _ name: String) -> String {
    parent == "/" ? "/" + name : parent + "/" + name
}

func isPackage(_ url: URL) -> Bool {
    let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "xcodeproj", "xcworkspace",
        "photoslibrary", "photolibrary", "musiclibrary", "sparsebundle", "playground"
    ]
    return packageExtensions.contains(url.pathExtension.lowercased())
        || (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
}

struct DiskCapacity: Sendable {
    let name: String?
    let total: Int64
    let free: Int64

    var used: Int64 { total - free }
    var usedFraction: Double { Double(used) / Double(total) }

    static func readStartup() -> DiskCapacity? {
        let volume = URL(fileURLWithPath: "/", isDirectory: true)
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey]
        guard let metadata = try? volume.resourceValues(forKeys: keys),
              let total = metadata.volumeTotalCapacity, let free = metadata.volumeAvailableCapacity,
              total > 0, (0...total).contains(free) else { return nil }
        return DiskCapacity(name: metadata.volumeName, total: Int64(total), free: Int64(free))
    }
}

struct CleanupPolicy: Sendable {
    let home: String
    private let protectedPaths: [String]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, protectedDirectories: [URL] = []) {
        self.home = home.path
        self.protectedPaths = protectedDirectories.map(\.path)
    }

    func allowsPath(_ path: String) -> Bool {
        guard path.hasPrefix(home + "/"),
              !protectedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            return false
        }

        let components = path.dropFirst(home.count + 1).split(separator: "/")
        guard let first = components.first?.lowercased(),
              !components.contains(where: { $0.hasPrefix(".") }),
              first != "library" else { return false }
        return !components.dropLast().contains { component in
            let name = component.lowercased()
            return Self.cloudNames.contains(name) || name.hasPrefix("onedrive - ")
        }
    }

    private static let cloudNames: Set<String> = [
        "icloud drive", "dropbox", "google drive", "googledrive", "onedrive", "nextcloud", "owncloud"
    ]

    static let syncMarkers: Set<String> = [
        ".dropbox", ".dropbox.cache", ".stfolder", ".owncloudsync.log", ".nextcloudsync.log"
    ]

    func allowsFile(_ stamp: FileStamp, at path: String) -> Bool {
        guard stamp.isFile, stamp.owner == getuid(), !stamp.isRestricted, allowsPath(path) else {
            return false
        }
        return isLocalFile(at: path)
    }

    private func isLocalFile(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .isHiddenKey]) else { return false }
        return values.isUbiquitousItem != true && values.isHidden != true
    }

    func hasSafeParents(at path: String) -> Bool {
        guard allowsPath(path), let homeVolume = mountedAt(home) else { return false }
        let relative = path.dropFirst(home.count + 1).split(separator: "/")
        var parent = home
        for component in relative.dropLast() {
            parent = childPath(parent, String(component))
            let url = URL(fileURLWithPath: parent, isDirectory: true)
            guard let stamp = try? FileStamp.read(parent),
                  stamp.isDirectory, !stamp.isRestricted,
                  mountedAt(parent) == homeVolume,
                  !isPackage(url), isLocalFile(at: parent),
                  !Self.syncMarkers.contains(where: {
                      (try? FileStamp.read(childPath(parent, $0))) != nil
                  }) else { return false }
        }
        return true
    }
}
