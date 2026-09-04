import CrabAppSupport
import SwiftUI

struct RuntimeOptimizerView: View {
    @ObservedObject var model: RuntimeOptimizerModel

    var body: some View {
        switch model.state {
        case .idle:
            home
        case let .running(taskID, completed, total):
            running(taskID: taskID, completed: completed, total: total)
        case let .finished(results):
            resultPage(results)
        }
    }

    private var home: some View {
        VStack(spacing: 0) {
            pageHeader(
                title: CrabL10n.text("运行优化", "Optimize Mac"),
                subtitle: CrabL10n.text("刷新可安全重建的系统服务，让 Mac 恢复顺畅", "Refresh rebuildable system services to keep your Mac responsive")
            )

            Spacer(minLength: 24)

            VStack(spacing: 22) {
                LogoView(size: 112)

                VStack(spacing: 9) {
                    Text(CrabL10n.text("给 Mac 做一次轻量整理", "Give your Mac a light tune-up"))
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.crabInk)
                    Text(CrabL10n.text("不关闭正在使用的第三方应用，也不删除任何文件。", "No third-party apps are closed, and no files are deleted."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    taskPill(.quickLook, symbol: "eye")
                    taskPill(.launchServices, symbol: "square.grid.2x2")
                    taskPill(.finder, symbol: "face.smiling")
                }

                Button(action: model.start) {
                    Label(CrabL10n.text("开始运行", "Start"), systemImage: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 188, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)

                Text(CrabL10n.text("运行时 Finder 窗口可能短暂刷新，随后会自动恢复。", "Finder windows may briefly refresh and then recover automatically."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 36)
        }
    }

    private func taskPill(_ taskID: MacOptimizationTaskID, symbol: String) -> some View {
        Label(taskTitle(taskID), systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.crabPurple)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.crabLavender, in: Capsule())
    }

    private func running(taskID: MacOptimizationTaskID, completed: Int, total: Int) -> some View {
        VStack(spacing: 22) {
            CrabLoadingIndicator(size: 124, motion: .scuttle)

            VStack(spacing: 8) {
                Text(CrabL10n.text("小螃蟹正在整理 Mac…", "Crab is tuning up your Mac…"))
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(Color.crabInk)
                Text(taskProgressTitle(taskID))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .tint(Color.crabPurple)
                .frame(width: 260)

            Text(CrabL10n.format("%d / %d", "%d / %d", min(completed + 1, total), total))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func resultPage(_ results: [MacOptimizationResult]) -> some View {
        VStack(spacing: 0) {
            pageHeader(
                title: CrabL10n.text("运行完成", "Tune-up complete"),
                subtitle: resultSummary(results)
            )

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            resultRow(result)
                            if index < results.count - 1 { Divider().padding(.leading, 58) }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.07))
                    }

                    HStack(spacing: 10) {
                        Button(CrabL10n.text("返回首页", "Back"), action: model.returnHome)
                            .buttonStyle(.bordered)
                        Button(CrabL10n.text("重新运行", "Run Again"), action: model.start)
                            .buttonStyle(.borderedProminent)
                            .tint(Color.crabPurple)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
        }
    }

    private func resultRow(_ result: MacOptimizationResult) -> some View {
        HStack(spacing: 14) {
            Image(systemName: outcomeSymbol(result.outcome))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(outcomeColor(result.outcome))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(taskTitle(result.taskID))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.crabInk)
                Text(outcomeDetail(result))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(outcomeTitle(result.outcome))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(outcomeColor(result.outcome))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(outcomeColor(result.outcome).opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.crabInk)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }

    private func taskTitle(_ taskID: MacOptimizationTaskID) -> String {
        switch taskID {
        case .quickLook: CrabL10n.text("预览服务", "Quick Look")
        case .launchServices: CrabL10n.text("应用关联", "App Associations")
        case .finder: "Finder"
        case .dock: "Dock"
        }
    }

    private func taskProgressTitle(_ taskID: MacOptimizationTaskID) -> String {
        switch taskID {
        case .quickLook: CrabL10n.text("正在刷新文件预览服务", "Refreshing file previews")
        case .launchServices: CrabL10n.text("正在整理应用关联", "Refreshing app associations")
        case .finder: CrabL10n.text("正在重启 Finder", "Restarting Finder")
        case .dock: CrabL10n.text("正在刷新 Dock", "Refreshing the Dock")
        }
    }

    private func resultSummary(_ results: [MacOptimizationResult]) -> String {
        let applied = results.filter { $0.outcome == .applied }.count
        return CrabL10n.format("已完成 %d 项系统整理", "%d system tasks completed", applied)
    }

    private func outcomeTitle(_ outcome: MacOptimizationOutcome) -> String {
        switch outcome {
        case .applied: CrabL10n.text("已完成", "Done")
        case .failed: CrabL10n.text("未完成", "Failed")
        case .unavailable: CrabL10n.text("已跳过", "Skipped")
        }
    }

    private func outcomeDetail(_ result: MacOptimizationResult) -> String {
        switch result.outcome {
        case .applied: CrabL10n.text("系统维护命令已完成", "The maintenance command completed")
        case .failed: CrabL10n.text("此项失败，其余任务仍已继续", "This task failed; remaining tasks continued")
        case .unavailable: CrabL10n.text("当前 macOS 不提供对应工具", "The required macOS tool is unavailable")
        }
    }

    private func outcomeSymbol(_ outcome: MacOptimizationOutcome) -> String {
        switch outcome {
        case .applied: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .unavailable: "minus.circle.fill"
        }
    }

    private func outcomeColor(_ outcome: MacOptimizationOutcome) -> Color {
        switch outcome {
        case .applied: Color.crabPurple
        case .failed: .orange
        case .unavailable: .secondary
        }
    }
}
