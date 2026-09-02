import CrabCore
import Foundation

public struct CacheWorkflowState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase
    public private(set) var snapshot: AppScanSnapshot
    public private(set) var issueCount: Int

    public init() {
        phase = .idle
        snapshot = AppScanSnapshot(candidates: [])
        issueCount = 0
    }

    public mutating func beginScan() {
        snapshot = AppScanSnapshot(candidates: [])
        issueCount = 0
        phase = .loading
    }

    public mutating func finish(snapshot: AppScanSnapshot, issueCount: Int) {
        guard phase == .loading else { return }
        self.snapshot = snapshot
        self.issueCount = max(0, issueCount)
        phase = .ready
    }

    public mutating func fail(message: String) {
        snapshot = AppScanSnapshot(candidates: [])
        issueCount = 0
        phase = .failed(message)
    }

    public mutating func setSelected(_ ruleID: RuleID, selected: Bool) {
        snapshot.setSelected(ruleID, selected: selected)
    }

    public mutating func setSelected(_ ruleIDs: [RuleID], selected: Bool) {
        snapshot.setSelected(ruleIDs, selected: selected)
    }

    public mutating func selectRecommended() {
        snapshot.selectRecommended()
    }

    public mutating func returnHome() {
        snapshot = AppScanSnapshot(candidates: [])
        issueCount = 0
        phase = .idle
    }
}
