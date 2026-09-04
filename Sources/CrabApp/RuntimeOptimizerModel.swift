import CrabAppSupport
import Foundation

@MainActor
final class RuntimeOptimizerModel: ObservableObject {
    enum RunningStep: Equatable {
        case diagnosis
        case maintenance(MacOptimizationTaskID)
    }

    enum State: Equatable {
        case idle
        case running(step: RunningStep, completed: Int, total: Int)
        case finished(RuntimeOptimizationReport)
    }

    enum ActionFeedback: Equatable {
        case refresh(MacOptimizationTaskID, MacOptimizationOutcome)
        case eject(URL, MountedDiskImageEjectOutcome)
    }

    enum ActionState: Equatable {
        case idle
        case refreshing(MacOptimizationTaskID)
        case ejecting(URL)
        case completed(ActionFeedback)

        var isRunning: Bool {
            switch self {
            case .refreshing, .ejecting: true
            case .idle, .completed: false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var actionState: ActionState = .idle

    private let diagnoser: any MacRuntimeDiagnosing
    private let optimizer: MacOptimizer
    private let diskImageEjector: any MountedDiskImageEjecting
    private var generation = UUID()

    init(
        diagnoser: any MacRuntimeDiagnosing = MacRuntimeDiagnoser(),
        commandRunner: any MaintenanceCommandRunning = SystemMaintenanceCommandRunner(),
        diskImageEjector: any MountedDiskImageEjecting = MountedDiskImageEjector()
    ) {
        self.diagnoser = diagnoser
        optimizer = MacOptimizer(commandRunner: commandRunner)
        self.diskImageEjector = diskImageEjector
    }

    func start() {
        if case .running = state { return }
        let generation = UUID()
        self.generation = generation
        actionState = .idle

        let tasks = optimizer.tasks
        let total = tasks.count + 1
        state = .running(step: .diagnosis, completed: 0, total: total)
        let diagnoser = self.diagnoser
        let optimizer = self.optimizer

        Task {
            let diagnosis = await Task.detached(priority: .userInitiated) {
                diagnoser.diagnose()
            }.value
            guard self.generation == generation else { return }

            var results: [MacOptimizationResult] = []
            for (index, task) in tasks.enumerated() {
                state = .running(
                    step: .maintenance(task.id),
                    completed: index + 1,
                    total: total
                )
                let result = await Task.detached(priority: .utility) {
                    optimizer.run(task)
                }.value
                guard self.generation == generation else { return }
                results.append(result)
            }

            state = .finished(RuntimeOptimizationReport(
                diagnosis: diagnosis,
                automaticResults: results
            ))
        }
    }

    func runOptional(_ taskID: MacOptimizationTaskID) {
        guard case .finished = state,
              !actionState.isRunning,
              MacOptimizationCatalog.optionalTasks.contains(where: { $0.id == taskID })
        else { return }

        let generation = self.generation
        let optimizer = self.optimizer
        actionState = .refreshing(taskID)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                optimizer.runOptional(taskID)
            }.value
            guard self.generation == generation,
                  let result,
                  case var .finished(report) = state
            else { return }

            report.recordOptionalResult(result)
            state = .finished(report)
            actionState = .completed(.refresh(taskID, result.outcome))
        }
    }

    func eject(_ image: MountedDiskImage) {
        guard case .finished = state, !actionState.isRunning else { return }

        let generation = self.generation
        let ejector = diskImageEjector
        actionState = .ejecting(image.id)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                ejector.eject(image)
            }.value
            guard self.generation == generation,
                  case var .finished(report) = state
            else { return }

            if outcome == .ejected {
                report.recordEjectedImage(image)
                state = .finished(report)
            }
            actionState = .completed(.eject(image.id, outcome))
        }
    }

    func returnHome() {
        guard case .running = state else {
            generation = UUID()
            actionState = .idle
            state = .idle
            return
        }
    }
}
