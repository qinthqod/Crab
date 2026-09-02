import Foundation

public struct ArchiveSnapshotEntry: Codable, Equatable, Sendable {
    public let relativeName: String
    public let path: URL
    public let rootIdentity: ArchiveFileIdentity
    public let identity: ArchiveFileIdentity
    public let latestActivity: Date
    public let logicalBytes: UInt64
    public let physicalBytes: UInt64
    public let fileCount: UInt64
    public let evidence: String
}

public struct ArchiveReviewSnapshot: Codable, Equatable, Sendable {
    public let schema: Int
    public let snapshotID: UUID
    public let root: URL
    public let rootIdentity: ArchiveFileIdentity
    public let scannedAt: Date
    public let createdAt: Date
    public let expiresAt: Date
    public let inactivityDays: Int
    public let entries: [ArchiveSnapshotEntry]
}

public enum ArchiveSnapshotError: Error, Equatable, CustomStringConvertible {
    case invalidLifetime
    case staleScan
    case inconsistentSuggestion(String)

    public var description: String {
        switch self {
        case .invalidLifetime:
            return "Archive review lifetime must be greater than zero and no more than fifteen minutes."
        case .staleScan:
            return "Archive scan evidence is no longer fresh enough for review."
        case let .inconsistentSuggestion(path):
            return "Archive suggestion does not match its read-only scan evidence: \(path)."
        }
    }
}

public struct ArchiveSnapshotBuilder: Sendable {
    public init() {}

    public func build(
        from result: ArchiveScanResult,
        now: Date = Date(),
        validFor lifetime: TimeInterval = 600
    ) throws -> ArchiveReviewSnapshot {
        guard lifetime > 0, lifetime <= 900 else {
            throw ArchiveSnapshotError.invalidLifetime
        }
        let evidenceAge = now.timeIntervalSince(result.scannedAt)
        guard evidenceAge >= 0, evidenceAge <= 600 else {
            throw ArchiveSnapshotError.staleScan
        }

        let rootPath = result.root.standardizedFileURL.path
        let cutoff = result.scannedAt.addingTimeInterval(
            -TimeInterval(result.inactivityDays) * 86_400
        )
        let entries = try result.suggestions.map { suggestion -> ArchiveSnapshotEntry in
            let path = suggestion.path.standardizedFileURL
            guard
                suggestion.root.standardizedFileURL.path == rootPath,
                path.deletingLastPathComponent().standardizedFileURL.path == rootPath,
                suggestion.rootIdentity == result.rootIdentity,
                suggestion.identity.kind == .directory,
                suggestion.latestActivity < cutoff,
                !path.lastPathComponent.isEmpty
            else {
                throw ArchiveSnapshotError.inconsistentSuggestion(path.path)
            }
            return ArchiveSnapshotEntry(
                relativeName: path.lastPathComponent,
                path: path,
                rootIdentity: suggestion.rootIdentity,
                identity: suggestion.identity,
                latestActivity: suggestion.latestActivity,
                logicalBytes: suggestion.logicalBytes,
                physicalBytes: suggestion.physicalBytes,
                fileCount: suggestion.fileCount,
                evidence: suggestion.evidence
            )
        }

        return ArchiveReviewSnapshot(
            schema: 1,
            snapshotID: UUID(),
            root: result.root,
            rootIdentity: result.rootIdentity,
            scannedAt: result.scannedAt,
            createdAt: now,
            expiresAt: now.addingTimeInterval(lifetime),
            inactivityDays: result.inactivityDays,
            entries: entries
        )
    }
}
