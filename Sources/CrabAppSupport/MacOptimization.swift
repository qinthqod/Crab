import Foundation

public enum MacOptimizationTaskID: String, CaseIterable, Equatable, Sendable {
    case quickLook
    case launchServices
    case finder
    case dock
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
    static let mountedDiskImageProbe = MaintenanceCommand(
        executablePath: "/usr/bin/hdiutil",
        arguments: ["info", "-plist"],
        timeoutSeconds: 8
    )

    public static let automaticTasks: [MacOptimizationTask] = [
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
    ]

    public static let optionalTasks: [MacOptimizationTask] = [
        MacOptimizationTask(
            id: .finder,
            command: MaintenanceCommand(
                executablePath: "/usr/bin/killall",
                arguments: ["-HUP", "Finder"],
                timeoutSeconds: 5
            )
        ),
        MacOptimizationTask(
            id: .dock,
            command: MaintenanceCommand(
                executablePath: "/usr/bin/killall",
                arguments: ["-HUP", "Dock"],
                timeoutSeconds: 5
            )
        ),
    ]

    public static let allTasks = automaticTasks + optionalTasks
    public static let defaultTasks = automaticTasks

    static var reviewedCommands: [MaintenanceCommand] {
        allTasks.map(\.command) + [mountedDiskImageProbe]
    }
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
        ReviewedSystemCommandExecutor.execute(command).status
    }
}

public protocol MountedDiskImageDataProviding: Sendable {
    func mountedDiskImageData() -> Data?
}

public final class SystemMountedDiskImageDataProvider: MountedDiskImageDataProviding, @unchecked Sendable {
    public init() {}

    public func mountedDiskImageData() -> Data? {
        let result = ReviewedSystemCommandExecutor.execute(
            MacOptimizationCatalog.mountedDiskImageProbe,
            capturesOutput: true
        )
        guard result.status == .succeeded else { return nil }
        return result.output
    }
}

private struct ReviewedSystemCommandResult {
    let status: MaintenanceCommandStatus
    let output: Data?
}

private final class CommandOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?

    func store(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func load() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class SendablePipe: @unchecked Sendable {
    let pipe = Pipe()
}

private enum ReviewedSystemCommandExecutor {
    private static let maximumCapturedBytes = 2 * 1_024 * 1_024

    static func execute(
        _ command: MaintenanceCommand,
        capturesOutput: Bool = false
    ) -> ReviewedSystemCommandResult {
        guard MacOptimizationCatalog.reviewedCommands.contains(command),
              !command.requiresAdministrator,
              FileManager.default.isExecutableFile(atPath: command.executablePath)
        else {
            return ReviewedSystemCommandResult(status: .unavailable, output: nil)
        }

        // This is the only process-launch boundary for Mac Optimization. The
        // executable and arguments come exclusively from the reviewed catalog.
        // No shell is involved and no user-provided value can reach Process.
        // Apple Foundation Process reference:
        // https://developer.apple.com/documentation/foundation/process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        let outputPipe = capturesOutput ? SendablePipe() : nil
        process.standardOutput = outputPipe?.pipe ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let didExit = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in didExit.signal() }

        do {
            try process.run()
        } catch {
            return ReviewedSystemCommandResult(status: .failed(-1), output: nil)
        }

        let outputBox = CommandOutputBox()
        let didReadOutput = DispatchSemaphore(value: 0)
        if let outputPipe {
            DispatchQueue.global(qos: .utility).async {
                outputBox.store(outputPipe.pipe.fileHandleForReading.readDataToEndOfFile())
                didReadOutput.signal()
            }
        }

        let deadline = DispatchTime.now() + command.timeoutSeconds
        guard didExit.wait(timeout: deadline) == .success else {
            // terminate() applies only to the maintenance child Crab launched.
            // Crab never sends a PID-based signal to an arbitrary user process.
            if process.isRunning { process.terminate() }
            _ = didExit.wait(timeout: .now() + 1)
            outputPipe?.pipe.fileHandleForReading.closeFile()
            return ReviewedSystemCommandResult(status: .timedOut, output: nil)
        }

        if outputPipe != nil,
           didReadOutput.wait(timeout: .now() + 1) != .success {
            outputPipe?.pipe.fileHandleForReading.closeFile()
            return ReviewedSystemCommandResult(status: .failed(-1), output: nil)
        }

        let output = outputBox.load()
        guard output?.count ?? 0 <= maximumCapturedBytes else {
            return ReviewedSystemCommandResult(status: .failed(-1), output: nil)
        }
        let status: MaintenanceCommandStatus = process.terminationStatus == 0
            ? .succeeded
            : .failed(process.terminationStatus)
        return ReviewedSystemCommandResult(status: status, output: output)
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
        guard MacOptimizationCatalog.allTasks.contains(task) else {
            return MacOptimizationResult(taskID: task.id, outcome: .unavailable)
        }
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

    public func runOptional(_ taskID: MacOptimizationTaskID) -> MacOptimizationResult? {
        guard let task = MacOptimizationCatalog.optionalTasks.first(where: { $0.id == taskID }) else {
            return nil
        }
        return run(task)
    }
}
