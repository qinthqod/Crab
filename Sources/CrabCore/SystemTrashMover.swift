import Foundation

public struct SystemTrashMover: TrashMoving {
    public init() {}

    public func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
