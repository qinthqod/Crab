import AppKit
import CrabAppSupport
import Foundation

private enum AIOptimizationSnapshotWorkResult: Sendable {
    case success(AIOptimizationSnapshot)
    case failure(String)
}

@MainActor
final class RuntimeOptimizerModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot = AIOptimizationSnapshot()

    private var generation = UUID()

    func refresh(force: Bool = false) {
        if !force, state == .loading { return }
        let generation = UUID()
        self.generation = generation
        state = .loading
        snapshot = AIOptimizationSnapshot()
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
                state = .ready
            case let .failure(message):
                state = .failed(CrabL10n.language == .simplifiedChinese
                    ? "Crab 无法读取当前进程的内存快照。"
                    : message)
            }
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
