import CrabAppSupport
import CrabArchive
import SwiftUI

struct ArchiveReminderView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeAlert: ProjectCleanupAlert?
    @State private var disclosureState = ProjectGroupDisclosureState()
    @State private var searchText = ""
    @State private var selectedFilter: ProjectCleanupFilter = .all
    @State private var selectedSort: ProjectCleanupSort = .recentActivity

    var body: some View {
        Group {
            switch model.projectScanAccessState {
            case .unknown:
                loadingState
            case .needsAuthorization:
                authorizationState
            case let .failed(message):
                authorizationFailureState(message)
            case .authorized:
                switch model.projectInventoryState {
                case .idle, .loading:
                    loadingState
                case .ready:
                    resultState
                case let .failed(message):
                    failureState(message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { model.scanProjects() }
        .onChange(of: model.projectCleanupState) { _, state in
            switch state {
            case let .succeeded(message):
                activeAlert = .result(
                    title: CrabL10n.text("处理完成", "Completed"),
                    message: message
                )
            case let .failed(message):
                activeAlert = .result(
                    title: CrabL10n.text("未处理项目", "Projects Not Moved"),
                    message: message
                )
            default: break
            }
        }
        .onChange(of: model.projectInventory.scannedAt) { _, _ in
            disclosureState = ProjectGroupDisclosureState()
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmation:
                Alert(
                    title: Text("确认移入废纸篓？"),
                    message: Text(confirmationMessage),
                    primaryButton: .destructive(Text("确认移入废纸篓")) {
                        model.moveSelectedProjectsToTrash()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case let .result(title, message):
                Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("完成")) {
                        model.dismissProjectCleanupResult()
                    }
                )
            }
        }
    }

    private var authorizationState: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.crabPurple)

            VStack(spacing: 7) {
                Text("授权一次，之后自动扫描")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color.crabInk)
                Text("请选择你的个人文件夹。Crab 会保存系统安全书签，以后进入项目清理时不再重复询问。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            HStack(spacing: 18) {
                Label("只扫描个人文件夹", systemImage: "person.crop.circle")
                Label("不读取代码内容", systemImage: "doc.text.magnifyingglass")
                Label("处理前二次确认", systemImage: "checkmark.shield")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            Button {
                model.requestProjectScanAccess()
            } label: {
                Label("选择个人文件夹", systemImage: "folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 180, minHeight: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.crabPurple)

            Text("不需要“完全磁盘访问”；授权失效或被撤销时才会再次询问。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 48)
    }

    private func authorizationFailureState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 46))
                .foregroundStyle(Color.crabPurple)
            Text("需要选择个人文件夹")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新选择") { model.requestProjectScanAccess() }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 48)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            CrabLoadingIndicator(size: 118, motion: .scuttle)
            Text("正在扫描本机项目…")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text(CrabL10n.text("正在逐项检查，全部检查结束后显示结果", "Checking all items before showing results"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(CrabL10n.format(
                "已遍历 %d 项 · 已检查 %d 项内容 · 已处理 %d 个项目",
                "%d entries searched · %d inspected · %d projects processed",
                model.projectScanProgress.discoveredEntryCount,
                model.projectScanProgress.inspectedEntryCount,
                model.projectScanProgress.inspectedProjectCount))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("只读取文件名、修改时间与大小，不读取代码或对话内容")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Button(CrabL10n.text("取消并返回首页", "Cancel and Return Home")) {
                model.setMode(.cache)
                model.returnToHome()
            }
            .buttonStyle(.bordered)
            .tint(Color.crabPurple)
        }
        .padding(.bottom, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在自动扫描项目并按应用归类")
    }

    private var resultState: some View {
        VStack(spacing: 0) {
            resultHeader
            if model.projectInventory.hasIncompleteResults {
                Label(partialScanMessage, systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 14)
            }
            if model.projectInventory.projects.isEmpty {
                emptyState
            } else if groupedProjects.isEmpty {
                filteredEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(groupedProjects) { group in
                            projectGroup(group)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
            if !model.projectInventory.projects.isEmpty {
                projectCleanupBar
            }
        }
    }

    private var resultHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("项目清理")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.crabInk)
                    Text(CrabL10n.format(
                        "自动发现 %d 个项目 · %d 个超过 6 个月未修改 · %d 个大项目",
                        "%d projects found · %d unmodified for over 6 months · %d large",
                        model.projectInventory.projects.count,
                        inactiveProjectCount,
                        largeProjectCount
                    ))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.projectInventory.projects.isEmpty {
                    Button(allVisibleProjectsAreSelected
                        ? CrabL10n.text("取消全选", "Deselect All")
                        : CrabL10n.text("全选当前结果", "Select Visible")) {
                        model.setProjectsSelected(
                            visibleProjects,
                            selected: !allVisibleProjectsAreSelected
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.crabPurple)
                    .disabled(isMovingProjects || !visibleProjects.contains(where: \.canClean))
                }
                Button {
                    model.scanProjects(force: true)
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(Color.crabPurple)
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索项目名称或路径", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(CrabL10n.text("清除搜索", "Clear Search"))
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.black.opacity(0.09))
                }

                Picker("筛选", selection: $selectedFilter) {
                    ForEach(ProjectCleanupFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 430)

                Picker("排序", selection: $selectedSort) {
                    ForEach(ProjectCleanupSort.allCases, id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .frame(width: 150)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private func projectGroup(_ group: ProjectGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                        disclosureState.toggle(group.appID)
                    }
                } label: {
                    HStack(spacing: 12) {
                        ProductIconView(
                            appID: group.appID,
                            productName: group.displayName,
                            fallbackSymbol: "sparkles"
                        )
                        .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.crabInk)
                            Text(projectGroupSummary(group))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded(group) ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CrabL10n.format(
                    "%@，%@",
                    "%@, %@",
                    group.displayName,
                    projectGroupSummary(group)
                ))
                .accessibilityValue(isExpanded(group)
                    ? CrabL10n.text("已展开", "Expanded")
                    : CrabL10n.text("已收起", "Collapsed"))
                .accessibilityHint(isExpanded(group)
                    ? CrabL10n.text("收起项目列表", "Collapse project list")
                    : CrabL10n.text("展开项目列表", "Expand project list"))

                if !group.projects.isEmpty {
                    Button(model.allProjectsAreSelected(in: group.projects)
                        ? CrabL10n.text("取消全选", "Deselect All")
                        : CrabL10n.text("全选", "Select All")) {
                        model.setProjectsSelected(
                            group.projects,
                            selected: !model.allProjectsAreSelected(in: group.projects)
                        )
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.crabPurple)
                    .disabled(isMovingProjects || !group.projects.contains(where: \.canClean))
                }
            }
            .padding(14)
            .background(Color.crabLavender.opacity(0.5))

            if isExpanded(group) {
                ForEach(group.projects) { project in
                    projectRow(project)
                    if project.id != group.projects.last?.id {
                        Divider().padding(.leading, 58)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.07))
        }
    }

    private func isExpanded(_ group: ProjectGroup) -> Bool {
        disclosureState.isExpanded(group.appID)
    }

    private func projectGroupSummary(_ group: ProjectGroup) -> String {
        let inactiveCount = group.projects.filter(\.isInactive).count
        let largeCount = group.projects.filter(isLargeProject).count
        if inactiveCount == 0, largeCount == 0 {
            return CrabL10n.format(
                "%d 个关联项目",
                "%d associated projects",
                group.projects.count
            )
        }
        return CrabL10n.format(
            "%d 个关联项目 · %d 个超过 6 个月 · %d 个大项目",
            "%d associated projects · %d over 6 months · %d large",
            group.projects.count,
            inactiveCount,
            largeCount
        )
    }

    private func projectRow(_ project: ProjectInventoryItem) -> some View {
        HStack(spacing: 14) {
            Button {
                model.setProjectSelected(project.id, selected: !isSelected(project))
            } label: {
                Image(systemName: isSelected(project) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected(project) ? Color.crabPurple : Color.secondary)
                    .frame(width: 30)
            }
            .buttonStyle(.plain)
            .disabled(isMovingProjects || !project.canClean)
            .accessibilityLabel(isSelected(project)
                ? CrabL10n.format("取消选择 %@", "Deselect %@", project.path.lastPathComponent)
                : CrabL10n.format("选择 %@", "Select %@", project.path.lastPathComponent))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.path.lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.crabInk)
                    if project.isInactive {
                        projectTag(
                            CrabL10n.text("6 个月未修改", "Unmodified for 6 Months"),
                            color: .orange
                        )
                    }
                    if isLargeProject(project) {
                        projectTag(
                            CrabL10n.text("大项目", "Large Project"),
                            color: .crabPurple
                        )
                    }
                }
                Text(project.path.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(projectMetadata(project))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                if !project.canClean {
                    Text(cleanupBlockMessage(project.cleanupBlockReason))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 18)
            Text((project.canClean ? "" : CrabL10n.text("已统计 ", "Measured "))
                 + ByteCountFormatter.string(fromByteCount: Int64(project.logicalBytes), countStyle: .file))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.crabInk)
            Button("在 Finder 中查看") {
                model.revealProjectInFinder(project)
            }
            .buttonStyle(.bordered)
            .tint(Color.crabPurple)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var projectCleanupBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(CrabL10n.format(
                    "已选择 %d 个项目",
                    "%d projects selected",
                    model.projectCleanupSelection.selectedProjects.count
                ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.crabInk)
                Text(CrabL10n.format(
                    "%@ · 只会移入废纸篓，清空前可恢复",
                    "%@ · moved only to Trash and recoverable until emptied",
                    selectedSizeText
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                activeAlert = .confirmation
            } label: {
                if isMovingProjects {
                    HStack(spacing: 7) {
                        CrabLoadingIndicator(size: 20, motion: .pinch)
                        Text("处理中")
                    }
                    .frame(width: 130)
                } else {
                    Label("移入废纸篓", systemImage: "trash")
                        .frame(width: 130)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.crabPurple)
            .disabled(model.projectCleanupSelection.selectedProjectIDs.isEmpty || isMovingProjects)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func cleanupBlockMessage(_ reason: ProjectCleanupBlockReason?) -> String {
        switch reason {
        case .symbolicLink:
            CrabL10n.text("含符号链接，为避免影响链接目标，不能清理", "Contains symbolic links · cleanup disabled to protect linked files")
        case .protectedDirectory:
            CrabL10n.text("含受保护目录，不能清理", "Contains a protected directory · cleanup disabled")
        case .unsupportedEntry:
            CrabL10n.text("含无法安全处理的特殊文件，不能清理", "Contains unsupported special files · cleanup disabled")
        case .changedDuringInspection:
            CrabL10n.text("扫描期间目录发生变化，请重新扫描", "Directory changed during inspection · scan again")
        case .inspectionLimitReached:
            CrabL10n.text("达到检查上限，仅显示已统计大小，不能清理", "Inspection limit reached · partial size · cleanup disabled")
        case .incompleteInspection, nil:
            CrabL10n.text("部分文件无法读取或已发生变化，不能清理", "Some files could not be read or have changed · cleanup disabled")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 46))
                .foregroundStyle(Color.crabPurple)
            Text(model.projectInventory.hasIncompleteResults
                ? CrabL10n.text("已检查范围内暂未发现项目", "No Projects Found in the Inspected Area")
                : CrabL10n.text("没有发现已关联的项目", "No Associated Projects Found"))
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text(model.projectInventory.hasIncompleteResults
                ? CrabL10n.text("部分目录尚未完成检查，这不表示本机没有关联项目。", "Some directories were not fully inspected. Associated projects may still exist.")
                : CrabL10n.text("Crab 已检查本机用户目录，但没有发现与已安装 AI 应用匹配的明确项目标记。", "No explicit project markers matching installed AI apps were found in the inspected user directories."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新扫描") { model.scanProjects(force: true) }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 48)
    }

    private var partialScanMessage: String {
        if model.projectInventory.discoveryWasLimited {
            return CrabL10n.text(
                "已保留发现的项目；部分目录达到扫描上限，结果可能不完整。只有完成安全检查的项目才能清理。",
                "Discovered projects are retained. A discovery limit was reached, so results may be incomplete. Only fully verified projects can be cleaned.")
        }
        if model.projectInventory.inspectionLimitedProjectCount > 0 {
            return CrabL10n.format(
                "%d 个项目达到内容检查上限，已单独保护；其他完整检查的项目仍可选择清理。",
                "%d projects reached the inspection limit and are protected. Other fully inspected projects can still be selected.",
                model.projectInventory.inspectionLimitedProjectCount)
        }
        return CrabL10n.text(
            "部分内容无法完整检查，相关项目已保护；当前仅显示可确认的结果。",
            "Some content could not be fully inspected. Affected projects are protected; only confirmed results are shown.")
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 46))
                .foregroundStyle(Color.crabPurple)
            Text("无法扫描项目")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            Button("重新扫描") { model.scanProjects(force: true) }
                .buttonStyle(.borderedProminent)
                .tint(Color.crabPurple)
        }
        .padding(.bottom, 48)
    }

    private var groupedProjects: [ProjectGroup] {
        Dictionary(grouping: visibleProjects, by: \.primaryAppID)
            .map { appID, projects in
                ProjectGroup(
                    appID: appID,
                    displayName: ProjectAssociationCatalog.displayName(for: appID),
                    projects: projects
                )
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var visibleProjects: [ProjectInventoryItem] {
        ProjectCleanupPresentation.projects(
            model.projectInventory.projects,
            query: searchText,
            filter: selectedFilter,
            sort: selectedSort
        )
    }

    private var inactiveProjectCount: Int {
        model.projectInventory.projects.filter(\.isInactive).count
    }

    private var largeProjectCount: Int {
        model.projectInventory.projects.filter(isLargeProject).count
    }

    private var allVisibleProjectsAreSelected: Bool {
        model.allProjectsAreSelected(in: visibleProjects)
    }

    private var isMovingProjects: Bool {
        model.projectCleanupState == .moving
    }

    private func isSelected(_ project: ProjectInventoryItem) -> Bool {
        model.projectCleanupSelection.selectedProjectIDs.contains(project.id)
    }

    private var selectedSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(model.projectCleanupSelection.selectedBytes),
            countStyle: .file
        )
    }

    private var confirmationMessage: String {
        let base = CrabL10n.format(
            "将把 %d 个项目（%@）移入废纸篓。Crab 会在执行前再次校验；这不是永久删除。",
            "Move %d projects (%@) to Trash. Crab will revalidate them first; this is not permanent deletion.",
            model.projectCleanupSelection.selectedProjects.count,
            selectedSizeText
        )
        let selectedProjects = model.projectCleanupSelection.selectedProjects
        let preview = selectedProjects.prefix(4).map { project in
            let date = project.latestActivity.formatted(date: .abbreviated, time: .omitted)
            return CrabL10n.format(
                "\n• %@\n  %@\n  最近活动：%@",
                "\n• %@\n  %@\n  Last activity: %@",
                project.path.lastPathComponent,
                project.path.path,
                date
            )
        }.joined()
        let remainder = selectedProjects.count > 4
            ? CrabL10n.format(
                "\n…以及另外 %d 个项目",
                "\n…and %d more projects",
                selectedProjects.count - 4
            )
            : ""
        let recentCount = selectedProjects.filter { !$0.isInactive }.count
        let recentWarning = recentCount > 0 ? CrabL10n.format(
            " 其中 %d 个项目在最近 6 个月内仍有活动，请确认不再需要。",
            " %d selected projects were active within the last 6 months; confirm they are no longer needed.",
            recentCount
        ) : ""
        return base + recentWarning + preview + remainder
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 44))
                .foregroundStyle(Color.crabPurple)
            Text("没有匹配的项目")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Color.crabInk)
            Text("更改搜索词或筛选条件后再试。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("清除筛选") {
                searchText = ""
                selectedFilter = .all
            }
            .buttonStyle(.bordered)
            .tint(Color.crabPurple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isLargeProject(_ project: ProjectInventoryItem) -> Bool {
        ProjectCleanupLabelPolicy.labels(
            isInactive: project.isInactive,
            logicalBytes: project.logicalBytes
        ).contains(.large)
    }

    private func projectTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func projectMetadata(_ project: ProjectInventoryItem) -> String {
        let date = project.latestActivity.formatted(date: .abbreviated, time: .omitted)
        let relatedNames = project.relatedAppIDs
            .filter { $0 != project.primaryAppID }
            .map(ProjectAssociationCatalog.displayName)
        let related = relatedNames.isEmpty
            ? ""
            : CrabL10n.format(
                " · 同时关联 %@",
                " · also associated with %@",
                relatedNames.joined(separator: CrabL10n.text("、", ", "))
            )
        return CrabL10n.format(
            "最近活动：%@ · %llu 个文件%@",
            "Last activity: %@ · %llu files%@",
            date,
            project.fileCount,
            related
        )
    }
}

private extension ProjectCleanupFilter {
    var title: String {
        switch self {
        case .all: CrabL10n.text("全部", "All")
        case .inactive: CrabL10n.text("6 个月未修改", "Unmodified 6 Months")
        case .large: CrabL10n.text("大项目", "Large")
        case .recent: CrabL10n.text("最近使用", "Recently Used")
        }
    }
}

private extension ProjectCleanupSort {
    var title: String {
        switch self {
        case .recentActivity: CrabL10n.text("最近活动", "Recent Activity")
        case .oldestActivity: CrabL10n.text("最久未用", "Oldest Activity")
        case .sizeDescending: CrabL10n.text("大小降序", "Largest First")
        }
    }
}

private enum ProjectCleanupAlert: Identifiable {
    case confirmation
    case result(title: String, message: String)

    var id: String {
        switch self {
        case .confirmation: "confirmation"
        case let .result(title, message): "result-\(title)-\(message)"
        }
    }
}

private struct ProjectGroup: Identifiable {
    let appID: String
    let displayName: String
    let projects: [ProjectInventoryItem]
    var id: String { appID }
}
