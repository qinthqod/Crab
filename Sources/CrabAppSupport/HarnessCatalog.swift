import Foundation

public struct HarnessCommandLineDefinition: Equatable, Hashable, Sendable {
    public let executableNames: [String]
    public let npmPackageName: String

    public init(executableNames: [String], npmPackageName: String) {
        self.executableNames = executableNames
        self.npmPackageName = npmPackageName
    }
}

public struct HarnessDefinition: Identifiable, Equatable, Hashable, Sendable {
    public let appID: String
    public let displayName: String
    public let bundleNames: [String]
    public let residueSupportDirectoryNames: [String]
    public let commandLine: HarnessCommandLineDefinition?

    public var id: String { appID }

    public init(
        appID: String,
        displayName: String,
        bundleNames: [String],
        residueSupportDirectoryNames: [String] = [],
        commandLine: HarnessCommandLineDefinition? = nil
    ) {
        self.appID = appID
        self.displayName = displayName
        self.bundleNames = bundleNames
        self.residueSupportDirectoryNames = residueSupportDirectoryNames
        self.commandLine = commandLine
    }
}

public enum HarnessCatalog {
    public static let supported: [HarnessDefinition] = [
        HarnessDefinition(appID: "com.openai.codex", displayName: "Codex", bundleNames: ["ChatGPT.app", "Codex.app"], residueSupportDirectoryNames: ["Codex"]),
        HarnessDefinition(appID: "com.openai.chat", displayName: "ChatGPT", bundleNames: ["ChatGPT.app"], residueSupportDirectoryNames: ["ChatGPT"]),
        HarnessDefinition(appID: "com.anthropic.claudefordesktop", displayName: "Claude", bundleNames: ["Claude.app"], residueSupportDirectoryNames: ["Claude"]),
        HarnessDefinition(appID: "com.todesktop.230313mzl4w4u92", displayName: "Cursor", bundleNames: ["Cursor.app"], residueSupportDirectoryNames: ["Cursor"]),
        HarnessDefinition(appID: "com.codeium.windsurf", displayName: "Windsurf", bundleNames: ["Windsurf.app"], residueSupportDirectoryNames: ["Windsurf"]),
        HarnessDefinition(appID: "cn.trae.app", displayName: "TRAE", bundleNames: ["Trae CN.app", "TRAE.app", "Trae.app"], residueSupportDirectoryNames: ["Trae", "TRAE"]),
        HarnessDefinition(appID: "cn.trae.solo.app", displayName: "TRAE SOLO", bundleNames: ["TRAE SOLO CN.app", "TRAE SOLO.app"], residueSupportDirectoryNames: ["TRAE SOLO", "TRAE SOLO CN"]),
        HarnessDefinition(appID: "dev.zed.Zed", displayName: "Zed", bundleNames: ["Zed.app"], residueSupportDirectoryNames: ["Zed"]),
        HarnessDefinition(appID: "com.electron.ollama", displayName: "Ollama", bundleNames: ["Ollama.app"], residueSupportDirectoryNames: ["Ollama"]),
        HarnessDefinition(appID: "com.bot.pc.doubao", displayName: "豆包", bundleNames: ["Doubao.app", "豆包.app"], residueSupportDirectoryNames: ["Doubao"]),
        HarnessDefinition(appID: "com.work.pc.doubao", displayName: "豆包工作版", bundleNames: ["DoubaoWork.app"], residueSupportDirectoryNames: ["DoubaoWork"]),
        HarnessDefinition(
            appID: "ai.anthropic.claude-code",
            displayName: "Claude Code",
            bundleNames: [],
            commandLine: HarnessCommandLineDefinition(
                executableNames: ["claude"],
                npmPackageName: "@anthropic-ai/claude-code"
            )
        ),
        HarnessDefinition(
            appID: "ai.deepseek.dsh",
            displayName: "DeepSeek Harness",
            bundleNames: [],
            commandLine: HarnessCommandLineDefinition(
                executableNames: ["dsh"],
                npmPackageName: "@deepseek-ai/dsh"
            )
        ),
    ]

    public static func definition(for appID: String) -> HarnessDefinition? {
        supported.first { $0.appID == appID }
    }
}
