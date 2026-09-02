import AppKit
import CrabAppSupport
import CrabCore
import SwiftUI

struct ProductGroupView: View {
    let product: AppProductScanSummary
    @ObservedObject var model: AppModel
    @State private var isExpanded: Bool

    init(product: AppProductScanSummary, model: AppModel) {
        self.product = product
        self.model = model
        _isExpanded = State(initialValue: !product.candidates.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            productHeader

            if isExpanded {
                ForEach(Array(product.candidates.enumerated()), id: \.element.rule.id) { index, candidate in
                    if index > 0 {
                        Divider().padding(.leading, 50)
                    }
                    CacheItemRow(
                        candidate: candidate,
                        productName: productName,
                        isSelected: model.snapshot.selectedRuleIDs.contains(candidate.rule.id),
                        isUnavailable: model.isApplicationRunning(for: candidate),
                        onToggle: { model.setSelected(candidate.rule.id, selected: $0) }
                    )
                }
            }
        }
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08))
        }
        .accessibilityElement(children: .contain)
    }

    private var productHeader: some View {
        HStack(spacing: 11) {
            Button(action: toggleExpanded) {
                HStack(spacing: 11) {
                ProductIconView(
                    appID: product.appID,
                    productName: productName,
                    fallbackSymbol: productSymbol
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(productName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.crabInk)
                        if productIsRunning {
                            Text("使用中")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.05), in: Capsule())
                        }
                    }
                    Text(productSubtitle)
                        .font(.caption)
                        .foregroundStyle(product.status == .limited ? Color.orange : Color.secondary)
                }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(product.candidates.isEmpty)

            Spacer()

            if product.candidates.isEmpty {
                statusBadge
            } else {
                Text(ByteCountFormatter.string(fromByteCount: Int64(product.totalBytes), countStyle: .file))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.crabInk)

                if product.status == .limited {
                    statusBadge
                }

                Button {
                    model.setAllSelected(
                        in: product.candidates,
                        selected: !allCandidatesAreSelected
                    )
                } label: {
                    Text(allCandidatesAreSelected
                        ? CrabL10n.text("取消全选", "Deselect All")
                        : CrabL10n.text("全选", "Select All"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.crabPurple)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 26)
                        .background(Color.white.opacity(0.78), in: Capsule())
                        .overlay {
                            Capsule().stroke(Color.crabPurple.opacity(0.2))
                        }
                }
                .buttonStyle(.plain)
                .disabled(!model.canToggleBulkSelection(in: product.candidates))
                .opacity(model.canToggleBulkSelection(in: product.candidates) ? 1 : 0.45)
                .accessibilityHint(CrabL10n.format(
                    "选择或取消选择 %@ 的所有可用缓存项",
                    "Select or deselect all available caches for %@",
                    productName
                ))

                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 28)
                .accessibilityLabel(isExpanded
                    ? CrabL10n.format("收起 %@", "Collapse %@", productName)
                    : CrabL10n.format("展开 %@", "Expand %@", productName))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.crabLavender.opacity(0.42))
        .accessibilityAddTraits(.isHeader)
    }

    private func toggleExpanded() {
        withAnimation(.snappy(duration: 0.22)) {
            isExpanded.toggle()
        }
    }

    private var productName: String {
        model.appName(forAppID: product.appID)
    }

    private var productIsRunning: Bool {
        product.candidates.contains(where: model.isApplicationRunning)
    }

    private var allCandidatesAreSelected: Bool {
        model.areAllSelectableCandidatesSelected(in: product.candidates)
    }

    private var productSubtitle: String {
        switch product.status {
        case .hasCache:
            CrabL10n.format("%d 个缓存项", "%d cache items", product.candidates.count)
        case .clean:
            CrabL10n.text("已检查 · 未发现可清理缓存", "Checked · no cleanable cache")
        case .limited:
            product.candidates.isEmpty
                ? CrabL10n.text("部分目录无法确认", "Some folders could not be verified")
                : CrabL10n.format(
                    "%d 个缓存项 · 部分目录无法确认",
                    "%d cache items · some folders could not be verified",
                    product.candidates.count
                )
        case .protected:
            CrabL10n.text("暂无已验证的可再生缓存路径", "No verified regenerable cache path")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch product.status {
        case .clean:
            Label("干净", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
        case .limited:
            Label("扫描受限", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
        case .protected:
            Label("用户数据受保护", systemImage: "lock.shield.fill")
                .foregroundStyle(Color.crabPurple)
        case .hasCache:
            EmptyView()
        }
    }

    private var productSymbol: String {
        switch product.appID {
        case "com.openai.codex", "com.todesktop.230313mzl4w4u92", "com.codeium.windsurf", "cn.trae.app", "cn.trae.solo.app", "dev.zed.Zed":
            "chevron.left.forwardslash.chevron.right"
        case "com.electron.ollama":
            "shippingbox.fill"
        case "com.openai.chat", "com.anthropic.claudefordesktop":
            "bubble.left.and.bubble.right.fill"
        case "ai.anthropic.claude-code", "ai.deepseek.dsh":
            "terminal.fill"
        default:
            "sparkles"
        }
    }
}

struct ProductIconView: View {
    let appID: String
    let productName: String
    let fallbackSymbol: String

    var body: some View {
        Group {
            if let icon = ProductIconLoader.icon(
                bundleIdentifier: appID,
                applicationName: productName
            ) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.crabPurple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.crabLavender, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

private enum ProductIconLoader {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    static func icon(bundleIdentifier: String, applicationName: String) -> NSImage? {
        let cacheKey = bundleIdentifier as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let workspace = NSWorkspace.shared
        let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? localApplicationURL(named: applicationName)
        guard let applicationURL else { return nil }

        let icon = workspace.icon(forFile: applicationURL.path)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func localApplicationURL(named applicationName: String) -> URL? {
        let fileManager = FileManager.default
        let appBundleName = applicationName.hasSuffix(".app")
            ? applicationName
            : "\(applicationName).app"
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        return candidates
            .map { $0.appendingPathComponent(appBundleName, isDirectory: true) }
            .first(where: { fileManager.fileExists(atPath: $0.path) })
    }
}

private struct CacheItemRow: View {
    let candidate: ScanCandidate
    let productName: String
    let isSelected: Bool
    let isUnavailable: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.crabPurple : Color.secondary.opacity(0.72))

                VStack(alignment: .leading, spacing: 2) {
                    Text(CrabL10n.runtime(candidate.rule.explanation))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.crabInk)
                        .lineLimit(1)
                    if isUnavailable {
                        Text("退出应用后可选择")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: Int64(candidate.logicalBytes), countStyle: .file))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(isSelected ? Color.crabLavender.opacity(0.72) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.56 : 1)
        .accessibilityLabel(CrabL10n.format(
            "%@，%@，%@",
            "%@, %@, %@",
            productName,
            CrabL10n.runtime(candidate.rule.explanation),
            ByteCountFormatter.string(fromByteCount: Int64(candidate.logicalBytes), countStyle: .file)
        ))
        .accessibilityValue(isUnavailable
            ? CrabL10n.text("应用使用中", "App is running")
            : (isSelected
                ? CrabL10n.text("已选择", "Selected")
                : CrabL10n.text("未选择", "Not selected")))
    }
}
