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
