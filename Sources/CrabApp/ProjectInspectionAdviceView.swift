import AppKit
import CrabArchive
import SwiftUI

enum ProjectInspectionAdvice {
    static func title(_ reason: ProjectCleanupBlockReason?) -> String {
        switch reason {
        case .symbolicLink: CrabL10n.text("项目内链接，目标不随之清理", "Project links · targets are not cleaned")
        case .protectedDirectory: CrabL10n.text("包含受保护目录", "Contains protected directories")
        case .unsupportedEntry: CrabL10n.text("包含特殊文件", "Contains special files")
        case .changedDuringInspection: CrabL10n.text("扫描期间目录有变化", "Directory changed during scanning")
        case .inspectionLimitReached: CrabL10n.text("本次检查范围受限", "Inspection was limited")
        case .incompleteInspection, nil: CrabL10n.text("部分位置未能读取", "Some locations could not be read")
        }
    }

    static func explanation(_ reason: ProjectCleanupBlockReason?) -> String {
        switch reason {
        case .symbolicLink:
            CrabL10n.text("符号链接常见于 node_modules/.bin 等依赖目录。Crab 只记录链接本身，不沿链接读取或清理目标。外部组件不计入本项目的大小，也不会随项目清理。项目目录内实际存在的文件仍属于项目。",
                "Symbolic links are common in dependency folders such as node_modules/.bin. Crab records the link itself without following it to read or clean its target. External components are excluded from project size and cleanup. Actual files inside the project folder remain part of the project.")
        case .protectedDirectory:
            CrabL10n.text("项目包含 Crab 排除的系统、同步盘或媒体目录。整体移动项目会同时移动这些目录，需要单独核对。",
                "The project contains a system, sync or media directory excluded by Crab. Moving the whole project would include this directory, so a separate review is needed.")
        case .unsupportedEntry:
            CrabL10n.text("发现普通文件和目录以外的特殊条目，可能是运行中的工具创建的通信文件。Crab 无法判断它是否仍在使用。",
                "A special entry was found, possibly a communication file created by a running tool. Crab cannot establish whether it is still in use.")
        case .changedDuringInspection:
            CrabL10n.text("目录在检查期间发生变化，统计与待处理内容可能不一致。",
                "The directory changed during inspection, so the totals may no longer describe the content to be moved.")
        case .inspectionLimitReached:
            CrabL10n.text("本次扫描使用了有限检查额度，统计不是完整结果。当前版本的正常扫描会持续到检查结束。",
                "This scan used an explicit inspection budget, so its totals are partial. Normal scans in the current version run until inspection finishes.")
        case .incompleteInspection, nil:
            CrabL10n.text("部分位置无法访问、已被移动，或不在同一磁盘上，未能获取完整文件信息。",
                "Some locations are inaccessible, have moved, or are on another volume. Complete file information could not be obtained.")
        }
    }

    static func suggestion(_ reason: ProjectCleanupBlockReason?) -> String {
        switch reason {
        case .symbolicLink:
            CrabL10n.text("确认整个项目不再需要后，返回列表选择项目，二次确认后即可移入废纸篓；无需先删除依赖链接。Crab 会再次核对链接是否变化。\n\n如果项目仍要使用，请保留项目及其链接；清理前备份唯一成果，先不清空废纸篓，以便恢复。",
                "If you no longer need the entire project, select it in the list and confirm twice to move it to Trash. There is no need to remove dependency links first. Crab rechecks links for changes.\n\nKeep the project and its links if you still use it. Back up unique work before cleanup and leave Trash unemptied so you can restore it.")
        case .protectedDirectory:
            CrabL10n.text("先定位目录并确认用途，保留系统和同步盘内容。若只需整理部分成果，请在 Finder 中逐项核对；不要为解除提示而搬走或删除受保护目录。",
                "Locate the directory and check its purpose. Keep system and synced content. Review individual outputs in Finder if only some are no longer needed; do not move or delete protected directories just to clear this notice.")
        case .unsupportedEntry:
            CrabL10n.text("先保存工作，手动停止正在使用此项目的开发服务或工具，再点击“重新检查”。若条目仍存在，定位后核对用途，不要强制删除。",
                "Save your work, manually stop development services or tools using this project, then choose Recheck. If the entry remains, locate it and identify its purpose instead of forcing deletion.")
        case .changedDuringInspection:
            CrabL10n.text("先保存工作，等待构建、下载或同步结束，再点击“重新检查”。Crab 不会替你关闭应用。",
                "Save your work, wait for builds, downloads or syncing to finish, then choose Recheck. Crab will not close applications for you.")
        case .inspectionLimitReached:
            CrabL10n.text("点击“重新检查”启动完整扫描，等待检查结束；期间可取消并返回首页。",
                "Choose Recheck to start a complete scan and wait for it to finish. You can cancel and return home while it runs.")
        case .incompleteInspection, nil:
            CrabL10n.text("在 Finder 确认位置仍存在，检查“显示简介 → 共享与权限”是否允许当前账户读取；外接磁盘需保持连接。只调整你有权访问的项目目录，然后重新检查，不要递归修改整个个人文件夹的权限。",
                "Check the location in Finder and ensure Get Info → Sharing & Permissions allows your account to read it. Keep external volumes connected. Adjust only project folders you are authorized to access, then recheck; do not recursively change permissions on your entire Home folder.")
        }
    }
}

struct ProjectInspectionAdviceView: View {
    let project: ProjectInventoryItem
    let recheck: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var reasons: [ProjectCleanupBlockReason] {
        ([project.cleanupBlockReason].compactMap { $0 } + project.inspectionIssues.map(\.reason))
            .reduce(into: []) { result, reason in
                if !result.contains(reason) { result.append(reason) }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CrabL10n.text("原因与处理建议", "Details & Suggested Actions"))
                .font(.title2.bold())
                .foregroundStyle(Color.crabInk)
            Text(project.path.lastPathComponent).font(.headline).textSelection(.enabled)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !project.symbolicLinks.isEmpty {
                        Text(ProjectInspectionAdvice.title(.symbolicLink)).font(.headline)
                        Text(ProjectInspectionAdvice.explanation(.symbolicLink)).foregroundStyle(.secondary)
                        Text(ProjectInspectionAdvice.suggestion(.symbolicLink)).foregroundStyle(.secondary)
                        ForEach(Array(project.symbolicLinks.prefix(20)), id: \.path) { link in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(relativePath(link.path)).textSelection(.enabled)
                                Text("→ " + link.destination).foregroundStyle(.secondary).textSelection(.enabled)
                                Button(CrabL10n.text("定位链接", "Locate Link")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([link.path])
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.system(size: 12, design: .monospaced))
                        }
                        Text(CrabL10n.format("显示 %d / %d 个链接。相对路径以链接所在目录为起点；未打开目标内容。",
                            "Showing %d of %d links. Relative paths start at the link's containing folder; target contents were not opened.",
                            min(20, project.symbolicLinks.count), project.symbolicLinks.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(reasons.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ProjectInspectionAdvice.title(reasons[index])).font(.headline)
                            Text(ProjectInspectionAdvice.explanation(reasons[index])).foregroundStyle(.secondary)
                            Text(CrabL10n.text("建议怎么处理", "What to do next")).font(.headline)
                            Text(ProjectInspectionAdvice.suggestion(reasons[index])).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                    }
                    if !project.inspectionIssues.isEmpty {
                        Text(CrabL10n.format("需处理的位置（显示 %d / %d 项）", "Locations needing attention (showing %d of %d)",
                            project.inspectionIssues.count, project.inspectionIssueCount)).font(.headline)
                    }
                    ForEach(project.inspectionIssues) { issue in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(relativePath(issue.path)).textSelection(.enabled)
                            if let target = issue.linkDestination {
                                Text(CrabL10n.text("链接指向：", "Link destination: ") + target)
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                                Text(CrabL10n.text("相对路径以链接所在目录为起点；未打开目标内容。",
                                    "Relative paths start at the link's containing folder; target contents were not opened."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button(CrabL10n.text("在 Finder 中定位", "Locate in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([issue.path])
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if project.inspectionIssueCount > project.inspectionIssues.count {
                        Text(CrabL10n.text("这里只展示部分位置，完整扫描未因此截断。",
                            "Only a sample of locations is shown; the underlying scan was not truncated."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button(CrabL10n.text("在 Finder 中查看项目", "Show Project in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([project.path])
                }
                Button(CrabL10n.text("重新检查", "Recheck")) { recheck() }
                Spacer()
                Button(CrabL10n.text("完成", "Done")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .tint(Color.crabPurple)
        }
        .padding(24)
        .frame(width: 680, height: 600)
    }

    private func relativePath(_ path: URL) -> String {
        let prefix = project.path.path + "/"
        return path.path.hasPrefix(prefix) ? String(path.path.dropFirst(prefix.count)) : path.path
    }
}
