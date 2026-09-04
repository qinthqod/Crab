public struct DesktopPresenceState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case mainWindow
        case menuBarOnly
    }

    public private(set) var phase: Phase

    public init() {
        phase = .mainWindow
    }

    public var isMenuBarVisible: Bool {
        true
    }

    @discardableResult
    public mutating func minimizeToMenuBar(enabled: Bool) -> Bool {
        false
    }

    @discardableResult
    public mutating func closeMainWindow() -> Bool {
        guard phase != .menuBarOnly else { return false }
        phase = .menuBarOnly
        return true
    }

    @discardableResult
    public mutating func restoreMainWindow() -> Bool {
        guard phase != .mainWindow else { return false }
        phase = .mainWindow
        return true
    }
}
