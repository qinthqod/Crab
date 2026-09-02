import Foundation

public enum RuleValidationError: Error, Equatable, CustomStringConvertible {
    case malformedJSON
    case unexpectedFields([String])
    case unsupportedSchema(Int)
    case invalidRuleID
    case invalidAppID
    case invalidLeaf(String)
    case missingExplanation(String)

    public var description: String {
        switch self {
        case .malformedJSON:
            return "Rule is not a valid JSON object."
        case let .unexpectedFields(fields):
            return "Rule contains unsupported fields: \(fields.joined(separator: ", "))."
        case let .unsupportedSchema(schema):
            return "Rule schema \(schema) is unsupported."
        case .invalidRuleID:
            return "Rule id must be a non-empty stable identifier."
        case .invalidAppID:
            return "Rule appID must be non-empty."
        case let .invalidLeaf(reason):
            return "Rule leaf is unsafe: \(reason)."
        case let .missingExplanation(field):
            return "Rule field \(field) must be non-empty."
        }
    }
}

public enum RuleValidator {
    private static let protectedLeafMarkers = [
        "sessions",
        "filehistory",
        "history",
        "models",
        "credentials",
        "tokens",
        "localstorage",
        "indexeddb",
        "databases",
        "containers",
        "groupcontainers",
        "clipboard",
        "conversations",
        "chats",
        "tmp",
        "temp",
    ]

    private static let allowedFields: Set<String> = [
        "schema",
        "id",
        "appID",
        "category",
        "risk",
        "leaf",
        "requiresAppStopped",
        "action",
        "explanation",
        "impact",
        "recovery",
    ]

    public static func decode(data: Data) throws -> AIFileRule {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            throw RuleValidationError.malformedJSON
        }

        let unexpectedFields = Set(dictionary.keys).subtracting(allowedFields).sorted()
        guard unexpectedFields.isEmpty else {
            throw RuleValidationError.unexpectedFields(unexpectedFields)
        }

        let rule: AIFileRule
        do {
            rule = try JSONDecoder().decode(AIFileRule.self, from: data)
        } catch {
            throw RuleValidationError.malformedJSON
        }

        try validate(rule)
        return rule
    }

    public static func validate(_ rule: AIFileRule) throws {
        guard rule.schema == 1 else {
            throw RuleValidationError.unsupportedSchema(rule.schema)
        }

        guard !rule.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleValidationError.invalidRuleID
        }

        guard !rule.appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleValidationError.invalidAppID
        }

        try validateLeaf(rule.leaf)
        try requireText(rule.explanation, field: "explanation")
        try requireText(rule.impact, field: "impact")
        try requireText(rule.recovery, field: "recovery")
    }

    private static func validateLeaf(_ leaf: String) throws {
        guard !leaf.isEmpty else {
            throw RuleValidationError.invalidLeaf("empty path")
        }

        guard !leaf.hasPrefix("/"), !leaf.hasPrefix("~") else {
            throw RuleValidationError.invalidLeaf("absolute and tilde paths are forbidden")
        }

        guard !leaf.utf8.contains(0) else {
            throw RuleValidationError.invalidLeaf("NUL byte is forbidden")
        }

        let components = leaf.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw RuleValidationError.invalidLeaf("empty, dot, and parent components are forbidden")
        }

        guard leaf.hasPrefix("Library/Caches/") else {
            throw RuleValidationError.invalidLeaf("the first slice only permits exact leaves below Library/Caches")
        }

        for component in components.dropFirst(2) {
            let normalized = component
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
            if let marker = protectedLeafMarkers.first(where: normalized.contains) {
                throw RuleValidationError.invalidLeaf("protected data marker \(marker) is forbidden")
            }
        }
    }

    private static func requireText(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleValidationError.missingExplanation(field)
        }
    }
}
