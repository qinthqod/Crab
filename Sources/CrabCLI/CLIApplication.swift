import CrabCore
import Darwin
import Foundation

public struct CLIApplication: Sendable {
    public static let help = """
    Crab \(CrabCore.version) — safe, read-only AI cache inspection

    Usage:
      crab rules validate <rule.json>
      crab scan --rules <directory> --home <test-home>
      crab plan --rules <directory> --home <test-home> --output <plan.json> [--select <rule-id>]...

    This build cannot move or delete files. Plan selection is empty by default.
    """

    public init() {}

    public func execute(_ command: CLICommand) throws -> [String] {
        switch command {
        case .help:
            return [Self.help]
        case let .validate(ruleFile):
            let rule = try RuleValidator.decode(data: Data(contentsOf: ruleFile))
            return ["VALID \(rule.id.rawValue) schema=\(rule.schema) action=\(rule.action.rawValue)"]
        case let .scan(rulesDirectory, home):
            let rules = try RuleLoader().load(directory: rulesDirectory)
            return scanLines(rules: rules, home: home)
        case let .plan(rulesDirectory, home, output, selectedRuleIDs):
            let rules = try RuleLoader().load(directory: rulesDirectory)
            var candidates: [ScanCandidate] = []
            for rule in rules {
                do {
                    candidates.append(try SafeScanner().scan(rule: rule, homeURL: home))
                } catch {
                    if selectedRuleIDs.contains(rule.id) {
                        throw error
                    }
                }
            }
            let plan = try PlanBuilder().build(
                candidates: candidates,
                selectedRuleIDs: Set(selectedRuleIDs)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try writeNewFile(try encoder.encode(plan), to: output)
            return [
                "PLAN \(plan.planID.uuidString.lowercased())",
                "entries=\(plan.entries.count)",
                "output=\(output.path)",
            ]
        }
    }

    private func scanLines(rules: [AIFileRule], home: URL) -> [String] {
        if rules.isEmpty {
            return ["No JSON rules found."]
        }

        return rules.map { rule in
            do {
                let candidate = try SafeScanner().scan(rule: rule, homeURL: home)
                return "SAFE \(rule.id.rawValue) logical=\(candidate.logicalBytes) allocated=\(candidate.physicalBytes) files=\(candidate.fileCount) leaf=\(rule.leaf)"
            } catch {
                return "SKIP \(rule.id.rawValue) reason=\(error)"
            }
        }
    }

    private func writeNewFile(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteFileExists)
        }
        defer { close(descriptor) }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard count > 0 else {
                    throw CocoaError(.fileWriteUnknown)
                }
                offset += count
            }
        }
    }
}
