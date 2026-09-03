import CrabAppSupport
import SwiftUI

struct RuntimeOptimizerView: View {
    @ObservedObject var model: RuntimeOptimizerModel
    @State private var presentsConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header

            switch model.state {
            case .idle, .loading:
                loadingState
            case .ready, .optimizing:
                results
            case let .failed(message):
                failureState(message)
            }
        }
        .confirmationDialog(
            CrabL10n.text("优化所选应用？", "Optimize Selected Apps?"),
            isPresented: $presentsConfirmation,
            titleVisibility: .visible
        ) {
            Button(CrabL10n.text("发送标准退出请求", "Send Standard Quit Requests")) {
                model.optimizeSelectedApplications()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert(resultTitle, isPresented: resultPresented) {
            Button("完成") { model.dismissResult() }
        } message: {
            Text(resultMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("运行优化")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.crabInk)
                Text("看清 AI 应用的运行占用，需要时让它们正常退出")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.refresh(force: true)
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(Color.crabPurple)
            .disabled(model.state == .loading || model.state == .optimizing)
        }
        .padding(.horizontal, 32)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            CrabLoadingIndicator(size: 72, motion: .scuttle)
            Text("正在查看 AI 应用的运行占用…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.crabInk)
            Text("只读取进程编号、父进程与内存大小")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var results: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard

                    if model.snapshot.applications.isEmpty {
                        emptyState
                    } else {
                        applicationList
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }

            if !model.snapshot.applications.isEmpty {
                actionBar
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.crabLavender)
                Image(systemName: "memorychip.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.crabPurple)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(memoryText(model.snapshot.totalResidentBytes))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(Color.crabInk)
                Text(CrabL10n.format(
                    "%d 个正在运行的 AI 应用",
                    "%d running AI apps",
                    model.snapshot.applications.count
                ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(
                CrabL10n.text("仅正常退出", "Standard Quit Only"),
                systemImage: "checkmark.shield.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.crabPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.crabLavender, in: Capsule())
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var applicationList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("运行中的应用")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.crabInk)
                Spacer()
                Button(allSelected ? "取消全选" : "全部选择") {
                    model.setAllSelected(!allSelected)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.crabPurple)
            }
            .padding(.horizontal, 18)
            .frame(height: 44)

            Divider()

            ForEach(Array(model.snapshot.applications.enumerated()), id: \.element.id) { index, application in
                RuntimeApplicationRow(
                    application: application,
                    isSelected: model.selection.selectedAppIDs.contains(application.appID),
                    onToggle: {
                        model.setSelected(
                            application.appID,
                            selected: !model.selection.selectedAppIDs.contains(application.appID)
                        )
                    }
                )
                if index < model.snapshot.applications.count - 1 {
                    Divider().padding(.leading, 74)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.crabPurple)
                .symbolRenderingMode(.hierarchical)
            Text("目前没有运行中的 AI 应用")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.crabInk)
            Text("Crab 只显示本机正在运行且已经支持的 AI 桌面应用。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(CrabL10n.format(
                    "已选择 %d 个应用",
                    "%d apps selected",
                    model.selectedApplications.count
                ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.crabInk)
                Text(CrabL10n.format(
                    "当前约占用 %@",
                    "Currently using about %@",
                    memoryText(model.selectedBytes)
                ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                presentsConfirmation = true
            } label: {
                if model.state == .optimizing {
                    HStack(spacing: 8) {
                        CrabLoadingIndicator(size: 20, motion: .pinch)
                        Text("正在优化")
                    }
                } else {
                    Label("优化所选应用", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.crabPurple)
            .controlSize(.large)
            .disabled(model.selectedApplications.isEmpty || model.state == .optimizing)
        }
        .padding(.horizontal, 32)
        .frame(height: 72)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text("无法读取运行占用")
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("重新读取") { model.refresh(force: true) }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allSelected: Bool {
        let applications = model.snapshot.applications
        return !applications.isEmpty && applications.allSatisfy {
            model.selection.selectedAppIDs.contains($0.appID)
        }
    }

    private var confirmationMessage: String {
        let separator = CrabL10n.language == .simplifiedChinese ? "、" : ", "
        let names = model.selectedApplications.map(\.displayName).joined(separator: separator)
        return CrabL10n.format(
            "Crab 将请求 %@ 正常退出，当前约占用 %@。应用仍可以询问你是否保存内容或拒绝退出；Crab 不会强制关闭。",
            "Crab will ask %@ to quit normally. They currently use about %@. Apps may ask you to save or refuse to quit; Crab never force-quits.",
            names,
            memoryText(model.selectedBytes)
        )
    }

    private var resultPresented: Binding<Bool> {
        Binding(
            get: { model.result != nil },
            set: { if !$0 { model.dismissResult() } }
        )
    }

    private var resultTitle: String {
        switch model.result {
        case .succeeded: CrabL10n.text("已发送退出请求", "Quit Requests Sent")
        case .failed: CrabL10n.text("无法优化", "Unable to Optimize")
        case nil: ""
        }
    }

    private var resultMessage: String {
        switch model.result {
        case let .succeeded(message), let .failed(message): message
        case nil: ""
        }
    }

    private func memoryText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(min(bytes, UInt64(Int64.max))),
            countStyle: .memory
        )
    }
}

private struct RuntimeApplicationRow: View {
    let application: RunningAIApplication
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isSelected ? Color.crabPurple : Color.secondary.opacity(0.55))

                ProductIconView(
                    appID: application.appID,
                    productName: application.displayName,
                    fallbackSymbol: "sparkles"
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text(application.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.crabInk)
                    Label("正在运行", systemImage: "circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                Spacer()

                if let launchedAt = application.launchedAt {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("运行时长")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(runtimeText(since: launchedAt))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 110, alignment: .trailing)
                }

                VStack(alignment: .trailing, spacing: 4) {
                    Text("内存占用")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(min(application.residentBytes, UInt64(Int64.max))),
                        countStyle: .memory
                    ))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.crabPurple)
                }
                .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CrabL10n.format(
            "%@，内存占用 %@",
            "%@, %@ memory",
            application.displayName,
            ByteCountFormatter.string(
                fromByteCount: Int64(min(application.residentBytes, UInt64(Int64.max))),
                countStyle: .memory
            )
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func runtimeText(since date: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: date, to: Date()) ?? CrabL10n.text("刚刚", "Just now")
    }
}
