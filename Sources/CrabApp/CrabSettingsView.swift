import CrabAppSupport
import SwiftUI

struct CrabSettingsView: View {
    @StateObject private var settings = CrabSettingsModel()
    @AppStorage(CrabLanguagePreference.defaultsKey)
    private var languagePreference = CrabLanguagePreference.system.rawValue

    var body: some View {
        ScrollView {
            singlePage
        }
        .tint(.crabPurple)
        .frame(width: 650, height: 600)
        .background(Color.crabBackground)
        .alert(
            CrabL10n.text("无法完成设置", "Setting Could Not Be Changed"),
            isPresented: operationErrorPresented
        ) {
            Button(CrabL10n.text("好", "OK")) { settings.operationError = nil }
        } message: {
            Text(settings.operationError ?? "")
        }
        .onAppear {
            if CrabLanguagePreference(rawValue: languagePreference) == nil {
                languagePreference = CrabLanguagePreference.system.rawValue
            }
            settings.refreshLaunchAtLoginStatus()
        }
    }

    private var singlePage: some View {
        settingsPage(
            title: CrabL10n.text("设置", "Settings"),
            subtitle: CrabL10n.text(
                "管理 Crab 的语言、系统权限、启动与更新",
                "Manage Crab's language, system access, startup, and updates"
            )
        ) {
            VStack(spacing: 14) {
                generalSection
                permissionsSection
                updatesSection
            }
        }
    }

    private var generalSection: some View {
        settingsCard {
                settingRow(
                    icon: "character.bubble",
                    title: CrabL10n.text("界面语言", "Interface Language"),
                    subtitle: CrabL10n.text("更改后立即应用到所有窗口", "Changes apply to every window immediately")
                ) {
                    Picker("", selection: $languagePreference) {
                        Text(CrabL10n.text("跟随系统", "System Default"))
                            .tag(CrabLanguagePreference.system.rawValue)
                        Text("简体中文")
                            .tag(CrabLanguagePreference.simplifiedChinese.rawValue)
                        Text("English")
                            .tag(CrabLanguagePreference.english.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                Divider().padding(.leading, 44)

                settingRow(
                    icon: "power",
                    title: CrabL10n.text("开机自动启动", "Launch at Login"),
                    subtitle: launchAtLoginSubtitle
                ) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .disabled(settings.launchAtLoginState == .unavailable)
                }

                if settings.launchAtLoginState == .requiresApproval {
                    Divider().padding(.leading, 44)
                    HStack {
                        Text(CrabL10n.text(
                            "macOS 需要你在“登录项”中确认 Crab。",
                            "macOS requires approval for Crab in Login Items."
                        ))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        Spacer()
                        Button(CrabL10n.text("打开系统设置", "Open System Settings")) {
                            settings.openLoginItemsSettings()
                        }
                    }
                    .padding(.leading, 44)
                }
        }
    }

    private var permissionsSection: some View {
        settingsCard {
            settingRow(
                icon: "externaldrive.badge.checkmark",
                title: CrabL10n.text("完全磁盘访问", "Full Disk Access"),
                subtitle: CrabL10n.text(
                    "由 macOS 授予；修改权限后请重新启动 Crab",
                    "Granted by macOS; restart Crab after changing access"
                )
            ) {
                Button(CrabL10n.text("打开系统设置", "Open System Settings")) {
                    settings.openFullDiskAccessSettings()
                }
            }
        }
    }

    private var updatesSection: some View {
        settingsCard {
                settingRow(
                    icon: "shippingbox",
                    title: CrabL10n.text("当前版本", "Current Version"),
                    subtitle: currentVersionText
                ) {
                    Button {
                        performUpdateAction()
                    } label: {
                        if isUpdateBusy {
                            HStack(spacing: 6) {
                                CrabLoadingIndicator(size: 18, motion: .pinch)
                                Text(updateButtonTitle)
                            }
                        } else {
                            Text(updateButtonTitle)
                        }
                    }
                    .disabled(isUpdateBusy)
                    .frame(minWidth: 112)
                }

                Divider().padding(.leading, 44)

                HStack(alignment: .top, spacing: 12) {
                    if isUpdateBusy {
                        CrabLoadingIndicator(size: 28, motion: .scuttle)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: updateStatusIcon)
                            .foregroundStyle(updateStatusColor)
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(updateStatusTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(updateStatusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.crabInk)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(Color.crabBackground)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .padding(16)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private func settingRow<Accessory: View>(
        icon: String,
        iconColor: Color = .crabPurple,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            accessory()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                settings.launchAtLoginState == .enabled
                    || settings.launchAtLoginState == .requiresApproval
            },
            set: { value in
                settings.setLaunchAtLogin(enabled: value)
            }
        )
    }

    private var launchAtLoginSubtitle: String {
        switch settings.launchAtLoginState {
        case .disabled:
            CrabL10n.text("登录 Mac 后不自动打开 Crab", "Crab does not open automatically after login")
        case .enabled:
            CrabL10n.text("登录 Mac 后自动运行并显示菜单栏图标", "Runs after login and shows the menu bar icon")
        case .requiresApproval:
            CrabL10n.text("等待系统设置确认", "Waiting for approval in System Settings")
        case .unavailable:
            CrabL10n.text("当前构建不支持登录项", "Login item is unavailable in this build")
        }
    }

    private var currentVersionText: String {
        guard let build = settings.currentBuild else { return settings.currentVersion }
        return CrabL10n.format("%@（构建 %@）", "%@ (Build %@)", settings.currentVersion, build)
    }

    private var updateStatusTitle: String {
        switch settings.updateActionState {
        case .downloading:
            return CrabL10n.text("正在下载新版 Crab", "Downloading Crab Update")
        case .installing:
            return CrabL10n.text("正在安全安装", "Installing Securely")
        case .relaunching:
            return CrabL10n.text("正在重新打开 Crab", "Reopening Crab")
        case .failed:
            return CrabL10n.text("更新未完成", "Update Not Completed")
        case .idle:
            break
        }
        return switch settings.updateState {
        case .idle: CrabL10n.text("准备检查", "Ready to Check")
        case .checking: CrabL10n.text("正在检查更新", "Checking for Updates")
        case .upToDate: CrabL10n.text("Crab 已是最新版本", "Crab Is Up to Date")
        case let .available(offer): CrabL10n.format("发现新版本 %@", "Version %@ Is Available", offer.latestVersion)
        case .unavailable: CrabL10n.text("此构建尚未配置更新源", "No Update Source Is Configured")
        case .failed: CrabL10n.text("暂时无法检查更新", "Unable to Check for Updates")
        }
    }

    private var updateStatusDetail: String {
        switch settings.updateActionState {
        case .downloading:
            return CrabL10n.text("正在从 Crab 官方 GitHub Release 下载更新。", "Downloading from Crab's official GitHub Release.")
        case .installing:
            return CrabL10n.text("正在校验大小、SHA-256、版本与应用签名，然后原子替换。", "Verifying size, SHA-256, version, and app signature before atomic replacement.")
        case .relaunching:
            return CrabL10n.text("新版已安装，Crab 即将重新打开。", "The update is installed and Crab is about to reopen.")
        case let .failed(message):
            return message
        case .idle:
            break
        }
        return switch settings.updateState {
        case .idle:
            CrabL10n.text("Crab 只会连接已配置的 HTTPS 更新源。", "Crab connects only to its configured HTTPS update source.")
        case .checking:
            CrabL10n.text("正在安全获取最新版本信息…", "Securely fetching the latest release information…")
        case .upToDate:
            CrabL10n.text("当前没有可用更新。", "No update is currently available.")
        case .available:
            CrabL10n.text("由你确认后，Crab 会在应用内下载、校验并安装。", "When you confirm, Crab downloads, verifies, and installs the update in app.")
        case .unavailable:
            CrabL10n.text("正式发布时配置更新源后即可在这里检查。", "Configure a release feed to enable in-app update checks.")
        case .failed:
            CrabL10n.text("请检查网络连接后再试。", "Check your network connection and try again.")
        }
    }

    private var updateStatusIcon: String {
        if case .failed = settings.updateActionState {
            return "exclamationmark.triangle.fill"
        }
        return switch settings.updateState {
        case .upToDate: "checkmark.circle.fill"
        case .available: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .checking: "clock.arrow.circlepath"
        case .idle, .unavailable: "info.circle.fill"
        }
    }

    private var updateStatusColor: Color {
        if case .failed = settings.updateActionState {
            return .orange
        }
        return switch settings.updateState {
        case .upToDate: .green
        case .available: .crabPurple
        case .failed: .orange
        case .idle, .checking, .unavailable: .secondary
        }
    }

    private var isUpdateBusy: Bool {
        settings.updateState == .checking || settings.updateActionState.isBusy
    }

    private var updateButtonTitle: String {
        switch settings.updateActionState {
        case .downloading: CrabL10n.text("正在下载", "Downloading")
        case .installing: CrabL10n.text("正在安装", "Installing")
        case .relaunching: CrabL10n.text("正在重启", "Restarting")
        case .failed:
            CrabL10n.text("重试安装", "Retry Install")
        case .idle:
            if case .available = settings.updateState {
                CrabL10n.text("下载并安装", "Download and Install")
            } else {
                CrabL10n.text("检查更新", "Check for Updates")
            }
        }
    }

    private func performUpdateAction() {
        if case .available = settings.updateState {
            settings.installAvailableUpdate()
        } else {
            settings.checkForUpdates()
        }
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding(
            get: { settings.operationError != nil },
            set: { if !$0 { settings.operationError = nil } }
        )
    }
}
