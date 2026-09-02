import Foundation

public protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws
}

public protocol ApplicationActivityChecking: Sendable {
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}

public struct CleanupOutcomeMeasure: Equatable, Sendable {
    public let count: Int
    public let logicalBytes: UInt64

    public init(count: Int = 0, logicalBytes: UInt64 = 0) {
        self.count = count
        self.logicalBytes = logicalBytes
    }
}

public struct CleanupReceipt: Equatable, Sendable {
    public let moved: CleanupOutcomeMeasure
    public let skipped: CleanupOutcomeMeasure
    public let failed: CleanupOutcomeMeasure

    public init(
        moved: CleanupOutcomeMeasure,
        skipped: CleanupOutcomeMeasure,
        failed: CleanupOutcomeMeasure
    ) {
        self.moved = moved
        self.skipped = skipped
        self.failed = failed
    }
}

public enum CleanupExecutionError: Error, Equatable, CustomStringConvertible {
    case unsupportedPlan
    case expiredPlan
    case emptyPlan
    case duplicateRule(RuleID)
    case unknownRule(RuleID)
    case planRuleMismatch(RuleID)
    case targetChanged(RuleID)
    case ownerRunning(RuleID)

    public var description: String {
        switch self {
        case .unsupportedPlan:
            return "The cleanup request uses an unsupported schema."
        case .expiredPlan:
            return "The cleanup request expired before execution."
        case .emptyPlan:
            return "The cleanup request contains no selected items."
        case let .duplicateRule(id):
            return "The cleanup rule set contains a duplicate id: \(id.rawValue)."
        case let .unknownRule(id):
            return "The cleanup request references an unknown rule: \(id.rawValue)."
        case let .planRuleMismatch(id):
            return "The cleanup request no longer matches rule \(id.rawValue)."
        case let .targetChanged(id):
            return "The cache changed after review and was not moved: \(id.rawValue)."
        case let .ownerRunning(id):
            return "The owning application is running, so the cache was not moved: \(id.rawValue)."
        }
    }
}

public struct CleanupExecutor<
    Mover: TrashMoving,
    ApplicationChecker: ApplicationActivityChecking
>: Sendable {
    private let trashMover: Mover
    private let applicationChecker: ApplicationChecker
    private let scanner: SafeScanner

    public init(
        trashMover: Mover,
        applicationChecker: ApplicationChecker,
        scanner: SafeScanner = SafeScanner()
    ) {
        self.trashMover = trashMover
        self.applicationChecker = applicationChecker
        self.scanner = scanner
    }

    public func execute(
        plan: CleanPlan,
        rules: [AIFileRule],
        homeURL: URL,
        now: Date = Date()
    ) throws -> CleanupReceipt {
        guard plan.schema == 1 else { throw CleanupExecutionError.unsupportedPlan }
        guard plan.expiresAt > now else { throw CleanupExecutionError.expiredPlan }
        guard !plan.entries.isEmpty else { throw CleanupExecutionError.emptyPlan }

        var rulesByID: [RuleID: AIFileRule] = [:]
        for rule in rules {
            guard rulesByID[rule.id] == nil else {
                throw CleanupExecutionError.duplicateRule(rule.id)
            }
            rulesByID[rule.id] = rule
        }
        var revalidated: [(candidate: ScanCandidate, entry: PlanEntry)] = []
        var skipped = CleanupOutcomeMeasure()

        for entry in plan.entries {
            guard let rule = rulesByID[entry.ruleID] else {
                throw CleanupExecutionError.unknownRule(entry.ruleID)
            }
            guard !isOwnerRunning(for: rule) else {
                throw CleanupExecutionError.ownerRunning(entry.ruleID)
            }
            guard
                rule.leaf == entry.relativeLeaf,
                rule.action == .trash,
                entry.action == .trash,
                rule.risk == .a,
                rule.category == .regenerableCache
            else {
                throw CleanupExecutionError.planRuleMismatch(entry.ruleID)
            }

            let fresh: ScanCandidate
            do {
                fresh = try scanner.scan(rule: rule, homeURL: homeURL)
            } catch ScanError.missingPath {
                skipped = CleanupOutcomeMeasure(
                    count: skipped.count + 1,
                    logicalBytes: skipped.logicalBytes + entry.logicalBytes
                )
                continue
            }
            guard fresh.identity == entry.identity else {
                throw CleanupExecutionError.targetChanged(entry.ruleID)
            }
            revalidated.append((fresh, entry))
        }

        var moved = CleanupOutcomeMeasure()
        var failed = CleanupOutcomeMeasure()

        for (candidate, entry) in revalidated {
            let immediatelyFresh: ScanCandidate
            do {
                immediatelyFresh = try scanner.scan(rule: candidate.rule, homeURL: homeURL)
            } catch ScanError.missingPath {
                skipped = CleanupOutcomeMeasure(
                    count: skipped.count + 1,
                    logicalBytes: skipped.logicalBytes + entry.logicalBytes
                )
                continue
            } catch {
                failed = CleanupOutcomeMeasure(
                    count: failed.count + 1,
                    logicalBytes: failed.logicalBytes + entry.logicalBytes
                )
                continue
            }
            guard immediatelyFresh.identity == entry.identity else {
                failed = CleanupOutcomeMeasure(
                    count: failed.count + 1,
                    logicalBytes: failed.logicalBytes + entry.logicalBytes
                )
                continue
            }
            guard !isOwnerRunning(for: candidate.rule) else {
                throw CleanupExecutionError.ownerRunning(entry.ruleID)
            }
            do {
                try trashMover.moveToTrash(candidate.path)
                moved = CleanupOutcomeMeasure(
                    count: moved.count + 1,
                    logicalBytes: moved.logicalBytes + immediatelyFresh.logicalBytes
                )
            } catch {
                failed = CleanupOutcomeMeasure(
                    count: failed.count + 1,
                    logicalBytes: failed.logicalBytes + immediatelyFresh.logicalBytes
                )
            }
        }

        return CleanupReceipt(
            moved: moved,
            skipped: skipped,
            failed: failed
        )
    }

    private func isOwnerRunning(for rule: AIFileRule) -> Bool {
        rule.requiresAppStopped
            && applicationChecker.isApplicationRunning(bundleIdentifier: rule.appID)
    }
}
