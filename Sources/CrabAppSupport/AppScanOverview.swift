import CrabCore
import Foundation

public struct AppScanOverview: Equatable, Sendable {
    public let products: [AppProductScanSummary]

    public init(products: [AppProductScanSummary] = []) {
        self.products = products
    }

    public init(
        rules: [AIFileRule],
        result: AppScanResult,
        installedAppIDs: Set<String>
    ) {
        let installedRules = rules.filter { installedAppIDs.contains($0.appID) }
        let installedCandidates = result.candidates.filter { installedAppIDs.contains($0.rule.appID) }
        let rulesByApp = Dictionary(grouping: installedRules, by: \.appID)
        let candidatesByApp = Dictionary(grouping: installedCandidates, by: \.rule.appID)
        let ruleToApp = Dictionary(uniqueKeysWithValues: installedRules.map { ($0.id, $0.appID) })
        let skippedByApp = Dictionary(grouping: result.skippedRuleIDs.compactMap { ruleID -> (String, RuleID)? in
            guard let appID = ruleToApp[ruleID] else { return nil }
            return (appID, ruleID)
        }, by: \.0)
        let issuesByApp = Dictionary(grouping: result.issues.compactMap { issue -> (String, AppScanIssue)? in
            guard let appID = ruleToApp[issue.ruleID] else { return nil }
            return (appID, issue)
        }, by: \.0)

        let appIDs = installedAppIDs
            .union(rulesByApp.keys)
            .union(candidatesByApp.keys)
        products = appIDs.map { appID in
            let appRules = rulesByApp[appID] ?? []
            let candidates = candidatesByApp[appID] ?? []
            let skippedCount = skippedByApp[appID]?.count ?? 0
            let issueCount = issuesByApp[appID]?.count ?? 0
            let accountedRuleIDs = Set(candidates.map(\.rule.id))
                .union(skippedByApp[appID]?.map(\.1) ?? [])
                .union(issuesByApp[appID]?.map { $0.1.ruleID } ?? [])
            let unaccountedRuleCount = max(0, appRules.count - accountedRuleIDs.count)

            return AppProductScanSummary(
                appID: appID,
                candidates: candidates,
                configuredRuleCount: appRules.count,
                skippedRuleCount: skippedCount,
                issueCount: issueCount + unaccountedRuleCount
            )
        }
        .sorted {
            if $0.sortRank != $1.sortRank { return $0.sortRank < $1.sortRank }
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            return $0.appID.localizedStandardCompare($1.appID) == .orderedAscending
        }
    }

    public var productsWithCacheCount: Int {
        products.count { !$0.candidates.isEmpty }
    }

    public var cleanProductCount: Int {
        products.count { $0.status == .clean }
    }

    public var limitedProductCount: Int {
        products.count { $0.status == .limited }
    }

    public var protectedProductCount: Int {
        products.count { $0.status == .protected }
    }
}

public struct AppProductScanSummary: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case hasCache
        case clean
        case limited
        case protected
    }

    public let appID: String
    public let candidates: [ScanCandidate]
    public let configuredRuleCount: Int
    public let skippedRuleCount: Int
    public let issueCount: Int

    public init(
        appID: String,
        candidates: [ScanCandidate],
        configuredRuleCount: Int,
        skippedRuleCount: Int,
        issueCount: Int
    ) {
        self.appID = appID
        self.candidates = candidates
        self.configuredRuleCount = configuredRuleCount
        self.skippedRuleCount = skippedRuleCount
        self.issueCount = issueCount
    }

    public var id: String { appID }

    public var status: Status {
        if configuredRuleCount == 0 { return .protected }
        if issueCount > 0 { return .limited }
        if candidates.isEmpty { return .clean }
        return .hasCache
    }

    public var totalBytes: UInt64 {
        candidates.reduce(0) { $0 + $1.logicalBytes }
    }

    fileprivate var sortRank: Int {
        switch status {
        case .hasCache: 0
        case .limited: 1
        case .clean: 2
        case .protected: 3
        }
    }
}

public enum AppProductScanFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case cleanable
    case clean
    case protectedData

    public var id: Self { self }

    public func products(in products: [AppProductScanSummary]) -> [AppProductScanSummary] {
        products.filter(matches)
    }

    public func matches(_ product: AppProductScanSummary) -> Bool {
        switch self {
        case .all:
            true
        case .cleanable:
            product.status == .hasCache
        case .clean:
            product.status == .clean
        case .protectedData:
            product.status == .limited || product.status == .protected
        }
    }
}
