import CrabCore
import Darwin
import Foundation

public struct HarnessResidueID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum HarnessResidueCategory: String, CaseIterable, Sendable {
    case cache
    case logs
    case savedState
    case preferences
    case webData
    case applicationData
}

public enum HarnessResidueRisk: String, Sendable {
    case recommended
    case reviewRequired
}

public struct HarnessResidueRule: Equatable, Sendable {
    public let id: HarnessResidueID
    public let appID: String
    public let category: HarnessResidueCategory
    public let risk: HarnessResidueRisk
    public let relativePath: String
    public let title: String
    public let explanation: String

    public init(
        id: HarnessResidueID,
        appID: String,
        category: HarnessResidueCategory,
        risk: HarnessResidueRisk,
        relativePath: String,
        title: String,
        explanation: String
    ) {
        self.id = id
        self.appID = appID
        self.category = category
        self.risk = risk
        self.relativePath = relativePath
        self.title = title
        self.explanation = explanation
    }
}

public enum HarnessResidueCatalog {
    public static func rules(
        for definition: HarnessDefinition,
        cacheRules: [AIFileRule]
    ) -> [HarnessResidueRule] {
        var rules = cacheRules
            .filter { $0.appID == definition.appID }
            .map { cacheRule in
                HarnessResidueRule(
                    id: HarnessResidueID(rawValue: "residue.\(cacheRule.id.rawValue)"),
                    appID: definition.appID,
                    category: .cache,
                    risk: .recommended,
                    relativePath: cacheRule.leaf,
                    title: "可再生缓存",
                    explanation: cacheRule.explanation
                )
            }

        let appID = definition.appID
        rules.append(contentsOf: [
            commonRule(appID: appID, category: .cache, risk: .recommended, path: "Library/Caches/\(appID)", title: "应用缓存"),
            commonRule(appID: appID, category: .cache, risk: .recommended, path: "Library/Caches/\(appID).ShipIt", title: "更新缓存"),
            commonRule(appID: appID, category: .logs, risk: .recommended, path: "Library/Logs/\(appID)", title: "诊断日志"),
            commonRule(appID: appID, category: .savedState, risk: .recommended, path: "Library/Saved Application State/\(appID).savedState", title: "窗口恢复状态"),
            commonRule(appID: appID, category: .preferences, risk: .reviewRequired, path: "Library/Preferences/\(appID).plist", title: "应用偏好设置"),
            commonRule(appID: appID, category: .webData, risk: .reviewRequired, path: "Library/HTTPStorages/\(appID)", title: "网络存储"),
            commonRule(appID: appID, category: .webData, risk: .reviewRequired, path: "Library/HTTPStorages/\(appID).binarycookies", title: "网络 Cookie"),
            commonRule(appID: appID, category: .webData, risk: .reviewRequired, path: "Library/WebKit/\(appID)", title: "网页数据"),
            commonRule(appID: appID, category: .applicationData, risk: .reviewRequired, path: "Library/Application Support/\(appID)", title: "应用数据"),
        ])

        for directoryName in definition.residueSupportDirectoryNames {
            rules.append(commonRule(
                appID: appID,
                category: .applicationData,
                risk: .reviewRequired,
                path: "Library/Application Support/\(directoryName)",
                title: "\(directoryName) 应用数据"
            ))
        }

        var seenPaths = Set<String>()
        return rules
            .filter { seenPaths.insert($0.relativePath).inserted }
            .sorted {
                if $0.risk != $1.risk { return $0.risk == .recommended }
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
    }

    private static func commonRule(
        appID: String,
        category: HarnessResidueCategory,
        risk: HarnessResidueRisk,
        path: String,
        title: String
    ) -> HarnessResidueRule {
        let stablePath = path
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
        return HarnessResidueRule(
            id: HarnessResidueID(rawValue: "residue.\(appID).\(stablePath)"),
            appID: appID,
            category: category,
            risk: risk,
            relativePath: path,
            title: title,
            explanation: explanation(for: category)
        )
    }

    private static func explanation(for category: HarnessResidueCategory) -> String {
        switch category {
        case .cache: "卸载后遗留的可重新生成缓存。"
        case .logs: "应用运行时留下的诊断日志。"
        case .savedState: "用于恢复上次窗口状态的数据。"
        case .preferences: "包含应用设置，重新安装时可能继续使用。"
        case .webData: "可能包含登录状态或网页组件数据。"
        case .applicationData: "可能包含账号、会话、扩展或其他用户数据。"
        }
    }
}

public struct HarnessResidueIdentity: Equatable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let kind: FileKind
    public let modificationNanoseconds: Int64

    fileprivate init(metadata: stat, kind: FileKind) {
        device = UInt64(metadata.st_dev)
        inode = UInt64(metadata.st_ino)
        self.kind = kind
        modificationNanoseconds = Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000
            + Int64(metadata.st_mtimespec.tv_nsec)
    }
}

public struct HarnessResidueCandidate: Equatable, Sendable {
    public let rule: HarnessResidueRule
    public let path: URL
    public let identity: HarnessResidueIdentity
    public let logicalBytes: UInt64
    public let physicalBytes: UInt64
    public let fileCount: UInt64
}

public struct HarnessResidueScanIssue: Equatable, Sendable {
    public let ruleID: HarnessResidueID
    public let message: String
}

public struct HarnessResidueScanResult: Equatable, Sendable {
    public let candidates: [HarnessResidueCandidate]
    public let skippedRuleIDs: [HarnessResidueID]
    public let issues: [HarnessResidueScanIssue]
}

public enum HarnessResidueScanError: Error, Equatable, CustomStringConvertible {
    case invalidRule(String)
    case missingPath(String)
    case escapedHome(String)
    case symbolicLink(String)
    case unsupportedFileType(String)
    case mountBoundary(String)
    case unreadableDirectory(String)
    case traversalLimit

    public var description: String {
        switch self {
        case let .invalidRule(message): "残留规则无效：\(message)"
        case .missingPath: "残留路径不存在。"
        case .escapedHome: "残留路径超出个人文件夹。"
        case .symbolicLink: "残留路径包含符号链接。"
        case .unsupportedFileType: "残留路径类型不受支持。"
        case .mountBoundary: "残留路径跨越了磁盘边界。"
        case .unreadableDirectory: "残留目录无法安全读取。"
        case .traversalLimit: "残留目录项目过多，已停止扫描。"
        }
    }
}

public struct HarnessResidueScanner: Sendable {
    private let maximumEntries: Int

    public init(maximumEntries: Int = 200_000) {
        self.maximumEntries = maximumEntries
    }

    public func scan(
        rules: [HarnessResidueRule],
        homeURL: URL
    ) -> HarnessResidueScanResult {
        var candidates: [HarnessResidueCandidate] = []
        var skipped: [HarnessResidueID] = []
        var issues: [HarnessResidueScanIssue] = []

        for rule in rules {
            do {
                candidates.append(try scan(rule: rule, homeURL: homeURL))
            } catch HarnessResidueScanError.missingPath {
                skipped.append(rule.id)
            } catch {
                issues.append(HarnessResidueScanIssue(
                    ruleID: rule.id,
                    message: String(describing: error)
                ))
            }
        }

        return HarnessResidueScanResult(
            candidates: candidates.sorted {
                if $0.rule.risk != $1.rule.risk { return $0.rule.risk == .recommended }
                if $0.logicalBytes != $1.logicalBytes { return $0.logicalBytes > $1.logicalBytes }
                return $0.rule.relativePath.localizedStandardCompare($1.rule.relativePath) == .orderedAscending
            },
            skippedRuleIDs: skipped.sorted { $0.rawValue < $1.rawValue },
            issues: issues.sorted { $0.ruleID.rawValue < $1.ruleID.rawValue }
        )
    }

    public func scan(
        rule: HarnessResidueRule,
        homeURL: URL
    ) throws -> HarnessResidueCandidate {
        try validate(rule)
        guard maximumEntries > 0 else { throw HarnessResidueScanError.traversalLimit }

        let home = homeURL.standardizedFileURL
        let target = home.appendingPathComponent(rule.relativePath).standardizedFileURL
        let homePrefix = home.path.hasSuffix("/") ? home.path : home.path + "/"
        guard target.path.hasPrefix(homePrefix) else {
            throw HarnessResidueScanError.escapedHome(target.path)
        }

        let metadata = try validatePathChain(homeURL: home, relativePath: rule.relativePath)
        let rootKind = try kind(for: metadata, path: target.path)
        let identity = HarnessResidueIdentity(metadata: metadata, kind: rootKind)
        var totals = ResidueTotals()

        switch rootKind {
        case .regularFile:
            totals.addFile(metadata)
        case .directory:
            var seenFiles = Set<ResidueFileKey>()
            var examinedEntries = 0
            try scanDirectory(
                target,
                rootDevice: identity.device,
                seenFiles: &seenFiles,
                totals: &totals,
                examinedEntries: &examinedEntries
            )
        }

        return HarnessResidueCandidate(
            rule: rule,
            path: target,
            identity: identity,
            logicalBytes: totals.logicalBytes,
            physicalBytes: totals.physicalBytes,
            fileCount: totals.fileCount
        )
    }

    private func validate(_ rule: HarnessResidueRule) throws {
        guard !rule.id.rawValue.isEmpty, !rule.appID.isEmpty else {
            throw HarnessResidueScanError.invalidRule("缺少稳定标识")
        }
        let path = rule.relativePath
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.utf8.contains(0) else {
            throw HarnessResidueScanError.invalidRule("路径必须是安全的相对路径")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw HarnessResidueScanError.invalidRule("路径层级不明确") }

        let allowedPrefix: String
        let expectedRisk: HarnessResidueRisk
        switch rule.category {
        case .cache:
            allowedPrefix = "Library/Caches/"
            expectedRisk = .recommended
        case .logs:
            allowedPrefix = "Library/Logs/"
            expectedRisk = .recommended
        case .savedState:
            allowedPrefix = "Library/Saved Application State/"
            expectedRisk = .recommended
        case .preferences:
            allowedPrefix = "Library/Preferences/"
            expectedRisk = .reviewRequired
        case .webData:
            let webPrefixes = ["Library/HTTPStorages/", "Library/WebKit/"]
            guard webPrefixes.contains(where: path.hasPrefix) else {
                throw HarnessResidueScanError.invalidRule("网页数据根目录不受支持")
            }
            allowedPrefix = ""
            expectedRisk = .reviewRequired
        case .applicationData:
            allowedPrefix = "Library/Application Support/"
            expectedRisk = .reviewRequired
        }
        guard (allowedPrefix.isEmpty || path.hasPrefix(allowedPrefix)), rule.risk == expectedRisk else {
            throw HarnessResidueScanError.invalidRule("路径与风险分类不匹配")
        }

        let normalized = path.lowercased().filter { $0.isLetter || $0.isNumber }
        for protectedMarker in ["containers", "groupcontainers", "photoslibrary", "musiclibrary"]
            where normalized.contains(protectedMarker) {
            throw HarnessResidueScanError.invalidRule("受保护目录不能成为残留目标")
        }
    }

    private func validatePathChain(homeURL: URL, relativePath: String) throws -> stat {
        var current = homeURL
        _ = try metadata(at: current)
        var latest = stat()
        for component in relativePath.split(separator: "/") {
            current.appendPathComponent(String(component))
            latest = try metadata(at: current)
        }
        return latest
    }

    private func scanDirectory(
        _ directory: URL,
        rootDevice: UInt64,
        seenFiles: inout Set<ResidueFileKey>,
        totals: inout ResidueTotals,
        examinedEntries: inout Int
    ) throws {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw HarnessResidueScanError.unreadableDirectory(directory.path)
        }

        for child in children {
            examinedEntries += 1
            guard examinedEntries <= maximumEntries else {
                throw HarnessResidueScanError.traversalLimit
            }
            let childMetadata = try metadata(at: child, rejectSymbolicLink: false)
            if childMetadata.st_mode & S_IFMT == S_IFLNK { continue }
            guard UInt64(childMetadata.st_dev) == rootDevice else {
                throw HarnessResidueScanError.mountBoundary(child.path)
            }

            switch try kind(for: childMetadata, path: child.path) {
            case .directory:
                try scanDirectory(
                    child,
                    rootDevice: rootDevice,
                    seenFiles: &seenFiles,
                    totals: &totals,
                    examinedEntries: &examinedEntries
                )
            case .regularFile:
                totals.fileCount += 1
                let key = ResidueFileKey(
                    device: UInt64(childMetadata.st_dev),
                    inode: UInt64(childMetadata.st_ino)
                )
                if seenFiles.insert(key).inserted {
                    totals.logicalBytes += UInt64(max(0, childMetadata.st_size))
                    totals.physicalBytes += UInt64(max(0, childMetadata.st_blocks)) * 512
                }
            }
        }
    }

    private func metadata(at url: URL, rejectSymbolicLink: Bool = true) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            throw HarnessResidueScanError.missingPath(url.path)
        }
        if rejectSymbolicLink, value.st_mode & S_IFMT == S_IFLNK {
            throw HarnessResidueScanError.symbolicLink(url.path)
        }
        return value
    }

    private func kind(for metadata: stat, path: String) throws -> FileKind {
        switch metadata.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .regularFile
        default: throw HarnessResidueScanError.unsupportedFileType(path)
        }
    }
}

public struct HarnessResidueSnapshot: Equatable, Sendable {
    public let candidates: [HarnessResidueCandidate]
    public private(set) var selectedRuleIDs: Set<HarnessResidueID>

    public init(
        candidates: [HarnessResidueCandidate] = [],
        selectedRuleIDs: Set<HarnessResidueID> = []
    ) {
        self.candidates = candidates
        self.selectedRuleIDs = selectedRuleIDs.intersection(Set(candidates.map(\.rule.id)))
    }

    public var selectedCandidates: [HarnessResidueCandidate] {
        candidates.filter { selectedRuleIDs.contains($0.rule.id) }
    }

    public var totalBytes: UInt64 {
        candidates.reduce(0) { $0 + $1.logicalBytes }
    }

    public var selectedBytes: UInt64 {
        selectedCandidates.reduce(0) { $0 + $1.logicalBytes }
    }

    public mutating func setSelected(_ ruleID: HarnessResidueID, selected: Bool) {
        guard candidates.contains(where: { $0.rule.id == ruleID }) else { return }
        if selected { selectedRuleIDs.insert(ruleID) } else { selectedRuleIDs.remove(ruleID) }
    }

    public mutating func setSelected(_ ruleIDs: [HarnessResidueID], selected: Bool) {
        let available = Set(candidates.map(\.rule.id))
        let requested = Set(ruleIDs).intersection(available)
        if selected { selectedRuleIDs.formUnion(requested) } else { selectedRuleIDs.subtract(requested) }
    }

    public mutating func selectRecommended() {
        selectedRuleIDs = Set(candidates.filter { $0.rule.risk == .recommended }.map(\.rule.id))
    }

    public mutating func clearSelection() {
        selectedRuleIDs.removeAll()
    }
}

public struct HarnessResiduePlanEntry: Equatable, Sendable {
    public let ruleID: HarnessResidueID
    public let relativePath: String
    public let appID: String
    public let identity: HarnessResidueIdentity
    public let logicalBytes: UInt64
}

public struct HarnessResiduePlan: Equatable, Sendable {
    public let schema: Int
    public let planID: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let entries: [HarnessResiduePlanEntry]
}

public enum HarnessResiduePlanError: Error, Equatable {
    case invalidLifetime
    case duplicateRule(HarnessResidueID)
    case unknownSelection(HarnessResidueID)
}

public struct HarnessResiduePlanBuilder: Sendable {
    public init() {}

    public func build(
        candidates: [HarnessResidueCandidate],
        selectedRuleIDs: Set<HarnessResidueID>,
        now: Date = Date(),
        validFor lifetime: TimeInterval = 600
    ) throws -> HarnessResiduePlan {
        guard lifetime > 0, lifetime <= 900 else { throw HarnessResiduePlanError.invalidLifetime }
        var byID: [HarnessResidueID: HarnessResidueCandidate] = [:]
        for candidate in candidates {
            guard byID[candidate.rule.id] == nil else {
                throw HarnessResiduePlanError.duplicateRule(candidate.rule.id)
            }
            byID[candidate.rule.id] = candidate
        }

        let entries = try selectedRuleIDs.sorted { $0.rawValue < $1.rawValue }.map { id in
            guard let candidate = byID[id] else { throw HarnessResiduePlanError.unknownSelection(id) }
            return HarnessResiduePlanEntry(
                ruleID: id,
                relativePath: candidate.rule.relativePath,
                appID: candidate.rule.appID,
                identity: candidate.identity,
                logicalBytes: candidate.logicalBytes
            )
        }
        return HarnessResiduePlan(
            schema: 1,
            planID: UUID(),
            createdAt: now,
            expiresAt: now.addingTimeInterval(lifetime),
            entries: entries
        )
    }
}

public enum HarnessResidueCleanupError: Error, Equatable, CustomStringConvertible {
    case unsupportedPlan
    case expiredPlan
    case emptyPlan
    case duplicateRule(HarnessResidueID)
    case unknownRule(HarnessResidueID)
    case planRuleMismatch(HarnessResidueID)
    case targetChanged(HarnessResidueID)
    case applicationRunning

    public var description: String {
        switch self {
        case .unsupportedPlan: "残留清理请求版本不受支持。"
        case .expiredPlan: "残留扫描结果已过期，请重新扫描。"
        case .emptyPlan: "尚未选择任何残留项目。"
        case .duplicateRule: "残留规则重复，未执行清理。"
        case .unknownRule: "残留规则无法确认，未执行清理。"
        case .planRuleMismatch: "残留规则在确认后发生变化。"
        case .targetChanged: "残留项目在确认后发生变化。"
        case .applicationRunning: "应用仍在运行，未清理残留。"
        }
    }
}

public struct HarnessResidueCleanupExecutor<
    Mover: TrashMoving,
    ApplicationChecker: ApplicationActivityChecking
>: Sendable {
    private let trashMover: Mover
    private let applicationChecker: ApplicationChecker
    private let scanner: HarnessResidueScanner

    public init(
        trashMover: Mover,
        applicationChecker: ApplicationChecker,
        scanner: HarnessResidueScanner = HarnessResidueScanner()
    ) {
        self.trashMover = trashMover
        self.applicationChecker = applicationChecker
        self.scanner = scanner
    }

    public func execute(
        plan: HarnessResiduePlan,
        rules: [HarnessResidueRule],
        homeURL: URL,
        now: Date = Date()
    ) throws -> CleanupReceipt {
        guard plan.schema == 1 else { throw HarnessResidueCleanupError.unsupportedPlan }
        guard plan.expiresAt > now else { throw HarnessResidueCleanupError.expiredPlan }
        guard !plan.entries.isEmpty else { throw HarnessResidueCleanupError.emptyPlan }

        var rulesByID: [HarnessResidueID: HarnessResidueRule] = [:]
        for rule in rules {
            guard rulesByID[rule.id] == nil else { throw HarnessResidueCleanupError.duplicateRule(rule.id) }
            rulesByID[rule.id] = rule
        }

        var revalidated: [(HarnessResidueCandidate, HarnessResiduePlanEntry)] = []
        var skipped = CleanupOutcomeMeasure()
        for entry in plan.entries {
            guard let rule = rulesByID[entry.ruleID] else { throw HarnessResidueCleanupError.unknownRule(entry.ruleID) }
            guard rule.relativePath == entry.relativePath, rule.appID == entry.appID else {
                throw HarnessResidueCleanupError.planRuleMismatch(entry.ruleID)
            }
            guard !applicationChecker.isApplicationRunning(bundleIdentifier: entry.appID) else {
                throw HarnessResidueCleanupError.applicationRunning
            }
            do {
                let fresh = try scanner.scan(rule: rule, homeURL: homeURL)
                guard fresh.identity == entry.identity else {
                    throw HarnessResidueCleanupError.targetChanged(entry.ruleID)
                }
                revalidated.append((fresh, entry))
            } catch HarnessResidueScanError.missingPath {
                skipped = CleanupOutcomeMeasure(
                    count: skipped.count + 1,
                    logicalBytes: skipped.logicalBytes + entry.logicalBytes
                )
            }
        }

        var moved = CleanupOutcomeMeasure()
        var failed = CleanupOutcomeMeasure()
        for (candidate, entry) in revalidated {
            let immediate: HarnessResidueCandidate
            do {
                immediate = try scanner.scan(rule: candidate.rule, homeURL: homeURL)
            } catch HarnessResidueScanError.missingPath {
                skipped = CleanupOutcomeMeasure(
                    count: skipped.count + 1,
                    logicalBytes: skipped.logicalBytes + entry.logicalBytes
                )
                continue
            } catch {
                failed = CleanupOutcomeMeasure(
                    count: failed.count + 1,
                    logicalBytes: failed.logicalBytes + entry.logicalBytes
                )
                continue
            }
            guard immediate.identity == entry.identity else {
                failed = CleanupOutcomeMeasure(
                    count: failed.count + 1,
                    logicalBytes: failed.logicalBytes + entry.logicalBytes
                )
                continue
            }
            guard !applicationChecker.isApplicationRunning(bundleIdentifier: entry.appID) else {
                throw HarnessResidueCleanupError.applicationRunning
            }
            do {
                try trashMover.moveToTrash(immediate.path)
                moved = CleanupOutcomeMeasure(
                    count: moved.count + 1,
                    logicalBytes: moved.logicalBytes + immediate.logicalBytes
                )
            } catch {
                failed = CleanupOutcomeMeasure(
                    count: failed.count + 1,
                    logicalBytes: failed.logicalBytes + immediate.logicalBytes
                )
            }
        }
        return CleanupReceipt(moved: moved, skipped: skipped, failed: failed)
    }
}

private struct ResidueFileKey: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct ResidueTotals {
    var logicalBytes: UInt64 = 0
    var physicalBytes: UInt64 = 0
    var fileCount: UInt64 = 0

    mutating func addFile(_ metadata: stat) {
        fileCount += 1
        logicalBytes += UInt64(max(0, metadata.st_size))
        physicalBytes += UInt64(max(0, metadata.st_blocks)) * 512
    }
}
