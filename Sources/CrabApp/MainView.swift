import CrabAppSupport
import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var desktopPresence: DesktopPresenceController
    @ObservedObject var settings: CrabSettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CrabWindowBackground()

            VStack(spacing: 0) {
                header

                Group {
                    if model.mode == .cache {
                        switch model.state {
                        case .idle:
                            ScanHomeView(
                                lastScan: model.lastCacheScan,
                                onScan: model.scanUserCaches
                            )
                        case .loading:
                            ScanLoadingView()
                        case .ready:
                            ScanResultView(model: model)
                        case let .failed(message):
                            ScanFailureView(
                                message: message,
                                onHome: model.returnToHome,
                                onRetry: model.scanUserCaches
                            )
                        }
                    } else if model.mode == .harness {
                        HarnessOverviewView(model: model)
                    } else if model.mode == .archive {
                        ArchiveReminderView(model: model)
                    } else {
                        RuntimeOptimizerView(model: model.runtimeOptimizer)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1),
                    value: model.state
                )

                if shouldShowSafetyFooter {
                    ScanSafetyFooter(mode: model.mode)
                }
            }
        }
        .background {
            MainWindowCloseObserver {
                desktopPresence.mainWindowWillClose()
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            settings.checkForUpdatesAtLaunch()
            loadSelectedModeIfNeeded(model.mode)
        }
        .onChange(of: model.mode) { _, mode in
            DispatchQueue.main.async {
                loadSelectedModeIfNeeded(mode)
            }
        }
        .alert("处理结果", isPresented: cleanupSucceeded) {
            Button("完成") { model.dismissCleanupResult() }
        } message: {
            Text(cleanupMessage)
        }
        .alert("无法清理", isPresented: cleanupFailed) {
            Button("好") { model.dismissCleanupResult() }
        } message: {
            Text(cleanupMessage)
        }
    }

    private func loadSelectedModeIfNeeded(_ mode: AppModel.Mode) {
        guard mode == model.mode else { return }
        switch mode {
        case .cache:
            break
        case .harness:
            model.refreshHarnessInventory()
        case .archive:
            model.scanProjects()
        case .optimizer:
            break
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                if !isLoading {
                    LogoView(size: 26)
                }
                Text("Crab")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.crabInk)
            }
            .frame(width: 150, alignment: .leading)

            Spacer()

            CrabModePicker(selection: model.mode) { mode in
                DispatchQueue.main.async {
                    model.setMode(mode)
                }
            }
            .frame(width: 520)

            Spacer()

            Group {
                if let offer = settings.homeUpdateOffer {
                    Button {
                        settings.installAvailableUpdate()
                    } label: {
                        Label {
                            Text(homeUpdateTitle(for: offer))
                        } icon: {
                            if settings.updateActionState.isBusy {
                                CrabLoadingIndicator(size: 16, motion: .pinch)
                            } else {
                                Image(systemName: homeUpdateIcon)
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(homeUpdateColor)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(Color.crabLavender, in: Capsule())
                        .overlay {
                            Capsule().stroke(Color.crabPurple.opacity(0.16))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.updateActionState.isBusy)
                    .help(homeUpdateHelp(for: offer))
                    .accessibilityLabel(homeUpdateAccessibilityLabel(for: offer))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Color.clear
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 150, alignment: .trailing)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1),
                value: settings.homeUpdateOffer?.latestVersion
            )
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    private func normalizedVersion(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private func homeUpdateTitle(for offer: CrabAppUpdateOffer) -> String {
        switch settings.updateActionState {
        case .downloading:
            CrabL10n.text("正在下载", "Downloading")
        case .installing:
            CrabL10n.text("正在安装", "Installing")
        case .relaunching:
            CrabL10n.text("正在重启", "Restarting")
        case .failed:
            CrabL10n.format(
                "重试 %@",
                "Retry %@",
                normalizedVersion(offer.latestVersion)
            )
        case .idle:
            CrabL10n.format(
                "更新 %@",
                "Update %@",
                normalizedVersion(offer.latestVersion)
            )
        }
    }

    private var homeUpdateIcon: String {
        if case .failed = settings.updateActionState {
            return "exclamationmark.triangle.fill"
        }
        return "arrow.down.circle.fill"
    }

    private var homeUpdateColor: Color {
        if case .failed = settings.updateActionState {
            return .orange
        }
        return .crabPurple
    }

    private func homeUpdateHelp(for offer: CrabAppUpdateOffer) -> String {
        switch settings.updateActionState {
        case .downloading:
            CrabL10n.text("正在从 Crab 官方发布源下载更新", "Downloading from Crab's official release source")
        case .installing:
            CrabL10n.text("正在校验并安全安装更新", "Verifying and securely installing the update")
        case .relaunching:
            CrabL10n.text("更新完成后将自动重新打开 Crab", "Crab will reopen automatically after updating")
        case let .failed(message):
            message
        case .idle:
            CrabL10n.format(
                "直接下载并安装 Crab %@",
                "Download and install Crab %@ directly",
                normalizedVersion(offer.latestVersion)
            )
        }
    }

    private func homeUpdateAccessibilityLabel(for offer: CrabAppUpdateOffer) -> String {
        switch settings.updateActionState {
        case .downloading:
            CrabL10n.text("正在下载 Crab 更新", "Downloading Crab update")
        case .installing:
            CrabL10n.text("正在安装 Crab 更新", "Installing Crab update")
        case .relaunching:
            CrabL10n.text("正在重新打开 Crab", "Reopening Crab")
        case .failed:
            CrabL10n.format(
                "更新失败，点击重试 Crab %@",
                "Update failed. Retry Crab %@",
                normalizedVersion(offer.latestVersion)
            )
        case .idle:
            CrabL10n.format(
                "发现 Crab 新版本 %@，点击直接更新",
                "Crab version %@ is available. Click to update directly",
                normalizedVersion(offer.latestVersion)
            )
        }
    }

    private var isLoading: Bool {
        if model.mode == .cache, case .loading = model.state { return true }
        if model.mode == .optimizer, case .running = model.runtimeOptimizer.state { return true }
        return false
    }

    private var shouldShowSafetyFooter: Bool {
        if model.mode == .cache, case .idle = model.state { return false }
        return true
    }

    private var cleanupMessage: String {
        switch model.cleanupState {
        case let .succeeded(message), let .failed(message): message
        default: ""
        }
    }

    private var cleanupSucceeded: Binding<Bool> {
        Binding(
            get: { if case .succeeded = model.cleanupState { true } else { false } },
            set: { if !$0 { model.dismissCleanupResult() } }
        )
    }

    private var cleanupFailed: Binding<Bool> {
        Binding(
            get: { if case .failed = model.cleanupState { true } else { false } },
            set: { if !$0 { model.dismissCleanupResult() } }
        )
    }
}

private struct CrabModePicker: View {
    let selection: AppModel.Mode
    let onSelect: (AppModel.Mode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppModel.Mode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: selection == mode ? .semibold : .medium))
                        .foregroundStyle(selection == mode ? Color.white : Color.crabInk.opacity(0.78))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            selection == mode ? Color.crabPurple : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("功能")
    }
}

struct ScanSafetyFooter: View {
    let mode: AppModel.Mode

    var body: some View {
        Label(footerText, systemImage: "checkmark.shield.fill")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.hierarchical)
        .padding(.horizontal, 24)
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }

    private var footerText: String {
        switch mode {
        case .cache:
            CrabL10n.text(
                "仅移动已选择的缓存到废纸篓，聊天、项目与生成文件保持受保护",
                "Only selected caches move to Trash; chats, projects, and generated files stay protected"
            )
        case .harness:
            CrabL10n.text(
                "卸载只移动应用本体；残留仅在单独选择并再次确认后移入废纸篓",
                "Uninstalling moves only the app; residues move to Trash only after separate selection and confirmation"
            )
        case .archive:
            CrabL10n.text(
                "仅处理明确选择并二次确认的项目；6 个月未使用与大项目只作为标签提示",
                "Only explicitly selected projects move to Trash after confirmation; inactive and large projects are labels only"
            )
        case .optimizer:
            CrabL10n.text(
                "体检数据仅在本机使用；不会删除文件或自动关闭第三方应用",
                "Checkup data stays on this Mac; Crab never deletes files or automatically closes third-party apps"
            )
        }
    }
}

struct CrabWindowBackground: View {
    var body: some View {
        Color.crabBackground
        .ignoresSafeArea()
    }
}

struct CrabPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                Color.crabPurple.opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1) : 0.42),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}
