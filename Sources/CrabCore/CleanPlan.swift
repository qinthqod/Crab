import Foundation

public struct PlanEntry: Codable, Equatable, Sendable {
    public let ruleID: RuleID
    public let relativeLeaf: String
    public let identity: FileIdentity
    public let logicalBytes: UInt64
    public let physicalBytes: UInt64
    public let action: RuleAction
}

public struct CleanPlan: Codable, Equatable, Sendable {
    public let schema: Int
    public let planID: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let entries: [PlanEntry]
}
