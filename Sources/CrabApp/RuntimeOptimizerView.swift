import CrabAppSupport
import SwiftUI

struct RuntimeOptimizerView: View {
    @ObservedObject var model: RuntimeOptimizerModel
    @State private var pendingEjectImage: MountedDiskImage?

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                home
            case let .running(step, completed, total):
                running(step: step, completed: completed, total: total)
            case let .finished(report):
                resultPage(report)
            }
        }
        .alert(item: $pendingEjectImage) { image in
            Alert(
                title: Text(CrabL10n.text("推出磁盘镜像？", "Eject disk image?")),
                message: Text(CrabL10n.format(
                    "将推出“%@”。不会删除原始 DMG 文件。",
                    "“%@” will be ejected. The original DMG file will not be deleted.",
                    image.mountURL.lastPathComponent
                )),
                primaryButton: .default(Text(CrabL10n.text("推出", "Eject"))) {
                    model.eject(image)
                },
                secondaryButton: .cancel(Text(CrabL10n.text("取消", "Cancel")))
            )
        }
    }

    private var home: some View {
        VStack(spacing: 0) {
            pageHeader(
                title: CrabL10n.text("运行优化", "Optimize Mac"),
                subtitle: CrabL10n.text(
                    "先体检，再处理真正影响流畅度的问题",
                    "Diagnose first, then address what actually slows your Mac"
                )
            )

            Spacer(minLength: 22)

            VStack(spacing: 22) {
                LogoView(size: 112)

                VStack(spacing: 9) {
                    Text(CrabL10n.text("给 Mac 做一次轻量体检", "Give your Mac a focused checkup"))
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.crabInk)
                    Text(CrabL10n.text(
                        "检查内存压力、CPU、磁盘与系统服务，只执行安全的必要维护。",
                        "Check memory pressure, CPU, disk, and system services, then apply only safe maintenance."
                    ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    homePill(CrabL10n.text("本地体检", "Local diagnosis"), symbol: "waveform.path.ecg")
                    homePill(CrabL10n.text("智能执行", "Smart actions"), symbol: "wand.and.stars")
                    homePill(CrabL10n.text("不删除文件", "No file deletion"), symbol: "checkmark.shield")
                }

                Button(action: model.start) {
                    Label(CrabL10n.text("开始运行", "Start"), systemImage: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 188, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)

                Text(CrabL10n.text(
                    "诊断数据只在本机内存中使用，不会上传或保存。",
                    "Diagnosis data stays in memory on this Mac and is never uploaded or saved."
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 34)
        }
    }

    private func homePill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.crabPurple)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.crabLavender, in: Capsule())
    }

    private func running(
        step: RuntimeOptimizerModel.RunningStep,
        completed: Int,
        total: Int
    ) -> some View {
        VStack(spacing: 22) {
            CrabLoadingIndicator(size: 124, motion: .scuttle)

            VStack(spacing: 8) {
                Text(CrabL10n.text("小螃蟹正在检查 Mac…", "Crab is checking your Mac…"))
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(Color.crabInk)
                Text(progressTitle(step))
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

    private func resultPage(_ report: RuntimeOptimizationReport) -> some View {
        VStack(spacing: 0) {
            pageHeader(
                title: CrabL10n.text("运行完成", "Checkup complete"),
                subtitle: resultSummary(report)
            )

            ScrollView {
                LazyVStack(spacing: 18) {
                    metricGrid(report.diagnosis.snapshot)
                    diagnosisSection(report.diagnosis)

                    if !report.diagnosis.resourceHeavyProcesses.isEmpty {
                        processSection(report.diagnosis.resourceHeavyProcesses)
                    }

                    maintenanceSection(report.automaticResults)
                    optionalRefreshSection(report)

                    if !report.visibleMountedDiskImages.isEmpty {
                        mountedImageSection(report.visibleMountedDiskImages)
                    }

                    actionFeedback

                    HStack(spacing: 10) {
                        Button(CrabL10n.text("返回首页", "Back"), action: model.returnHome)
                            .buttonStyle(.bordered)
                        Button(CrabL10n.text("重新运行", "Run Again"), action: model.start)
                            .buttonStyle(.borderedProminent)
                            .tint(Color.crabPurple)
                    }
                    .disabled(model.actionState.isRunning)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
        }
    }

    private func metricGrid(_ snapshot: MacRuntimeSnapshot) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            metricCard(
                title: CrabL10n.text("可用磁盘", "Disk Available"),
                value: bytes(snapshot.diskAvailableBytes),
                symbol: "internaldrive"
            )
            metricCard(
                title: CrabL10n.text("内存压力", "Memory Pressure"),
                value: memoryPressureTitle(snapshot.memoryPressure),
                symbol: "memorychip"
            )
            metricCard(
                title: "Swap",
                value: bytes(Int64(clamping: snapshot.swapUsedBytes)),
                symbol: "arrow.left.arrow.right"
            )
            metricCard(
                title: CrabL10n.text("连续运行", "Uptime"),
                value: uptimeTitle(snapshot.uptime),
                symbol: "clock"
            )
        }
    }

    private func metricCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.crabPurple)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.crabInk)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private func diagnosisSection(_ diagnosis: MacRuntimeDiagnosis) -> some View {
        sectionCard(
            title: CrabL10n.text("状态体检", "System Check"),
            symbol: healthSymbol(diagnosis.level)
        ) {
            if diagnosis.findings.isEmpty {
                compactMessageRow(
                    symbol: "checkmark.circle.fill",
                    color: .green,
                    title: CrabL10n.text("当前状态良好", "Your Mac looks healthy"),
                    detail: CrabL10n.text("没有发现需要立即处理的运行瓶颈。", "No immediate runtime bottleneck was detected.")
                )
            } else {
                ForEach(Array(diagnosis.findings.enumerated()), id: \.element.id) { index, finding in
                    findingRow(finding, snapshot: diagnosis.snapshot)
                    if index < diagnosis.findings.count - 1 { Divider().padding(.leading, 44) }
                }
            }
        }
    }

    private func findingRow(_ finding: MacRuntimeFinding, snapshot: MacRuntimeSnapshot) -> some View {
        compactMessageRow(
            symbol: findingSymbol(finding.id),
            color: finding.level == .critical ? .orange : Color.crabPurple,
            title: findingTitle(finding.id),
            detail: findingDetail(finding.id, snapshot: snapshot)
        )
    }

    private func processSection(_ processes: [MacRuntimeProcessUsage]) -> some View {
        sectionCard(title: CrabL10n.text("资源占用", "Resource Usage"), symbol: "chart.bar.xaxis") {
            ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                HStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.crabPurple)
                        .frame(width: 28)
                    Text(process.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.crabInk)
                        .lineLimit(1)
                    Spacer()
                    if process.cpuPercent >= 1 {
                        metricTag(String(format: "CPU %.0f%%", process.cpuPercent))
                    }
                    if process.memoryBytes > 0 {
                        metricTag(ByteCountFormatter.string(fromByteCount: Int64(clamping: process.memoryBytes), countStyle: .memory))
                    }
                }
                .padding(.horizontal, 15)
                .frame(minHeight: 48)
                if index < processes.count - 1 { Divider().padding(.leading, 55) }
            }
        }
    }

    private func maintenanceSection(_ results: [MacOptimizationResult]) -> some View {
        sectionCard(title: CrabL10n.text("已完成维护", "Maintenance Completed"), symbol: "checkmark.seal") {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                resultRow(result)
                if index < results.count - 1 { Divider().padding(.leading, 56) }
            }
        }
    }

    private func optionalRefreshSection(_ report: RuntimeOptimizationReport) -> some View {
        sectionCard(title: CrabL10n.text("可选刷新", "Optional Refresh"), symbol: "slider.horizontal.3") {
            optionalRefreshRow(
                taskID: .finder,
                detail: CrabL10n.text("仅在 Finder 卡顿时使用，窗口可能短暂刷新。", "Use only when Finder is stuck; windows may briefly refresh."),
                result: report.optionalResults[.finder]
            )
            Divider().padding(.leading, 56)
            optionalRefreshRow(
                taskID: .dock,
                detail: CrabL10n.text("仅在 Dock 卡顿时使用，Dock 会短暂隐藏后恢复。", "Use only when the Dock is stuck; it briefly hides and returns."),
                result: report.optionalResults[.dock]
            )
        }
    }

    private func optionalRefreshRow(
        taskID: MacOptimizationTaskID,
        detail: String,
        result: MacOptimizationResult?
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: taskID == .finder ? "face.smiling" : "dock.rectangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.crabPurple)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(taskTitle(taskID))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.crabInk)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRefreshing(taskID) {
                ProgressView().controlSize(.small)
            } else if let result {
                outcomeTag(result.outcome)
            } else {
                Button(CrabL10n.text("刷新", "Refresh")) {
                    model.runOptional(taskID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.actionState.isRunning)
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 62)
    }

    private func mountedImageSection(_ images: [MountedDiskImage]) -> some View {
        sectionCard(title: CrabL10n.text("已挂载磁盘镜像", "Mounted Disk Images"), symbol: "externaldrive.badge.checkmark") {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                HStack(spacing: 14) {
                    Image(systemName: "opticaldiscdrive")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.crabPurple)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(image.mountURL.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.crabInk)
                        Text(image.imageURL.lastPathComponent)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isEjecting(image) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(CrabL10n.text("推出", "Eject")) {
                            pendingEjectImage = image
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.actionState.isRunning)
                    }
                }
                .padding(.horizontal, 15)
                .frame(minHeight: 58)
                if index < images.count - 1 { Divider().padding(.leading, 56) }
            }
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        switch model.actionState {
        case let .completed(.eject(_, outcome)) where outcome != .ejected:
            compactMessageRow(
                symbol: "exclamationmark.circle.fill",
                color: .orange,
                title: outcome == .changed
                    ? CrabL10n.text("挂载状态已变化", "Mount state changed")
                    : CrabL10n.text("无法推出磁盘镜像", "Could not eject disk image"),
                detail: CrabL10n.text("Crab 没有执行操作，请重新运行体检后再试。", "No action was taken. Run the checkup again before retrying.")
            )
            .padding(14)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case let .completed(.refresh(taskID, outcome)) where outcome != .applied:
            compactMessageRow(
                symbol: "exclamationmark.circle.fill",
                color: .orange,
                title: CrabL10n.format("%@ 未能刷新", "%@ could not be refreshed", taskTitle(taskID)),
                detail: CrabL10n.text("其他体检结果不受影响。", "Other checkup results are unaffected.")
            )
            .padding(14)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        default:
            EmptyView()
        }
    }

    private func resultRow(_ result: MacOptimizationResult) -> some View {
        HStack(spacing: 14) {
            Image(systemName: outcomeSymbol(result.outcome))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(outcomeColor(result.outcome))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(taskTitle(result.taskID))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.crabInk)
                Text(outcomeDetail(result.outcome))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            outcomeTag(result.outcome)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 58)
    }

    private func compactMessageRow(
        symbol: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.crabInk)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 58)
    }

    private func sectionCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.crabInk)
                .padding(.horizontal, 15)
                .frame(height: 42)
            Divider()
            content()
        }
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.07))
            }
    }

    private func metricTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.crabPurple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.crabLavender, in: Capsule())
    }

    private func outcomeTag(_ outcome: MacOptimizationOutcome) -> some View {
        Text(outcomeTitle(outcome))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(outcomeColor(outcome))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(outcomeColor(outcome).opacity(0.1), in: Capsule())
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

    private func progressTitle(_ step: RuntimeOptimizerModel.RunningStep) -> String {
        switch step {
        case .diagnosis:
            CrabL10n.text("正在采样内存、CPU、磁盘与系统状态", "Sampling memory, CPU, disk, and system state")
        case let .maintenance(taskID):
            taskProgressTitle(taskID)
        }
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
        case .finder: CrabL10n.text("正在刷新 Finder", "Refreshing Finder")
        case .dock: CrabL10n.text("正在刷新 Dock", "Refreshing the Dock")
        }
    }

    private func resultSummary(_ report: RuntimeOptimizationReport) -> String {
        switch report.diagnosis.level {
        case .healthy:
            CrabL10n.text("体检完成，当前没有明显运行瓶颈", "Checkup complete with no obvious runtime bottleneck")
        case .attention:
            CrabL10n.format("发现 %d 项值得留意的状态", "%d items may need attention", report.diagnosis.findings.count)
        case .critical:
            CrabL10n.format("发现 %d 项需要优先处理的状态", "%d items should be addressed first", report.diagnosis.findings.count)
        }
    }

    private func findingTitle(_ id: MacRuntimeFindingID) -> String {
        switch id {
        case .lowDiskSpace: CrabL10n.text("磁盘空间不足", "Low disk space")
        case .memoryPressure: CrabL10n.text("内存压力较高", "High memory pressure")
        case .thermalPressure: CrabL10n.text("系统温度较高", "Elevated thermal pressure")
        case .longUptime: CrabL10n.text("Mac 已连续运行较久", "Long system uptime")
        case .resourcePressure: CrabL10n.text("发现高占用进程", "Resource-heavy processes found")
        }
    }

    private func findingDetail(_ id: MacRuntimeFindingID, snapshot: MacRuntimeSnapshot) -> String {
        switch id {
        case .lowDiskSpace:
            CrabL10n.format("启动磁盘剩余 %@。", "%@ remains on the startup disk.", bytes(snapshot.diskAvailableBytes))
        case .memoryPressure:
            CrabL10n.format("当前为%@，Swap 已使用 %@。", "Current state: %@; %@ of swap is in use.", memoryPressureTitle(snapshot.memoryPressure), bytes(Int64(clamping: snapshot.swapUsedBytes)))
        case .thermalPressure:
            CrabL10n.text("降低持续高负载并保持散热通畅。", "Reduce sustained load and keep airflow clear.")
        case .longUptime:
            CrabL10n.format("已经连续运行 %@，可在方便时重新启动。", "The Mac has been running for %@; restart when convenient.", uptimeTitle(snapshot.uptime))
        case .resourcePressure:
            CrabL10n.text("以下应用持续占用较多 CPU 或内存，Crab 不会自动关闭它们。", "The apps below are sustaining high CPU or memory use. Crab will not close them.")
        }
    }

    private func findingSymbol(_ id: MacRuntimeFindingID) -> String {
        switch id {
        case .lowDiskSpace: "internaldrive.fill"
        case .memoryPressure: "memorychip.fill"
        case .thermalPressure: "thermometer.high"
        case .longUptime: "clock.badge.exclamationmark"
        case .resourcePressure: "chart.line.uptrend.xyaxis"
        }
    }

    private func healthSymbol(_ level: MacRuntimeHealthLevel) -> String {
        switch level {
        case .healthy: "checkmark.circle"
        case .attention: "exclamationmark.circle"
        case .critical: "exclamationmark.triangle"
        }
    }

    private func memoryPressureTitle(_ pressure: MacRuntimeMemoryPressure) -> String {
        switch pressure {
        case .normal: CrabL10n.text("正常", "Normal")
        case .warning: CrabL10n.text("偏高", "Elevated")
        case .critical: CrabL10n.text("严重", "Critical")
        case .unknown: CrabL10n.text("未知", "Unknown")
        }
    }

    private func uptimeTitle(_ uptime: TimeInterval) -> String {
        let days = max(0, Int(uptime / 86_400))
        if days > 0 {
            return CrabL10n.format("%d 天", "%d days", days)
        }
        let hours = max(1, Int(uptime / 3_600))
        return CrabL10n.format("%d 小时", "%d hours", hours)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }

    private func outcomeTitle(_ outcome: MacOptimizationOutcome) -> String {
        switch outcome {
        case .applied: CrabL10n.text("已完成", "Done")
        case .failed: CrabL10n.text("未完成", "Failed")
        case .unavailable: CrabL10n.text("已跳过", "Skipped")
        }
    }

    private func outcomeDetail(_ outcome: MacOptimizationOutcome) -> String {
        switch outcome {
        case .applied: CrabL10n.text("安全维护已完成", "Safe maintenance completed")
        case .failed: CrabL10n.text("此项失败，其余结果不受影响", "This task failed; other results are unaffected")
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

    private func isRefreshing(_ taskID: MacOptimizationTaskID) -> Bool {
        if case let .refreshing(current) = model.actionState { return current == taskID }
        return false
    }

    private func isEjecting(_ image: MountedDiskImage) -> Bool {
        if case let .ejecting(current) = model.actionState { return current == image.id }
        return false
    }
}
