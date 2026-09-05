import Foundation

/// Serializes disk-heavy read jobs off the UI actor and forwards cancellation to the worker.
public enum ScanWorker {
    private static let diskLock = NSLock()

    public static func run<Value: Sendable>(
        priority: TaskPriority = .utility,
        _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
        let worker = Task.detached(priority: priority) {
            diskLock.withLock { operation() }
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
