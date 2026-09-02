import CrabArchive
import Darwin
import Foundation

public struct HarnessUsageSummary: Equatable, Sendable {
    public let appID: String
    public let projectCount: Int?
    public let conversationCount: Int?
    public let tokenCount: UInt64?

    public init(
        appID: String,
        projectCount: Int?,
        conversationCount: Int?,
        tokenCount: UInt64?
    ) {
        self.appID = appID
        self.projectCount = projectCount
        self.conversationCount = conversationCount
        self.tokenCount = tokenCount
    }

    public var availableMetrics: [HarnessUsageMetric] {
        var metrics: [HarnessUsageMetric] = []
        if let projectCount, projectCount > 0 {
            metrics.append(HarnessUsageMetric(kind: .projects, value: UInt64(projectCount)))
        }
        if let conversationCount, conversationCount > 0 {
            metrics.append(HarnessUsageMetric(kind: .conversations, value: UInt64(conversationCount)))
        }
        if let tokenCount, tokenCount > 0 {
            metrics.append(HarnessUsageMetric(kind: .tokens, value: tokenCount))
        }
        return metrics
    }
}

public struct HarnessUsageMetric: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case projects
        case conversations
        case tokens
    }

    public let kind: Kind
    public let value: UInt64

    public init(kind: Kind, value: UInt64) {
        self.kind = kind
        self.value = value
    }
}

public struct HarnessUsageScanner: Sendable {
    private let maxEntries: Int
    private let maxDepth: Int

    public init(maxEntries: Int = 50_000, maxDepth: Int = 12) {
        self.maxEntries = maxEntries
        self.maxDepth = maxDepth
    }

    public func scan(
        installedAppIDs: Set<String>,
        projectInventory: ProjectInventoryResult?,
        homeURL: URL
    ) -> [String: HarnessUsageSummary] {
        var projectCounts: [String: Int] = [:]
        for project in projectInventory?.projects ?? [] {
            for appID in project.relatedAppIDs where installedAppIDs.contains(appID) {
                projectCounts[appID, default: 0] += 1
            }
        }

        return Dictionary(uniqueKeysWithValues: installedAppIDs.map { appID in
            let conversationCount = conversationCount(for: appID, homeURL: homeURL)
            return (appID, HarnessUsageSummary(
                appID: appID,
                projectCount: projectInventory == nil ? nil : projectCounts[appID, default: 0],
                conversationCount: conversationCount,
                tokenCount: tokenCount(for: appID, homeURL: homeURL)
            ))
        })
    }

    private func tokenCount(for appID: String, homeURL: URL) -> UInt64? {
        guard appID == "com.openai.codex" else { return nil }
        return CodexTokenUsageScanner().scan(homeURL: homeURL)
    }

    private func conversationCount(for appID: String, homeURL: URL) -> Int? {
        switch appID {
        case "com.openai.codex":
            return countRecords(
                roots: [
                    homeURL.appendingPathComponent(".codex/sessions", isDirectory: true),
                    homeURL.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
                ],
                matches: { $0.pathExtension.lowercased() == "jsonl" }
            )
        case "ai.anthropic.claude-code":
            return countRecords(
                roots: [
                    homeURL.appendingPathComponent(".claude/sessions", isDirectory: true),
                    homeURL.appendingPathComponent(".claude/projects", isDirectory: true),
                ],
                matches: { $0.pathExtension.lowercased() == "jsonl" }
            )
        case "ai.deepseek.dsh":
            return countRecords(
                roots: [homeURL.appendingPathComponent(".dsh/sessions", isDirectory: true)],
                matches: { $0.lastPathComponent == "session.jsonl.zstd" }
            )
        default:
            return nil
        }
    }

    private func countRecords(
        roots: [URL],
        matches: (URL) -> Bool
    ) -> Int? {
        guard maxEntries > 0, maxDepth > 0 else { return nil }
        var visited = 0
        var count = 0

        for root in roots {
            var rootMetadata = stat()
            if lstat(root.path, &rootMetadata) != 0 { continue }
            guard rootMetadata.st_mode & S_IFMT == S_IFDIR else { return nil }
            guard walk(
                directory: root,
                depth: 0,
                visited: &visited,
                count: &count,
                matches: matches
            ) else { return nil }
        }
        return count
    }

    private func walk(
        directory: URL,
        depth: Int,
        visited: inout Int,
        count: inout Int,
        matches: (URL) -> Bool
    ) -> Bool {
        guard depth <= maxDepth else { return true }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            return false
        }

        for entry in entries {
            visited += 1
            guard visited <= maxEntries else { return false }
            var metadata = stat()
            guard lstat(entry.path, &metadata) == 0 else { continue }
            switch metadata.st_mode & S_IFMT {
            case S_IFREG:
                if matches(entry) { count += 1 }
            case S_IFDIR:
                guard walk(
                    directory: entry,
                    depth: depth + 1,
                    visited: &visited,
                    count: &count,
                    matches: matches
                ) else { return false }
            default:
                continue
            }
        }
        return true
    }
}

public struct CodexTokenUsageScanner: Sendable {
    private let sqliteExecutableURL: URL
    private let maximumDatabaseBytes: Int64

    public init(
        sqliteExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/sqlite3"),
        maximumDatabaseBytes: Int64 = 512 * 1_024 * 1_024
    ) {
        self.sqliteExecutableURL = sqliteExecutableURL
        self.maximumDatabaseBytes = maximumDatabaseBytes
    }

    public func scan(homeURL: URL) -> UInt64? {
        guard maximumDatabaseBytes > 0 else { return nil }
        let candidates = [
            homeURL.appendingPathComponent(".codex/state_5.sqlite"),
            homeURL.appendingPathComponent(".codex/sqlite/state_5.sqlite"),
        ]
        guard let databaseURL = candidates.first(where: isTrustedDatabase) else { return nil }

        let process = Process()
        process.executableURL = sqliteExecutableURL
        process.arguments = [
            "-readonly",
            "-noheader",
            databaseURL.path,
            "SELECT COALESCE(SUM(tokens_used), 0) FROM threads WHERE tokens_used > 0;",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= 64,
              let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = UInt64(string),
              value > 0
        else { return nil }
        return value
    }

    private func isTrustedDatabase(_ databaseURL: URL) -> Bool {
        var metadata = stat()
        guard lstat(databaseURL.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0,
              metadata.st_size <= maximumDatabaseBytes
        else { return false }
        return true
    }
}
