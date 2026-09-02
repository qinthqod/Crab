import Foundation

public enum PlanBuilderError: Error, Equatable, CustomStringConvertible {
    case duplicateRuleID(RuleID)
    case unknownSelections([RuleID])
    case ineligibleCandidate(RuleID)
    case invalidLifetime

    public var description: String {
        switch self {
        case let .duplicateRuleID(id):
            return "The scan contains duplicate rule id \(id.rawValue)."
        case let .unknownSelections(ids):
            return "The selection contains rules missing from the scan: \(ids.map(\.rawValue).joined(separator: ", "))."
        case let .ineligibleCandidate(id):
            return "Candidate \(id.rawValue) is not eligible for a safe plan."
        case .invalidLifetime:
            return "Plan lifetime must be greater than zero and no more than fifteen minutes."
        }
    }
}

public struct PlanBuilder: Sendable {
    public init() {}

    public func build(
        candidates: [ScanCandidate],
        selectedRuleIDs: Set<RuleID>,
        now: Date = Date(),
        validFor lifetime: TimeInterval = 600
    ) throws -> CleanPlan {
        guard lifetime > 0, lifetime <= 900 else {
            throw PlanBuilderError.invalidLifetime
        }

        var byRuleID: [RuleID: ScanCandidate] = [:]
        for candidate in candidates {
            guard byRuleID[candidate.rule.id] == nil else {
                throw PlanBuilderError.duplicateRuleID(candidate.rule.id)
            }
            byRuleID[candidate.rule.id] = candidate
        }

        let unknownSelections = selectedRuleIDs
            .subtracting(Set(byRuleID.keys))
            .sorted { $0.rawValue < $1.rawValue }
        guard unknownSelections.isEmpty else {
            throw PlanBuilderError.unknownSelections(unknownSelections)
        }

        let entries = try selectedRuleIDs
            .sorted { $0.rawValue < $1.rawValue }
            .map { ruleID -> PlanEntry in
                guard let candidate = byRuleID[ruleID] else {
                    throw PlanBuilderError.unknownSelections([ruleID])
                }
                guard
                    candidate.safety == .verifiedSafe,
                    candidate.rule.risk == .a,
                    candidate.rule.category == .regenerableCache,
                    candidate.rule.action == .trash
                else {
                    throw PlanBuilderError.ineligibleCandidate(ruleID)
                }

                return PlanEntry(
                    ruleID: ruleID,
                    relativeLeaf: candidate.rule.leaf,
                    identity: candidate.identity,
                    logicalBytes: candidate.logicalBytes,
                    physicalBytes: candidate.physicalBytes,
                    action: candidate.rule.action
                )
            }

        return CleanPlan(
            schema: 1,
            planID: UUID(),
            createdAt: now,
            expiresAt: now.addingTimeInterval(lifetime),
            entries: entries
        )
    }
}
