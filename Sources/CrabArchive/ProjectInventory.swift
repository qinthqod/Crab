import Darwin
import Foundation

public struct ProjectApplicationRule: Equatable, Sendable {
    public let appID: String
    public let displayName: String
    public let markerNames: [String]

    public init(appID: String, displayName: String, markerNames: [String]) {
        self.appID = appID
        self.displayName = displayName
        self.markerNames = markerNames
    }
}

public struct ProjectInventoryItem: Identifiable, Equatable, Sendable {
    public let path: URL
    public let identity: ArchiveFileIdentity
    public let primaryAppID: String
    public let relatedAppIDs: [String]
    public let latestActivity: Date
    public let logicalBytes: UInt64
    public let fileCount: UInt64
    public let isInactive: Bool
    public internal(set) var cleanupBlockReason: ProjectCleanupBlockReason? = nil
    public internal(set) var inspectionIssues: [ProjectInspectionIssue] = []
    public internal(set) var inspectionIssueCount: Int = 0
    public internal(set) var symbolicLinks: [ProjectSymbolicLink] = []

    public var canClean: Bool { cleanupBlockReason == nil }

    public var id: URL { path }
}

public enum ProjectCleanupBlockReason: Equatable, Sendable {
    case incompleteInspection
    case inspectionLimitReached
    case symbolicLink
    case protectedDirectory
    case unsupportedEntry
    case changedDuringInspection
}

public struct ProjectInventoryProgress: Equatable, Sendable {
    public var discoveredEntryCount: Int = 0
    public var inspectedEntryCount: Int = 0
    public var inspectedProjectCount: Int = 0

    public init() {}
}

/// Metadata for actionable diagnostics. Reading the destination does not follow a link.
public struct ProjectInspectionIssue: Identifiable, Equatable, Sendable {
    public let path: URL
    public let reason: ProjectCleanupBlockReason
    public let linkDestination: String?
    public var id: URL { path }
}

/// The link entry belongs to the project; its target is never traversed.
public struct ProjectSymbolicLink: Equatable, Sendable {
    public let path: URL
    public let destination: String
    private let device: UInt64
    private let inode: UInt64
    private let byteCount: Int64
    private let modifiedSeconds: Int
    private let modifiedNanoseconds: Int
    private let changedSeconds: Int
    private let changedNanoseconds: Int

    init(path: URL, destination: String, metadata: stat) {
        self.path = path
        self.destination = destination
        device = UInt64(metadata.st_dev)
        inode = UInt64(metadata.st_ino)
        byteCount = metadata.st_size
        modifiedSeconds = metadata.st_mtimespec.tv_sec
        modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
        changedSeconds = metadata.st_ctimespec.tv_sec
        changedNanoseconds = metadata.st_ctimespec.tv_nsec
    }
}

public struct ProjectInventoryResult: Equatable, Sendable {
    public let scannedAt: Date
    public let projects: [ProjectInventoryItem]
    public let skippedDirectoryCount: Int
    public let discoveryWasLimited: Bool

    public var inspectionLimitedProjectCount: Int {
        projects.filter { $0.cleanupBlockReason == .inspectionLimitReached }.count
    }

    public var hasIncompleteResults: Bool {
        discoveryWasLimited || skippedDirectoryCount > 0 || projects.contains { !$0.canClean }
    }

    public init(
        scannedAt: Date = Date(),
        projects: [ProjectInventoryItem] = [],
        skippedDirectoryCount: Int = 0,
        discoveryWasLimited: Bool = false
    ) {
        self.scannedAt = scannedAt
        self.projects = projects.sorted { $0.path.path.localizedStandardCompare($1.path.path) == .orderedAscending }
        self.skippedDirectoryCount = skippedDirectoryCount
        self.discoveryWasLimited = discoveryWasLimited
    }
}

public enum ProjectInventoryScanError: Error, Equatable, CustomStringConvertible {
    case invalidConfiguration
    case invalidRoot(String)
    case traversalLimitExceeded(Int)

    public var description: String {
        switch self {
        case .invalidConfiguration:
            "项目扫描配置无效。"
        case let .invalidRoot(path):
            "无法扫描项目目录：\(path)"
        case let .traversalLimitExceeded(limit):
            "项目扫描已达到 \(limit) 项安全上限。"
        }
    }
}

public enum ProjectInventoryVerificationError: Error, Equatable, CustomStringConvertible {
    case staleEvidence
    case unsafePath(String)
    case missingPath(String)
    case changed(String)

    public var description: String {
        switch self {
        case .staleEvidence:
            "项目扫描结果已过期，请重新扫描后再试。"
        case let .unsafePath(path):
            "项目路径不在 Crab 的安全清理范围内：\(path)"
        case let .missingPath(path):
            "项目已经不存在：\(path)"
        case let .changed(path):
            "项目在确认后发生了变化，已停止处理：\(path)"
        }
    }
}

public struct ProjectInventoryScanner: Sendable {
    private let maxEntries: Int?
    private let maxDepth: Int?
    private let inactivityDays: Int
    private let maxProjectEntries: Int?
    private let maxInspectionEntries: Int?

    public init(
        maxEntries: Int? = nil, maxDepth: Int? = nil, inactivityDays: Int = 180,
        maxProjectEntries: Int? = nil, maxInspectionEntries: Int? = nil
    ) {
        self.maxEntries = maxEntries
        self.maxDepth = maxDepth
        self.inactivityDays = inactivityDays
        self.maxProjectEntries = maxProjectEntries
        self.maxInspectionEntries = maxInspectionEntries
    }

    public func scan(
        rootURLs: [URL],
        rules: [ProjectApplicationRule],
        installedAppIDs: Set<String>,
        evidencedProjectURLsByAppID: [String: [URL]] = [:],
        now: Date = Date(),
        onProgress: (@Sendable (ProjectInventoryProgress) -> Void)? = nil
    ) throws -> ProjectInventoryResult {
        // Interactive scans run to completion. Optional budgets remain available to
        // callers that explicitly request bounded scans; they never authorize cleanup.
        guard [maxEntries, maxDepth, maxProjectEntries, maxInspectionEntries]
            .allSatisfy({ $0.map { $0 > 0 } ?? true }), inactivityDays > 0 else {
            throw ProjectInventoryScanError.invalidConfiguration
        }

        let eligibleRules = rules.filter { installedAppIDs.contains($0.appID) && !$0.markerNames.isEmpty }
        guard !eligibleRules.isEmpty else {
            return ProjectInventoryResult(scannedAt: now)
        }

        var context = ScanContext(maxEntries: maxEntries, onProgress: onProgress)
        context.reportProgress(force: true)
        for rootURL in rootURLs {
            let root = rootURL.standardizedFileURL
            var rootMetadata = stat()
            guard lstat(root.path, &rootMetadata) == 0,
                  rootMetadata.st_mode & S_IFMT == S_IFDIR
            else { throw ProjectInventoryScanError.invalidRoot(root.path) }

            do {
                try discoverProjects(
                    in: root,
                    depth: 0,
                    scanRoot: root,
                    rootDevice: UInt64(rootMetadata.st_dev),
                    rules: eligibleRules,
                    now: now,
                    context: &context
                )
            } catch ProjectInventoryScanError.traversalLimitExceeded {
                // Retain verified results and still process explicit indexed roots.
                context.discoveryWasLimited = true
            }
            try addEvidencedProjects(
                in: root,
                rootDevice: UInt64(rootMetadata.st_dev),
                rules: eligibleRules,
                projectURLsByAppID: evidencedProjectURLsByAppID,
                now: now,
                context: &context
            )
        }

        try Task.checkCancellation()
        context.reportProgress(force: true)
        return ProjectInventoryResult(
            scannedAt: now,
            projects: context.projects,
            skippedDirectoryCount: context.skippedDirectoryCount,
            discoveryWasLimited: context.discoveryWasLimited
        )
    }

    private func addEvidencedProjects(
        in scanRoot: URL,
        rootDevice: UInt64,
        rules: [ProjectApplicationRule],
        projectURLsByAppID: [String: [URL]],
        now: Date,
        context: inout ScanContext
    ) throws {
        let eligibleAppIDs = Set(rules.map(\.appID))
        var appIDsByPath: [String: Set<String>] = [:]
        for (appID, projectURLs) in projectURLsByAppID where eligibleAppIDs.contains(appID) {
            for projectURL in projectURLs {
                appIDsByPath[projectURL.standardizedFileURL.path, default: []].insert(appID)
            }
        }

        for path in appIDsByPath.keys.sorted() {
            try Task.checkCancellation()
            let projectURL = URL(fileURLWithPath: path, isDirectory: true)
            guard isSafeEvidencedProject(projectURL, scanRoot: scanRoot, rootDevice: rootDevice),
                  let appIDs = appIDsByPath[path],
                  !appIDs.isEmpty
            else { continue }

            if let index = context.projects.firstIndex(where: { $0.path.path == path }) {
                let project = context.projects[index]
                let relatedAppIDs = Set(project.relatedAppIDs).union(appIDs).sorted()
                context.projects[index] = ProjectInventoryItem(
                    path: project.path,
                    identity: project.identity,
                    primaryAppID: appIDs.sorted()[0],
                    relatedAppIDs: relatedAppIDs,
                    latestActivity: project.latestActivity,
                    logicalBytes: project.logicalBytes,
                    fileCount: project.fileCount,
                    isInactive: project.isInactive,
                    cleanupBlockReason: project.cleanupBlockReason,
                    inspectionIssues: project.inspectionIssues,
                    inspectionIssueCount: project.inspectionIssueCount,
                    symbolicLinks: project.symbolicLinks
                )
                continue
            }

            let totals = try summarizeProject(
                projectURL,
                scanRoot: scanRoot,
                rootDevice: rootDevice,
                context: &context
            )
            guard !totals.containsProtectedMedia else { continue }
            let cutoff = now.addingTimeInterval(-TimeInterval(inactivityDays) * 86_400)
            let sortedAppIDs = appIDs.sorted()
            context.seenProjectPaths.insert(path)
            context.projects.append(ProjectInventoryItem(
                path: projectURL,
                identity: totals.identity,
                primaryAppID: sortedAppIDs[0],
                relatedAppIDs: sortedAppIDs,
                latestActivity: totals.latestActivity,
                logicalBytes: totals.logicalBytes,
                fileCount: totals.fileCount,
                isInactive: !totals.inspectionIncomplete && totals.latestActivity < cutoff,
                cleanupBlockReason: totals.cleanupBlockReason,
                inspectionIssues: totals.issues,
                inspectionIssueCount: totals.issueCount,
                symbolicLinks: totals.symbolicLinks
            ))
        }
    }

    private func isSafeEvidencedProject(
        _ projectURL: URL,
        scanRoot: URL,
        rootDevice: UInt64
    ) -> Bool {
        let root = scanRoot.standardizedFileURL
        let project = projectURL.standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard project.path.hasPrefix(rootPrefix) else { return false }

        let relativePath = String(project.path.dropFirst(rootPrefix.count))
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              !isProtectedMediaRootName(components[0]),
              components.allSatisfy({ !shouldSkipDirectory(named: $0) && !isMediaLibraryName($0) })
        else { return false }

        var cursor = root
        for component in components {
            cursor.appendPathComponent(component, isDirectory: true)
            var metadata = stat()
            guard lstat(cursor.path, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFDIR,
                  UInt64(metadata.st_dev) == rootDevice
            else { return false }
        }
        return true
    }

    private func discoverProjects(
        in directory: URL,
        depth: Int,
        scanRoot: URL,
        rootDevice: UInt64,
        rules: [ProjectApplicationRule],
        now: Date,
        context: inout ScanContext
    ) throws {
        // An explicit stack avoids call-stack growth when scanning deep project trees.
        var pending: [(url: URL, depth: Int, isEntry: Bool)] = [(directory, depth, false)]
        while let (directory, depth, isEntry) = pending.popLast() {
            try Task.checkCancellation()
            if isEntry {
                try context.visit()
                guard !shouldSkipDirectory(directory, scanRoot: scanRoot) else { continue }
                var metadata = stat()
                guard lstat(directory.path, &metadata) == 0,
                      metadata.st_mode & S_IFMT == S_IFDIR,
                      UInt64(metadata.st_dev) == rootDevice else { continue }
            }
            if let maxDepth, depth > maxDepth {
                context.discoveryWasLimited = true
                continue
            }
            guard context.seenDiscoveryPaths.insert(directory.path).inserted else { continue }
            guard !isProtectedMediaDirectory(directory, scanRoot: scanRoot) else { continue }
            let entries: [URL]
            do {
                entries = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            } catch {
                context.skippedDirectoryCount += 1
                continue
            }

            let names = Set(entries.map(\.lastPathComponent))
            let matches = rules.filter { !names.isDisjoint(with: $0.markerNames) }
            if depth > 0,
               !matches.isEmpty,
               hasProjectBoundary(in: names),
               context.seenProjectPaths.insert(directory.path).inserted {
                let primary = primaryRule(from: matches, entries: entries)
                let totals = try summarizeProject(
                    directory,
                    scanRoot: scanRoot,
                    rootDevice: rootDevice,
                    context: &context
                )
                guard !totals.containsProtectedMedia else { continue }
                let cutoff = now.addingTimeInterval(-TimeInterval(inactivityDays) * 86_400)
                context.projects.append(ProjectInventoryItem(
                    path: directory.standardizedFileURL,
                    identity: totals.identity,
                    primaryAppID: primary.appID,
                    relatedAppIDs: matches.map(\.appID).sorted(),
                    latestActivity: totals.latestActivity,
                    logicalBytes: totals.logicalBytes,
                    fileCount: totals.fileCount,
                    isInactive: !totals.inspectionIncomplete && totals.latestActivity < cutoff,
                    cleanupBlockReason: totals.cleanupBlockReason,
                    inspectionIssues: totals.issues,
                    inspectionIssueCount: totals.issueCount,
                    symbolicLinks: totals.symbolicLinks
                ))
            }

            for entry in entries.sorted(by: { $0.path > $1.path }) {
                pending.append((entry, depth + 1, true))
            }
        }
    }

    public func revalidateForTrash(
        _ project: ProjectInventoryItem,
        homeURL: URL,
        scannedAt: Date,
        now: Date = Date(),
        maxEvidenceAge: TimeInterval = 600
    ) throws -> ProjectInventoryItem {
        guard project.canClean else {
            throw ProjectInventoryVerificationError.unsafePath(project.path.path)
        }
        let evidenceAge = now.timeIntervalSince(scannedAt)
        guard maxEvidenceAge > 0, evidenceAge >= 0, evidenceAge <= maxEvidenceAge else {
            throw ProjectInventoryVerificationError.staleEvidence
        }

        let home = homeURL.standardizedFileURL
        let path = project.path.standardizedFileURL
        let homePrefix = home.path.hasSuffix("/") ? home.path : home.path + "/"
        guard path.path.hasPrefix(homePrefix), path.path != home.path else {
            throw ProjectInventoryVerificationError.unsafePath(path.path)
        }

        let relativePath = String(path.path.dropFirst(homePrefix.count))
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.first != "Library",
              components.first != "Applications",
              components.first != ".Trash",
              !isProtectedMediaRootName(components[0]),
              components.allSatisfy({ !shouldSkipDirectory(named: $0) && !isMediaLibraryName($0) })
        else {
            throw ProjectInventoryVerificationError.unsafePath(path.path)
        }

        var homeMetadata = stat()
        guard lstat(home.path, &homeMetadata) == 0,
              homeMetadata.st_mode & S_IFMT == S_IFDIR
        else { throw ProjectInventoryVerificationError.unsafePath(home.path) }
        let homeDevice = UInt64(homeMetadata.st_dev)

        var cursor = home
        var targetMetadata = stat()
        for component in components {
            cursor.appendPathComponent(component, isDirectory: true)
            var metadata = stat()
            guard lstat(cursor.path, &metadata) == 0 else {
                throw ProjectInventoryVerificationError.missingPath(path.path)
            }
            guard metadata.st_mode & S_IFMT == S_IFDIR,
                  UInt64(metadata.st_dev) == homeDevice
            else {
                throw ProjectInventoryVerificationError.unsafePath(path.path)
            }
            targetMetadata = metadata
        }

        let currentIdentity = ArchiveFileIdentity(metadata: targetMetadata, kind: .directory)
        guard currentIdentity == project.identity else {
            throw ProjectInventoryVerificationError.changed(path.path)
        }

        var context = ScanContext(maxEntries: maxEntries)
        let totals = try summarizeProject(
            path,
            scanRoot: home,
            rootDevice: homeDevice,
            context: &context
        )
        guard !totals.containsProtectedMedia, !totals.inspectionIncomplete else {
            throw ProjectInventoryVerificationError.unsafePath(path.path)
        }
        guard totals.identity == project.identity,
              totals.latestActivity == project.latestActivity,
              totals.logicalBytes == project.logicalBytes,
              totals.fileCount == project.fileCount,
              totals.symbolicLinks.sorted(by: { $0.path.path < $1.path.path })
                == project.symbolicLinks.sorted(by: { $0.path.path < $1.path.path })
        else {
            throw ProjectInventoryVerificationError.changed(path.path)
        }

        let cutoff = now.addingTimeInterval(-TimeInterval(inactivityDays) * 86_400)

        return ProjectInventoryItem(
            path: path,
            identity: totals.identity,
            primaryAppID: project.primaryAppID,
            relatedAppIDs: project.relatedAppIDs,
            latestActivity: totals.latestActivity,
            logicalBytes: totals.logicalBytes,
            fileCount: totals.fileCount,
            isInactive: totals.latestActivity < cutoff,
            symbolicLinks: totals.symbolicLinks
        )
    }

    private func primaryRule(
        from matches: [ProjectApplicationRule],
        entries: [URL]
    ) -> ProjectApplicationRule {
        let entryByName = Dictionary(uniqueKeysWithValues: entries.map { ($0.lastPathComponent, $0) })
        return matches.max { lhs, rhs in
            markerDate(for: lhs, entries: entryByName) < markerDate(for: rhs, entries: entryByName)
        } ?? matches[0]
    }

    private func markerDate(
        for rule: ProjectApplicationRule,
        entries: [String: URL]
    ) -> Date {
        rule.markerNames.compactMap { name -> Date? in
            guard let url = entries[name] else { return nil }
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0 else { return nil }
            return modificationDate(metadata)
        }.max() ?? .distantPast
    }

    private func summarizeProject(
        _ root: URL,
        scanRoot: URL,
        rootDevice: UInt64,
        context: inout ScanContext
    ) throws -> ProjectTotals {
        var rootMetadata = stat()
        guard lstat(root.path, &rootMetadata) == 0,
              rootMetadata.st_mode & S_IFMT == S_IFDIR,
              UInt64(rootMetadata.st_dev) == rootDevice else {
            throw ProjectInventoryScanError.invalidRoot(root.path)
        }
        var totals = ProjectTotals(
            identity: ArchiveFileIdentity(metadata: rootMetadata, kind: .directory),
            latestActivity: modificationDate(rootMetadata)
        )
        var stack: [(URL, ArchiveFileIdentity)] = [(root, totals.identity)]
        var seenFiles = Set<ProjectFileKey>()
        var projectEntryCount = 0
        defer {
            context.inspectedProjectCount += 1
            context.reportProgress()
        }

        while let (directory, expectedIdentity) = stack.popLast() {
            try Task.checkCancellation()
            if let maxInspectionEntries, context.inspectedEntryCount >= maxInspectionEntries {
                totals.block(.inspectionLimitReached, at: directory)
                totals.inspectionLimitReached = true
                return totals
            }
            var current = stat()
            guard lstat(directory.path, &current) == 0,
                  current.st_mode & S_IFMT == S_IFDIR,
                  ArchiveFileIdentity(metadata: current, kind: .directory) == expectedIdentity else {
                totals.block(.changedDuringInspection, at: directory)
                continue
            }
            let entries: [URL]
            do {
                entries = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            } catch {
                context.skippedDirectoryCount += 1
                totals.block(.incompleteInspection, at: directory)
                continue
            }

            for entry in entries {
                try Task.checkCancellation()
                if maxProjectEntries.map({ projectEntryCount >= $0 }) == true
                    || maxInspectionEntries.map({ context.inspectedEntryCount >= $0 }) == true {
                    totals.block(.inspectionLimitReached, at: entry)
                    totals.inspectionLimitReached = true
                    return totals
                }
                projectEntryCount += 1
                context.inspectedEntryCount += 1
                context.reportProgress()
                var metadata = stat()
                guard lstat(entry.path, &metadata) == 0,
                      UInt64(metadata.st_dev) == rootDevice
                else {
                    totals.block(.incompleteInspection, at: entry)
                    continue
                }
                totals.latestActivity = max(totals.latestActivity, modificationDate(metadata))
                switch metadata.st_mode & S_IFMT {
                case S_IFDIR:
                    if isProtectedMediaDirectory(entry, scanRoot: scanRoot) {
                        totals.containsProtectedMedia = true
                    } else if isProtectedContentDirectory(entry.lastPathComponent) {
                        totals.block(.protectedDirectory, at: entry)
                    } else {
                        stack.append((entry, ArchiveFileIdentity(metadata: metadata, kind: .directory)))
                    }
                case S_IFREG:
                    let key = ProjectFileKey(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
                    if seenFiles.insert(key).inserted {
                        totals.fileCount += 1
                        totals.logicalBytes += UInt64(max(0, metadata.st_size))
                    }
                case S_IFLNK:
                    guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path) else {
                        totals.block(.incompleteInspection, at: entry)
                        continue
                    }
                    let link = ProjectSymbolicLink(path: entry, destination: destination, metadata: metadata)
                    var afterRead = stat()
                    guard lstat(entry.path, &afterRead) == 0, afterRead.st_mode & S_IFMT == S_IFLNK,
                          link == ProjectSymbolicLink(path: entry, destination: destination, metadata: afterRead) else {
                        totals.block(.changedDuringInspection, at: entry)
                        continue
                    }
                    totals.symbolicLinks.append(link)
                    let key = ProjectFileKey(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
                    if seenFiles.insert(key).inserted {
                        totals.fileCount += 1
                        totals.logicalBytes += UInt64(max(0, metadata.st_size))
                    }
                default:
                    // Never follow links or silently approve an incompletely inspected target.
                    totals.block(.unsupportedEntry, at: entry)
                    continue
                }
            }
            var afterEnumeration = stat()
            if lstat(directory.path, &afterEnumeration) != 0
                || afterEnumeration.st_mode & S_IFMT != S_IFDIR
                || ArchiveFileIdentity(metadata: afterEnumeration, kind: .directory) != expectedIdentity {
                totals.block(.changedDuringInspection, at: directory)
            }
        }
        return totals
    }

    private func isProtectedContentDirectory(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["library", "applications", ".trash", "pictures", "music"].contains(name)
            || name.hasPrefix("onedrive") || name.hasPrefix("dropbox")
            || name.hasPrefix("google drive") || name.hasPrefix("icloud drive")
    }

    private func shouldSkipDirectory(named name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let normalized = name.lowercased()
        let exact: Set<String> = [
            "library", "applications", "node_modules", "vendor", "pods",
            "deriveddata", "build", "dist", "target", ".trash",
        ]
        if exact.contains(normalized) { return true }
        return normalized.hasPrefix("onedrive")
            || normalized.hasPrefix("dropbox")
            || normalized.hasPrefix("google drive")
            || normalized.hasPrefix("icloud drive")
    }

    private func shouldSkipDirectory(_ directory: URL, scanRoot: URL) -> Bool {
        shouldSkipDirectory(named: directory.lastPathComponent)
            || isProtectedMediaDirectory(directory, scanRoot: scanRoot)
    }

    private func isProtectedMediaDirectory(_ directory: URL, scanRoot: URL) -> Bool {
        if directory.deletingLastPathComponent().standardizedFileURL == scanRoot.standardizedFileURL,
           isProtectedMediaRootName(directory.lastPathComponent) {
            return true
        }
        return isMediaLibraryName(directory.lastPathComponent)
    }

    private func isProtectedMediaRootName(_ name: String) -> Bool {
        ["pictures", "music"].contains(name.lowercased())
    }

    private func isMediaLibraryName(_ name: String) -> Bool {
        let extensionName = URL(fileURLWithPath: name).pathExtension.lowercased()
        return ["photoslibrary", "photolibrary", "musiclibrary"].contains(extensionName)
    }

    private func hasProjectBoundary(in names: Set<String>) -> Bool {
        let exact: Set<String> = [
            ".git", "Package.swift", "package.json", "pyproject.toml",
            "Cargo.toml", "go.mod", "Gemfile", "pom.xml", "build.gradle",
            "build.gradle.kts", "Makefile",
        ]
        if !names.isDisjoint(with: exact) { return true }
        return names.contains { name in
            name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
        }
    }

    private func modificationDate(_ metadata: stat) -> Date {
        Date(
            timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec)
                + TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000
        )
    }
}

private struct ScanContext {
    let maxEntries: Int?
    var onProgress: (@Sendable (ProjectInventoryProgress) -> Void)? = nil
    var visitedEntryCount = 0
    var skippedDirectoryCount = 0
    var projects: [ProjectInventoryItem] = []
    var seenProjectPaths = Set<String>()
    var seenDiscoveryPaths = Set<String>()
    var inspectedEntryCount = 0
    var inspectedProjectCount = 0
    var discoveryWasLimited = false
    private var lastProgressTime: TimeInterval = 0

    init(maxEntries: Int?, onProgress: (@Sendable (ProjectInventoryProgress) -> Void)? = nil) {
        self.maxEntries = maxEntries
        self.onProgress = onProgress
    }

    mutating func reportProgress(force: Bool = false) {
        guard let onProgress else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastProgressTime >= 0.25 else { return }
        lastProgressTime = now
        var progress = ProjectInventoryProgress()
        progress.discoveredEntryCount = visitedEntryCount
        progress.inspectedEntryCount = inspectedEntryCount
        progress.inspectedProjectCount = inspectedProjectCount
        onProgress(progress)
    }

    mutating func visit() throws {
        try Task.checkCancellation()
        visitedEntryCount += 1
        reportProgress()
        if let maxEntries, visitedEntryCount > maxEntries {
            throw ProjectInventoryScanError.traversalLimitExceeded(maxEntries)
        }
    }
}

private struct ProjectTotals {
    let identity: ArchiveFileIdentity
    var latestActivity: Date
    var logicalBytes: UInt64 = 0
    var fileCount: UInt64 = 0
    var containsProtectedMedia = false
    var inspectionIncomplete = false
    var inspectionLimitReached = false
    var specificBlockReason: ProjectCleanupBlockReason?
    var issues: [ProjectInspectionIssue] = []
    var issueCount = 0
    var symbolicLinks: [ProjectSymbolicLink] = []

    mutating func block(_ reason: ProjectCleanupBlockReason, at path: URL, linkDestination: String? = nil) {
        inspectionIncomplete = true
        if specificBlockReason == nil { specificBlockReason = reason }
        issueCount += 1
        // Limit retained diagnostics, not the underlying scan.
        if issues.count < 20 {
            issues.append(ProjectInspectionIssue(path: path, reason: reason, linkDestination: linkDestination))
        }
    }

    var cleanupBlockReason: ProjectCleanupBlockReason? {
        if inspectionLimitReached { return .inspectionLimitReached }
        return inspectionIncomplete ? (specificBlockReason ?? .incompleteInspection) : nil
    }
}

private struct ProjectFileKey: Hashable {
    let device: UInt64
    let inode: UInt64
}
