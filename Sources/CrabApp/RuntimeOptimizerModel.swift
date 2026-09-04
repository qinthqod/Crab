import CrabAppSupport
import Foundation

@MainActor
final class RuntimeOptimizerModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running(taskID: MacOptimizationTaskID, completed: Int, total: Int)
        case finished([MacOptimizationResult])
    }

    @Published private(set) var state: State = .idle

    private let optimizer: MacOptimizer
    private var generation = UUID()

    init(commandRunner: any MaintenanceCommandRunning = SystemMaintenanceCommandRunner()) {
        optimizer = MacOptimizer(commandRunner: commandRunner)
    }

    func start() {
        if case .running = state { return }
        let generation = UUID()
        self.generation = generation
        let tasks = optimizer.tasks
        guard let firstTask = tasks.first else {
            state = .finished([])
            return
        }
        state = .running(taskID: firstTask.id, completed: 0, total: tasks.count)
        let optimizer = self.optimizer

        Task {
            var results: [MacOptimizationResult] = []
            for (index, task) in tasks.enumerated() {
                guard self.generation == generation else { return }
                state = .running(taskID: task.id, completed: index, total: tasks.count)

                let result = await Task.detached(priority: .userInitiated) {
                    optimizer.run(task)
                }.value
                results.append(result)
            }

            guard self.generation == generation else { return }
            state = .finished(results)
        }
    }

    func returnHome() {
        guard case .running = state else {
            generation = UUID()
            state = .idle
            return
        }
    }
}
