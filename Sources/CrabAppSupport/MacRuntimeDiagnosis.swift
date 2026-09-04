import Darwin
import Foundation

public enum MacRuntimeHealthLevel: Int, Comparable, Equatable, Sendable {
    case healthy
    case attention
    case critical

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MacRuntimeMemoryPressure: Equatable, Sendable {
    case normal
    case warning
    case critical
    case unknown
}

public enum MacRuntimeThermalState: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public struct MacRuntimeProcessUsage: Identifiable, Equatable, Sendable {
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public var id: String { name }

    public init(name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.name = name
        self.cpuPercent = max(0, cpuPercent)
        self.memoryBytes = memoryBytes
    }
}

public struct MountedDiskImage: Identifiable, Equatable, Sendable {
    public let imageURL: URL
    public let mountURL: URL
    public let deviceIdentifier: String

    public var id: URL { mountURL }

    public init(imageURL: URL, mountURL: URL, deviceIdentifier: String) {
        self.imageURL = imageURL.standardizedFileURL
        self.mountURL = mountURL.standardizedFileURL
        self.deviceIdentifier = deviceIdentifier
    }
}

public struct MacRuntimeSnapshot: Equatable, Sendable {
    public let diskAvailableBytes: Int64
    public let diskTotalBytes: Int64
    public let memoryPressure: MacRuntimeMemoryPressure
    public let swapUsedBytes: UInt64
    public let uptime: TimeInterval
    public let thermalState: MacRuntimeThermalState
    public let processes: [MacRuntimeProcessUsage]
    public let mountedDiskImages: [MountedDiskImage]

    public init(
        diskAvailableBytes: Int64,
        diskTotalBytes: Int64,
        memoryPressure: MacRuntimeMemoryPressure,
        swapUsedBytes: UInt64,
        uptime: TimeInterval,
        thermalState: MacRuntimeThermalState,
        processes: [MacRuntimeProcessUsage],
        mountedDiskImages: [MountedDiskImage]
    ) {
        self.diskAvailableBytes = max(0, diskAvailableBytes)
        self.diskTotalBytes = max(0, diskTotalBytes)
        self.memoryPressure = memoryPressure
        self.swapUsedBytes = swapUsedBytes
        self.uptime = max(0, uptime)
        self.thermalState = thermalState
        self.processes = processes
        self.mountedDiskImages = mountedDiskImages
    }
}

public enum MacRuntimeFindingID: Equatable, Hashable, Sendable {
    case lowDiskSpace
    case memoryPressure
    case thermalPressure
    case longUptime
    case resourcePressure
}

public struct MacRuntimeFinding: Identifiable, Equatable, Sendable {
    public let id: MacRuntimeFindingID
    public let level: MacRuntimeHealthLevel

    public init(id: MacRuntimeFindingID, level: MacRuntimeHealthLevel) {
        self.id = id
        self.level = level
    }
}

public struct MacRuntimeDiagnosis: Equatable, Sendable {
    public let level: MacRuntimeHealthLevel
    public let snapshot: MacRuntimeSnapshot
    public let findings: [MacRuntimeFinding]
    public let resourceHeavyProcesses: [MacRuntimeProcessUsage]

    public init(
        level: MacRuntimeHealthLevel,
        snapshot: MacRuntimeSnapshot,
        findings: [MacRuntimeFinding],
        resourceHeavyProcesses: [MacRuntimeProcessUsage]
    ) {
        self.level = level
        self.snapshot = snapshot
        self.findings = findings
        self.resourceHeavyProcesses = resourceHeavyProcesses
    }
}

public enum MacRuntimeDiagnosisEvaluator {
    private static let criticalDiskBytes: Int64 = 5_000_000_000
    private static let warningDiskBytes: Int64 = 15_000_000_000
    private static let criticalDiskRatio = 0.05
    private static let warningDiskRatio = 0.10
    private static let longUptime: TimeInterval = 14 * 86_400
    private static let heavyProcessMemoryBytes: UInt64 = 2_000_000_000
    private static let heavyProcessCPUPercent = 25.0
    private static let maximumProcesses = 5

    public static func evaluate(_ snapshot: MacRuntimeSnapshot) -> MacRuntimeDiagnosis {
        var findings: [MacRuntimeFinding] = []

        if let level = diskFindingLevel(snapshot) {
            findings.append(MacRuntimeFinding(id: .lowDiskSpace, level: level))
        }
        switch snapshot.memoryPressure {
        case .warning:
            findings.append(MacRuntimeFinding(id: .memoryPressure, level: .attention))
        case .critical:
            findings.append(MacRuntimeFinding(id: .memoryPressure, level: .critical))
        case .normal, .unknown:
            break
        }
        switch snapshot.thermalState {
        case .fair:
            findings.append(MacRuntimeFinding(id: .thermalPressure, level: .attention))
        case .serious, .critical:
            findings.append(MacRuntimeFinding(id: .thermalPressure, level: .critical))
        case .nominal, .unknown:
            break
        }
        if snapshot.uptime >= longUptime {
            findings.append(MacRuntimeFinding(id: .longUptime, level: .attention))
        }

        let heavyProcesses = snapshot.processes
            .filter {
                $0.cpuPercent >= heavyProcessCPUPercent ||
                    $0.memoryBytes >= heavyProcessMemoryBytes
            }
            .sorted {
                if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
                if $0.memoryBytes != $1.memoryBytes { return $0.memoryBytes > $1.memoryBytes }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .prefix(maximumProcesses)

        if !heavyProcesses.isEmpty {
            findings.append(MacRuntimeFinding(id: .resourcePressure, level: .attention))
        }

        return MacRuntimeDiagnosis(
            level: findings.map(\.level).max() ?? .healthy,
            snapshot: snapshot,
            findings: findings,
            resourceHeavyProcesses: Array(heavyProcesses)
        )
    }

    private static func diskFindingLevel(_ snapshot: MacRuntimeSnapshot) -> MacRuntimeHealthLevel? {
        guard snapshot.diskTotalBytes > 0 else { return nil }
        let ratio = Double(snapshot.diskAvailableBytes) / Double(snapshot.diskTotalBytes)
        if snapshot.diskAvailableBytes < criticalDiskBytes || ratio < criticalDiskRatio {
            return .critical
        }
        if snapshot.diskAvailableBytes < warningDiskBytes || ratio < warningDiskRatio {
            return .attention
        }
        return nil
    }
}

public enum MountedDiskImageParser {
    public static func parse(_ data: Data) -> [MountedDiskImage] {
        guard
            let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = root as? [String: Any],
            let imageRecords = dictionary["images"] as? [[String: Any]]
        else { return [] }

        var imagesByMount: [String: MountedDiskImage] = [:]
        for imageRecord in imageRecords {
            guard
                let imagePath = imageRecord["image-path"] as? String,
                imagePath.hasPrefix("/"),
                let entities = imageRecord["system-entities"] as? [[String: Any]]
            else { continue }

            for entity in entities {
                guard
                    let mountPath = entity["mount-point"] as? String,
                    mountPath.hasPrefix("/Volumes/"),
                    let deviceIdentifier = entity["dev-entry"] as? String,
                    deviceIdentifier.hasPrefix("/dev/disk")
                else { continue }

                let image = MountedDiskImage(
                    imageURL: URL(fileURLWithPath: imagePath),
                    mountURL: URL(fileURLWithPath: mountPath, isDirectory: true),
                    deviceIdentifier: deviceIdentifier
                )
                imagesByMount[image.mountURL.path] = image
            }
        }
        return imagesByMount.values.sorted {
            $0.mountURL.lastPathComponent.localizedStandardCompare($1.mountURL.lastPathComponent) == .orderedAscending
        }
    }
}

public protocol MacRuntimeSnapshotCollecting: Sendable {
    func collect() -> MacRuntimeSnapshot
}

public protocol MacRuntimeDiagnosing: Sendable {
    func diagnose() -> MacRuntimeDiagnosis
}

public struct MacRuntimeDiagnoser: MacRuntimeDiagnosing {
    private let snapshotCollector: any MacRuntimeSnapshotCollecting

    public init(snapshotCollector: any MacRuntimeSnapshotCollecting = SystemMacRuntimeSnapshotCollector()) {
        self.snapshotCollector = snapshotCollector
    }

    public func diagnose() -> MacRuntimeDiagnosis {
        MacRuntimeDiagnosisEvaluator.evaluate(snapshotCollector.collect())
    }
}

public struct SystemMacRuntimeSnapshotCollector: MacRuntimeSnapshotCollecting {
    private static let maximumReportedProcesses = 20

    private let sampleInterval: TimeInterval
    private let maximumPIDCount: Int
    private let mountedDiskImageDataProvider: any MountedDiskImageDataProviding

    public init(
        sampleInterval: TimeInterval = 0.8,
        maximumPIDCount: Int = 4_096,
        mountedDiskImageDataProvider: any MountedDiskImageDataProviding = SystemMountedDiskImageDataProvider()
    ) {
        self.sampleInterval = min(max(sampleInterval, 0), 1)
        self.maximumPIDCount = min(max(maximumPIDCount, 1), 4_096)
        self.mountedDiskImageDataProvider = mountedDiskImageDataProvider
    }

    public func collect() -> MacRuntimeSnapshot {
        let before = processCounters()
        if sampleInterval > 0 {
            Thread.sleep(forTimeInterval: sampleInterval)
        }
        let after = processCounters()
        let capacities = diskCapacities()
        let mountedImages = mountedDiskImageDataProvider.mountedDiskImageData()
            .map(MountedDiskImageParser.parse) ?? []

        return MacRuntimeSnapshot(
            diskAvailableBytes: capacities.available,
            diskTotalBytes: capacities.total,
            memoryPressure: memoryPressure(),
            swapUsedBytes: swapUsedBytes(),
            uptime: ProcessInfo.processInfo.systemUptime,
            thermalState: thermalState(),
            processes: processUsage(before: before, after: after),
            mountedDiskImages: mountedImages
        )
    }

    private func diskCapacities() -> (available: Int64, total: Int64) {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else {
            return (0, 0)
        }
        return (
            Int64(values.volumeAvailableCapacityForImportantUsage ?? 0),
            Int64(values.volumeTotalCapacity ?? 0)
        )
    }

    private func memoryPressure() -> MacRuntimeMemoryPressure {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else {
            return .unknown
        }
        if value & 4 != 0 { return .critical }
        if value & 2 != 0 { return .warning }
        if value & 1 != 0 { return .normal }
        return .unknown
    }

    private func swapUsedBytes() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private func thermalState() -> MacRuntimeThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }

    private func processCounters() -> [pid_t: NativeProcessCounter] {
        var pids = [pid_t](repeating: 0, count: maximumPIDCount)
        let listed = proc_listallpids(
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard listed > 0 else { return [:] }

        var counters: [pid_t: NativeProcessCounter] = [:]
        for pid in pids.prefix(min(Int(listed), pids.count)) where pid > 0 {
            var taskInfo = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size) == size else { continue }

            var nameBuffer = [CChar](repeating: 0, count: 1_024)
            let nameLength = Int(proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)))
            guard nameLength > 0 else { continue }
            let name = String(
                decoding: nameBuffer.prefix(nameLength).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            guard !name.isEmpty else { continue }

            counters[pid] = NativeProcessCounter(
                name: name,
                cpuNanoseconds: taskInfo.pti_total_user &+ taskInfo.pti_total_system,
                residentBytes: taskInfo.pti_resident_size
            )
        }
        return counters
    }

    private func processUsage(
        before: [pid_t: NativeProcessCounter],
        after: [pid_t: NativeProcessCounter]
    ) -> [MacRuntimeProcessUsage] {
        guard sampleInterval > 0 else { return [] }
        var aggregated: [String: (cpu: Double, memory: UInt64)] = [:]

        for (pid, current) in after {
            guard let previous = before[pid], previous.name == current.name else { continue }
            let delta = current.cpuNanoseconds >= previous.cpuNanoseconds
                ? current.cpuNanoseconds - previous.cpuNanoseconds
                : 0
            let cpuPercent = Double(delta) / (sampleInterval * 1_000_000_000) * 100
            let old = aggregated[current.name] ?? (0, 0)
            aggregated[current.name] = (
                old.cpu + cpuPercent,
                old.memory &+ current.residentBytes
            )
        }

        return aggregated.map { name, usage in
            MacRuntimeProcessUsage(
                name: name,
                cpuPercent: usage.cpu,
                memoryBytes: usage.memory
            )
        }
        .sorted {
            let leftScore = max($0.cpuPercent / 25, Double($0.memoryBytes) / 2_000_000_000)
            let rightScore = max($1.cpuPercent / 25, Double($1.memoryBytes) / 2_000_000_000)
            if leftScore != rightScore { return leftScore > rightScore }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        .prefix(Self.maximumReportedProcesses)
        .map { $0 }
    }
}

private struct NativeProcessCounter {
    let name: String
    let cpuNanoseconds: UInt64
    let residentBytes: UInt64
}
