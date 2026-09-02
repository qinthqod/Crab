import Darwin
import Foundation
import Security

public enum CrabUpdateInstallationError: Error, Equatable, CustomStringConvertible {
    case invalidArchive
    case archiveSizeMismatch
    case archiveDigestMismatch
    case extractionFailed
    case extractionTimedOut
    case downloadFailed
    case untrustedDownloadResponse
    case invalidCurrentApplication
    case currentApplicationChanged
    case differentVolume
    case destinationNotWritable
    case replacementFailed

    public var description: String {
        switch self {
        case .invalidArchive: "更新文件无效。"
        case .archiveSizeMismatch: "更新文件大小与发布信息不一致。"
        case .archiveDigestMismatch: "更新文件校验失败，未安装任何内容。"
        case .extractionFailed: "无法安全解压更新文件。"
        case .extractionTimedOut: "解压更新文件超时。"
        case .downloadFailed: "无法下载更新文件。"
        case .untrustedDownloadResponse: "更新下载来源未通过安全校验。"
        case .invalidCurrentApplication: "当前 Crab 应用无法通过签名校验。"
        case .currentApplicationChanged: "Crab 在准备更新后发生了变化，已停止安装。"
        case .differentVolume: "更新文件与 Crab 不在同一磁盘卷，无法安全替换。"
        case .destinationNotWritable: "Crab 所在位置不可写，请将应用移到“应用程序”文件夹后重试。"
        case .replacementFailed: "无法安全替换 Crab 应用。"
        }
    }
}

public enum CrabUpdateInstallationPhase: Sendable {
    case downloading
    case installing
}

public struct CrabUpdateInstallationPlan: @unchecked Sendable {
    public let currentAppURL: URL
    public let stagedAppURL: URL
    public let expectedVersion: String
    fileprivate let currentVersion: String
    fileprivate let currentIdentity: CrabUpdateApplicationIdentity
    fileprivate let designatedRequirement: SecRequirement
    fileprivate let cleanupRoot: URL?

    public static func prepare(
        currentAppURL: URL,
        stagedAppURL: URL,
        expectedVersion: String
    ) throws -> CrabUpdateInstallationPlan {
        let current = currentAppURL.standardizedFileURL
        let staged = stagedAppURL.standardizedFileURL
        let currentVersion: String
        do {
            currentVersion = try CrabUpdatePackageValidator.applicationVersion(at: current)
        } catch {
            throw CrabUpdateInstallationError.invalidCurrentApplication
        }

        let requirement = try CrabUpdatePackageValidator.designatedRequirement(for: current)
        do {
            try CrabUpdatePackageValidator.validateApplication(
                at: current,
                expectedVersion: currentVersion,
                requirement: requirement
            )
            try CrabUpdatePackageValidator.validateApplication(
                at: staged,
                expectedVersion: expectedVersion,
                requirement: requirement
            )
        } catch {
            throw CrabUpdateInstallationError.invalidCurrentApplication
        }

        let currentIdentity = try CrabUpdateApplicationIdentity.capture(at: current)
        let stagedIdentity = try CrabUpdateApplicationIdentity.capture(at: staged)
        guard currentIdentity.device == stagedIdentity.device else {
            throw CrabUpdateInstallationError.differentVolume
        }

        return CrabUpdateInstallationPlan(
            currentAppURL: current,
            stagedAppURL: staged,
            expectedVersion: expectedVersion,
            currentVersion: currentVersion,
            currentIdentity: currentIdentity,
            designatedRequirement: requirement,
            cleanupRoot: nil
        )
    }

    fileprivate func cleaningUp(_ root: URL) -> CrabUpdateInstallationPlan {
        CrabUpdateInstallationPlan(
            currentAppURL: currentAppURL,
            stagedAppURL: stagedAppURL,
            expectedVersion: expectedVersion,
            currentVersion: currentVersion,
            currentIdentity: currentIdentity,
            designatedRequirement: designatedRequirement,
            cleanupRoot: root
        )
    }
}

public enum CrabAppUpdateInstaller {
    @discardableResult
    public static func downloadAndInstall(
        offer: CrabAppUpdateOffer,
        currentAppURL: URL,
        progress: @escaping @Sendable (CrabUpdateInstallationPhase) async -> Void = { _ in }
    ) async throws -> URL {
        guard isTrustedOffer(offer) else {
            throw CrabUpdateInstallationError.untrustedDownloadResponse
        }
        await progress(.downloading)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 180
        let redirectDelegate = CrabUpdateRedirectDelegate()
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: offer.assetURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await session.download(for: request)
        } catch {
            throw CrabUpdateInstallationError.downloadFailed
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let finalURL = http.url,
              finalURL.scheme == "https",
              Self.isTrustedDownloadHost(finalURL.host),
              http.expectedContentLength <= 0
                || http.expectedContentLength <= offer.assetSize
        else { throw CrabUpdateInstallationError.untrustedDownloadResponse }

        await progress(.installing)
        let plan = try prepareDownloadedArchive(
            downloadedURL,
            offer: offer,
            currentAppURL: currentAppURL
        )
        return try install(plan)
    }

    public static func prepareDownloadedArchive(
        _ archiveURL: URL,
        offer: CrabAppUpdateOffer,
        currentAppURL: URL
    ) throws -> CrabUpdateInstallationPlan {
        let archive = archiveURL.standardizedFileURL
        guard isTrustedOffer(offer),
              isRegularFileWithoutFollowingLinks(archive),
              offer.assetSize > 0,
              offer.assetSize <= 250 * 1_024 * 1_024
        else { throw CrabUpdateInstallationError.invalidArchive }

        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        guard let byteCount = attributes[.size] as? NSNumber,
              byteCount.int64Value == offer.assetSize
        else { throw CrabUpdateInstallationError.archiveSizeMismatch }
        guard try CrabUpdateDigest.sha256Hex(ofFileAt: archive) == offer.sha256.lowercased() else {
            throw CrabUpdateInstallationError.archiveDigestMismatch
        }

        let manager = FileManager.default
        let replacementRoot = try manager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: currentAppURL,
            create: true
        ).standardizedFileURL
        var shouldCleanUp = true
        defer {
            if shouldCleanUp {
                try? manager.removeItem(at: replacementRoot)
            }
        }

        let copiedArchive = replacementRoot.appendingPathComponent(offer.assetName)
        let payload = replacementRoot.appendingPathComponent("Payload", isDirectory: true)
        try manager.copyItem(at: archive, to: copiedArchive)
        try manager.createDirectory(at: payload, withIntermediateDirectories: false)
        try extractArchive(copiedArchive, to: payload)

        let entries = try manager.contentsOfDirectory(
            at: payload,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard entries.count == 1,
              entries[0].lastPathComponent == "Crab.app"
        else { throw CrabUpdateInstallationError.invalidArchive }

        let stagedApp = entries[0].standardizedFileURL
        try CrabUpdatePackageValidator.validateApplication(
            at: stagedApp,
            expectedVersion: offer.latestVersion
        )
        let plan = try CrabUpdateInstallationPlan.prepare(
            currentAppURL: currentAppURL,
            stagedAppURL: stagedApp,
            expectedVersion: offer.latestVersion
        )
        shouldCleanUp = false
        return plan.cleaningUp(replacementRoot)
    }

    @discardableResult
    public static func install(_ plan: CrabUpdateInstallationPlan) throws -> URL {
        defer {
            if let cleanupRoot = plan.cleanupRoot {
                try? FileManager.default.removeItem(at: cleanupRoot)
            }
        }
        guard try CrabUpdateApplicationIdentity.capture(at: plan.currentAppURL)
            == plan.currentIdentity
        else { throw CrabUpdateInstallationError.currentApplicationChanged }

        do {
            try CrabUpdatePackageValidator.validateApplication(
                at: plan.currentAppURL,
                expectedVersion: plan.currentVersion,
                requirement: plan.designatedRequirement
            )
            try CrabUpdatePackageValidator.validateApplication(
                at: plan.stagedAppURL,
                expectedVersion: plan.expectedVersion,
                requirement: plan.designatedRequirement
            )
        } catch {
            throw CrabUpdateInstallationError.currentApplicationChanged
        }

        let parent = plan.currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw CrabUpdateInstallationError.destinationNotWritable
        }

        do {
            let installed = try FileManager.default.replaceItemAt(
                plan.currentAppURL,
                withItemAt: plan.stagedAppURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            ) ?? plan.currentAppURL
            try CrabUpdatePackageValidator.validateApplication(
                at: installed,
                expectedVersion: plan.expectedVersion,
                requirement: plan.designatedRequirement
            )
            return installed.standardizedFileURL
        } catch let error as CrabUpdatePackageError {
            throw error
        } catch {
            throw CrabUpdateInstallationError.replacementFailed
        }
    }

    private static func extractArchive(_ archive: URL, to payload: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, payload.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        do {
            try process.run()
        } catch {
            throw CrabUpdateInstallationError.extractionFailed
        }
        guard completion.wait(timeout: .now() + 30) == .success else {
            process.terminate()
            process.waitUntilExit()
            throw CrabUpdateInstallationError.extractionTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw CrabUpdateInstallationError.extractionFailed
        }
    }

    private static func isRegularFileWithoutFollowingLinks(_ url: URL) -> Bool {
        var metadata = stat()
        return lstat(url.path, &metadata) == 0 && metadata.st_mode & S_IFMT == S_IFREG
    }

    fileprivate static func isTrustedDownloadHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "github.com" || host == "release-assets.githubusercontent.com"
    }

    private static func isTrustedOffer(_ offer: CrabAppUpdateOffer) -> Bool {
        let normalizedVersion = offer.latestVersion.hasPrefix("v")
            ? String(offer.latestVersion.dropFirst())
            : offer.latestVersion
        guard !normalizedVersion.isEmpty,
              normalizedVersion.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value)
                      || (65...90).contains(scalar.value)
                      || (97...122).contains(scalar.value)
                      || scalar == "." || scalar == "-"
              })
        else { return false }

        let expectedName = "Crab-\(normalizedVersion)-macOS-\(CrabAppUpdateChecker.currentArchitecture).zip"
        guard offer.assetName == expectedName,
              offer.assetName == URL(fileURLWithPath: offer.assetName).lastPathComponent,
              offer.releaseURL.scheme == "https",
              offer.releaseURL.host?.lowercased() == "github.com",
              offer.releaseURL.path == "/qinthqod/Crab/releases/tag/\(offer.latestVersion)",
              offer.assetURL.scheme == "https",
              offer.assetURL.host?.lowercased() == "github.com",
              offer.assetURL.path == "/qinthqod/Crab/releases/download/\(offer.latestVersion)/\(expectedName)",
              offer.sha256.count == 64,
              offer.sha256.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
              })
        else { return false }
        return true
    }
}

private final class CrabUpdateRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme == "https",
              CrabAppUpdateInstaller.isTrustedDownloadHost(url.host)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private struct CrabUpdateApplicationIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let modificationNanoseconds: Int64

    static func capture(at url: URL) throws -> CrabUpdateApplicationIdentity {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR
        else { throw CrabUpdateInstallationError.invalidCurrentApplication }
        return CrabUpdateApplicationIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            modificationNanoseconds: Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000
                + Int64(metadata.st_mtimespec.tv_nsec)
        )
    }
}
