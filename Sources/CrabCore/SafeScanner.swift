import Darwin
import Foundation

public enum ScanError: Error, Equatable, CustomStringConvertible {
    case missingPath(String)
    case symbolicLink(String)
    case unsupportedFileType(String)
    case mountBoundary(String)
    case escapedHome(String)
    case unreadableDirectory(String)

    public var description: String {
        switch self {
        case let .missingPath(path):
            return "Required path is missing: \(path)."
        case let .symbolicLink(path):
            return "Symbolic links are not eligible for scanning: \(path)."
        case let .unsupportedFileType(path):
            return "Unsupported file type at \(path)."
        case let .mountBoundary(path):
            return "Scanning cannot cross a filesystem boundary at \(path)."
        case let .escapedHome(path):
            return "Rule resolved outside the configured home: \(path)."
        case let .unreadableDirectory(path):
            return "Directory metadata could not be enumerated: \(path)."
        }
    }
}

public struct SafeScanner: Sendable {
    public init() {}

    public func scan(rule: AIFileRule, homeURL: URL) throws -> ScanCandidate {
        try Task.checkCancellation()
        try RuleValidator.validate(rule)

        let normalizedHome = homeURL.standardizedFileURL
        let target = normalizedHome
            .appendingPathComponent(rule.leaf, isDirectory: true)
            .standardizedFileURL
        let homePrefix = normalizedHome.path.hasSuffix("/")
            ? normalizedHome.path
            : normalizedHome.path + "/"

        guard target.path.hasPrefix(homePrefix) else {
            throw ScanError.escapedHome(target.path)
        }

        let targetMetadata = try validatePathChain(
            homeURL: normalizedHome,
            relativeLeaf: rule.leaf
        )
        let rootKind = try kind(for: targetMetadata, path: target.path)
        guard rootKind == .directory else {
            throw ScanError.unsupportedFileType(target.path)
        }

        let rootIdentity = FileIdentity(metadata: targetMetadata, kind: rootKind)
        var seenFiles = Set<FileKey>()
        var totals = Totals()
        try scanDirectory(
            target,
            rootDevice: rootIdentity.device,
            seenFiles: &seenFiles,
            totals: &totals
        )

        return ScanCandidate(
            rule: rule,
            path: target,
            identity: rootIdentity,
            logicalBytes: totals.logicalBytes,
            physicalBytes: totals.physicalBytes,
            fileCount: totals.fileCount,
            safety: .verifiedSafe
        )
    }

    private func validatePathChain(homeURL: URL, relativeLeaf: String) throws -> stat {
        var current = homeURL
        _ = try metadata(at: current)

        var latest = stat()
        for component in relativeLeaf.split(separator: "/") {
            current.appendPathComponent(String(component))
            latest = try metadata(at: current)
        }
        return latest
    }

    private func scanDirectory(
        _ directory: URL,
        rootDevice: UInt64,
        seenFiles: inout Set<FileKey>,
        totals: inout Totals
    ) throws {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw ScanError.unreadableDirectory(directory.path)
        }

        for child in children {
            try Task.checkCancellation()
            let childMetadata = try metadata(at: child, rejectSymbolicLink: false)
            if childMetadata.st_mode & S_IFMT == S_IFLNK {
                continue
            }
            guard UInt64(childMetadata.st_dev) == rootDevice else {
                throw ScanError.mountBoundary(child.path)
            }

            let childKind = try kind(for: childMetadata, path: child.path)
            switch childKind {
            case .directory:
                try scanDirectory(
                    child,
                    rootDevice: rootDevice,
                    seenFiles: &seenFiles,
                    totals: &totals
                )
            case .regularFile:
                totals.fileCount += 1
                let identity = FileIdentity(metadata: childMetadata, kind: childKind)
                let key = FileKey(device: identity.device, inode: identity.inode)
                if seenFiles.insert(key).inserted {
                    totals.logicalBytes += identity.logicalBytes
                    totals.physicalBytes += identity.allocatedBytes
                }
            }
        }
    }

    private func metadata(at url: URL, rejectSymbolicLink: Bool = true) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            throw ScanError.missingPath(url.path)
        }

        if rejectSymbolicLink, value.st_mode & S_IFMT == S_IFLNK {
            throw ScanError.symbolicLink(url.path)
        }
        return value
    }

    private func kind(for metadata: stat, path: String) throws -> FileKind {
        switch metadata.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFREG:
            return .regularFile
        default:
            throw ScanError.unsupportedFileType(path)
        }
    }
}

private struct FileKey: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct Totals {
    var logicalBytes: UInt64 = 0
    var physicalBytes: UInt64 = 0
    var fileCount: UInt64 = 0
}
