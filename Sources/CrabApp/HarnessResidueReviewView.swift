import CrabAppSupport
import SwiftUI

struct HarnessResidueReviewView: View {
    @ObservedObject var model: AppModel
    @State private var showsCleanupConfirmation = false

    var body: some View {
        Group {
            switch model.harnessResidueState {
            case .idle:
                Color.clear
            case .scanning:
                activityState(
                    title: CrabL10n.text("正在检查残留资源", "Checking Residues"),
                    detail: CrabL10n.format(
                        "只检查与 %@ 精确匹配的安全路径",
                        "Checking only safe paths that exactly match %@",
                        model.harnessResidueAppName
                    ),
                    motion: .scuttle
                )
            case .reviewing:
                reviewContent
            case .cleaning:
                activityState(
                    title: CrabL10n.text("正在移入废纸篓", "Moving to Trash"),
                    detail: CrabL10n.text(
                        "每一项都已重新验证，未选择的内容保持不变",
                        "Every item was revalidated; unselected content remains unchanged"
                    ),
                    motion: .pinch
                )
            case let .failed(message):
                failureState(message)
            }
        }
        .frame(width: 760, height: 620)
        .background(Color.crabBackground)
        .confirmationDialog(
            "将已选择的残留移入废纸篓？",
            isPresented: $showsCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button(CrabL10n.format("清理 %d 项", "Clean %d Items", selectedCount), role: .destructive) {
                model.cleanSelectedHarnessResidues()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cleanupConfirmationMessage)
        }
    }

    private var reviewContent: some View {
        VStack(spacing: 0) {
            reviewHeader

            ScrollView {
                LazyVStack(spacing: 20) {
                    if !recommendedCandidates.isEmpty {
                        residueSection(
                            title: CrabL10n.text("建议清理", "Recommended"),
                            subtitle: CrabL10n.text(
                                "缓存、日志和窗口状态，可由应用重新生成",
                                "Caches, logs, and window state that the app can recreate"
                            ),
                            candidates: recommendedCandidates,
                            warning: false
                        )
                    }

                    if !reviewCandidates.isEmpty {
                        residueSection(
                            title: CrabL10n.text("需要确认", "Review Required"),
                            subtitle: CrabL10n.text(
                                "可能包含设置、登录状态或其他用户数据",
                                "May contain settings, sign-in state, or other user data"
                            ),
                            candidates: reviewCandidates,
                            warning: true
                        )
                    }

                    if !model.harnessResidueIssues.isEmpty {
                        Label(
                            CrabL10n.format(
                                "另有 %d 个路径无法安全读取，已自动跳过",
                                "%d additional paths could not be read safely and were skipped",
                                model.harnessResidueIssues.count
                            ),
                            systemImage: "exclamationmark.shield.fill"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }

            Divider()
            reviewActions
        }
    }

    private var reviewHeader: some View {
        HStack(spacing: 16) {
            Group {
                if let icon = model.harnessResidueIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    ProductIconView(
                        appID: model.harnessResidueAppID,
                        productName: model.harnessResidueAppName,
                        fallbackSymbol: "sparkles"
                    )
                }
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 5) {
                Text(CrabL10n.format(
                    "%@ 已卸载",
                    "%@ Uninstalled",
                    model.harnessResidueAppName
                ))
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(Color.crabInk)
                Text(CrabL10n.format(
                    "发现 %d 项残留 · 共 %@",
                    "%d residues found · %@ total",
                    allCandidates.count,
                    formattedBytes(model.harnessResidueSnapshot.totalBytes)
                ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(selectedCount == 0
                    ? CrabL10n.text("尚未选择", "Nothing Selected")
                    : CrabL10n.format("已选 %d 项", "%d selected", selectedCount))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selectedCount == 0 ? Color.secondary : Color.crabPurple)
                if selectedCount > 0 {
                    Text(formattedBytes(model.harnessResidueSnapshot.selectedBytes))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private func residueSection(
        title: String,
        subtitle: String,
        candidates: [HarnessResidueCandidate],
        warning: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.crabInk)
                        Text("\(candidates.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(warning ? Color.orange : Color.crabPurple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                (warning ? Color.orange : Color.crabPurple).opacity(0.09),
                                in: Capsule()
                            )
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            ForEach(Array(candidates.enumerated()), id: \.element.rule.id) { index, candidate in
                residueRow(candidate, warning: warning)
                if index < candidates.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(warning ? Color.orange.opacity(0.13) : Color.crabPurple.opacity(0.10))
        }
    }

    private func residueRow(_ candidate: HarnessResidueCandidate, warning: Bool) -> some View {
        Button {
            model.setHarnessResidueSelected(
                candidate.rule.id,
                selected: !isSelected(candidate)
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected(candidate) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected(candidate) ? Color.crabPurple : Color.secondary.opacity(0.55))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(CrabL10n.runtime(candidate.rule.title))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.crabInk)
                        if warning {
                            Text("可能包含用户数据")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.08), in: Capsule())
                        }
                    }
                    Text("~/\(candidate.rule.relativePath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                Text(formattedBytes(candidate.logicalBytes))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CrabL10n.format(
            "%@，%@",
            "%@, %@",
            CrabL10n.runtime(candidate.rule.title),
            formattedBytes(candidate.logicalBytes)
        ))
        .accessibilityValue(isSelected(candidate)
            ? CrabL10n.text("已选择", "Selected")
            : CrabL10n.text("未选择", "Not selected"))
    }

    private var reviewActions: some View {
        HStack(spacing: 12) {
            Button("暂不清理") {
                model.skipHarnessResidueCleanup()
            }
            .buttonStyle(.bordered)
            .tint(Color.crabPurple)

            Spacer()

            if !recommendedCandidates.isEmpty {
                Button(allRecommendedSelected
                    ? CrabL10n.text("取消选择", "Clear Selection")
                    : CrabL10n.text("选择建议项", "Select Recommended")) {
                    if allRecommendedSelected {
                        model.clearHarnessResidueSelection()
                    } else {
                        model.selectRecommendedHarnessResidues()
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color.crabPurple)
            }

            Button(CrabL10n.format("清理 %d 项", "Clean %d Items", selectedCount)) {
                showsCleanupConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.crabPurple)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 28)
        .frame(height: 70)
    }

    private func activityState(
        title: String,
        detail: String,
        motion: CrabLoadingMotion
    ) -> some View {
        VStack(spacing: 16) {
            CrabLoadingIndicator(size: 112, motion: motion)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 15) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.crabPurple)
            Text("残留扫描未完成")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text("应用本体已在废纸篓中，Crab 没有处理任何残留。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Button("完成") {
                model.dismissHarnessResidueResult()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.crabPurple)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allCandidates: [HarnessResidueCandidate] {
        model.harnessResidueSnapshot.candidates
    }

    private var recommendedCandidates: [HarnessResidueCandidate] {
        allCandidates.filter { $0.rule.risk == .recommended }
    }

    private var reviewCandidates: [HarnessResidueCandidate] {
        allCandidates.filter { $0.rule.risk == .reviewRequired }
    }

    private var selectedCount: Int {
        model.harnessResidueSnapshot.selectedRuleIDs.count
    }

    private var allRecommendedSelected: Bool {
        !recommendedCandidates.isEmpty && recommendedCandidates.allSatisfy(isSelected)
    }

    private var selectedReviewRequiredCount: Int {
        reviewCandidates.filter(isSelected).count
    }

    private var cleanupConfirmationMessage: String {
        var message = CrabL10n.text(
            "Crab 会在操作前重新验证目标，并只将已选择的项目移入废纸篓。",
            "Crab will revalidate each target and move only selected items to Trash."
        )
        if selectedReviewRequiredCount > 0 {
            message += CrabL10n.format(
                " 其中 %d 项可能包含设置或用户数据，请确认不再需要。",
                " %d selected items may contain settings or user data. Confirm that you no longer need them.",
                selectedReviewRequiredCount
            )
        }
        return message
    }

    private func isSelected(_ candidate: HarnessResidueCandidate) -> Bool {
        model.harnessResidueSnapshot.selectedRuleIDs.contains(candidate.rule.id)
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
