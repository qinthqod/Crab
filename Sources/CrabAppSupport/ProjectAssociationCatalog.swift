import CrabArchive

public struct ProjectGroupDisclosureState: Equatable, Sendable {
    public private(set) var expandedAppIDs: Set<String>

    public init(expandedAppIDs: Set<String> = []) {
        self.expandedAppIDs = expandedAppIDs
    }

    public func isExpanded(_ appID: String) -> Bool {
        expandedAppIDs.contains(appID)
    }

    public mutating func toggle(_ appID: String) {
        if expandedAppIDs.contains(appID) {
            expandedAppIDs.remove(appID)
        } else {
            expandedAppIDs.insert(appID)
        }
    }
}

public enum ProjectAssociationCatalog {
    public static let supported: [ProjectApplicationRule] = [
        ProjectApplicationRule(
            appID: "ai.anthropic.claude-code",
            displayName: "Claude Code",
            markerNames: [".claude", "CLAUDE.md"]
        ),
        ProjectApplicationRule(
            appID: "com.openai.codex",
            displayName: "Codex",
            markerNames: [".codex", "AGENTS.md"]
        ),
        ProjectApplicationRule(
            appID: "com.todesktop.230313mzl4w4u92",
            displayName: "Cursor",
            markerNames: [".cursor", ".cursorrules"]
        ),
        ProjectApplicationRule(
            appID: "com.codeium.windsurf",
            displayName: "Windsurf",
            markerNames: [".windsurf", ".windsurfrules"]
        ),
        ProjectApplicationRule(
            appID: "cn.trae.app",
            displayName: "TRAE",
            markerNames: [".trae"]
        ),
        ProjectApplicationRule(
            appID: "cn.trae.solo.app",
            displayName: "TRAE SOLO",
            markerNames: [".trae-solo"]
        ),
        ProjectApplicationRule(
            appID: "dev.zed.Zed",
            displayName: "Zed",
            markerNames: [".zed"]
        ),
        ProjectApplicationRule(
            appID: "ai.deepseek.dsh",
            displayName: "DeepSeek Harness",
            markerNames: [".dsh", "dsh.json"]
        ),
    ]

    public static func rules(for installedAppIDs: Set<String>) -> [ProjectApplicationRule] {
        supported.filter { installedAppIDs.contains($0.appID) }
    }

    public static func displayName(for appID: String) -> String {
        supported.first { $0.appID == appID }?.displayName
            ?? HarnessCatalog.definition(for: appID)?.displayName
            ?? appID
    }
}
