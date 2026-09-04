import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
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
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
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

            Spacer()

            CrabModePicker(selection: model.mode) { mode in
                DispatchQueue.main.async {
                    model.setMode(mode)
                }
            }
            .frame(width: 520)

            Spacer()

            Color.clear
                .frame(width: 76, height: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
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
                "只读查看 AI 应用的运行占用；不会关闭、暂停应用或修改任何文件",
                "Read-only AI app usage overview; Crab never closes, pauses, or modifies applications"
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
