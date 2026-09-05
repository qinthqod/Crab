import AppKit
import CrabAppSupport
import Foundation
import ServiceManagement

@MainActor
final class CrabSettingsModel: ObservableObject {
    enum UpdateActionState: Equatable {
        case idle
        case downloading
        case installing
        case relaunching
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .installing, .relaunching: true
            case .idle, .failed: false
            }
        }
    }

    enum LaunchAtLoginState: Equatable {
        case disabled
        case enabled
        case requiresApproval
        case unavailable
    }

    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .unavailable
    @Published private(set) var updateState: CrabAppUpdateStatus = .idle
    @Published private(set) var updateActionState: UpdateActionState = .idle
    @Published var operationError: String?
    private var launchUpdateCheckState = CrabLaunchUpdateCheckState()

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

    var availableUpdateOffer: CrabAppUpdateOffer? {
        guard !updateActionState.isBusy else { return nil }
        return CrabLaunchUpdateCheckState.availableOffer(from: updateState)
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
        guard updateState != .checking, !updateActionState.isBusy else { return }
        updateActionState = .idle
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

    func checkForUpdatesAtLaunch() {
        guard launchUpdateCheckState.beginCheckIfNeeded() else { return }
        checkForUpdates()
    }

    func installAvailableUpdate() {
        guard case let .available(offer) = updateState,
              !updateActionState.isBusy
        else { return }

        updateActionState = .downloading
        let currentAppURL = Bundle.main.bundleURL
        Task {
            do {
                let installedURL = try await CrabAppUpdateInstaller.downloadAndInstall(
                    offer: offer,
                    currentAppURL: currentAppURL,
                    progress: { [weak self] phase in
                        await MainActor.run {
                            switch phase {
                            case .downloading: self?.updateActionState = .downloading
                            case .installing: self?.updateActionState = .installing
                            }
                        }
                    }
                )
                updateActionState = .relaunching
                relaunchApplication(at: installedURL)
            } catch {
                updateActionState = .failed(
                    CrabL10n.text(
                        "更新未安装，当前版本保持不变。请检查网络后重试。",
                        "The update was not installed. Your current version is unchanged. Check your connection and try again."
                    )
                )
            }
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

    private func relaunchApplication(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.updateActionState = .failed(
                        CrabL10n.text(
                            "更新已安装，但无法自动重新打开 Crab。请手动打开。\n\(error.localizedDescription)",
                            "The update was installed, but Crab could not reopen automatically. Open it manually.\n\(error.localizedDescription)"
                        )
                    )
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
