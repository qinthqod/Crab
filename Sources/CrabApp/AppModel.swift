import AppKit
import CrabArchive
import CrabAppSupport
import CrabCore
import Foundation
import OSLog

private let crabPerformanceLogger = Logger(
    subsystem: "dev.crab.cleaner",
    category: "Performance"
)

private enum ScanWorkResult: Sendable {
    case success(rules: [AIFileRule], result: AppScanResult, inventory: HarnessInventory)
    case failure(String)
}

private enum HarnessInventoryWorkResult: Sendable {
    case success(
        inventory: HarnessInventory,
        projectInventory: ProjectInventoryResult?,
        usage: [String: HarnessUsageSummary]
    )
    case failure(String)
}

private enum HarnessUninstallWorkResult: Sendable {
    case success(HarnessUninstallReceipt)
    case failure(String)
}

private enum HarnessResidueScanWorkResult: Sendable {
    case success(rules: [HarnessResidueRule], result: HarnessResidueScanResult)
    case failure(String)
}

private enum HarnessResidueCleanupWorkResult: Sendable {
    case success(CleanupReceipt)
    case failure(String)
}

private enum CleanupWorkResult: Sendable {
    case success(CleanupReceipt)
    case failure(String)
}

private enum ArchiveWorkResult: Sendable {
    case success(ArchiveReviewSnapshot)
    case failure(String)
}

private enum ProjectInventoryWorkResult: Sendable {
    case success(inventory: HarnessInventory, result: ProjectInventoryResult)
    case failure(String)
}

private enum ProjectCleanupWorkResult: Sendable {
    case success(CleanupReceipt)
    case failure(String)
}

private struct SystemApplicationActivityChecker: ApplicationActivityChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Mode: CaseIterable, Identifiable {
        case cache
        case harness
        case archive

        var id: Self { self }

        var title: String {
            switch self {
            case .cache: CrabL10n.text("缓存清理", "Cache Cleanup")
            case .harness: CrabL10n.text("应用管理", "App Management")
            case .archive: CrabL10n.text("项目清理", "Project Cleanup")
            }
        }
    }

    typealias ScanState = CacheWorkflowState.Phase

    enum CleanupState: Equatable {
        case idle
        case moving
        case succeeded(String)
        case failed(String)
    }

    typealias InventoryState = HarnessInventoryLoadState

    enum ProjectInventoryState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    enum ProjectScanAccessState: Equatable {
        case unknown
        case needsAuthorization
        case authorized
        case failed(String)
    }

    enum ProjectCleanupState: Equatable {
        case idle
        case moving
        case succeeded(String)
        case failed(String)
    }

    enum HarnessUninstallState: Equatable {
        case idle
        case moving(String)
        case succeeded(String)
        case failed(String)
    }

    enum HarnessResidueState: Equatable {
        case idle
        case scanning
        case reviewing
        case cleaning
        case failed(String)
    }

    @Published private var cacheWorkflow = CacheWorkflowState()
    @Published private(set) var scanOverview = AppScanOverview()
    @Published private(set) var lastCacheScan: CacheScanHistorySummary?
    @Published private(set) var harnessInventory = HarnessInventory()
    @Published private(set) var harnessUsageByAppID: [String: HarnessUsageSummary] = [:]
    @Published private(set) var inventoryState: InventoryState = .idle
    @Published private(set) var harnessMetadataIsLoading = false
    @Published private(set) var harnessUninstallState: HarnessUninstallState = .idle
    @Published private(set) var harnessResidueState: HarnessResidueState = .idle
    @Published private(set) var harnessResidueSnapshot = HarnessResidueSnapshot()
    @Published private(set) var harnessResidueAppID = ""
    @Published private(set) var harnessResidueAppName = ""
    @Published private(set) var harnessResidueIcon: NSImage?
    @Published private(set) var harnessResidueIssues: [HarnessResidueScanIssue] = []
    @Published private(set) var projectInventoryState: ProjectInventoryState = .idle
    @Published private(set) var projectScanAccessState: ProjectScanAccessState = .unknown
    @Published private(set) var projectInventory = ProjectInventoryResult()
    @Published private(set) var projectCleanupSelection = ProjectCleanupSelection()
    @Published private(set) var projectCleanupState: ProjectCleanupState = .idle
    @Published private(set) var cleanupState: CleanupState = .idle
    @Published private(set) var mode: Mode = .cache
    @Published private(set) var archiveState = ArchiveReminderState()

    private var loadedRules: [AIFileRule] = []
    private var scanGeneration = UUID()
    private var archiveGeneration = UUID()
    private var inventoryGeneration = UUID()
    private var projectInventoryGeneration = UUID()
    private var harnessMetadataTask: Task<Void, Never>?
    private var harnessResidueRules: [HarnessResidueRule] = []
    private var harnessResidueGeneration = UUID()
    private let projectScanBookmarkKey = "dev.crab.project-scan.home-bookmark.v1"

    var state: ScanState { cacheWorkflow.phase }
    var snapshot: AppScanSnapshot { cacheWorkflow.snapshot }
    var scanIssueCount: Int { cacheWorkflow.issueCount }

    var cacheSpaceSummary: CacheActionableSpaceSummary {
        let runningAppIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let blockedRuleIDs = Set(snapshot.candidates.lazy.compactMap { candidate in
            candidate.rule.requiresAppStopped && runningAppIDs.contains(candidate.rule.appID)
                ? candidate.rule.id
                : nil
        })
        return CacheActionableSpaceSummary(
            candidates: snapshot.candidates,
            blockedRuleIDs: blockedRuleIDs
        )
    }

    var detectedAppCount: Int {
        scanOverview.productsWithCacheCount
    }

    var scannedHarnessCount: Int { scanOverview.products.count }
    var cleanHarnessCount: Int { scanOverview.cleanProductCount }
    var limitedHarnessCount: Int { scanOverview.limitedProductCount }
    var protectedHarnessCount: Int { scanOverview.protectedProductCount }

    func scanUserCaches() {
        let generation = UUID()
        scanGeneration = generation
        loadedRules = []
        scanOverview = AppScanOverview()
        cacheWorkflow.beginScan()
        let scanStartedAt = Date()

        guard let resources = Bundle.main.resourceURL else {
            cacheWorkflow.fail(message: CrabL10n.text(
                "无法读取应用资源。",
                "Crab could not read its app resources."
            ))
            return
        }

        let ruleDirectory = resources.appendingPathComponent("Rules", isDirectory: true)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let applicationRoots = harnessApplicationRoots(homeDirectory: homeDirectory)
        let executableRoots = harnessExecutableRoots(homeDirectory: homeDirectory)

        Task {
            let work = await Task.detached(priority: .userInitiated) {
                do {
                    let rules = try RuleLoader().load(directory: ruleDirectory)
                    let inventory = HarnessInventoryScanner().scan(
                        definitions: HarnessCatalog.supported,
                        applicationRoots: applicationRoots,
                        executableRoots: executableRoots,
                        measureInstalledBytes: false,
                        lastUsedDateProvider: { _ in nil }
                    )
                    let installedRules = rules.filter { inventory.installedAppIDs.contains($0.appID) }
                    let result = AppCacheScanner().scan(rules: installedRules, homeURL: homeDirectory)
                    return ScanWorkResult.success(
                        rules: installedRules,
                        result: result,
                        inventory: inventory
                    )
                } catch {
                    return ScanWorkResult.failure(String(describing: error))
                }
            }.value

            let remainingLoadingTime = 1.4 - Date().timeIntervalSince(scanStartedAt)
            if remainingLoadingTime > 0 {
                try? await Task.sleep(for: .seconds(remainingLoadingTime))
            }

            guard scanGeneration == generation else { return }
            switch work {
            case let .success(rules, result, inventory):
                loadedRules = rules
                acceptLightweightHarnessInventory(inventory)
                scanOverview = AppScanOverview(
                    rules: rules,
                    result: result,
                    installedAppIDs: inventory.installedAppIDs
                )
                cacheWorkflow.finish(
                    snapshot: AppScanSnapshot(candidates: result.candidates),
                    issueCount: result.issues.count
                )
                lastCacheScan = CacheScanHistorySummary(
                    scannedAt: Date(),
                    discoveredBytes: result.candidates.reduce(0) { $0 + $1.logicalBytes },
                    installedAppCount: inventory.installations.count
                )
            case let .failure(message):
                loadedRules = []
                scanOverview = AppScanOverview()
                cacheWorkflow.fail(message: CrabL10n.language == .simplifiedChinese
                    ? "扫描失败：\(message)"
                    : "The scan could not be completed. No files were changed.")
            }
        }
    }

    func returnToHome() {
        scanGeneration = UUID()
        loadedRules = []
        scanOverview = AppScanOverview()
        cleanupState = .idle
        cacheWorkflow.returnHome()
    }

    func setMode(_ mode: Mode) {
        guard self.mode != mode else { return }
        self.mode = mode
    }

    func scanProjects(force: Bool = false) {
        guard force || projectInventoryState == .idle else { return }
        guard let scanRoot = restoreProjectScanRoot() else {
            projectInventoryState = .idle
            return
        }
        let generation = UUID()
        projectInventoryGeneration = generation
        projectInventoryState = .loading
        projectInventory = ProjectInventoryResult()
        projectCleanupSelection = ProjectCleanupSelection()

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let applicationRoots = harnessApplicationRoots(homeDirectory: homeDirectory)
        let executableRoots = harnessExecutableRoots(homeDirectory: homeDirectory)

        Task {
            let work = await Task.detached(priority: .utility) {
                let accessed = scanRoot.startAccessingSecurityScopedResource()
                defer { if accessed { scanRoot.stopAccessingSecurityScopedResource() } }
                do {
                    let inventory = HarnessInventoryScanner().scan(
                        definitions: HarnessCatalog.supported,
                        applicationRoots: applicationRoots,
                        executableRoots: executableRoots,
                        measureInstalledBytes: false,
                        lastUsedDateProvider: { _ in nil }
                    )
                    let rules = ProjectAssociationCatalog.rules(for: inventory.installedAppIDs)
                    let result = try ProjectInventoryScanner().scan(
                        rootURLs: [scanRoot],
                        rules: rules,
                        installedAppIDs: inventory.installedAppIDs
                    )
                    return ProjectInventoryWorkResult.success(inventory: inventory, result: result)
                } catch {
                    return ProjectInventoryWorkResult.failure(String(describing: error))
                }
            }.value

            guard projectInventoryGeneration == generation else { return }
            switch work {
            case let .success(inventory, result):
                acceptLightweightHarnessInventory(inventory)
                projectInventory = result
                projectCleanupSelection = ProjectCleanupSelection(inventory: result)
                projectInventoryState = .ready
            case let .failure(message):
                projectInventory = ProjectInventoryResult()
                projectCleanupSelection = ProjectCleanupSelection()
                projectInventoryState = .failed(CrabL10n.language == .simplifiedChinese
                    ? "项目扫描失败：\(message)"
                    : "The project scan could not be completed. No files were changed.")
            }
        }
    }

    func requestProjectScanAccess() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let panel = NSOpenPanel()
        panel.title = CrabL10n.text("授权项目扫描", "Authorize Project Scanning")
        panel.message = CrabL10n.text(
            "请选择你的个人文件夹。Crab 会保存这一次授权，以后自动扫描；扫描只读取文件名、大小和修改时间。",
            "Select your Home folder. Crab will save this authorization for future scans and read only filenames, sizes, and modification dates."
        )
        panel.prompt = CrabL10n.text("授权并扫描", "Authorize and Scan")
        panel.directoryURL = homeDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            if projectScanAccessState == .unknown {
                projectScanAccessState = .needsAuthorization
            }
            return
        }

        do {
            let root = try ProjectScanAccessPolicy.authorizedRoot(
                selectedURL: selectedURL,
                homeURL: homeDirectory
            )
            try saveProjectScanBookmark(for: root)
            projectScanAccessState = .authorized
            projectInventoryState = .idle
            scanProjects(force: true)
        } catch {
            projectScanAccessState = .failed(String(describing: error))
            projectInventoryState = .idle
        }
    }

    func setProjectSelected(_ projectID: URL, selected: Bool) {
        guard projectCleanupState != .moving else { return }
        projectCleanupSelection.setSelected(projectID, selected: selected)
    }

    func setProjectsSelected(_ projects: [ProjectInventoryItem], selected: Bool) {
        guard projectCleanupState != .moving else { return }
        projectCleanupSelection.setSelected(projects, selected: selected)
    }

    func allProjectsAreSelected(in projects: [ProjectInventoryItem]) -> Bool {
        !projects.isEmpty && projects.allSatisfy {
            projectCleanupSelection.selectedProjectIDs.contains($0.id)
        }
    }

    func moveSelectedProjectsToTrash() {
        guard projectCleanupState != .moving else { return }
        guard let scanRoot = restoreProjectScanRoot() else {
            projectCleanupState = .failed(CrabL10n.text(
                "项目访问授权已失效，请重新授权后再试。",
                "Project access has expired. Authorize your Home folder again and retry."
            ))
            return
        }

        let plan: ProjectCleanupPlan
        do {
            plan = try ProjectCleanupPlanBuilder().build(
                inventory: projectInventory,
                selectedProjectIDs: projectCleanupSelection.selectedProjectIDs,
                homeURL: scanRoot
            )
        } catch {
            projectCleanupState = .failed(String(describing: error))
            return
        }

        projectCleanupState = .moving
        Task {
            let work = await Task.detached(priority: .userInitiated) {
                let accessed = scanRoot.startAccessingSecurityScopedResource()
                defer { if accessed { scanRoot.stopAccessingSecurityScopedResource() } }
                do {
                    let receipt = try ProjectCleanupExecutor(
                        trashMover: SystemTrashMover()
                    ).execute(plan: plan)
                    return ProjectCleanupWorkResult.success(receipt)
                } catch {
                    return ProjectCleanupWorkResult.failure(String(describing: error))
                }
            }.value

            switch work {
            case let .success(receipt):
                projectCleanupState = .succeeded(projectCleanupSummary(receipt))
                scanProjects(force: true)
            case let .failure(message):
                projectCleanupState = .failed(CrabL10n.language == .simplifiedChinese
                    ? "没有处理已变化的项目：\(message)"
                    : "Some projects changed before they could be moved. No changed project was processed.")
                scanProjects(force: true)
            }
        }
    }

    func dismissProjectCleanupResult() {
        projectCleanupState = .idle
    }

    private func projectCleanupSummary(_ receipt: CleanupReceipt) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(receipt.moved.logicalBytes),
            countStyle: .file
        )
        var parts = [CrabL10n.format(
            "已将 %d 个项目（%@）移入废纸篓",
            "%d projects (%@) moved to Trash",
            receipt.moved.count,
            size
        )]
        if receipt.skipped.count > 0 {
            parts.append(CrabL10n.format("跳过 %d 个", "%d skipped", receipt.skipped.count))
        }
        if receipt.failed.count > 0 {
            parts.append(CrabL10n.format("失败 %d 个", "%d failed", receipt.failed.count))
        }
        return parts.joined(separator: CrabL10n.text("；", "; "))
            + CrabL10n.text("。清空废纸篓前仍可恢复。", ". Items can be restored until Trash is emptied.")
    }

    func revealProjectInFinder(_ project: ProjectInventoryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([project.path])
    }

    func refreshHarnessInventory(force: Bool = false) {
        guard inventoryState.permitsRefresh(force: force) else { return }
        let refreshStartedAt = Date()
        crabPerformanceLogger.info("Application inventory refresh started")
        let generation = UUID()
        inventoryGeneration = generation
        inventoryState = .loading
        harnessMetadataIsLoading = true
        harnessMetadataTask?.cancel()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let roots = harnessApplicationRoots(homeDirectory: homeDirectory)
        let executableRoots = harnessExecutableRoots(homeDirectory: homeDirectory)
        let cachedProjectInventory = projectInventoryState == .ready ? projectInventory : nil

        Task {
            let work = await Task.detached(priority: .utility) {
                let inventory = HarnessInventoryScanner().scan(
                    definitions: HarnessCatalog.supported,
                    applicationRoots: roots,
                    executableRoots: executableRoots,
                    measureInstalledBytes: false,
                    lastUsedDateProvider: { _ in nil }
                )
                let usage = HarnessUsageScanner().scan(
                    installedAppIDs: inventory.installedAppIDs,
                    projectInventory: cachedProjectInventory,
                    homeURL: homeDirectory
                )
                return HarnessInventoryWorkResult.success(
                    inventory: inventory,
                    projectInventory: cachedProjectInventory,
                    usage: usage
                )
            }.value

            guard inventoryGeneration == generation else { return }
            switch work {
            case let .success(inventory, scannedProjects, usage):
                harnessInventory = inventory
                harnessUsageByAppID = usage
                if let scannedProjects {
                    projectInventory = scannedProjects
                    projectCleanupSelection = ProjectCleanupSelection(inventory: scannedProjects)
                    projectInventoryState = .ready
                }
                inventoryState = .ready
                crabPerformanceLogger.info(
                    "Application inventory ready in \(Date().timeIntervalSince(refreshStartedAt), privacy: .public) seconds"
                )
                enrichHarnessMetadata(in: inventory, generation: generation)
            case let .failure(message):
                harnessMetadataIsLoading = false
                inventoryState = .failed(message)
            }
        }
    }

    private func enrichHarnessMetadata(in inventory: HarnessInventory, generation: UUID) {
        harnessMetadataTask = Task {
            let activityInventory = await Task.detached(priority: .utility) {
                HarnessInventoryScanner().measuringLastUsedDates(in: inventory)
            }.value
            guard !Task.isCancelled, inventoryGeneration == generation else { return }
            harnessInventory = activityInventory

            let completeInventory = await Task.detached(priority: .background) {
                HarnessInventoryScanner().measuringInstalledBytes(in: activityInventory)
            }.value
            guard !Task.isCancelled, inventoryGeneration == generation else { return }
            harnessInventory = completeInventory
            harnessMetadataIsLoading = false
        }
    }

    private func acceptLightweightHarnessInventory(_ inventory: HarnessInventory) {
        guard harnessInventory.installations.isEmpty
                || harnessInventory.installedAppIDs != inventory.installedAppIDs
        else { return }
        harnessInventory = inventory
        harnessUsageByAppID = [:]
        inventoryState = .idle
    }

    func setSelected(_ ruleID: RuleID, selected: Bool) {
        guard
            let candidate = snapshot.candidates.first(where: { $0.rule.id == ruleID }),
            !isApplicationRunning(for: candidate)
        else { return }
        cacheWorkflow.setSelected(ruleID, selected: selected)
    }

    func setAllSelected(in candidates: [ScanCandidate], selected: Bool) {
        let ruleIDs = selected
            ? candidates.filter { !isApplicationRunning(for: $0) }.map(\.rule.id)
            : candidates.map(\.rule.id)
        cacheWorkflow.setSelected(ruleIDs, selected: selected)
    }

    func canToggleBulkSelection(in candidates: [ScanCandidate]) -> Bool {
        candidates.contains { candidate in
            !isApplicationRunning(for: candidate)
                || snapshot.selectedRuleIDs.contains(candidate.rule.id)
        }
    }

    func areAllSelectableCandidatesSelected(in candidates: [ScanCandidate]) -> Bool {
        let selectableRuleIDs = candidates
            .filter { !isApplicationRunning(for: $0) }
            .map(\.rule.id)
        if selectableRuleIDs.isEmpty {
            return candidates.contains { snapshot.selectedRuleIDs.contains($0.rule.id) }
        }
        return selectableRuleIDs.allSatisfy(snapshot.selectedRuleIDs.contains)
    }

    func selectRecommended() {
        cacheWorkflow.selectRecommended()
        for candidate in snapshot.candidates where isApplicationRunning(for: candidate) {
            cacheWorkflow.setSelected(candidate.rule.id, selected: false)
        }
    }

    func chooseArchiveFolder() {
        let panel = NSOpenPanel()
        panel.title = CrabL10n.text("选择项目所在的文件夹", "Choose a Project Folder")
        panel.message = CrabL10n.text(
            "Crab 只读取这个文件夹下一级项目的文件元数据。",
            "Crab reads only file metadata for projects directly inside this folder."
        )
        panel.prompt = CrabL10n.text("选择文件夹", "Choose Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanArchive(rootURL: url)
    }

    func rescanArchive() {
        guard let rootURL = archiveState.rootURL else {
            chooseArchiveFolder()
            return
        }
        scanArchive(rootURL: rootURL)
    }

    func revealInFinder(_ entry: ArchiveSnapshotEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.path])
    }

    private func scanArchive(rootURL: URL) {
        let generation = UUID()
        archiveGeneration = generation
        archiveState.beginScanning(rootURL: rootURL)
        let inactivityDays = archiveState.inactivityDays
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

        Task {
            let work = await Task.detached(priority: .userInitiated) {
                do {
                    let result = try ArchiveScanner().scan(
                        rootURL: rootURL,
                        homeURL: homeDirectory,
                        inactivityDays: inactivityDays
                    )
                    let snapshot = try ArchiveSnapshotBuilder().build(from: result)
                    return ArchiveWorkResult.success(snapshot)
                } catch {
                    return ArchiveWorkResult.failure(String(describing: error))
                }
            }.value

            guard archiveGeneration == generation else { return }
            switch work {
            case let .success(snapshot):
                archiveState.finish(with: snapshot)
            case let .failure(message):
                archiveState.fail(message: CrabL10n.language == .simplifiedChinese
                    ? "无法扫描所选文件夹：\(message)"
                    : "The selected folder could not be scanned. No files were changed.")
            }
        }
    }

    func isApplicationRunning(for candidate: ScanCandidate) -> Bool {
        guard candidate.rule.requiresAppStopped else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == candidate.rule.appID
        }
    }

    func appName(for candidate: ScanCandidate) -> String {
        appName(forAppID: candidate.rule.appID)
    }

    func appName(forAppID appID: String) -> String {
        HarnessCatalog.definition(for: appID)?.displayName ?? appID
    }

    func cacheBytes(for appID: String) -> UInt64 {
        snapshot.candidates
            .filter { $0.rule.appID == appID }
            .reduce(0) { $0 + $1.logicalBytes }
    }

    func isHarnessRunning(_ installation: HarnessInstallation) -> Bool {
        SystemApplicationActivityChecker().isApplicationRunning(bundleIdentifier: installation.appID)
    }

    func revealHarnessInstallation(_ installation: HarnessInstallation) {
        NSWorkspace.shared.activateFileViewerSelecting([installation.bundleURL])
    }

    func uninstallHarness(_ installation: HarnessInstallation) {
        if case .moving = harnessUninstallState { return }
        if isHarnessRunning(installation) {
            harnessUninstallState = .failed(CrabL10n.format(
                "请先退出 %@，然后再卸载。",
                "Quit %@ before uninstalling it.",
                installation.displayName
            ))
            return
        }
        harnessResidueIcon = NSWorkspace.shared.icon(forFile: installation.bundleURL.path)
        harnessUninstallState = .moving(installation.appID)
        let roots = harnessApplicationRoots(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )

        Task {
            let work = await Task.detached(priority: .userInitiated) {
                do {
                    let receipt = try HarnessUninstaller(
                        trashMover: SystemTrashMover(),
                        applicationChecker: SystemApplicationActivityChecker()
                    ).uninstall(
                        installation: installation,
                        allowedApplicationRoots: roots
                    )
                    return HarnessUninstallWorkResult.success(receipt)
                } catch {
                    return HarnessUninstallWorkResult.failure(String(describing: error))
                }
            }.value

            switch work {
            case let .success(receipt):
                harnessInventory = HarnessInventory(
                    installations: harnessInventory.installations.filter { $0.appID != receipt.appID }
                )
                harnessUsageByAppID[receipt.appID] = nil
                scanOverview = AppScanOverview(
                    products: scanOverview.products.filter { $0.appID != receipt.appID }
                )
                harnessUninstallState = .idle
                inventoryState = .idle
                refreshHarnessInventory(force: true)
                scanHarnessResidues(afterUninstalling: installation)
            case let .failure(message):
                harnessResidueIcon = nil
                harnessUninstallState = .failed(CrabL10n.language == .simplifiedChinese
                    ? "卸载未完成：\(message)"
                    : "The app could not be uninstalled. Its user data was not changed.")
            }
        }
    }

    func dismissHarnessUninstallResult() {
        harnessUninstallState = .idle
    }

    func setHarnessResidueSelected(_ ruleID: HarnessResidueID, selected: Bool) {
        guard harnessResidueState == .reviewing else { return }
        harnessResidueSnapshot.setSelected(ruleID, selected: selected)
    }

    func selectRecommendedHarnessResidues() {
        guard harnessResidueState == .reviewing else { return }
        harnessResidueSnapshot.selectRecommended()
    }

    func clearHarnessResidueSelection() {
        guard harnessResidueState == .reviewing else { return }
        harnessResidueSnapshot.clearSelection()
    }

    func skipHarnessResidueCleanup() {
        let appName = harnessResidueAppName
        resetHarnessResidueReview()
        harnessUninstallState = .succeeded(
            CrabL10n.format(
                "已将 %@ 应用本体移入废纸篓。发现的残留均已保留，之后仍可通过缓存清理处理可再生缓存。",
                "The %@ app was moved to Trash. All detected residues were kept; regenerable caches can still be handled in Cache Cleanup.",
                appName
            )
        )
    }

    func cleanSelectedHarnessResidues() {
        guard harnessResidueState == .reviewing,
              !harnessResidueSnapshot.selectedRuleIDs.isEmpty
        else { return }

        let plan: HarnessResiduePlan
        do {
            plan = try HarnessResiduePlanBuilder().build(
                candidates: harnessResidueSnapshot.candidates,
                selectedRuleIDs: harnessResidueSnapshot.selectedRuleIDs
            )
        } catch {
            harnessResidueState = .failed(CrabL10n.language == .simplifiedChinese
                ? "无法创建安全清理计划：\(error)"
                : "Crab could not create a safe cleanup plan. No residues were changed.")
            return
        }

        let rules = harnessResidueRules
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        harnessResidueState = .cleaning
        Task {
            let work = await Task.detached(priority: .userInitiated) {
                do {
                    let receipt = try HarnessResidueCleanupExecutor(
                        trashMover: SystemTrashMover(),
                        applicationChecker: SystemApplicationActivityChecker()
                    ).execute(plan: plan, rules: rules, homeURL: homeDirectory)
                    return HarnessResidueCleanupWorkResult.success(receipt)
                } catch {
                    return HarnessResidueCleanupWorkResult.failure(String(describing: error))
                }
            }.value

            switch work {
            case let .success(receipt):
                let appName = harnessResidueAppName
                let summary = residueCleanupSummary(receipt)
                resetHarnessResidueReview()
                harnessUninstallState = .succeeded(CrabL10n.format(
                    "%@ 已卸载；%@",
                    "%@ was uninstalled. %@",
                    appName,
                    summary
                ))
            case let .failure(message):
                harnessResidueState = .failed(CrabL10n.language == .simplifiedChinese
                    ? "残留未被清理：\(message)"
                    : "Residues could not be cleaned. No unverified data was changed.")
            }
        }
    }

    func dismissHarnessResidueResult() {
        let appName = harnessResidueAppName
        resetHarnessResidueReview()
        harnessUninstallState = .succeeded(
            CrabL10n.format(
                "已将 %@ 应用本体移入废纸篓。无法安全确认的残留均已保留。",
                "The %@ app was moved to Trash. All residues that could not be safely verified were kept.",
                appName
            )
        )
    }

    private func scanHarnessResidues(afterUninstalling installation: HarnessInstallation) {
        let generation = UUID()
        harnessResidueGeneration = generation
        harnessResidueAppID = installation.appID
        harnessResidueAppName = installation.displayName
        harnessResidueSnapshot = HarnessResidueSnapshot()
        harnessResidueIssues = []
        harnessResidueRules = []
        harnessResidueState = .scanning

        guard let resources = Bundle.main.resourceURL else {
            harnessResidueState = .failed(CrabL10n.text(
                "无法读取 Crab 的安全规则，未扫描或清理任何残留。",
                "Crab could not read its safety rules. No residues were scanned or cleaned."
            ))
            return
        }
        let ruleDirectory = resources.appendingPathComponent("Rules", isDirectory: true)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let definition = installation.definition

        Task {
            let work = await Task.detached(priority: .userInitiated) {
                do {
                    let cacheRules = try RuleLoader().load(directory: ruleDirectory)
                    let rules = HarnessResidueCatalog.rules(for: definition, cacheRules: cacheRules)
                    let result = HarnessResidueScanner().scan(rules: rules, homeURL: homeDirectory)
                    return HarnessResidueScanWorkResult.success(rules: rules, result: result)
                } catch {
                    return HarnessResidueScanWorkResult.failure(String(describing: error))
                }
            }.value

            guard harnessResidueGeneration == generation else { return }
            switch work {
            case let .success(rules, result):
                harnessResidueRules = rules
                harnessResidueIssues = result.issues
                harnessResidueSnapshot = HarnessResidueSnapshot(candidates: result.candidates)
                if result.candidates.isEmpty {
                    if result.issues.isEmpty {
                        let appName = harnessResidueAppName
                        resetHarnessResidueReview()
                        harnessUninstallState = .succeeded(
                            CrabL10n.format(
                                "已将 %@ 应用本体移入废纸篓，未发现可确认的残留资源。",
                                "The %@ app was moved to Trash. No verified residues were found.",
                                appName
                            )
                        )
                    } else {
                        harnessResidueState = .failed(CrabL10n.text(
                            "部分路径无法安全读取，Crab 未清理任何残留。",
                            "Some paths could not be read safely. Crab did not clean any residues."
                        ))
                    }
                } else {
                    harnessResidueState = .reviewing
                }
            case let .failure(message):
                harnessResidueState = .failed(CrabL10n.language == .simplifiedChinese
                    ? "残留扫描未完成：\(message)。Crab 未清理任何残留。"
                    : "The residue scan could not be completed. Crab did not clean any residues.")
            }
        }
    }

    private func resetHarnessResidueReview() {
        harnessResidueGeneration = UUID()
        harnessResidueState = .idle
        harnessResidueSnapshot = HarnessResidueSnapshot()
        harnessResidueIssues = []
        harnessResidueRules = []
        harnessResidueAppID = ""
        harnessResidueAppName = ""
        harnessResidueIcon = nil
    }

    private func residueCleanupSummary(_ receipt: CleanupReceipt) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(receipt.moved.logicalBytes),
            countStyle: .file
        )
        var parts = [CrabL10n.format(
            "已将 %d 项残留（%@）移入废纸篓",
            "%d residues (%@) moved to Trash",
            receipt.moved.count,
            size
        )]
        if receipt.skipped.count > 0 {
            parts.append(CrabL10n.format("跳过 %d 项", "%d skipped", receipt.skipped.count))
        }
        if receipt.failed.count > 0 {
            parts.append(CrabL10n.format("失败 %d 项", "%d failed", receipt.failed.count))
        }
        return parts.joined(separator: CrabL10n.text("；", "; "))
            + CrabL10n.text("。清空废纸篓前仍可恢复。", ". Items can be restored until Trash is emptied.")
    }

    private func harnessApplicationRoots(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    private func restoreProjectScanRoot() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: projectScanBookmarkKey) else {
            projectScanAccessState = .needsAuthorization
            return nil
        }

        do {
            var isStale = false
            let bookmarkedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let root = try SecurityScopedResourceAccess.withAccess(to: bookmarkedURL) {
                let authorizedRoot = try ProjectScanAccessPolicy.authorizedRoot(
                    selectedURL: bookmarkedURL,
                    homeURL: FileManager.default.homeDirectoryForCurrentUser
                )
                if isStale {
                    try saveProjectScanBookmark(for: authorizedRoot)
                }
                return authorizedRoot
            }
            projectScanAccessState = .authorized
            return root
        } catch {
            UserDefaults.standard.removeObject(forKey: projectScanBookmarkKey)
            projectScanAccessState = .needsAuthorization
            return nil
        }
    }

    private func saveProjectScanBookmark(for root: URL) throws {
        let bookmarkData = try root.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: projectScanBookmarkKey)
    }

    private func harnessExecutableRoots(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/pnpm", isDirectory: true),
        ]
    }

    func moveSelectedToTrash() {
        guard cleanupState != .moving else { return }

        let runningSelections = snapshot.candidates.filter {
            snapshot.selectedRuleIDs.contains($0.rule.id) && isApplicationRunning(for: $0)
        }
        guard runningSelections.isEmpty else {
            let names = Set(runningSelections.map(appName)).sorted().joined(
                separator: CrabL10n.text("、", ", ")
            )
            cleanupState = .failed(CrabL10n.format(
                "请先退出 %@，然后重新确认。",
                "Quit %@, then confirm again.",
                names
            ))
            return
        }

        let plan: CleanPlan
        do {
            plan = try PlanBuilder().build(
                candidates: snapshot.candidates,
                selectedRuleIDs: snapshot.selectedRuleIDs
            )
        } catch {
            cleanupState = .failed(String(describing: error))
            return
        }

        let selectedIDs = snapshot.selectedRuleIDs
        let rules = loadedRules.filter { selectedIDs.contains($0.id) }
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        cleanupState = .moving

        Task {
            let work = await Task.detached(priority: .userInitiated) {
                do {
                    let receipt = try CleanupExecutor(
                        trashMover: SystemTrashMover(),
                        applicationChecker: SystemApplicationActivityChecker()
                    ).execute(
                        plan: plan,
                        rules: rules,
                        homeURL: homeDirectory
                    )
                    return CleanupWorkResult.success(receipt)
                } catch {
                    return CleanupWorkResult.failure(String(describing: error))
                }
            }.value

            switch work {
            case let .success(receipt):
                cleanupState = .succeeded(cleanupSummary(receipt))
                scanUserCaches()
            case let .failure(message):
                cleanupState = .failed(CrabL10n.language == .simplifiedChinese
                    ? "操作未完全完成，请以重新扫描结果为准：\(message)"
                    : "The operation did not fully complete. Refer to the new scan results for the current state.")
                scanUserCaches()
            }
        }
    }

    func dismissCleanupResult() {
        cleanupState = .idle
    }

    private func cleanupSummary(_ receipt: CleanupReceipt) -> String {
        let movedSize = ByteCountFormatter.string(
            fromByteCount: Int64(receipt.moved.logicalBytes),
            countStyle: .file
        )
        var parts = [CrabL10n.format(
            "已将 %d 项（%@）移入废纸篓",
            "%d items (%@) moved to Trash",
            receipt.moved.count,
            movedSize
        )]
        if receipt.skipped.count > 0 {
            parts.append(CrabL10n.format("跳过 %d 项", "%d skipped", receipt.skipped.count))
        }
        if receipt.failed.count > 0 {
            parts.append(CrabL10n.format("失败 %d 项", "%d failed", receipt.failed.count))
        }
        return parts.joined(separator: CrabL10n.text("；", "; "))
            + CrabL10n.text(
                "。只有已移动项目计入回收空间，可在清空废纸篓前恢复。",
                ". Only moved items count toward reclaimed space and can be restored until Trash is emptied."
            )
    }
}
