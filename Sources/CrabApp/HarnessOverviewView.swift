import CrabAppSupport
import AppKit
import Combine
import SwiftUI

struct HarnessOverviewView: View {
    @ObservedObject var model: AppModel
    @State private var pendingUninstall: HarnessInstallation?
    @State private var launchFailureMessage: String?
    @State private var runningAppIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.inventoryState {
            case .idle, .loading: loadingState
            case .ready where model.harnessInventory.installations.isEmpty: emptyState
            case .ready: applicationList
            case let .failed(message): failureState(message)
            }
        }
        .confirmationDialog(
            CrabL10n.format(
                "卸载 %@？",
                "Uninstall %@?",
                pendingUninstall?.displayName ?? CrabL10n.text("应用", "App")
            ),
            isPresented: uninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("仅将应用本体移入废纸篓", role: .destructive) {
                guard let pendingUninstall else { return }
                model.uninstallHarness(pendingUninstall)
                self.pendingUninstall = nil
            }
            Button("取消", role: .cancel) { pendingUninstall = nil }
        } message: {
            Text("缓存、聊天、项目、模型、账号和偏好设置都会保留。")
        }
        .alert("应用卸载", isPresented: uninstallResultPresented) {
            Button("完成") { model.dismissHarnessUninstallResult() }
        } message: {
            Text(uninstallResultMessage)
        }
        .alert("无法打开应用", isPresented: launchFailurePresented) {
            Button("完成") { launchFailureMessage = nil }
        } message: {
            Text(launchFailureMessage ?? CrabL10n.text(
                "Crab 无法打开这个应用。",
                "Crab could not open this app."
            ))
        }
        .sheet(isPresented: residueReviewPresented) {
            HarnessResidueReviewView(model: model)
                .interactiveDismissDisabled(true)
        }
        .onAppear(perform: refreshRunningAppIDs)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )) { _ in
            refreshRunningAppIDs()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )) { _ in
            refreshRunningAppIDs()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("应用管理")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.crabInk)
                Text("运行中优先，其次按最近使用排序")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Text(CrabL10n.format(
                "%d 个已安装",
                "%d installed",
                model.harnessInventory.installations.count
            ))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.crabPurple)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 32)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }

    private var applicationList: some View {
        ScrollView {
            VStack(spacing: 0) {
                HarnessTableHeader(showsUsageColumn: showsUsageColumn)
                LazyVStack(spacing: 0) {
                    ForEach(Array(orderedInstallations.enumerated()), id: \.element.id) { index, installation in
                        HarnessApplicationRow(
                            installation: installation,
                            usage: model.harnessUsageByAppID[installation.appID],
                            cacheBytes: model.cacheBytes(for: installation.appID),
                            cacheWasScanned: model.state == .ready,
                            isRunning: runningAppIDs.contains(installation.appID),
                            isUninstalling: uninstallingAppID == installation.appID,
                            metadataIsLoading: model.harnessMetadataIsLoading,
                            showsUsageColumn: showsUsageColumn,
                            onOpen: { openApplication(installation) },
                            onUninstall: { pendingUninstall = installation }
                        )
                        if index < orderedInstallations.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.07))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            CrabLoadingIndicator(size: 96, motion: .pinch)
            Text("正在读取最近使用记录…").font(.system(size: 15, weight: .medium))
            Text("只读取应用和固定日志的元数据，不读取对话内容")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在读取已安装应用")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 42))
                .foregroundStyle(Color.crabPurple)
            Text("没有发现支持的 AI 应用").font(.system(size: 22, weight: .bold))
            Text("未安装的产品不会显示，也不会参与扫描。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("无法读取应用清单").font(.system(size: 21, weight: .bold))
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            Button("重新读取") { model.refreshHarnessInventory(force: true) }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var orderedInstallations: [HarnessInstallation] {
        model.harnessInventory.orderedInstallations(runningAppIDs: runningAppIDs)
    }

    private func refreshRunningAppIDs() {
        runningAppIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private var showsUsageColumn: Bool {
        model.harnessUsageByAppID.values.contains { !$0.availableMetrics.isEmpty }
    }

    private var uninstallingAppID: String? {
        guard case let .moving(appID) = model.harnessUninstallState else { return nil }
        return appID
    }

    private var uninstallConfirmation: Binding<Bool> {
        Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } })
    }

    private var uninstallResultPresented: Binding<Bool> {
        Binding(
            get: {
                if case .succeeded = model.harnessUninstallState { return true }
                if case .failed = model.harnessUninstallState { return true }
                return false
            },
            set: { if !$0 { model.dismissHarnessUninstallResult() } }
        )
    }

    private var uninstallResultMessage: String {
        switch model.harnessUninstallState {
        case let .succeeded(message), let .failed(message): message
        default: ""
        }
    }

    private var launchFailurePresented: Binding<Bool> {
        Binding(
            get: { launchFailureMessage != nil },
            set: { if !$0 { launchFailureMessage = nil } }
        )
    }

    private var residueReviewPresented: Binding<Bool> {
        Binding(
            get: { model.harnessResidueState != .idle },
            set: { _ in }
        )
    }

    private func openApplication(_ installation: HarnessInstallation) {
        guard installation.kind == .applicationBundle else { return }
        if !NSWorkspace.shared.open(installation.bundleURL) {
            launchFailureMessage = CrabL10n.format(
                "无法打开 %@，应用可能已经移动或损坏。",
                "Unable to open %@. The app may have been moved or damaged.",
                installation.displayName
            )
        }
    }
}

private struct HarnessTableHeader: View {
    let showsUsageColumn: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("应用")
                .frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)
            Text("最近使用")
                .frame(width: 150, alignment: .leading)
            if showsUsageColumn {
                Text("模型相关数据")
                    .frame(width: 235, alignment: .leading)
            }
            Text("本地占用")
                .frame(width: 96, alignment: .trailing)
            Text("操作")
                .frame(width: 196, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.018))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

private struct HarnessApplicationRow: View {
    let installation: HarnessInstallation
    let usage: HarnessUsageSummary?
    let cacheBytes: UInt64
    let cacheWasScanned: Bool
    let isRunning: Bool
    let isUninstalling: Bool
    let metadataIsLoading: Bool
    let showsUsageColumn: Bool
    let onOpen: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                ProductIconView(
                    appID: installation.appID,
                    productName: installation.displayName,
                    fallbackSymbol: installation.kind == .commandLineTool ? "terminal.fill" : "sparkles"
                )
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(installation.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.crabInk)
                            .lineLimit(1)
                        if installation.kind == .applicationBundle,
                           let version = installation.versionDisplayText {
                            Text(version)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.035), in: Capsule())
                        }
                    }
                    if isRunning {
                        Label("正在运行", systemImage: "circle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    } else if installation.kind == .commandLineTool {
                        HStack(spacing: 6) {
                            Text("命令行工具")
                                .foregroundStyle(Color.crabPurple)
                            if let version = installation.versionDisplayText {
                                Text(version)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    }
                }
            }
            .frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(lastUsedRelativeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.crabInk.opacity(0.78))
                if let date = installation.lastUsedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 150, alignment: .leading)

            if showsUsageColumn {
                usageSummary.frame(width: 235, alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 4) {
                if installation.installedBytes == 0, metadataIsLoading {
                    HStack(spacing: 6) {
                        CrabLoadingIndicator(size: 16, motion: .pinch)
                        Text("计算中")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                } else {
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(installation.installedBytes + (cacheWasScanned ? cacheBytes : 0)),
                        countStyle: .file
                    ))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.crabInk)
                    Text(cacheWasScanned
                        ? CrabL10n.text("应用与缓存", "App and Cache")
                        : CrabL10n.text("应用本体", "App Only"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 96, alignment: .trailing)

            applicationActions.frame(width: 196, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var applicationActions: some View {
        if isUninstalling {
            HStack(spacing: 7) {
                CrabLoadingIndicator(size: 18, motion: .pinch)
                Text("正在卸载")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.crabPurple)
            .accessibilityLabel(CrabL10n.format(
                "正在卸载 %@",
                "Uninstalling %@",
                installation.displayName
            ))
        } else if installation.kind == .applicationBundle {
            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Label("打开应用", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .tint(Color.crabPurple)
                .controlSize(.small)
                .help(CrabL10n.format(
                    "启动或切换到 %@",
                    "Launch or switch to %@",
                    installation.displayName
                ))

                Button(role: .destructive, action: onUninstall) {
                    Label("卸载应用", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunning)
                .help(isRunning
                    ? CrabL10n.text("请先退出应用再卸载", "Quit the app before uninstalling")
                    : CrabL10n.text("仅将应用本体移入废纸篓", "Move only the app to Trash"))
            }
        } else {
            Label("命令行工具", systemImage: "terminal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .help(CrabL10n.text(
                    "命令行工具没有可打开的 App 本体",
                    "Command-line tools do not have an app to open"
                ))
        }
    }

    private var usageSummary: some View {
        HStack(spacing: 6) {
            ForEach(usage?.availableMetrics ?? [], id: \.kind) { metric in
                usageMetric(metric)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func usageMetric(_ metric: HarnessUsageMetric) -> some View {
        HStack(spacing: 4) {
            Image(systemName: metricSymbol(metric.kind))
                .font(.system(size: 9, weight: .semibold))

            Text(metricValue(metric))
                .font(.system(size: 10, weight: .semibold, design: .rounded))

            Text(metricLabel(metric.kind))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Color.crabPurple)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.crabLavender.opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.crabPurple.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metricValue(metric)) \(metricLabel(metric.kind))")
    }

    private func metricSymbol(_ kind: HarnessUsageMetric.Kind) -> String {
        switch kind {
        case .projects: "folder.fill"
        case .conversations: "bubble.left.and.bubble.right.fill"
        case .tokens: "bolt.horizontal.circle.fill"
        }
    }

    private func metricValue(_ metric: HarnessUsageMetric) -> String {
        switch metric.kind {
        case .projects, .conversations:
            metric.value.formatted()
        case .tokens:
            metric.value.formatted(.number.notation(.compactName))
        }
    }

    private func metricLabel(_ kind: HarnessUsageMetric.Kind) -> String {
        switch kind {
        case .projects: CrabL10n.text("项目", "Projects")
        case .conversations: CrabL10n.text("对话", "Chats")
        case .tokens: "Token"
        }
    }

    private var lastUsedRelativeText: String {
        guard let date = installation.lastUsedAt else {
            return metadataIsLoading
                ? CrabL10n.text("正在读取", "Reading")
                : CrabL10n.text("暂无系统记录", "No system record")
        }
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: CrabL10n.language.rawValue)
        relative.unitsStyle = .full
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
