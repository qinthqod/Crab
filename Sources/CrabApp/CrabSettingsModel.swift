import AppKit
import CrabAppSupport
import Foundation
import ServiceManagement

@MainActor
final class CrabSettingsModel: ObservableObject {
    enum LaunchAtLoginState: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case unavailable
    }

    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .unavailable
    @Published private(set) var updateState: CrabAppUpdateStatus = .idle
    @Published var operationError: String?

    init() {
        refreshLaunchAtLoginStatus()
    }

    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.isEmpty == false ? version! : "Development"
    }

    var currentBuild: String? {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build?.isEmpty == false ? build : nil
    }

    func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            launchAtLoginState = .disabled
        case .enabled:
            launchAtLoginState = .enabled
        case .requiresApproval:
            launchAtLoginState = .requiresApproval
        case .notFound:
            launchAtLoginState = .disabled
        @unknown default:
            launchAtLoginState = .unavailable
        }
    }

    func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            operationError = CrabL10n.text(
                "无法修改开机启动设置，请在系统设置的“登录项”中确认。",
                "Crab could not change this setting. Check Login Items in System Settings."
            )
        }
    }

    func checkForUpdates() {
        guard updateState != .checking else { return }
        updateState = .checking
        let version = currentVersion
        let feedURL = (Bundle.main.object(forInfoDictionaryKey: "CrabUpdateFeedURL") as? String)
            .flatMap(URL.init(string:))

        Task {
            updateState = await CrabAppUpdateChecker().check(
                currentVersion: version,
                feedURL: feedURL
            )
        }
    }

    func openLoginItemsSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    func openFullDiskAccessSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private func openSystemSettings(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
