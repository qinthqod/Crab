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

public struct MacRuntimeProcess: Identifiable, Equatable, Sendable {
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
    public let processes: [MacRuntimeProcess]
    public let mountedDiskImages: [MountedDiskImage]

    public init(
        diskAvailableBytes: Int64,
        diskTotalBytes: Int64,
        memoryPressure: MacRuntimeMemoryPressure,
        swapUsedBytes: UInt64,
        uptime: TimeInterval,
        thermalState: MacRuntimeThermalState,
        processes: [MacRuntimeProcess],
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
    public let resourceHeavyProcesses: [MacRuntimeProcess]

    public init(
        level: MacRuntimeHealthLevel,
        snapshot: MacRuntimeSnapshot,
        findings: [MacRuntimeFinding],
        resourceHeavyProcesses: [MacRuntimeProcess]
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
