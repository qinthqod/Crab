import Darwin
import Foundation

public enum ArchiveScanError: Error, Equatable, CustomStringConvertible {
    case invalidConfiguration
    case protectedRoot(String)
    case missingPath(String)
    case symbolicLink(String)
    case unsupportedFileType(String)
    case mountBoundary(String)
    case unreadableDirectory(String)
    case traversalLimitExceeded(Int)

    public var description: String {
        switch self {
        case .invalidConfiguration:
            return "Archive scan configuration is invalid."
        case let .protectedRoot(path):
            return "This folder is protected from archive scanning: \(path)."
        case let .missingPath(path):
            return "The selected folder is missing: \(path)."
        case let .symbolicLink(path):
            return "Linked folders are not eligible for archive scanning: \(path)."
        case let .unsupportedFileType(path):
            return "Unsupported file type in archive scan: \(path)."
        case let .mountBoundary(path):
            return "Archive scanning cannot cross a filesystem boundary: \(path)."
        case let .unreadableDirectory(path):
            return "Directory metadata could not be enumerated: \(path)."
        case let .traversalLimitExceeded(limit):
            return "Archive scan stopped at its \(limit)-entry safety limit."
        }
    }
}

public struct ArchiveScanner: Sendable {
    private let maxEntries: Int

    public init(maxEntries: Int = 250_000) {
        self.maxEntries = maxEntries
    }

    public func scan(
        rootURL: URL,
        homeURL: URL,
        now: Date = Date(),
        inactivityDays: Int = 180
    ) throws -> ArchiveScanResult {
        guard maxEntries > 0, inactivityDays > 0 else {
            throw ArchiveScanError.invalidConfiguration
        }

        let root = canonicalSystemAlias(rootURL.standardizedFileURL)
        let home = canonicalSystemAlias(homeURL.standardizedFileURL)
        try validateRoot(root, homeURL: home)
        let rootMetadata = try metadata(at: root)
        guard try kind(for: rootMetadata, path: root.path) == .directory else {
            throw ArchiveScanError.unsupportedFileType(root.path)
        }
        let rootIdentity = ArchiveFileIdentity(metadata: rootMetadata, kind: .directory)
        let children = try directoryContents(root)
        let cutoff = now.addingTimeInterval(-TimeInterval(inactivityDays) * 86_400)
        var entryCount = 0
        var skippedChildCount = 0
        var suggestions: [ArchiveSuggestion] = []

        for child in children.sorted(by: { $0.path < $1.path }) {
            entryCount += 1
            guard entryCount <= maxEntries else {
                throw ArchiveScanError.traversalLimitExceeded(maxEntries)
            }
            guard !isMediaLibrary(child) else { continue }
            let childMetadata = try metadata(at: child)
            let childKind = try kind(for: childMetadata, path: child.path)
            guard childKind == .directory else { continue }

            do {
                var totals = ArchiveTotals(latestActivity: modificationDate(childMetadata))
                var seenFiles = Set<ArchiveFileKey>()
                try scanDirectory(
                    child,
                    rootDevice: rootIdentity.device,
                    entryCount: &entryCount,
                    seenFiles: &seenFiles,
                    totals: &totals
                )
                guard !totals.containsProtectedMedia else { continue }
                guard totals.latestActivity < cutoff else { continue }
                suggestions.append(ArchiveSuggestion(
                    root: root,
                    path: child,
                    rootIdentity: rootIdentity,
                    identity: ArchiveFileIdentity(metadata: childMetadata, kind: .directory),
                    latestActivity: totals.latestActivity,
                    logicalBytes: totals.logicalBytes,
                    physicalBytes: totals.physicalBytes,
                    fileCount: totals.fileCount,
                    evidence: "Latest filesystem modification is older than \(inactivityDays) days."
                ))
            } catch ArchiveScanError.unreadableDirectory {
                skippedChildCount += 1
            }
        }

        return ArchiveScanResult(
            root: root,
            rootIdentity: rootIdentity,
            inactivityDays: inactivityDays,
            scannedAt: now,
            suggestions: suggestions,
            skippedChildCount: skippedChildCount
        )
    }

    private func scanDirectory(
        _ directory: URL,
        rootDevice: UInt64,
        entryCount: inout Int,
        seenFiles: inout Set<ArchiveFileKey>,
        totals: inout ArchiveTotals
    ) throws {
        for child in try directoryContents(directory) {
            entryCount += 1
            guard entryCount <= maxEntries else {
                throw ArchiveScanError.traversalLimitExceeded(maxEntries)
            }
            let value = try metadata(at: child)
            guard UInt64(value.st_dev) == rootDevice else {
                throw ArchiveScanError.mountBoundary(child.path)
            }
            totals.latestActivity = max(totals.latestActivity, modificationDate(value))
            switch try kind(for: value, path: child.path) {
            case .directory:
                if isMediaLibrary(child) {
                    totals.containsProtectedMedia = true
                } else {
                    try scanDirectory(
                        child,
                        rootDevice: rootDevice,
                        entryCount: &entryCount,
                        seenFiles: &seenFiles,
                        totals: &totals
                    )
                }
            case .regularFile:
                totals.fileCount += 1
                let identity = ArchiveFileIdentity(metadata: value, kind: .regularFile)
                if seenFiles.insert(ArchiveFileKey(device: identity.device, inode: identity.inode)).inserted {
                    totals.logicalBytes += identity.logicalBytes
                    totals.physicalBytes += identity.allocatedBytes
                }
            }
        }
    }

    private func validateRoot(_ root: URL, homeURL: URL) throws {
        let path = root.path
        let exactProtected = Set([
            "/", "/System", "/Library", "/Applications",
            homeURL.path,
            homeURL.appendingPathComponent("Library").path,
            homeURL.appendingPathComponent("Desktop").path,
            homeURL.appendingPathComponent("Pictures").path,
            homeURL.appendingPathComponent("Music").path,
            homeURL.appendingPathComponent(".Trash").path,
        ])
        let protectedPrefixes = [
            "/System/", "/Library/", "/Applications/",
            homeURL.appendingPathComponent("Library").path + "/",
            homeURL.appendingPathComponent("Pictures").path + "/",
            homeURL.appendingPathComponent("Music").path + "/",
            homeURL.appendingPathComponent(".Trash").path + "/",
        ]
        let normalizedComponents = root.pathComponents.map(normalizedMarker)
        let protectedMarkers: Set<String> = [
            "mobiledocuments", "cloudstorage", "dropbox", "onedrive", "googledrive",
            "sessions", "filehistory", "conversations", "chats", "databases",
        ]
        guard
            !exactProtected.contains(path),
            !protectedPrefixes.contains(where: path.hasPrefix),
            !root.pathComponents.contains(where: isMediaLibraryName),
            protectedMarkers.isDisjoint(with: normalizedComponents)
        else {
            throw ArchiveScanError.protectedRoot(path)
        }

        let homePrefix = homeURL.path.hasSuffix("/") ? homeURL.path : homeURL.path + "/"
        let startsInsideHome = path.hasPrefix(homePrefix)
        var current = startsInsideHome
            ? homeURL
            : URL(fileURLWithPath: "/", isDirectory: true)
        _ = try metadata(at: current)
        let components = startsInsideHome
            ? String(path.dropFirst(homePrefix.count)).split(separator: "/").map(String.init)
            : Array(root.pathComponents.dropFirst())
        for component in components {
            current.appendPathComponent(component)
            _ = try metadata(at: current)
        }
    }

    private func directoryContents(_ directory: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw ArchiveScanError.unreadableDirectory(directory.path)
        }
    }

    private func metadata(at url: URL) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            throw ArchiveScanError.missingPath(url.path)
        }
        guard value.st_mode & S_IFMT != S_IFLNK else {
            throw ArchiveScanError.symbolicLink(url.path)
        }
        return value
    }

    private func kind(for metadata: stat, path: String) throws -> ArchiveFileKind {
        switch metadata.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .regularFile
        default: throw ArchiveScanError.unsupportedFileType(path)
        }
    }

    private func modificationDate(_ metadata: stat) -> Date {
        Date(
            timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec)
                + TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000
        )
    }

    private func normalizedMarker(_ component: String) -> String {
        component.lowercased().filter(\.isLetter)
    }

    private func isMediaLibrary(_ url: URL) -> Bool {
        isMediaLibraryName(url.lastPathComponent)
    }

    private func isMediaLibraryName(_ name: String) -> Bool {
        let extensionName = URL(fileURLWithPath: name).pathExtension.lowercased()
        return ["photoslibrary", "photolibrary", "musiclibrary"].contains(extensionName)
    }

    private func canonicalSystemAlias(_ url: URL) -> URL {
        let path = url.path
        for alias in ["/tmp", "/var"] {
            if path == alias || path.hasPrefix(alias + "/") {
                return URL(fileURLWithPath: "/private" + path, isDirectory: true)
            }
        }
        return url
    }
}

private struct ArchiveFileKey: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct ArchiveTotals {
    var latestActivity: Date
    var logicalBytes: UInt64 = 0
    var physicalBytes: UInt64 = 0
    var fileCount: UInt64 = 0
    var containsProtectedMedia = false
}
