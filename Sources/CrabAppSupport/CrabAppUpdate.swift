import CryptoKit
import Darwin
import Foundation
import Security

public struct CrabAppUpdateOffer: Equatable, Sendable {
    public let latestVersion: String
    public let releaseURL: URL
    public let assetURL: URL
    public let assetName: String
    public let assetSize: Int64
    public let sha256: String

    public init(
        latestVersion: String,
        releaseURL: URL,
        assetURL: URL,
        assetName: String,
        assetSize: Int64,
        sha256: String
    ) {
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
        self.assetURL = assetURL
        self.assetName = assetName
        self.assetSize = assetSize
        self.sha256 = sha256
    }
}

public enum CrabAppUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(CrabAppUpdateOffer)
    case unavailable
    case failed
}

public enum CrabHomeUpdateAction: Equatable, Sendable {
    case install(CrabAppUpdateOffer)
}

public struct CrabLaunchUpdateCheckState: Equatable, Sendable {
    public private(set) var didBeginCheck = false

    public init() {}

    public mutating func beginCheckIfNeeded() -> Bool {
        guard !didBeginCheck else { return false }
        didBeginCheck = true
        return true
    }

    public static func availableOffer(
        from status: CrabAppUpdateStatus
    ) -> CrabAppUpdateOffer? {
        guard case let .available(offer) = status else { return nil }
        return offer
    }

    public static func homeAction(
        from status: CrabAppUpdateStatus
    ) -> CrabHomeUpdateAction? {
        availableOffer(from: status).map(CrabHomeUpdateAction.install)
    }
}

public struct CrabAppUpdateChecker: Sendable {
    private static let maximumFeedBytes = 256 * 1_024
    private static let maximumAssetBytes: Int64 = 250 * 1_024 * 1_024
    private static let releaseManifestURL = URL(
        string: "https://github.com/qinthqod/Crab/releases/latest/download/update.json"
    )!

    public init() {}

    public func check(currentVersion: String, feedURL: URL?) async -> CrabAppUpdateStatus {
        guard let feedURL else { return .unavailable }
        let feedURLs = Self.feedURLs(primary: feedURL)
        guard !feedURLs.isEmpty else { return .unavailable }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        var releaseDataCandidates: [Data] = []

        for candidate in feedURLs {
            var request = URLRequest(url: candidate)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Crab/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      Self.isTrustedResponseURL(http.url, requestedURL: candidate),
                      data.count <= Self.maximumFeedBytes
                else { continue }

                releaseDataCandidates.append(data)
                let status = Self.evaluateFeeds(
                    currentVersion: currentVersion,
                    releaseDataCandidates: releaseDataCandidates,
                    architecture: Self.currentArchitecture
                )
                if status != .unavailable { return status }
            } catch {
                continue
            }
        }
        return releaseDataCandidates.isEmpty ? .failed : .unavailable
    }

    public static func feedURLs(primary: URL) -> [URL] {
        guard isTrustedFeedURL(primary) else { return [] }
        if primary.scheme == "https",
           primary.host?.lowercased() == "api.github.com",
           primary.path == "/repos/qinthqod/Crab/releases" {
            return [primary, releaseManifestURL]
        }
        return [primary]
    }

    public static func evaluate(
        currentVersion: String,
        releaseData: Data,
        architecture: String = currentArchitecture
    ) -> CrabAppUpdateStatus {
        guard releaseData.count <= maximumFeedBytes,
              let current = CrabReleaseVersion(currentVersion),
              ["arm64", "x86_64"].contains(architecture),
              let releases = decodeReleases(releaseData)
        else { return .unavailable }

        var foundNewerRelease = false
        for release in releases where !release.draft {
            guard let latest = CrabReleaseVersion(release.version),
                  latest > current,
                  isTrustedReleaseURL(release.releaseURL)
            else { continue }
            foundNewerRelease = true

            let expectedName = "Crab-\(latest.fileVersion)-macOS-\(architecture).zip"
            guard let asset = release.assets.first(where: { $0.name == expectedName }),
                  let offer = validatedOffer(release: release, asset: asset)
            else { continue }
            return .available(offer)
        }
        return foundNewerRelease ? .unavailable : .upToDate
    }

    public static func evaluateFeeds(
        currentVersion: String,
        releaseDataCandidates: [Data],
        architecture: String = currentArchitecture
    ) -> CrabAppUpdateStatus {
        for data in releaseDataCandidates {
            let status = evaluate(
                currentVersion: currentVersion,
                releaseData: data,
                architecture: architecture
            )
            if status != .unavailable { return status }
        }
        return .unavailable
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unsupported"
        #endif
    }

    private static func decodeReleases(_ data: Data) -> [CrabReleaseMetadata]? {
        let decoder = JSONDecoder()
        if let releases = try? decoder.decode([CrabReleaseMetadata].self, from: data) {
            return releases
        }
        if let release = try? decoder.decode(CrabReleaseMetadata.self, from: data) {
            return [release]
        }
        return nil
    }

    private static func validatedOffer(
        release: CrabReleaseMetadata,
        asset: CrabReleaseAsset
    ) -> CrabAppUpdateOffer? {
        guard asset.state == "uploaded",
              asset.contentType == "application/zip",
              asset.size > 0,
              asset.size <= maximumAssetBytes,
              asset.downloadURL.scheme == "https",
              asset.downloadURL.host?.lowercased() == "github.com",
              asset.downloadURL.path.hasPrefix("/qinthqod/Crab/releases/download/"),
              asset.downloadURL.lastPathComponent == asset.name,
              let digest = asset.digest,
              digest.hasPrefix("sha256:")
        else { return nil }

        let sha256 = String(digest.dropFirst("sha256:".count)).lowercased()
        guard sha256.count == 64,
              sha256.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value) || (97...102).contains($0.value)
              })
        else { return nil }

        return CrabAppUpdateOffer(
            latestVersion: release.version,
            releaseURL: release.releaseURL,
            assetURL: asset.downloadURL,
            assetName: asset.name,
            assetSize: asset.size,
            sha256: sha256
        )
    }

    private static func isTrustedFeedURL(_ url: URL) -> Bool {
        guard url.scheme == "https" else { return false }
        if url.host?.lowercased() == "api.github.com" {
            return url.path == "/repos/qinthqod/Crab/releases"
        }
        return url == releaseManifestURL
    }

    private static func isTrustedResponseURL(_ url: URL?, requestedURL: URL) -> Bool {
        guard let url, url.scheme == "https" else { return false }
        if requestedURL.host?.lowercased() == "api.github.com" {
            return url.host?.lowercased() == "api.github.com"
                && url.path == "/repos/qinthqod/Crab/releases"
        }
        return (url == releaseManifestURL)
            || url.host?.lowercased() == "release-assets.githubusercontent.com"
    }

    private static func isTrustedReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/qinthqod/Crab/releases/tag/")
    }
}

public enum CrabUpdateDigest {
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum CrabUpdatePackageError: Error, Equatable, CustomStringConvertible {
    case invalidApplication
    case linkedApplication
    case wrongBundleIdentifier
    case wrongVersion
    case invalidSignature
    case tooManyEntries

    public var description: String {
        switch self {
        case .invalidApplication: "更新包中的 Crab.app 结构无效。"
        case .linkedApplication: "更新包包含不允许的符号链接。"
        case .wrongBundleIdentifier: "更新包不是 Crab 应用。"
        case .wrongVersion: "更新包版本与发布信息不一致。"
        case .invalidSignature: "更新包签名校验失败。"
        case .tooManyEntries: "更新包内容数量超出安全限制。"
        }
    }
}

public enum CrabUpdatePackageValidator {
    public static func validateApplication(
        at appURL: URL,
        expectedVersion: String,
        requirement: SecRequirement? = nil
    ) throws {
        let normalizedURL = appURL.standardizedFileURL
        guard normalizedURL.pathExtension.lowercased() == "app",
              isDirectoryWithoutFollowingLinks(normalizedURL)
        else { throw CrabUpdatePackageError.invalidApplication }
        try rejectLinks(in: normalizedURL)

        let metadata = try applicationMetadata(at: normalizedURL)
        guard metadata.bundleIdentifier == "dev.crab.cleaner" else {
            throw CrabUpdatePackageError.wrongBundleIdentifier
        }
        let normalizedVersion = expectedVersion.hasPrefix("v")
            ? String(expectedVersion.dropFirst())
            : expectedVersion
        guard metadata.version == normalizedVersion else {
            throw CrabUpdatePackageError.wrongVersion
        }
        let executableURL = normalizedURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(metadata.executable)
        guard
              isRegularFileWithoutFollowingLinks(executableURL)
        else { throw CrabUpdatePackageError.invalidApplication }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            normalizedURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
            let staticCode
        else { throw CrabUpdatePackageError.invalidSignature }

        let effectiveRequirement: SecRequirement
        if let requirement {
            effectiveRequirement = requirement
        } else {
            var identifierRequirement: SecRequirement?
            guard SecRequirementCreateWithString(
                "identifier \"dev.crab.cleaner\"" as CFString,
                SecCSFlags(),
                &identifierRequirement
            ) == errSecSuccess,
                let identifierRequirement
            else { throw CrabUpdatePackageError.invalidSignature }
            effectiveRequirement = identifierRequirement
        }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(
            staticCode,
            flags,
            effectiveRequirement
        ) == errSecSuccess
        else { throw CrabUpdatePackageError.invalidSignature }
    }

    public static func designatedRequirement(for appURL: URL) throws -> SecRequirement {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            appURL.standardizedFileURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
            let staticCode
        else { throw CrabUpdatePackageError.invalidSignature }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(
            staticCode,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess,
            let requirement
        else { throw CrabUpdatePackageError.invalidSignature }
        return requirement
    }

    public static func applicationVersion(at appURL: URL) throws -> String {
        try applicationMetadata(at: appURL.standardizedFileURL).version
    }

    private static func applicationMetadata(
        at appURL: URL
    ) throws -> (bundleIdentifier: String, version: String, executable: String) {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard isRegularFileWithoutFollowingLinks(plistURL),
              let attributes = try? FileManager.default.attributesOfItem(atPath: plistURL.path),
              let byteCount = attributes[.size] as? NSNumber,
              byteCount.intValue > 0,
              byteCount.intValue <= 1_048_576,
              let data = try? Data(contentsOf: plistURL, options: [.mappedIfSafe]),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let bundleIdentifier = plist["CFBundleIdentifier"] as? String,
              let version = plist["CFBundleShortVersionString"] as? String,
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty,
              !executable.contains("/"),
              executable != ".",
              executable != ".."
        else { throw CrabUpdatePackageError.invalidApplication }
        return (bundleIdentifier, version, executable)
    }

    private static func rejectLinks(in root: URL) throws {
        var pending = [root]
        var visited = 0
        while let directory = pending.popLast() {
            let entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
            for entry in entries {
                visited += 1
                guard visited <= 100_000 else { throw CrabUpdatePackageError.tooManyEntries }
                var metadata = stat()
                guard lstat(entry.path, &metadata) == 0 else {
                    throw CrabUpdatePackageError.invalidApplication
                }
                switch metadata.st_mode & S_IFMT {
                case S_IFLNK:
                    throw CrabUpdatePackageError.linkedApplication
                case S_IFDIR:
                    pending.append(entry)
                case S_IFREG:
                    continue
                default:
                    throw CrabUpdatePackageError.invalidApplication
                }
            }
        }
    }

    private static func isDirectoryWithoutFollowingLinks(_ url: URL) -> Bool {
        var metadata = stat()
        return lstat(url.path, &metadata) == 0 && metadata.st_mode & S_IFMT == S_IFDIR
    }

    private static func isRegularFileWithoutFollowingLinks(_ url: URL) -> Bool {
        var metadata = stat()
        return lstat(url.path, &metadata) == 0 && metadata.st_mode & S_IFMT == S_IFREG
    }
}

private struct CrabReleaseMetadata: Decodable {
    let version: String
    let releaseURL: URL
    let draft: Bool
    let assets: [CrabReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case version
        case releaseURL = "release_url"
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let version = try container.decodeIfPresent(String.self, forKey: .version),
           let releaseURL = try container.decodeIfPresent(URL.self, forKey: .releaseURL) {
            self.version = version
            self.releaseURL = releaseURL
        } else {
            version = try container.decode(String.self, forKey: .tagName)
            releaseURL = try container.decode(URL.self, forKey: .htmlURL)
        }
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        assets = try container.decodeIfPresent([CrabReleaseAsset].self, forKey: .assets) ?? []
    }
}

private struct CrabReleaseAsset: Decodable {
    let name: String
    let state: String
    let contentType: String
    let size: Int64
    let digest: String?
    let downloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case state
        case contentType = "content_type"
        case size
        case digest
        case downloadURL = "browser_download_url"
    }
}

private struct CrabReleaseVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    var fileVersion: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }

    init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let withoutBuild = normalized.split(separator: "+", maxSplits: 1)[0]
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Int(core[0]),
              let minor = Int(core[1]),
              let patch = Int(core[2]),
              major >= 0, minor >= 0, patch >= 0,
              parts.count == 1 || !parts[1].isEmpty
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        prerelease = parts.count == 2 ? String(parts[1]) : nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): false
        case (nil, _): false
        case (_, nil): true
        case let (left?, right?): left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}
