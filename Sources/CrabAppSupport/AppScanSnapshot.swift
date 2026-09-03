import CrabCore
import Foundation

public struct CacheActionableSpaceSummary: Equatable, Sendable {
    public let discoveredBytes: UInt64
    public let availableNowBytes: UInt64
    public let blockedByRunningAppsBytes: UInt64

    public init(candidates: [ScanCandidate], blockedRuleIDs: Set<RuleID>) {
        discoveredBytes = candidates.reduce(0) { $0 + $1.logicalBytes }
        blockedByRunningAppsBytes = candidates
            .filter { blockedRuleIDs.contains($0.rule.id) }
            .reduce(0) { $0 + $1.logicalBytes }
        availableNowBytes = discoveredBytes - blockedByRunningAppsBytes
    }
}

public struct CacheScanHistorySummary: Equatable, Sendable {
    public let scannedAt: Date
    public let discoveredBytes: UInt64
    public let installedAppCount: Int

    public init(scannedAt: Date, discoveredBytes: UInt64, installedAppCount: Int) {
        self.scannedAt = scannedAt
        self.discoveredBytes = discoveredBytes
        self.installedAppCount = installedAppCount
    }
}

public struct AppScanSnapshot: Equatable, Sendable {
    public let candidates: [ScanCandidate]
    public private(set) var selectedRuleIDs: Set<RuleID>

    public init(candidates: [ScanCandidate], selectedRuleIDs: Set<RuleID> = []) {
        self.candidates = candidates
        let available = Set(candidates.map(\.rule.id))
        self.selectedRuleIDs = selectedRuleIDs.intersection(available)
    }

    public var totalBytes: UInt64 {
        candidates.reduce(0) { $0 + $1.logicalBytes }
    }

    public var selectedBytes: UInt64 {
        candidates
            .filter { selectedRuleIDs.contains($0.rule.id) }
            .reduce(0) { $0 + $1.logicalBytes }
    }

    public var selectedCount: Int {
        selectedRuleIDs.count
    }

    public var productGroups: [AppProductGroup] {
        Dictionary(grouping: candidates, by: \.rule.appID)
            .map { AppProductGroup(appID: $0.key, candidates: $0.value) }
            .sorted {
                if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
                return $0.appID.localizedStandardCompare($1.appID) == .orderedAscending
            }
    }

    public mutating func setSelected(_ ruleID: RuleID, selected: Bool) {
        guard candidates.contains(where: { $0.rule.id == ruleID }) else { return }
        if selected {
            selectedRuleIDs.insert(ruleID)
        } else {
            selectedRuleIDs.remove(ruleID)
        }
    }

    public mutating func setSelected(_ ruleIDs: [RuleID], selected: Bool) {
        let available = Set(candidates.map(\.rule.id))
        let requested = Set(ruleIDs).intersection(available)
        if selected {
            selectedRuleIDs.formUnion(requested)
        } else {
            selectedRuleIDs.subtract(requested)
        }
    }

    public mutating func selectRecommended() {
        selectedRuleIDs = Set(candidates.lazy.filter(Self.isPlanEligible).map(\.rule.id))
    }

    public mutating func clearSelection() {
        selectedRuleIDs.removeAll()
    }

    private static func isPlanEligible(_ candidate: ScanCandidate) -> Bool {
        candidate.safety == .verifiedSafe
            && candidate.rule.risk == .a
            && candidate.rule.category == .regenerableCache
            && candidate.rule.action == .trash
    }
}

public struct AppProductGroup: Identifiable, Equatable, Sendable {
    public let appID: String
    public let candidates: [ScanCandidate]

    public var id: String { appID }

    public var totalBytes: UInt64 {
        candidates.reduce(0) { $0 + $1.logicalBytes }
    }

    public init(appID: String, candidates: [ScanCandidate]) {
        self.appID = appID
        self.candidates = candidates.sorted { $0.rule.id.rawValue < $1.rule.id.rawValue }
    }
}
