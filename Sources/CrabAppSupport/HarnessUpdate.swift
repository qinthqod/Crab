import Foundation

public enum HarnessUpdateStatus: Equatable, Sendable {
    case checking
    case upToDate
    case available(latestVersion: String, updateURL: URL)
    case unavailable
    case failed
}

public struct HarnessUpdatePlan: Equatable, Sendable {
    public let appID: String
    public let latestVersion: String
    public let packageRoot: URL
    public let expectedIdentity: HarnessBundleIdentity
    public let executableURL: URL
    public let arguments: [String]
}

public enum HarnessUpdateError: Error, Equatable, CustomStringConvertible {
    case unsupportedInstallation
    case invalidVersion
    case unsafePackageLocation
    case packageChanged
    case npmUnavailable
    case launchFailed
    case commandFailed(Int32)
    case versionNotUpdated

    public var description: String {
        switch self {
        case .unsupportedInstallation: "这个应用暂不支持在 Crab 内直接更新。"
        case .invalidVersion: "更新版本信息无效。"
        case .unsafePackageLocation: "无法确认原安装位置，已停止更新。"
        case .packageChanged: "应用在确认更新后发生了变化，请重新检查。"
        case .npmUnavailable: "没有找到与原安装位置匹配的 npm。"
        case .launchFailed: "无法启动安全更新程序。"
        case let .commandFailed(status): "更新程序未完成（退出状态：\(status)）。"
        case .versionNotUpdated: "更新程序结束后未检测到目标版本。"
        }
    }
}

public struct HarnessUpdatePlanner: Sendable {
    public init() {}

    public func build(
        installation: HarnessInstallation,
        latestVersion: String,
        npmExecutableURLs: [URL]
    ) throws -> HarnessUpdatePlan {
        guard installation.kind == .commandLineTool,
              let commandLine = installation.definition.commandLine,
              let installedVersion = installation.version
        else { throw HarnessUpdateError.unsupportedInstallation }
        guard let installed = SemanticVersion(installedVersion),
              let latest = SemanticVersion(latestVersion),
              latest > installed
        else { throw HarnessUpdateError.invalidVersion }

        let packageRoot = installation.bundleURL.standardizedFileURL
        let marker = "/lib/node_modules/"
        guard let markerRange = packageRoot.path.range(of: marker, options: .backwards) else {
            throw HarnessUpdateError.unsafePackageLocation
        }
        let prefixPath = String(packageRoot.path[..<markerRange.lowerBound])
        guard !prefixPath.isEmpty else { throw HarnessUpdateError.unsafePackageLocation }
        let prefix = URL(fileURLWithPath: prefixPath, isDirectory: true).standardizedFileURL
        let expectedPackageRoot = prefix
            .appendingPathComponent("lib/node_modules", isDirectory: true)
            .appendingPathComponent(commandLine.npmPackageName, isDirectory: true)
            .standardizedFileURL
        guard expectedPackageRoot == packageRoot else {
            throw HarnessUpdateError.unsafePackageLocation
        }

        let expectedNPM = prefix.appendingPathComponent("bin/npm").standardizedFileURL
        guard npmExecutableURLs.map(\.standardizedFileURL).contains(expectedNPM),
              FileManager.default.isExecutableFile(atPath: expectedNPM.path)
        else { throw HarnessUpdateError.npmUnavailable }

        return HarnessUpdatePlan(
            appID: installation.appID,
            latestVersion: latestVersion,
            packageRoot: packageRoot,
            expectedIdentity: installation.identity,
            executableURL: expectedNPM,
            arguments: [
                "install", "--global", "--prefix", prefix.path,
                "--no-audit", "--no-fund",
                "\(commandLine.npmPackageName)@\(latestVersion)",
            ]
        )
    }
}

public struct HarnessUpdater: Sendable {
    public init() {}

    public func execute(_ plan: HarnessUpdatePlan) throws {
        guard HarnessBundleIdentity.capture(at: plan.packageRoot) == plan.expectedIdentity else {
            throw HarnessUpdateError.packageChanged
        }
        guard FileManager.default.isExecutableFile(atPath: plan.executableURL.path) else {
            throw HarnessUpdateError.npmUnavailable
        }

        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let inherited = ProcessInfo.processInfo.environment
        let allowedEnvironmentKeys = ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"]
        process.environment = Dictionary(uniqueKeysWithValues: allowedEnvironmentKeys.compactMap { key in
            inherited[key].map { (key, $0) }
        }).merging(["NO_UPDATE_NOTIFIER": "1"], uniquingKeysWith: { _, new in new })

        do {
            try process.run()
        } catch {
            throw HarnessUpdateError.launchFailed
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw HarnessUpdateError.commandFailed(process.terminationStatus)
        }
        guard installedPackageVersion(at: plan.packageRoot) == plan.latestVersion else {
            throw HarnessUpdateError.versionNotUpdated
        }
    }

    private func installedPackageVersion(at packageRoot: URL) -> String? {
        struct Manifest: Decodable { let version: String }
        let manifestURL = packageRoot.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL, options: [.mappedIfSafe]),
              data.count <= 1_048_576,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        return manifest.version
    }
}

public struct HarnessUpdateChecker: Sendable {
    public init() {}

    public func check(_ installation: HarnessInstallation) async -> HarnessUpdateStatus {
        guard installation.kind == .commandLineTool else { return .unavailable }
        guard let installedVersion = installation.version,
              let endpoint = endpoint(for: installation.appID)
        else { return .unavailable }

        var request = URLRequest(url: endpoint.metadataURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 10
            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.url?.scheme == "https",
                  http.url?.host == "registry.npmjs.org",
                  data.count <= 8_192
            else { return .failed }
            let metadata = try JSONDecoder().decode(NPMLatestMetadata.self, from: data)
            return Self.evaluate(
                installedVersion: installedVersion,
                latestVersion: metadata.version,
                updateURL: endpoint.updateURL
            )
        } catch {
            return .failed
        }
    }

    public static func evaluate(
        installedVersion: String,
        latestVersion: String,
        updateURL: URL
    ) -> HarnessUpdateStatus {
        guard let installed = SemanticVersion(installedVersion),
              let latest = SemanticVersion(latestVersion)
        else { return .unavailable }
        guard latest > installed else { return .upToDate }
        return .available(latestVersion: latestVersion, updateURL: updateURL)
    }

    private func endpoint(for appID: String) -> UpdateEndpoint? {
        switch appID {
        case "ai.anthropic.claude-code":
            return UpdateEndpoint(
                metadataURL: URL(string: "https://registry.npmjs.org/@anthropic-ai%2Fclaude-code/latest")!,
                updateURL: URL(string: "https://www.npmjs.com/package/@anthropic-ai/claude-code")!
            )
        case "ai.deepseek.dsh":
            return UpdateEndpoint(
                metadataURL: URL(string: "https://registry.npmjs.org/@deepseek-ai%2Fdsh/latest")!,
                updateURL: URL(string: "https://www.npmjs.com/package/@deepseek-ai/dsh")!
            )
        default:
            return nil
        }
    }
}

private struct UpdateEndpoint: Sendable {
    let metadataURL: URL
    let updateURL: URL
}

private struct NPMLatestMetadata: Decodable {
    let version: String
}

private struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    private let prerelease: [Identifier]

    init?(_ rawValue: String) {
        let withoutBuild = rawValue.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Int(core[0]),
              let minor = Int(core[1]),
              let patch = Int(core[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        let prerelease: [Identifier]
        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } })
            else { return nil }
            prerelease = identifiers.map(Identifier.init)
        } else {
            prerelease = []
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
        for index in 0..<min(lhs.prerelease.count, rhs.prerelease.count) {
            if lhs.prerelease[index] != rhs.prerelease[index] {
                return lhs.prerelease[index] < rhs.prerelease[index]
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private enum Identifier: Comparable {
        case number(Int)
        case text(String)

        init(_ value: Substring) {
            if let number = Int(value), !value.hasPrefix("0") || value == "0" {
                self = .number(number)
            } else {
                self = .text(String(value))
            }
        }

        static func < (lhs: Identifier, rhs: Identifier) -> Bool {
            switch (lhs, rhs) {
            case let (.number(left), .number(right)): left < right
            case (.number, .text): true
            case (.text, .number): false
            case let (.text(left), .text(right)): left < right
            }
        }
    }
}
