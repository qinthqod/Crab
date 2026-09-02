import AppKit
import SwiftUI

struct ScanHomeView: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LogoView(size: 124)
                .shadow(color: Color.crabPurple.opacity(0.1), radius: 18, y: 10)

            if CrabL10n.language == .simplifiedChinese {
                Text("断舍离")
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(Color.crabInk)
                    .padding(.top, 28)

                Text("Stable Cleaning")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(Color.crabPurple)
                    .padding(.top, 8)
            } else {
                Text("Stable Cleaning")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(Color.crabInk)
                    .padding(.top, 28)
            }

            Button(action: onScan) {
                Label("开始扫描", systemImage: "magnifyingglass")
            }
            .buttonStyle(CrabPrimaryButtonStyle())
            .frame(width: 320)
            .padding(.top, 32)
        }
        .padding(.bottom, 40)
        .accessibilityElement(children: .contain)
    }
}

struct ScanLoadingView: View {
    var body: some View {
        VStack(spacing: 0) {
            CrabLoadingIndicator(size: 156, motion: .scuttle)

            Text("正在扫描 AI 缓存…")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Color.crabInk)
                .padding(.top, 30)

            Text("正在检查受支持 AI 工具的缓存目录")
                .font(.system(size: 14))
                .foregroundStyle(Color.crabInk.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Text("只读取文件大小与元数据")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
        }
        .padding(.bottom, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在扫描 AI 工具缓存")
    }
}

struct ScanFailureView: View {
    let message: String
    let onHome: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.crabPurple)
                .frame(width: 112, height: 112)
                .background(Color.crabLavender, in: Circle())

            Text("无法完成扫描")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.crabInk)
                .padding(.top, 22)

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 460)
                .padding(.top, 10)

            HStack(spacing: 12) {
                Button("返回首页", action: onHome)
                    .buttonStyle(.bordered)
                    .tint(Color.crabPurple)
                    .controlSize(.large)

                Button("重新扫描", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.crabPurple)
                    .controlSize(.large)
            }
            .padding(.top, 26)
        }
    }
}
