import Darwin
import Foundation

public enum FileKind: String, Codable, Equatable, Sendable {
    case directory
    case regularFile
}

public struct FileIdentity: Codable, Equatable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let kind: FileKind
    public let logicalBytes: UInt64
    public let allocatedBytes: UInt64
    public let modificationNanoseconds: Int64

    init(metadata: stat, kind: FileKind) {
        device = UInt64(metadata.st_dev)
        inode = UInt64(metadata.st_ino)
        self.kind = kind
        logicalBytes = UInt64(max(0, metadata.st_size))
        allocatedBytes = UInt64(max(0, metadata.st_blocks)) * 512
        modificationNanoseconds = Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000
            + Int64(metadata.st_mtimespec.tv_nsec)
    }
}
