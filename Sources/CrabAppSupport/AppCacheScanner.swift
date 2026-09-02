import CrabCore
import Foundation

public struct AppScanIssue: Equatable, Sendable {
    public let ruleID: RuleID
    public let message: String

    public init(ruleID: RuleID, message: String) {
        self.ruleID = ruleID
        self.message = message
    }
}

public struct AppScanResult: Equatable, Sendable {
    public let candidates: [ScanCandidate]
    public let skippedRuleIDs: [RuleID]
    public let issues: [AppScanIssue]

    public init(
        candidates: [ScanCandidate],
        skippedRuleIDs: [RuleID],
        issues: [AppScanIssue]
    ) {
        self.candidates = candidates
        self.skippedRuleIDs = skippedRuleIDs
        self.issues = issues
    }
}

public struct AppCacheScanner: Sendable {
    private let scanner: SafeScanner

    public init(scanner: SafeScanner = SafeScanner()) {
        self.scanner = scanner
    }

    public func scan(rules: [AIFileRule], homeURL: URL) -> AppScanResult {
        var candidates: [ScanCandidate] = []
        var skipped: [RuleID] = []
        var issues: [AppScanIssue] = []

        for rule in rules {
            do {
                candidates.append(try scanner.scan(rule: rule, homeURL: homeURL))
            } catch ScanError.missingPath {
                skipped.append(rule.id)
            } catch {
                issues.append(AppScanIssue(ruleID: rule.id, message: String(describing: error)))
            }
        }

        return AppScanResult(
            candidates: candidates.sorted { $0.rule.appID < $1.rule.appID },
            skippedRuleIDs: skipped.sorted { $0.rawValue < $1.rawValue },
            issues: issues.sorted { $0.ruleID.rawValue < $1.ruleID.rawValue }
        )
    }
}
