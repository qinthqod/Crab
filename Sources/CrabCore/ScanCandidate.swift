import Foundation

public enum SafetyVerdict: String, Codable, Equatable, Sendable {
    case verifiedSafe = "verified-safe"
}

public struct ScanCandidate: Codable, Equatable, Sendable {
    public let rule: AIFileRule
    public let path: URL
    public let identity: FileIdentity
    public let logicalBytes: UInt64
    public let physicalBytes: UInt64
    public let fileCount: UInt64
    public let safety: SafetyVerdict
}
