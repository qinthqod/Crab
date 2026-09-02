import Foundation

public enum CrabAppUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(latestVersion: String, releaseURL: URL)
    case unavailable
    case failed
}

public struct CrabAppUpdateChecker: Sendable {
    public init() {}

    public func check(currentVersion: String, feedURL: URL?) async -> CrabAppUpdateStatus {
        guard let feedURL,
              feedURL.scheme == "https"
        else { return .unavailable }

        var request = URLRequest(url: feedURL)
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
                  data.count <= 32_768
            else { return .failed }

            return Self.evaluate(currentVersion: currentVersion, releaseData: data)
        } catch {
            return .failed
        }
    }

    public static func evaluate(
        currentVersion: String,
        latestVersion: String,
        releaseURL: URL
    ) -> CrabAppUpdateStatus {
        guard releaseURL.scheme == "https",
              let current = CrabReleaseVersion(currentVersion),
              let latest = CrabReleaseVersion(latestVersion)
        else { return .unavailable }
        guard latest > current else { return .upToDate }
        return .available(latestVersion: latestVersion, releaseURL: releaseURL)
    }

    public static func evaluate(
        currentVersion: String,
        releaseData: Data
    ) -> CrabAppUpdateStatus {
        guard releaseData.count <= 32_768,
              let release = try? JSONDecoder().decode(CrabReleaseMetadata.self, from: releaseData)
        else { return .unavailable }
        return evaluate(
            currentVersion: currentVersion,
            latestVersion: release.version,
            releaseURL: release.releaseURL
        )
    }
}

private struct CrabReleaseMetadata: Decodable {
    let version: String
    let releaseURL: URL

    private enum CodingKeys: String, CodingKey {
        case version
        case releaseURL = "release_url"
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let version = try container.decodeIfPresent(String.self, forKey: .version),
           let releaseURL = try container.decodeIfPresent(URL.self, forKey: .releaseURL) {
            self.version = version
            self.releaseURL = releaseURL
            return
        }
        version = try container.decode(String.self, forKey: .tagName)
        releaseURL = try container.decode(URL.self, forKey: .htmlURL)
    }
}

private struct CrabReleaseVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

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
