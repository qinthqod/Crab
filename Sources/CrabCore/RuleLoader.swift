import Foundation

public enum RuleLoaderError: Error, Equatable, CustomStringConvertible {
    case unreadableDirectory(String)
    case duplicateRuleID(RuleID)

    public var description: String {
        switch self {
        case let .unreadableDirectory(path):
            return "Rules directory is not readable: \(path)."
        case let .duplicateRuleID(id):
            return "Rules directory contains duplicate id \(id.rawValue)."
        }
    }
}

public struct RuleLoader: Sendable {
    public init() {}

    public func load(directory: URL) throws -> [AIFileRule] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw RuleLoaderError.unreadableDirectory(directory.path)
        }

        var seen = Set<RuleID>()
        return try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { file in
                let rule = try RuleValidator.decode(data: Data(contentsOf: file))
                guard seen.insert(rule.id).inserted else {
                    throw RuleLoaderError.duplicateRuleID(rule.id)
                }
                return rule
            }
    }
}
