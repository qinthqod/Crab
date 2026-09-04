import AppKit
import Foundation

public enum MountedDiskImageEjectOutcome: Equatable, Sendable {
    case ejected
    case changed
    case failed
}

public protocol MountedVolumeEjecting: Sendable {
    func ejectVolume(at url: URL) throws
}

public protocol MountedDiskImageEjecting: Sendable {
    func eject(_ reviewedImage: MountedDiskImage) -> MountedDiskImageEjectOutcome
}

public struct SystemMountedVolumeEjector: MountedVolumeEjecting {
    public init() {}

    public func ejectVolume(at url: URL) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }
}

public struct MountedDiskImageEjector: MountedDiskImageEjecting {
    private let dataProvider: any MountedDiskImageDataProviding
    private let volumeEjector: any MountedVolumeEjecting

    public init(
        dataProvider: any MountedDiskImageDataProviding = SystemMountedDiskImageDataProvider(),
        volumeEjector: any MountedVolumeEjecting = SystemMountedVolumeEjector()
    ) {
        self.dataProvider = dataProvider
        self.volumeEjector = volumeEjector
    }

    public func eject(_ reviewedImage: MountedDiskImage) -> MountedDiskImageEjectOutcome {
        let mountURL = reviewedImage.mountURL.standardizedFileURL
        guard mountURL.path.hasPrefix("/Volumes/"),
              let data = dataProvider.mountedDiskImageData()
        else { return .changed }

        let isUnchanged = MountedDiskImageParser.parse(data).contains { current in
            current.imageURL.standardizedFileURL == reviewedImage.imageURL.standardizedFileURL &&
                current.mountURL.standardizedFileURL == mountURL &&
                current.deviceIdentifier == reviewedImage.deviceIdentifier
        }
        guard isUnchanged else { return .changed }

        do {
            try volumeEjector.ejectVolume(at: mountURL)
            return .ejected
        } catch {
            return .failed
        }
    }
}
