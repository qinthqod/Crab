import CrabCore
import Darwin
import Foundation

public struct HarnessUninstallReceipt: Equatable, Sendable {
    public let appID: String
    public let bundleURL: URL

    public init(appID: String, bundleURL: URL) {
        self.appID = appID
        self.bundleURL = bundleURL
    }
}

public enum HarnessUninstallError: Error, Equatable, CustomStringConvertible {
    case unsupportedLocation
    case invalidBundle
    case targetChanged
    case applicationRunning

    public var description: String {
        switch self {
        case .unsupportedLocation:
            "应用不在 Crab 允许的 Applications 目录中。"
        case .invalidBundle:
            "应用本体无法验证，未执行卸载。"
        case .targetChanged:
            "应用在确认后发生变化，请刷新后重试。"
        case .applicationRunning:
            "请先退出这个应用，再尝试卸载。"
        }
    }
}

public struct HarnessUninstaller<
    Mover: TrashMoving,
    ApplicationChecker: ApplicationActivityChecking
>: Sendable {
    private let trashMover: Mover
    private let applicationChecker: ApplicationChecker

    public init(trashMover: Mover, applicationChecker: ApplicationChecker) {
        self.trashMover = trashMover
        self.applicationChecker = applicationChecker
    }

    public func uninstall(
        installation: HarnessInstallation,
        allowedApplicationRoots: [URL]
    ) throws -> HarnessUninstallReceipt {
        let bundleURL = installation.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension.lowercased() == "app",
              let root = allowedApplicationRoots
                .map(\.standardizedFileURL)
                .first(where: { contains(bundleURL, inside: $0) }),
              hasNoSymbolicLink(from: root, through: bundleURL)
        else { throw HarnessUninstallError.unsupportedLocation }

        guard HarnessBundleIdentity.capture(at: bundleURL) == installation.identity else {
            throw HarnessUninstallError.targetChanged
        }
        guard Bundle(url: bundleURL)?.bundleIdentifier == installation.appID else {
            throw HarnessUninstallError.invalidBundle
        }
        guard !applicationChecker.isApplicationRunning(bundleIdentifier: installation.appID) else {
            throw HarnessUninstallError.applicationRunning
        }

        try trashMover.moveToTrash(bundleURL)
        return HarnessUninstallReceipt(appID: installation.appID, bundleURL: bundleURL)
    }

    private func contains(_ target: URL, inside root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return target.path.hasPrefix(rootPath) && target.path != root.path
    }

    private func hasNoSymbolicLink(from root: URL, through target: URL) -> Bool {
        let rootComponents = root.pathComponents
        let targetComponents = target.pathComponents
        guard targetComponents.starts(with: rootComponents) else { return false }

        var current = root
        var rootMetadata = stat()
        guard lstat(root.path, &rootMetadata) == 0,
              (rootMetadata.st_mode & S_IFMT) != S_IFLNK
        else { return false }

        for component in targetComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component)
            var metadata = stat()
            guard lstat(current.path, &metadata) == 0,
                  (metadata.st_mode & S_IFMT) != S_IFLNK
            else { return false }
        }
        return true
    }
}
