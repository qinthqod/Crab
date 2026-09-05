import CoreServices
import Darwin
import Foundation
import Security

public struct HarnessBundleIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let modificationNanoseconds: Int64

    public static func capture(at url: URL) -> HarnessBundleIdentity? {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR
        else { return nil }
        return HarnessBundleIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            modificationNanoseconds: Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000
                + Int64(metadata.st_mtimespec.tv_nsec)
        )
    }

    static func captureExecutable(at url: URL) -> HarnessBundleIdentity? {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else { return nil }
        return HarnessBundleIdentity(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino),
            modificationNanoseconds: Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(metadata.st_mtimespec.tv_nsec))
    }
}

public enum HarnessInstallationKind: Equatable, Sendable {
    case applicationBundle
    case commandLineTool
}

public enum HarnessInventoryLoadState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)

    public func permitsRefresh(force: Bool) -> Bool {
        if force { return true }
        if case .idle = self { return true }
        return false
    }
}

public struct HarnessInstallation: Identifiable, Equatable, Sendable {
    public let definition: HarnessDefinition
    public let bundleURL: URL
    public let executableURL: URL?
    public let kind: HarnessInstallationKind
    public let version: String?
    public let installedBytes: UInt64
    public let lastUsedAt: Date?
    public let identity: HarnessBundleIdentity

    public var id: String { definition.appID }
    public var appID: String { definition.appID }
    public var displayName: String { definition.displayName }
    public var versionDisplayText: String? {
        guard let version, !version.isEmpty else { return nil }
        return kind == .commandLineTool ? "CLI v\(version)" : "v\(version)"
    }
}

public struct HarnessInventory: Equatable, Sendable {
    public let installations: [HarnessInstallation]

    public init(installations: [HarnessInstallation] = []) {
        self.installations = installations.sorted {
            switch ($0.lastUsedAt, $1.lastUsedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        }
    }

    public var installedAppIDs: Set<String> {
        Set(installations.map(\.appID))
    }

    public func installation(for appID: String) -> HarnessInstallation? {
        installations.first { $0.appID == appID }
    }

    public func orderedInstallations(runningAppIDs: Set<String>) -> [HarnessInstallation] {
        installations.enumerated().sorted { left, right in
            let leftIsRunning = runningAppIDs.contains(left.element.appID)
            let rightIsRunning = runningAppIDs.contains(right.element.appID)
            if leftIsRunning != rightIsRunning {
                return leftIsRunning
            }
            return left.offset < right.offset
        }.map(\.element)
    }
}

public struct HarnessInventoryScanner: Sendable {
    public init() {}

    public func scan(
        definitions: [HarnessDefinition],
        applicationRoots: [URL],
        executableRoots: [URL] = [],
        measureInstalledBytes: Bool = true,
        lastUsedDateProvider: @Sendable (URL) -> Date? = SpotlightHarnessUsage.lastUsedDate
    ) -> HarnessInventory {
        let availableApps = discoverApplications(in: applicationRoots)
        var installations: [HarnessInstallation] = []

        for definition in definitions {
            if Task.isCancelled { break }
            if let bundleURL = locate(definition, roots: applicationRoots, availableApps: availableApps),
               let installation = inspectApplication(
                definition: definition,
                bundleURL: bundleURL,
                measureInstalledBytes: measureInstalledBytes,
                lastUsedDateProvider: lastUsedDateProvider
               ) {
                installations.append(installation)
                continue
            }
            if let installation = inspectCommandLineTool(
                definition: definition,
                executableRoots: executableRoots,
                measureInstalledBytes: measureInstalledBytes,
                lastUsedDateProvider: lastUsedDateProvider
            ) {
                installations.append(installation)
            }
        }

        return HarnessInventory(installations: installations)
    }

    public func measuringInstalledBytes(in inventory: HarnessInventory) -> HarnessInventory {
        HarnessInventory(installations: inventory.installations.map { installation in
            if Task.isCancelled { return installation }
            return HarnessInstallation(
                definition: installation.definition,
                bundleURL: installation.bundleURL,
                executableURL: installation.executableURL,
                kind: installation.kind,
                version: installation.version,
                installedBytes: allocatedSize(of: installation.bundleURL),
                lastUsedAt: installation.lastUsedAt,
                identity: installation.identity
            )
        })
    }

    public func measuringLastUsedDates(
        in inventory: HarnessInventory,
        lastUsedDateProvider: @Sendable (URL) -> Date? = SpotlightHarnessUsage.lastUsedDate
    ) -> HarnessInventory {
        HarnessInventory(installations: inventory.installations.map { installation in
            if Task.isCancelled { return installation }
            let activityURL = installation.executableURL ?? installation.bundleURL
            return HarnessInstallation(
                definition: installation.definition,
                bundleURL: installation.bundleURL,
                executableURL: installation.executableURL,
                kind: installation.kind,
                version: installation.version,
                installedBytes: installation.installedBytes,
                lastUsedAt: lastUsedDateProvider(activityURL),
                identity: installation.identity
            )
        })
    }

    private func discoverApplications(in roots: [URL]) -> [String: URL] {
        var discovered: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return discovered }
                guard url.pathExtension.lowercased() == "app" else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      let appID = Bundle(url: url)?.bundleIdentifier,
                      discovered[appID] == nil
                else { continue }
                discovered[appID] = url.standardizedFileURL
            }
        }
        return discovered
    }

    private func locate(
        _ definition: HarnessDefinition,
        roots: [URL],
        availableApps: [String: URL]
    ) -> URL? {
        if let discovered = availableApps[definition.appID] { return discovered }
        for root in roots {
            for bundleName in definition.bundleNames {
                let candidate = root.appendingPathComponent(bundleName, isDirectory: true)
                if Bundle(url: candidate)?.bundleIdentifier == definition.appID {
                    return candidate.standardizedFileURL
                }
            }
        }
        return nil
    }

    private func inspectApplication(
        definition: HarnessDefinition,
        bundleURL: URL,
        measureInstalledBytes: Bool,
        lastUsedDateProvider: @Sendable (URL) -> Date?
    ) -> HarnessInstallation? {
        guard let identity = HarnessBundleIdentity.capture(at: bundleURL),
              let bundle = Bundle(url: bundleURL),
              bundle.bundleIdentifier == definition.appID
        else { return nil }

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return HarnessInstallation(
            definition: definition,
            bundleURL: bundleURL.standardizedFileURL,
            executableURL: nil,
            kind: .applicationBundle,
            version: version,
            installedBytes: measureInstalledBytes ? allocatedSize(of: bundleURL) : 0,
            lastUsedAt: lastUsedDateProvider(bundleURL),
            identity: identity
        )
    }

    private func inspectCommandLineTool(
        definition: HarnessDefinition,
        executableRoots: [URL],
        measureInstalledBytes: Bool,
        lastUsedDateProvider: @Sendable (URL) -> Date?
    ) -> HarnessInstallation? {
        guard let commandLine = definition.commandLine else { return nil }

        for root in executableRoots {
            for executableName in commandLine.executableNames {
                let candidate = root.appendingPathComponent(executableName)
                guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
                let executableURL = candidate.resolvingSymlinksInPath().standardizedFileURL
                if let native = inspectNativeClaude(definition: definition, executableURL: executableURL,
                    measureInstalledBytes: measureInstalledBytes, lastUsedDateProvider: lastUsedDateProvider) {
                    return native
                }
                guard let package = npmPackage(
                    containing: executableURL,
                    expectedName: commandLine.npmPackageName
                ),
                      let identity = HarnessBundleIdentity.capture(at: package.url)
                else { continue }

                return HarnessInstallation(
                    definition: definition,
                    bundleURL: package.url,
                    executableURL: executableURL,
                    kind: .commandLineTool,
                    version: package.version,
                    installedBytes: measureInstalledBytes ? allocatedSize(of: package.url) : 0,
                    lastUsedAt: lastUsedDateProvider(executableURL),
                    identity: identity
                )
            }
        }
        return nil
    }

    private func inspectNativeClaude(
        definition: HarnessDefinition, executableURL: URL, measureInstalledBytes: Bool,
        lastUsedDateProvider: @Sendable (URL) -> Date?
    ) -> HarnessInstallation? {
        // Native installer layout plus the verified publisher identity; never execute a candidate.
        guard !Task.isCancelled, definition.appID == "ai.anthropic.claude-code",
              executableURL.path.contains("/.local/share/claude/versions/"),
              executableURL.deletingLastPathComponent().lastPathComponent == "versions",
              let identity = HarnessBundleIdentity.captureExecutable(at: executableURL)
        else { return nil }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let publisher = "anchor apple generic and identifier \"com.anthropic.claude-code\" and certificate leaf[subject.OU] = \"Q6L2SF6YDW\""
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString(publisher as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
        let size = (try? executableURL.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0
        // A version-looking filename is not authenticated version metadata.
        return HarnessInstallation(definition: definition, bundleURL: executableURL, executableURL: executableURL,
            kind: .commandLineTool, version: nil, installedBytes: measureInstalledBytes ? UInt64(max(0, size)) : 0,
            lastUsedAt: lastUsedDateProvider(executableURL), identity: identity)
    }

    private func npmPackage(containing executableURL: URL, expectedName: String) -> (url: URL, version: String?)? {
        struct Manifest: Decodable {
            let name: String
            let version: String?
        }

        var directory = executableURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let manifestURL = directory.appendingPathComponent("package.json")
            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
               manifest.name == expectedName {
                return (directory.standardizedFileURL, manifest.version)
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    private func allocatedSize(of root: URL) -> UInt64 {
        if let values = try? root.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey]),
           values.isRegularFile == true {
            return UInt64(max(0, values.fileAllocatedSize ?? 0))
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileResourceIdentifierKey,
        ]
        var total: UInt64 = 0
        var identities = Set<AnyHashable>()

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        for case let url as URL in enumerator {
            if Task.isCancelled { return 0 }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            if let identifier = values.fileResourceIdentifier as? AnyHashable,
               !identities.insert(identifier).inserted {
                continue
            }
            let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += UInt64(max(0, bytes))
        }
        return total
    }
}

public enum SpotlightHarnessUsage {
    public static func lastUsedDate(for bundleURL: URL) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, bundleURL.path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate)
        else { return nil }
        return value as? Date
    }
}
