import AppKit
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section {
            Label(statusLabel, systemImage: statusSymbol)
                .foregroundStyle(.secondary)
        }

        Section {
            Button {
                showMainWindow()
            } label: {
                Label("显示 Crab", systemImage: "macwindow")
            }
            .keyboardShortcut("o", modifiers: .command)

            cacheAction

            Button {
                model.setMode(.harness)
                showMainWindow()
            } label: {
                Label("应用管理…", systemImage: "square.grid.2x2")
            }

            Button {
                model.setMode(.archive)
                showMainWindow()
            } label: {
                Label("项目清理…", systemImage: "folder.badge.clock")
            }
        }

        Section {
            SettingsLink {
                Label("设置…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        Section {
            Button("退出 Crab") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    @ViewBuilder
    private var cacheAction: some View {
        switch model.state {
        case .idle:
            Button {
                model.setMode(.cache)
                model.scanUserCaches()
                showMainWindow()
            } label: {
                Label("扫描 AI 缓存…", systemImage: "magnifyingglass")
            }
        case .loading:
            Button {
                model.setMode(.cache)
                showMainWindow()
            } label: {
                Label("查看扫描进度", systemImage: "hourglass")
            }
        case .ready:
            Button {
                model.setMode(.cache)
                showMainWindow()
            } label: {
                Label("查看可清理项…", systemImage: "checklist")
            }
            Button {
                model.setMode(.cache)
                model.scanUserCaches()
                showMainWindow()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
        case .failed:
            Button {
                model.setMode(.cache)
                model.scanUserCaches()
                showMainWindow()
            } label: {
                Label("重新扫描 AI 缓存…", systemImage: "arrow.clockwise")
            }
        }
    }

    private var statusLabel: String {
        switch model.state {
        case .idle: return CrabL10n.text("Crab 已在菜单栏待命", "Crab is ready in the menu bar")
        case .loading: return CrabL10n.text("正在扫描 AI 缓存", "Scanning AI caches")
        case .ready:
            if model.cacheSpaceSummary.discoveredBytes == 0 {
                return CrabL10n.format(
                    "已检查 %d 个应用，未发现缓存",
                    "Checked %d apps; no cache found",
                    model.scannedHarnessCount
                )
            }
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(model.cacheSpaceSummary.availableNowBytes),
                countStyle: .file
            )
            if model.cacheSpaceSummary.availableNowBytes == 0 {
                return CrabL10n.text(
                    "发现缓存，退出相关应用后可清理",
                    "Cache found; quit related apps to clean"
                )
            }
            return CrabL10n.format("当前可清理 %@", "%@ available to clean now", size)
        case .failed: return CrabL10n.text("上次扫描未完成", "The last scan did not complete")
        }
    }

    private var statusSymbol: String {
        switch model.state {
        case .idle: "checkmark.circle"
        case .loading: "hourglass"
        case .ready: "externaldrive"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")

        DispatchQueue.main.async {
            let mainWindow = NSApplication.shared.windows.first { $0.title == "Crab" }
            mainWindow?.deminiaturize(nil)
            mainWindow?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
