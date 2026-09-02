import CrabArchive
import Foundation

public struct ArchiveReminderState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case awaitingFolder
        case scanning
        case ready
        case failed
    }

    public private(set) var phase: Phase
    public private(set) var rootURL: URL?
    public private(set) var snapshot: ArchiveReviewSnapshot?
    public private(set) var errorMessage: String?
    public let inactivityDays: Int

    public init(inactivityDays: Int = 180) {
        self.inactivityDays = max(1, inactivityDays)
        phase = .awaitingFolder
        rootURL = nil
        snapshot = nil
        errorMessage = nil
    }

    public mutating func beginScanning(rootURL: URL) {
        self.rootURL = rootURL
        snapshot = nil
        errorMessage = nil
        phase = .scanning
    }

    public mutating func finish(with snapshot: ArchiveReviewSnapshot) {
        guard
            phase == .scanning,
            let rootURL,
            canonicalPath(rootURL) == canonicalPath(snapshot.root),
            inactivityDays == snapshot.inactivityDays
        else {
            fail(message: "扫描结果与所选文件夹不一致，请重新选择。")
            return
        }
        self.snapshot = snapshot
        errorMessage = nil
        phase = .ready
    }

    public mutating func fail(message: String) {
        snapshot = nil
        errorMessage = message
        phase = .failed
    }

    public mutating func reset() {
        rootURL = nil
        snapshot = nil
        errorMessage = nil
        phase = .awaitingFolder
    }

    private func canonicalPath(_ url: URL) -> String {
        let path = url.path
        for alias in ["/tmp", "/var"] {
            if path == alias || path.hasPrefix(alias + "/") {
                return "/private" + path
            }
        }
        return path
    }
}
