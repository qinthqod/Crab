import CrabArchive
import CrabCore
import Foundation

public enum ProjectCleanupLabel: Hashable, Sendable {
    case inactive
    case large
}

public enum ProjectCleanupLabelPolicy {
    public static let largeProjectBytes: UInt64 = 1_024 * 1_024 * 1_024

    public static func labels(
        isInactive: Bool,
        logicalBytes: UInt64
    ) -> Set<ProjectCleanupLabel> {
        var labels = Set<ProjectCleanupLabel>()
        if isInactive { labels.insert(.inactive) }
        if logicalBytes >= largeProjectBytes { labels.insert(.large) }
        return labels
    }
}

public enum ProjectCleanupFilter: String, CaseIterable, Sendable {
    case all
    case inactive
    case large
    case recent
}

public enum ProjectCleanupSort: String, CaseIterable, Sendable {
    case recentActivity
    case oldestActivity
    case sizeDescending
}

public enum ProjectCleanupPresentation {
    public static func projects(
        _ projects: [ProjectInventoryItem],
        query: String,
        filter: ProjectCleanupFilter,
        sort: ProjectCleanupSort
    ) -> [ProjectInventoryItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return projects
            .filter { project in
                normalizedQuery.isEmpty
                    || project.path.lastPathComponent.localizedCaseInsensitiveContains(normalizedQuery)
                    || project.path.path.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .filter { project in
                switch filter {
                case .all: true
                case .inactive: project.isInactive
                case .large:
                    ProjectCleanupLabelPolicy.labels(
                        isInactive: project.isInactive,
                        logicalBytes: project.logicalBytes
                    ).contains(.large)
                case .recent: !project.isInactive
                }
            }
            .sorted { left, right in
                switch sort {
                case .recentActivity:
                    if left.latestActivity != right.latestActivity {
                        return left.latestActivity > right.latestActivity
                    }
                case .oldestActivity:
                    if left.latestActivity != right.latestActivity {
                        return left.latestActivity < right.latestActivity
                    }
                case .sizeDescending:
                    if left.logicalBytes != right.logicalBytes {
                        return left.logicalBytes > right.logicalBytes
                    }
                }
                return left.path.path.localizedStandardCompare(right.path.path) == .orderedAscending
            }
    }
}

public struct ProjectCleanupSelection: Equatable, Sendable {
    public let inventory: ProjectInventoryResult
    public private(set) var selectedProjectIDs: Set<URL>

    public init(inventory: ProjectInventoryResult = ProjectInventoryResult()) {
        self.inventory = inventory
        selectedProjectIDs = []
    }

    public var selectedProjects: [ProjectInventoryItem] {
        inventory.projects.filter { selectedProjectIDs.contains($0.id) }
    }

    public var selectedBytes: UInt64 {
        selectedProjects.reduce(0) { $0 + $1.logicalBytes }
    }

    public mutating func setSelected(_ projectID: URL, selected: Bool) {
        let normalizedID = projectID.standardizedFileURL
        guard inventory.projects.contains(where: { $0.id == normalizedID && $0.canClean }) else {
            selectedProjectIDs.remove(normalizedID)
            return
        }
        if selected {
            selectedProjectIDs.insert(normalizedID)
        } else {
            selectedProjectIDs.remove(normalizedID)
        }
    }

    public mutating func setSelected(_ projects: [ProjectInventoryItem], selected: Bool) {
        for project in projects {
            setSelected(project.id, selected: selected)
        }
    }
}

public struct ProjectCleanupPlan: Equatable, Sendable {
    public let schema: Int
    public let planID: UUID
    public let homeURL: URL
    public let scannedAt: Date
    public let createdAt: Date
    public let expiresAt: Date
    public let entries: [ProjectInventoryItem]
}

public enum ProjectCleanupPlanError: Error, Equatable, CustomStringConvertible {
    case invalidLifetime
    case staleEvidence
    case emptySelection
    case unknownProject(String)
    case overlappingProjects

    public var description: String {
        switch self {
        case .invalidLifetime:
            "项目清理确认有效期无效。"
        case .staleEvidence:
            "项目扫描结果已过期，请重新扫描后再试。"
        case .emptySelection:
            "请先选择要移入废纸篓的项目。"
        case let .unknownProject(path):
            "所选项目不在本次扫描结果中：\(path)"
        case .overlappingProjects:
            "不能同时处理互相包含的项目，请只保留外层或内层项目。"
        }
    }
}

public struct ProjectCleanupPlanBuilder: Sendable {
    public init() {}

    public func build(
        inventory: ProjectInventoryResult,
        selectedProjectIDs: Set<URL>,
        homeURL: URL,
        now: Date = Date(),
        validFor lifetime: TimeInterval = 600
    ) throws -> ProjectCleanupPlan {
        guard lifetime > 0, lifetime <= 900 else { throw ProjectCleanupPlanError.invalidLifetime }
        let age = now.timeIntervalSince(inventory.scannedAt)
        guard age >= 0, age <= 600 else { throw ProjectCleanupPlanError.staleEvidence }
        guard !selectedProjectIDs.isEmpty else { throw ProjectCleanupPlanError.emptySelection }

        let projectsByID = Dictionary(uniqueKeysWithValues: inventory.projects.map { ($0.id, $0) })
        let normalizedIDs = Set(selectedProjectIDs.map(\.standardizedFileURL))
        let entries = try normalizedIDs.map { id -> ProjectInventoryItem in
            guard let project = projectsByID[id] else {
                throw ProjectCleanupPlanError.unknownProject(id.path)
            }
            guard project.canClean else {
                throw ProjectInventoryVerificationError.unsafePath(project.path.path)
            }
            return project
        }.sorted { $0.path.path < $1.path.path }

        for (index, project) in entries.enumerated() {
            let prefix = project.path.path + "/"
            if entries.dropFirst(index + 1).contains(where: { $0.path.path.hasPrefix(prefix) }) {
                throw ProjectCleanupPlanError.overlappingProjects
            }
        }

        return ProjectCleanupPlan(
            schema: 1,
            planID: UUID(),
            homeURL: homeURL.standardizedFileURL,
            scannedAt: inventory.scannedAt,
            createdAt: now,
            expiresAt: now.addingTimeInterval(lifetime),
            entries: entries
        )
    }
}

public enum ProjectCleanupExecutionError: Error, Equatable, CustomStringConvertible {
    case unsupportedPlan
    case expiredPlan
    case emptyPlan
    case targetChanged(String)

    public var description: String {
        switch self {
        case .unsupportedPlan:
            "项目清理请求格式不受支持。"
        case .expiredPlan:
            "项目清理确认已过期，请重新扫描。"
        case .emptyPlan:
            "项目清理请求中没有可处理的项目。"
        case let .targetChanged(path):
            "项目在确认后发生了变化，未移入废纸篓：\(path)"
        }
    }
}

public struct ProjectCleanupExecutor<Mover: TrashMoving>: Sendable {
    private let trashMover: Mover
    private let scanner: ProjectInventoryScanner

    public init(trashMover: Mover, scanner: ProjectInventoryScanner = ProjectInventoryScanner()) {
        self.trashMover = trashMover
        self.scanner = scanner
    }

    public func execute(plan: ProjectCleanupPlan, now: Date = Date()) throws -> CleanupReceipt {
        guard plan.schema == 1 else { throw ProjectCleanupExecutionError.unsupportedPlan }
        guard plan.expiresAt > now else { throw ProjectCleanupExecutionError.expiredPlan }
        guard !plan.entries.isEmpty else { throw ProjectCleanupExecutionError.emptyPlan }

        var verified: [ProjectInventoryItem] = []
        var skipped = CleanupOutcomeMeasure()
        for entry in plan.entries {
            do {
                verified.append(try scanner.revalidateForTrash(
                    entry,
                    homeURL: plan.homeURL,
                    scannedAt: plan.scannedAt,
                    now: now
                ))
            } catch ProjectInventoryVerificationError.missingPath {
                skipped = CleanupOutcomeMeasure(
                    count: skipped.count + 1,
                    logicalBytes: skipped.logicalBytes + entry.logicalBytes
                )
            } catch {
                throw ProjectCleanupExecutionError.targetChanged(entry.path.path)
            }
        }

        var moved = CleanupOutcomeMeasure()
        var failed = CleanupOutcomeMeasure()
        for entry in verified {
            do {
                _ = try scanner.revalidateForTrash(
                    entry,
                    homeURL: plan.homeURL,
                    scannedAt: plan.scannedAt,
                    now: now
                )
                try trashMover.moveToTrash(entry.path)
                moved = CleanupOutcomeMeasure(
                    count: moved.count + 1,
                    logicalBytes: moved.logicalBytes + entry.logicalBytes
                )
            } catch ProjectInventoryVerificationError.missingPath {
                skipped = CleanupOutcomeMeasure(
                    count: skipped.count + 1,
                    logicalBytes: skipped.logicalBytes + entry.logicalBytes
                )
            } catch {
                failed = CleanupOutcomeMeasure(
                    count: failed.count + 1,
                    logicalBytes: failed.logicalBytes + entry.logicalBytes
                )
            }
        }

        return CleanupReceipt(moved: moved, skipped: skipped, failed: failed)
    }
}
