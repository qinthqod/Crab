import Foundation

public struct RuleID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum RuleCategory: String, Codable, Sendable {
    case regenerableCache = "regenerable-cache"
    case diagnostics
    case downloadableAsset = "downloadable-asset"
    case protectedContent = "protected-content"
}

public enum RiskLevel: String, Codable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
}

public enum RuleAction: String, Codable, Sendable {
    case trash
}

public struct AIFileRule: Codable, Equatable, Sendable {
    public let schema: Int
    public let id: RuleID
    public let appID: String
    public let category: RuleCategory
    public let risk: RiskLevel
    public let leaf: String
    public let requiresAppStopped: Bool
    public let action: RuleAction
    public let explanation: String
    public let impact: String
    public let recovery: String
}
