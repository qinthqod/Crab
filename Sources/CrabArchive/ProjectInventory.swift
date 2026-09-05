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

    public var id: URL { path }
}

public struct ProjectInventoryResult: Equatable, Sendable {
    public let scannedAt: Date
    public let projects: [ProjectInventoryItem]
    public let skippedDirectoryCount: Int

    public init(
        scannedAt: Date = Date(),
        projects: [ProjectInventoryItem] = [],
        skippedDirectoryCount: Int = 0
    ) {
        self.scannedAt = scannedAt
        self.projects = projects.sorted { $0.path.path.localizedStandardCompare($1.path.path) == .orderedAscending }
        self.skippedDirectoryCount = skippedDirectoryCount
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
    private let maxEntries: Int
    private let maxDepth: Int
    private let inactivityDays: Int

    public init(maxEntries: Int = 250_000, maxDepth: Int = 12, inactivityDays: Int = 180) {
        self.maxEntries = maxEntries
        self.maxDepth = maxDepth
        self.inactivityDays = inactivityDays
    }

    public func scan(
        rootURLs: [URL],
        rules: [ProjectApplicationRule],
        installedAppIDs: Set<String>,
        evidencedProjectURLsByAppID: [String: [URL]] = [:],
        now: Date = Date()
    ) throws -> ProjectInventoryResult {
        guard maxEntries > 0, maxDepth > 0, inactivityDays > 0 else {
            throw ProjectInventoryScanError.invalidConfiguration
        }

        let eligibleRules = rules.filter { installedAppIDs.contains($0.appID) && !$0.markerNames.isEmpty }
        guard !eligibleRules.isEmpty else {
            return ProjectInventoryResult(scannedAt: now)
        }

        var context = ScanContext(maxEntries: maxEntries)
        for rootURL in rootURLs {
            let root = rootURL.standardizedFileURL
            var rootMetadata = stat()
            guard lstat(root.path, &rootMetadata) == 0,
                  rootMetadata.st_mode & S_IFMT == S_IFDIR
            else { throw ProjectInventoryScanError.invalidRoot(root.path) }

            try discoverProjects(
                in: root,
                depth: 0,
                scanRoot: root,
                rootDevice: UInt64(rootMetadata.st_dev),
                rules: eligibleRules,
                now: now,
                context: &context
            )
            try addEvidencedProjects(
                in: root,
                rootDevice: UInt64(rootMetadata.st_dev),
                rules: eligibleRules,
                projectURLsByAppID: evidencedProjectURLsByAppID,
                now: now,
                context: &context
            )
        }

        return ProjectInventoryResult(
            scannedAt: now,
            projects: context.projects,
            skippedDirectoryCount: context.skippedDirectoryCount
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
                    isInactive: project.isInactive
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
                isInactive: totals.latestActivity < cutoff
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
        guard depth <= maxDepth else { return }
        guard !isProtectedMediaDirectory(directory, scanRoot: scanRoot) else { return }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            context.skippedDirectoryCount += 1
            return
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
            guard !totals.containsProtectedMedia else { return }
            let cutoff = now.addingTimeInterval(-TimeInterval(inactivityDays) * 86_400)
            context.projects.append(ProjectInventoryItem(
                path: directory.standardizedFileURL,
                identity: totals.identity,
                primaryAppID: primary.appID,
                relatedAppIDs: matches.map(\.appID).sorted(),
                latestActivity: totals.latestActivity,
                logicalBytes: totals.logicalBytes,
                fileCount: totals.fileCount,
                isInactive: totals.latestActivity < cutoff
            ))
        }

        for entry in entries.sorted(by: { $0.path < $1.path }) {
            try context.visit()
            guard !shouldSkipDirectory(entry, scanRoot: scanRoot) else { continue }
            var metadata = stat()
            guard lstat(entry.path, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFDIR,
                  UInt64(metadata.st_dev) == rootDevice
            else { continue }
            try discoverProjects(
                in: entry,
                depth: depth + 1,
                scanRoot: scanRoot,
                rootDevice: rootDevice,
                rules: rules,
                now: now,
                context: &context
            )
        }
    }

    public func revalidateForTrash(
        _ project: ProjectInventoryItem,
        homeURL: URL,
        scannedAt: Date,
        now: Date = Date(),
        maxEvidenceAge: TimeInterval = 600
    ) throws -> ProjectInventoryItem {
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
        guard !totals.containsProtectedMedia else {
            throw ProjectInventoryVerificationError.unsafePath(path.path)
        }
        guard totals.identity == project.identity,
              totals.latestActivity == project.latestActivity,
              totals.logicalBytes == project.logicalBytes,
              totals.fileCount == project.fileCount
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
            isInactive: totals.latestActivity < cutoff
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
        guard lstat(root.path, &rootMetadata) == 0 else {
            throw ProjectInventoryScanError.invalidRoot(root.path)
        }
        var totals = ProjectTotals(
            identity: ArchiveFileIdentity(metadata: rootMetadata, kind: .directory),
            latestActivity: modificationDate(rootMetadata)
        )
        var stack = [root]
        var seenFiles = Set<ProjectFileKey>()

        while let directory = stack.popLast() {
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

            for entry in entries {
                try context.visit()
                var metadata = stat()
                guard lstat(entry.path, &metadata) == 0,
                      UInt64(metadata.st_dev) == rootDevice
                else { continue }
                totals.latestActivity = max(totals.latestActivity, modificationDate(metadata))
                switch metadata.st_mode & S_IFMT {
                case S_IFDIR:
                    if isProtectedMediaDirectory(entry, scanRoot: scanRoot) {
                        totals.containsProtectedMedia = true
                    } else if !shouldSkipDirectory(named: entry.lastPathComponent) {
                        stack.append(entry)
                    }
                case S_IFREG:
                    let key = ProjectFileKey(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
                    if seenFiles.insert(key).inserted {
                        totals.fileCount += 1
                        totals.logicalBytes += UInt64(max(0, metadata.st_size))
                    }
                default:
                    continue
                }
            }
        }
        return totals
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
    let maxEntries: Int
    var visitedEntryCount = 0
    var skippedDirectoryCount = 0
    var projects: [ProjectInventoryItem] = []
    var seenProjectPaths = Set<String>()

    mutating func visit() throws {
        visitedEntryCount += 1
        guard visitedEntryCount <= maxEntries else {
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
}

private struct ProjectFileKey: Hashable {
    let device: UInt64
    let inode: UInt64
}
