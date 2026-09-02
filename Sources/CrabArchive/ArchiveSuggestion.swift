import Foundation

public enum ArchiveFileKind: String, Codable, Equatable, Sendable {
    case directory
    case regularFile
}

public struct ArchiveFileIdentity: Codable, Equatable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let kind: ArchiveFileKind
    public let logicalBytes: UInt64
    public let allocatedBytes: UInt64
    public let modificationNanoseconds: Int64

    init(metadata: stat, kind: ArchiveFileKind) {
        device = UInt64(metadata.st_dev)
        inode = UInt64(metadata.st_ino)
        self.kind = kind
        logicalBytes = UInt64(max(0, metadata.st_size))
        allocatedBytes = UInt64(max(0, metadata.st_blocks)) * 512
        modificationNanoseconds = Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000
            + Int64(metadata.st_mtimespec.tv_nsec)
    }
}

public struct ArchiveSuggestion: Equatable, Sendable {
    public let root: URL
    public let path: URL
    public let rootIdentity: ArchiveFileIdentity
    public let identity: ArchiveFileIdentity
    public let latestActivity: Date
    public let logicalBytes: UInt64
    public let physicalBytes: UInt64
    public let fileCount: UInt64
    public let evidence: String
}

public struct ArchiveScanResult: Equatable, Sendable {
    public let root: URL
    public let rootIdentity: ArchiveFileIdentity
    public let inactivityDays: Int
    public let scannedAt: Date
    public let suggestions: [ArchiveSuggestion]
    public let skippedChildCount: Int
}
