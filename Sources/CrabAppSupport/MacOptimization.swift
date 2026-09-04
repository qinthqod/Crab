import Foundation

public enum MacOptimizationTaskID: String, CaseIterable, Equatable, Sendable {
    case quickLook
    case launchServices
    case finder
}

public struct MaintenanceCommand: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let timeoutSeconds: TimeInterval
    public let requiresAdministrator: Bool

    public init(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval,
        requiresAdministrator: Bool = false
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.requiresAdministrator = requiresAdministrator
    }
}

public struct MacOptimizationTask: Equatable, Sendable {
    public let id: MacOptimizationTaskID
    public let command: MaintenanceCommand

    public init(id: MacOptimizationTaskID, command: MaintenanceCommand) {
        self.id = id
        self.command = command
    }
}

public enum MacOptimizationCatalog {
    public static let defaultTasks: [MacOptimizationTask] = [
        MacOptimizationTask(
            id: .quickLook,
            command: MaintenanceCommand(
                executablePath: "/usr/bin/qlmanage",
                arguments: ["-r"],
                timeoutSeconds: 10
            )
        ),
        MacOptimizationTask(
            id: .launchServices,
            command: MaintenanceCommand(
                executablePath: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister",
                arguments: ["-gc"],
                timeoutSeconds: 20
            )
        ),
        MacOptimizationTask(
            id: .finder,
            command: MaintenanceCommand(
                executablePath: "/usr/bin/killall",
                arguments: ["-HUP", "Finder"],
                timeoutSeconds: 5
            )
        ),
    ]
}

public enum MaintenanceCommandStatus: Equatable, Sendable {
    case succeeded
    case failed(Int32)
    case unavailable
    case timedOut
}

public protocol MaintenanceCommandRunning: Sendable {
    func run(_ command: MaintenanceCommand) -> MaintenanceCommandStatus
}

public final class SystemMaintenanceCommandRunner: MaintenanceCommandRunning, @unchecked Sendable {
    public init() {}

    public func run(_ command: MaintenanceCommand) -> MaintenanceCommandStatus {
        guard MacOptimizationCatalog.defaultTasks.contains(where: { $0.command == command }),
              !command.requiresAdministrator,
              FileManager.default.isExecutableFile(atPath: command.executablePath)
        else { return .unavailable }

        // This is the only process-launch boundary for Mac Optimization. The
        // executable and arguments come exclusively from MacOptimizationCatalog.
        // No shell is involved and no user-provided value can reach Process.
        // Apple Foundation Process reference:
        // https://developer.apple.com/documentation/foundation/process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let didExit = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in didExit.signal() }

        do {
            try process.run()
        } catch {
            return .failed(-1)
        }

        let deadline = DispatchTime.now() + command.timeoutSeconds
        guard didExit.wait(timeout: deadline) == .success else {
            // terminate() applies only to the maintenance child Crab launched.
            // Crab never sends a PID-based signal to an arbitrary user process.
            if process.isRunning { process.terminate() }
            return .timedOut
        }
        return process.terminationStatus == 0 ? .succeeded : .failed(process.terminationStatus)
    }
}

public enum MacOptimizationOutcome: Equatable, Sendable {
    case applied
    case failed
    case unavailable
}

public struct MacOptimizationResult: Identifiable, Equatable, Sendable {
    public let taskID: MacOptimizationTaskID
    public let outcome: MacOptimizationOutcome

    public var id: MacOptimizationTaskID { taskID }

    public init(taskID: MacOptimizationTaskID, outcome: MacOptimizationOutcome) {
        self.taskID = taskID
        self.outcome = outcome
    }
}

public struct MacOptimizer: Sendable {
    private let commandRunner: any MaintenanceCommandRunning
    public let tasks: [MacOptimizationTask]

    public init(
        commandRunner: any MaintenanceCommandRunning = SystemMaintenanceCommandRunner()
    ) {
        self.commandRunner = commandRunner
        tasks = MacOptimizationCatalog.defaultTasks
    }

    public func run() -> [MacOptimizationResult] {
        tasks.map(run)
    }

    public func run(_ task: MacOptimizationTask) -> MacOptimizationResult {
        let outcome: MacOptimizationOutcome
        switch commandRunner.run(task.command) {
        case .succeeded:
            outcome = .applied
        case .unavailable:
            outcome = .unavailable
        case .failed, .timedOut:
            outcome = .failed
        }
        return MacOptimizationResult(taskID: task.id, outcome: outcome)
    }
}
