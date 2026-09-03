import CrabAppSupport
import CrabCore
import SwiftUI

struct ScanResultView: View {
    @ObservedObject var model: AppModel
    @State private var showingConfirmation = false
    @State private var selectedFilter: AppProductScanFilter = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            resultHeader

            if model.scanOverview.products.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 22) {
                    summaryRail
                    resultsList
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            }
        }
        .confirmationDialog("移入废纸篓？", isPresented: $showingConfirmation) {
            Button("移入废纸篓", role: .destructive) {
                model.moveSelectedToTrash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(CrabL10n.format(
                "将 %d 项（%@）移入废纸篓。聊天、项目和生成文件不会被移动。",
                "Move %d items (%@) to Trash. Chats, projects, and generated files will not be moved.",
                model.snapshot.selectedCount,
                selectedSize
            ))
        }
    }

    private var resultHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("扫描结果")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.crabInk)
                Text(scanSummaryText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Text(CrabL10n.format("已选择 %@", "%@ selected", selectedSize))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.crabPurple)
                    .contentTransition(.numericText())

                Button {
                    model.setAllSelected(
                        in: visibleCandidates,
                        selected: !allCandidatesAreSelected
                    )
                } label: {
                    Label(
                        allCandidatesAreSelected
                            ? CrabL10n.text("取消全选", "Deselect All")
                            : CrabL10n.text("全部选择", "Select All"),
                        systemImage: allCandidatesAreSelected ? "checkmark.square.fill" : "square"
                    )
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.crabPurple)
                .disabled(!model.canToggleBulkSelection(in: visibleCandidates))
                .accessibilityHint("选择或取消选择当前分类中的可用缓存项")
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var summaryRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("当前可清理", systemImage: "internaldrive")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(formattedAvailableNow)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(Color.crabPurple)
                .contentTransition(.numericText())
                .padding(.top, 6)
            Text(CrabL10n.format("已选择 %@", "%@ selected", selectedSize))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(spacing: 8) {
                spaceSummaryRow(
                    title: CrabL10n.text("发现缓存", "Cache Found"),
                    value: formattedDiscovered
                )
                if model.cacheSpaceSummary.blockedByRunningAppsBytes > 0 {
                    spaceSummaryRow(
                        title: CrabL10n.text("退出应用后可清理", "Available After Quitting"),
                        value: formattedBlocked
                    )
                }
            }
            .padding(.top, 14)

            Divider().padding(.vertical, 17)

            Text("应用分类")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                ForEach(AppProductScanFilter.allCases) { filter in
                    categoryButton(filter)
                }
            }
            .padding(.top, 9)

            Spacer(minLength: 14)

            VStack(alignment: .leading, spacing: 8) {
                Label("保护状态", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("安全可清理")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.crabPurple)
                Text("只移动明确选择的缓存；用户内容不在扫描范围内。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(14)
            .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.crabPurple.opacity(0.12))
            }
        }
        .padding(16)
        .frame(width: 218)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.crabLavender.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.crabPurple.opacity(0.12))
        }
    }

    private func spaceSummaryRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.crabInk)
        }
    }

    private func categoryButton(_ filter: AppProductScanFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: filter.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.white : filter.color)
                    .frame(width: 30, height: 30)
                    .background(
                        isSelected ? Color.crabPurple : filter.color.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                Text(filter.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.crabInk)

                Spacer(minLength: 6)

                Text("\(filter.products(in: model.scanOverview.products).count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.crabPurple : Color.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isSelected ? Color.white.opacity(0.92) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.crabPurple.opacity(0.16))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CrabL10n.format(
            "%@，%d 个应用",
            "%@, %d apps",
            filter.title,
            filter.products(in: model.scanOverview.products).count
        ))
        .accessibilityRemoveTraits(.isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    if filteredProducts.isEmpty {
                        filteredEmptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredProducts) { product in
                                ProductGroupView(product: product, model: model)
                            }
                        }
                    }
                }
                .id(selectedFilter)
                .transition(.opacity)
                .padding(.vertical, 1)
                .padding(.trailing, 5)
            }

            Divider().padding(.top, 14)

            HStack(spacing: 12) {
                Button {
                    model.returnToHome()
                } label: {
                    Label("返回首页", systemImage: "house")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: 100, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(Color.crabPurple)

                Button {
                    model.scanUserCaches()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: 112, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(Color.crabPurple)

                Button(actionLabel) {
                    showingConfirmation = true
                }
                .buttonStyle(CrabPrimaryButtonStyle())
                .disabled(model.snapshot.selectedCount == 0 || model.cleanupState == .moving)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: selectedFilter.symbol)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selectedFilter.color)
            Text(CrabL10n.format(
                "没有“%@”分类的应用",
                "No apps in %@",
                selectedFilter.title
            ))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.crabInk)
            Text(selectedFilter.emptyDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.crabPurple)
            Text("没有发现已安装的 AI 应用")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text("未安装的产品不会显示。安装受支持的 AI 应用后可重新扫描。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    model.returnToHome()
                } label: {
                    Label("返回首页", systemImage: "house")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .tint(Color.crabPurple)

                Button {
                    model.scanUserCaches()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 50)
    }

    private var formattedDiscovered: String {
        formattedBytes(model.cacheSpaceSummary.discoveredBytes)
    }

    private var formattedAvailableNow: String {
        formattedBytes(model.cacheSpaceSummary.availableNowBytes)
    }

    private var formattedBlocked: String {
        formattedBytes(model.cacheSpaceSummary.blockedByRunningAppsBytes)
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var selectedSize: String {
        guard model.snapshot.selectedBytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(model.snapshot.selectedBytes), countStyle: .file)
    }

    private var scanSummaryText: String {
        var parts = [
            CrabL10n.format("已检查 %d 个应用", "%d apps checked", model.scannedHarnessCount),
            CrabL10n.format("%d 个有可清理缓存", "%d with cleanable cache", model.detectedAppCount),
            CrabL10n.format("%d 个干净", "%d clean", model.cleanHarnessCount),
        ]
        if model.limitedHarnessCount > 0 {
            parts.append(CrabL10n.format("%d 个扫描受限", "%d scan-limited", model.limitedHarnessCount))
        }
        if model.protectedHarnessCount > 0 {
            parts.append(CrabL10n.format("%d 个暂无安全规则", "%d without safe rules", model.protectedHarnessCount))
        }
        return parts.joined(separator: " · ")
    }

    private var actionLabel: String {
        if model.cleanupState == .moving {
            return CrabL10n.text("正在移入废纸篓…", "Moving to Trash…")
        }
        if model.snapshot.selectedCount == 0 {
            return CrabL10n.text("移入废纸篓", "Move to Trash")
        }
        return CrabL10n.format("移入废纸篓（%d）", "Move to Trash (%d)", model.snapshot.selectedCount)
    }

    private var allCandidatesAreSelected: Bool {
        model.areAllSelectableCandidatesSelected(in: visibleCandidates)
    }

    private var filteredProducts: [AppProductScanSummary] {
        selectedFilter.products(in: model.scanOverview.products)
    }

    private var visibleCandidates: [ScanCandidate] {
        filteredProducts.flatMap(\.candidates)
    }
}

private extension AppProductScanFilter {
    var title: String {
        switch self {
        case .all: CrabL10n.text("全部应用", "All Apps")
        case .cleanable: CrabL10n.text("可清理", "Cleanable")
        case .clean: CrabL10n.text("已干净", "Clean")
        case .protectedData: CrabL10n.text("受保护", "Protected")
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .cleanable: "sparkles"
        case .clean: "checkmark.circle.fill"
        case .protectedData: "lock.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .all, .cleanable: Color.crabPurple
        case .clean: Color.green
        case .protectedData: Color.orange
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: CrabL10n.text("重新扫描后，已安装且受支持的应用会显示在这里。", "Installed supported apps will appear here after a scan.")
        case .cleanable: CrabL10n.text("当前没有发现可以安全清理的缓存。", "No safely cleanable cache was found.")
        case .clean: CrabL10n.text("当前没有已确认干净的应用。", "No apps are currently confirmed clean.")
        case .protectedData: CrabL10n.text("当前没有扫描受限或缺少安全规则的应用。", "No apps are scan-limited or missing safe rules.")
        }
    }
}
