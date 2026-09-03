import Darwin
import Foundation

public struct ProcessResourceSample: Equatable, Sendable {
    public let processIdentifier: Int32
    public let parentProcessIdentifier: Int32
    public let residentBytes: UInt64

    public init(
        processIdentifier: Int32,
        parentProcessIdentifier: Int32,
        residentBytes: UInt64
    ) {
        self.processIdentifier = processIdentifier
        self.parentProcessIdentifier = parentProcessIdentifier
        self.residentBytes = residentBytes
    }
}

public struct RunningAIApplicationSeed: Equatable, Sendable {
    public let appID: String
    public let displayName: String
    public let processIdentifier: Int32
    public let launchedAt: Date?

    public init(
        appID: String,
        displayName: String,
        processIdentifier: Int32,
        launchedAt: Date?
    ) {
        self.appID = appID
        self.displayName = displayName
        self.processIdentifier = processIdentifier
        self.launchedAt = launchedAt
    }
}

public struct RunningAIApplication: Identifiable, Equatable, Sendable {
    public let appID: String
    public let displayName: String
    public let processIdentifiers: Set<Int32>
    public let residentBytes: UInt64
    public let launchedAt: Date?

    public var id: String { appID }

    public init(
        appID: String,
        displayName: String,
        processIdentifiers: Set<Int32>,
        residentBytes: UInt64,
        launchedAt: Date?
    ) {
        self.appID = appID
        self.displayName = displayName
        self.processIdentifiers = processIdentifiers
        self.residentBytes = residentBytes
        self.launchedAt = launchedAt
    }
}

public struct AIOptimizationSnapshot: Equatable, Sendable {
    public let applications: [RunningAIApplication]
    public let capturedAt: Date

    public init(applications: [RunningAIApplication] = [], capturedAt: Date = Date()) {
        self.applications = applications.sorted {
            if $0.residentBytes != $1.residentBytes {
                return $0.residentBytes > $1.residentBytes
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        self.capturedAt = capturedAt
    }

    public var totalResidentBytes: UInt64 {
        applications.reduce(0) { partial, application in
            partial.addingReportingOverflow(application.residentBytes).overflow
                ? UInt64.max
                : partial + application.residentBytes
        }
    }
}

public struct AIOptimizationSnapshotBuilder: Sendable {
    public init() {}

    public func build(
        applications: [RunningAIApplicationSeed],
        processes: [ProcessResourceSample],
        capturedAt: Date = Date()
    ) -> AIOptimizationSnapshot {
        let processByID = Dictionary(uniqueKeysWithValues: processes.map {
            ($0.processIdentifier, $0)
        })
        let childrenByParent = Dictionary(grouping: processes, by: \.parentProcessIdentifier)
        let groupedApplications = Dictionary(grouping: applications, by: \.appID)

        let results = groupedApplications.compactMap { appID, seeds -> RunningAIApplication? in
            guard let first = seeds.first else { return nil }
            let roots = Set(seeds.map(\.processIdentifier))
            var visited = Set<Int32>()
            var queue = Array(roots)
            var index = 0

            while index < queue.count {
                let processID = queue[index]
                index += 1
                guard visited.insert(processID).inserted else { continue }
                for child in childrenByParent[processID, default: []] {
                    queue.append(child.processIdentifier)
                }
            }

            let residentBytes = visited.reduce(UInt64(0)) { partial, processID in
                let bytes = processByID[processID]?.residentBytes ?? 0
                return partial.addingReportingOverflow(bytes).overflow ? UInt64.max : partial + bytes
            }
            return RunningAIApplication(
                appID: appID,
                displayName: first.displayName,
                processIdentifiers: roots,
                residentBytes: residentBytes,
                launchedAt: seeds.compactMap(\.launchedAt).min()
            )
        }
        return AIOptimizationSnapshot(applications: results, capturedAt: capturedAt)
    }
}

public struct AIOptimizationSelection: Equatable, Sendable {
    public private(set) var selectedAppIDs: Set<String>
    private let availableAppIDs: Set<String>

    public init(snapshot: AIOptimizationSnapshot) {
        selectedAppIDs = []
        availableAppIDs = Set(snapshot.applications.map(\.appID))
    }

    public mutating func setSelected(_ appID: String, selected: Bool) {
        guard availableAppIDs.contains(appID) else { return }
        if selected {
            selectedAppIDs.insert(appID)
        } else {
            selectedAppIDs.remove(appID)
        }
    }
}

public struct AIOptimizationTarget: Equatable, Sendable {
    public let appID: String
    public let displayName: String
    public let processIdentifiers: Set<Int32>
    public let estimatedResidentBytes: UInt64
}

public struct AIOptimizationPlan: Equatable, Sendable {
    public let targets: [AIOptimizationTarget]
    public let expiresAt: Date
}

public enum AIOptimizationError: Error, Equatable, CustomStringConvertible {
    case unknownApplication(String)
    case expiredPlan

    public var description: String {
        switch self {
        case let .unknownApplication(appID):
            "The optimization selection contains an unknown application: \(appID)."
        case .expiredPlan:
            "The running-application snapshot expired. Refresh before optimizing."
        }
    }
}

public struct AIOptimizationPlanBuilder: Sendable {
    public init() {}

    public func build(
        snapshot: AIOptimizationSnapshot,
        selectedAppIDs: Set<String>,
        now: Date = Date()
    ) throws -> AIOptimizationPlan {
        let available = Dictionary(uniqueKeysWithValues: snapshot.applications.map { ($0.appID, $0) })
        let unknown = selectedAppIDs.subtracting(available.keys)
        if let appID = unknown.sorted().first {
            throw AIOptimizationError.unknownApplication(appID)
        }
        let targets = snapshot.applications.compactMap { application -> AIOptimizationTarget? in
            guard selectedAppIDs.contains(application.appID) else { return nil }
            return AIOptimizationTarget(
                appID: application.appID,
                displayName: application.displayName,
                processIdentifiers: application.processIdentifiers,
                estimatedResidentBytes: application.residentBytes
            )
        }
        return AIOptimizationPlan(targets: targets, expiresAt: now.addingTimeInterval(30))
    }
}

public protocol AIApplicationTerminationControlling: AnyObject {
    func runningProcessIdentifiers(for appID: String) -> Set<Int32>?
    func requestGracefulTermination(appID: String, processIdentifiers: Set<Int32>) -> Bool
}

public struct AIOptimizationReceipt: Equatable, Sendable {
    public let requestedAppIDs: Set<String>
    public let skippedAppIDs: Set<String>
    public let estimatedResidentBytes: UInt64
}

public struct AIOptimizationExecutor {
    private let controller: AIApplicationTerminationControlling

    public init(controller: AIApplicationTerminationControlling) {
        self.controller = controller
    }

    public func execute(plan: AIOptimizationPlan, now: Date = Date()) throws -> AIOptimizationReceipt {
        guard now <= plan.expiresAt else { throw AIOptimizationError.expiredPlan }
        var requested = Set<String>()
        var skipped = Set<String>()
        var estimatedBytes: UInt64 = 0

        for target in plan.targets {
            guard let running = controller.runningProcessIdentifiers(for: target.appID),
                  target.processIdentifiers.isSubset(of: running),
                  controller.requestGracefulTermination(
                    appID: target.appID,
                    processIdentifiers: target.processIdentifiers
                  )
            else {
                skipped.insert(target.appID)
                continue
            }
            requested.insert(target.appID)
            estimatedBytes = estimatedBytes.addingReportingOverflow(target.estimatedResidentBytes).overflow
                ? UInt64.max
                : estimatedBytes + target.estimatedResidentBytes
        }

        return AIOptimizationReceipt(
            requestedAppIDs: requested,
            skippedAppIDs: skipped,
            estimatedResidentBytes: estimatedBytes
        )
    }
}

public enum SystemProcessResourceSamplingError: Error, CustomStringConvertible {
    case unavailable

    public var description: String {
        "Crab could not read the current process memory snapshot."
    }
}

public struct SystemProcessResourceSampler: Sendable {
    public init() {}

    public func sample() throws -> [ProcessResourceSample] {
        let expectedCount = max(Int(proc_listallpids(nil, 0)), 0)
        guard expectedCount > 0 else { throw SystemProcessResourceSamplingError.unavailable }
        var processIdentifiers = [pid_t](repeating: 0, count: expectedCount + 128)
        let count = processIdentifiers.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { throw SystemProcessResourceSamplingError.unavailable }

        return processIdentifiers.prefix(Int(count)).compactMap { processIdentifier in
            guard processIdentifier > 0 else { return nil }
            var bsdInfo = proc_bsdinfo()
            let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(
                processIdentifier,
                PROC_PIDTBSDINFO,
                0,
                &bsdInfo,
                bsdInfoSize
            ) == bsdInfoSize else { return nil }

            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(
                processIdentifier,
                PROC_PIDTASKINFO,
                0,
                &taskInfo,
                taskInfoSize
            ) == taskInfoSize else { return nil }

            return ProcessResourceSample(
                processIdentifier: processIdentifier,
                parentProcessIdentifier: Int32(bsdInfo.pbi_ppid),
                residentBytes: taskInfo.pti_resident_size
            )
        }
    }
}
