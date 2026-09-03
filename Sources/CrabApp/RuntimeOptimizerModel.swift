import AppKit
import CrabAppSupport
import Foundation

private enum AIOptimizationSnapshotWorkResult: Sendable {
    case success(AIOptimizationSnapshot)
    case failure(String)
}

private final class SystemAIApplicationTerminator: AIApplicationTerminationControlling {
    func runningProcessIdentifiers(for appID: String) -> Set<Int32>? {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: appID).map(\.processIdentifier))
    }

    func requestGracefulTermination(appID: String, processIdentifiers: Set<Int32>) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: appID)
            .filter { processIdentifiers.contains($0.processIdentifier) }
        guard Set(running.map(\.processIdentifier)) == processIdentifiers else { return false }
        return running.map { $0.terminate() }.allSatisfy { $0 }
    }
}

@MainActor
final class RuntimeOptimizerModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case optimizing
        case failed(String)
    }

    enum Result: Equatable {
        case succeeded(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot = AIOptimizationSnapshot()
    @Published private(set) var selection = AIOptimizationSelection(
        snapshot: AIOptimizationSnapshot()
    )
    @Published private(set) var result: Result?

    private var generation = UUID()

    func refresh(force: Bool = false) {
        if !force, state == .loading || state == .optimizing { return }
        let generation = UUID()
        self.generation = generation
        state = .loading
        snapshot = AIOptimizationSnapshot()
        selection = AIOptimizationSelection(snapshot: snapshot)
        let seeds = runningAIApplicationSeeds()

        Task {
            let work = await Task.detached(priority: .userInitiated) {
                do {
                    let processes = try SystemProcessResourceSampler().sample()
                    return AIOptimizationSnapshotWorkResult.success(
                        AIOptimizationSnapshotBuilder().build(
                            applications: seeds,
                            processes: processes
                        )
                    )
                } catch {
                    return AIOptimizationSnapshotWorkResult.failure(String(describing: error))
                }
            }.value

            guard self.generation == generation else { return }
            switch work {
            case let .success(snapshot):
                self.snapshot = snapshot
                selection = AIOptimizationSelection(snapshot: snapshot)
                state = .ready
            case let .failure(message):
                state = .failed(CrabL10n.language == .simplifiedChinese
                    ? "Crab 无法读取当前进程的内存快照。"
                    : message)
            }
        }
    }

    func setSelected(_ appID: String, selected: Bool) {
        guard state == .ready else { return }
        selection.setSelected(appID, selected: selected)
    }

    func setAllSelected(_ selected: Bool) {
        guard state == .ready else { return }
        for application in snapshot.applications {
            selection.setSelected(application.appID, selected: selected)
        }
    }

    var selectedApplications: [RunningAIApplication] {
        snapshot.applications.filter { selection.selectedAppIDs.contains($0.appID) }
    }

    var selectedBytes: UInt64 {
        selectedApplications.reduce(0) { partial, application in
            partial.addingReportingOverflow(application.residentBytes).overflow
                ? UInt64.max
                : partial + application.residentBytes
        }
    }

    func optimizeSelectedApplications() {
        guard state == .ready, !selection.selectedAppIDs.isEmpty else { return }
        do {
            let plan = try AIOptimizationPlanBuilder().build(
                snapshot: snapshot,
                selectedAppIDs: selection.selectedAppIDs
            )
            state = .optimizing
            let receipt = try AIOptimizationExecutor(
                controller: SystemAIApplicationTerminator()
            ).execute(plan: plan)
            if receipt.requestedAppIDs.isEmpty {
                result = .failed(CrabL10n.text(
                    "所选应用的运行状态已经变化，Crab 没有发送退出请求。已为你重新读取。",
                    "The selected apps changed while you were reviewing them. Crab sent no quit requests and refreshed the list."
                ))
            } else {
                result = .succeeded(resultMessage(receipt))
            }
            state = .ready
            selection = AIOptimizationSelection(snapshot: snapshot)
            scheduleRefresh()
        } catch {
            result = .failed(CrabL10n.language == .simplifiedChinese
                ? "优化未执行：\(error)"
                : "Optimization was not performed: \(error)")
            state = .ready
        }
    }

    func dismissResult() {
        result = nil
    }

    private func resultMessage(_ receipt: AIOptimizationReceipt) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(min(receipt.estimatedResidentBytes, UInt64(Int64.max))),
            countStyle: .memory
        )
        var message = CrabL10n.format(
            "已向 %d 个应用发送标准退出请求，预计占用 %@。应用可能会先询问是否保存内容。",
            "Sent standard quit requests to %d apps holding about %@. Apps may ask you to save first.",
            receipt.requestedAppIDs.count,
            size
        )
        if !receipt.skippedAppIDs.isEmpty {
            message += CrabL10n.format(
                " %d 个应用因运行状态变化而跳过。",
                " %d apps were skipped because their running state changed.",
                receipt.skippedAppIDs.count
            )
        }
        return message
    }

    private func scheduleRefresh() {
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            refresh(force: true)
        }
    }

    private func runningAIApplicationSeeds() -> [RunningAIApplicationSeed] {
        let supported = Dictionary(uniqueKeysWithValues: HarnessCatalog.supported
            .filter { !$0.bundleNames.isEmpty }
            .map { ($0.appID, $0) })
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.processIdentifier != ownPID,
                  let appID = application.bundleIdentifier,
                  let definition = supported[appID]
            else { return nil }
            return RunningAIApplicationSeed(
                appID: appID,
                displayName: definition.displayName,
                processIdentifier: application.processIdentifier,
                launchedAt: application.launchDate
            )
        }
    }
}
