import CrabCore
import CrabArchive
import CrabCLI
import CrabAppSupport
import Darwin
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else {
        throw TestFailure(description: message)
    }
}

private let tests: [(String, () throws -> Void)] = [
    ("Version identifies the 0.1.2 release", {
        try expect(
            CrabCore.version == "0.1.2",
            "Expected release version, got \(CrabCore.version)"
        )
    }),
    ("Application language follows Chinese preference and otherwise uses English", {
        try expect(
            CrabLanguage.resolve(preferredLanguages: ["zh-Hans-CN", "en-US"]) == .simplifiedChinese,
            "Simplified Chinese must follow a Chinese primary language"
        )
        try expect(
            CrabLanguage.resolve(preferredLanguages: ["en-US", "zh-Hans-CN"]) == .english,
            "English must follow an English primary language"
        )
        try expect(
            CrabLanguage.resolve(preferredLanguages: ["ja-JP"]) == .english,
            "Unsupported languages must fall back to English"
        )
        try expect(
            CrabLanguage.resolve(preferredLanguages: []) == .english,
            "A missing preference must fail safely to English"
        )
        try expect(
            CrabLanguage.english.choose(chinese: "扫描结果", english: "Scan Results") == "Scan Results",
            "English copy must be selected deterministically"
        )
        try expect(
            CrabLanguage.simplifiedChinese.choose(chinese: "扫描结果", english: "Scan Results") == "扫描结果",
            "Chinese copy must be selected deterministically"
        )
    }),
    ("Application language preference supports system and explicit overrides", {
        try expect(
            CrabLanguagePreference.system.resolve(preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese,
            "System preference must use the primary macOS language"
        )
        try expect(
            CrabLanguagePreference.english.resolve(preferredLanguages: ["zh-Hans-CN"]) == .english,
            "An English override must ignore the system language"
        )
        try expect(
            CrabLanguagePreference.simplifiedChinese.resolve(preferredLanguages: ["en-US"]) == .simplifiedChinese,
            "A Chinese override must ignore the system language"
        )
        try expect(
            CrabLanguagePreference(storedValue: "invalid") == .system,
            "An invalid stored preference must fail safely to the system language"
        )
    }),
    ("Crab update checker accepts only an exact signed release asset", {
        let releaseData = Data(#"""
        [{
            "tag_name": "v0.3.0",
            "html_url": "https://github.com/qinthqod/Crab/releases/tag/v0.3.0",
            "draft": false,
            "assets": [{
                "name": "Crab-0.3.0-macOS-arm64.zip",
                "state": "uploaded",
                "content_type": "application/zip",
                "size": 3326908,
                "digest": "sha256:647b216f734bc6f9aa5ad11a1b3bcb6e397005c1cfd25904180e6ea4bdbf72c3",
                "browser_download_url": "https://github.com/qinthqod/Crab/releases/download/v0.3.0/Crab-0.3.0-macOS-arm64.zip"
            }]
        }]
        """#.utf8)
        let offer = CrabAppUpdateOffer(
            latestVersion: "v0.3.0",
            releaseURL: URL(string: "https://github.com/qinthqod/Crab/releases/tag/v0.3.0")!,
            assetURL: URL(string: "https://github.com/qinthqod/Crab/releases/download/v0.3.0/Crab-0.3.0-macOS-arm64.zip")!,
            assetName: "Crab-0.3.0-macOS-arm64.zip",
            assetSize: 3_326_908,
            sha256: "647b216f734bc6f9aa5ad11a1b3bcb6e397005c1cfd25904180e6ea4bdbf72c3"
        )
        try expect(
            CrabAppUpdateChecker.evaluate(
                currentVersion: "0.2.0",
                releaseData: releaseData,
                architecture: "arm64"
            ) == .available(offer),
            "A newer release with an exact architecture asset and SHA-256 digest must be offered"
        )
        try expect(
            CrabAppUpdateChecker.evaluate(
                currentVersion: "0.3.0",
                releaseData: releaseData,
                architecture: "arm64"
            ) == .upToDate,
            "The current release must report up to date"
        )
        try expect(
            CrabAppUpdateChecker.evaluate(
                currentVersion: "development",
                releaseData: releaseData,
                architecture: "arm64"
            ) == .unavailable,
            "A non-release build must not offer an update"
        )
    }),
    ("Crab update checker rejects unsafe release assets", {
        let missingDigest = Data(#"""
        [{
            "tag_name": "v0.3.0",
            "html_url": "https://github.com/qinthqod/Crab/releases/tag/v0.3.0",
            "draft": false,
            "assets": [{
                "name": "Crab-0.3.0-macOS-arm64.zip",
                "state": "uploaded",
                "content_type": "application/zip",
                "size": 10,
                "digest": null,
                "browser_download_url": "https://github.com/qinthqod/Crab/releases/download/v0.3.0/Crab-0.3.0-macOS-arm64.zip"
            }]
        }]
        """#.utf8)
        try expect(
            CrabAppUpdateChecker.evaluate(
                currentVersion: "0.2.0",
                releaseData: missingDigest,
                architecture: "arm64"
            ) == .unavailable,
            "A release asset without a SHA-256 digest must fail closed"
        )

        let wrongHost = Data(#"""
        [{
            "tag_name": "v0.3.0",
            "html_url": "https://github.com/qinthqod/Crab/releases/tag/v0.3.0",
            "draft": false,
            "assets": [{
                "name": "Crab-0.3.0-macOS-arm64.zip",
                "state": "uploaded",
                "content_type": "application/zip",
                "size": 10,
                "digest": "sha256:647b216f734bc6f9aa5ad11a1b3bcb6e397005c1cfd25904180e6ea4bdbf72c3",
                "browser_download_url": "https://example.com/Crab-0.3.0-macOS-arm64.zip"
            }]
        }]
        """#.utf8)
        try expect(
            CrabAppUpdateChecker.evaluate(
                currentVersion: "0.2.0",
                releaseData: wrongHost,
                architecture: "arm64"
            ) == .unavailable,
            "An asset outside the official GitHub repository must fail closed"
        )
    }),
    ("Crab update digest verifies SHA-256 without loading an archive contract", {
        try expect(
            CrabUpdateDigest.sha256Hex(of: Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "The updater must use a standard SHA-256 digest"
        )
        try withTemporaryHome { root in
            let archive = root.appendingPathComponent("Crab.zip")
            try Data("abc".utf8).write(to: archive)
            let digest = try CrabUpdateDigest.sha256Hex(ofFileAt: archive)
            try expect(
                digest
                    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "The updater must stream the downloaded archive through SHA-256"
            )
        }
    }),
    ("Crab update package validation checks bundle identity version and signature", {
        try withTemporaryHome { root in
            let app = try makeSignedCrabApplication(in: root, version: "0.2.0")
            try CrabUpdatePackageValidator.validateApplication(
                at: app,
                expectedVersion: "v0.2.0"
            )

            let executable = app.appendingPathComponent("Contents/MacOS/Crab")
            try Data("tampered".utf8).write(to: executable)
            try expectThrows("A modified update application must fail signature validation") {
                try CrabUpdatePackageValidator.validateApplication(
                    at: app,
                    expectedVersion: "v0.2.0"
                )
            }
        }
    }),
    ("Crab update installer atomically replaces only the revalidated application", {
        try withTemporaryHome { root in
            let currentRoot = root.appendingPathComponent("Current", isDirectory: true)
            let stagedRoot = root.appendingPathComponent("Staged", isDirectory: true)
            try FileManager.default.createDirectory(at: currentRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stagedRoot, withIntermediateDirectories: true)
            let current = try makeSignedCrabApplication(in: currentRoot, version: "0.1.0")
            let staged = try makeSignedCrabApplication(in: stagedRoot, version: "0.2.0")
            let plan = try CrabUpdateInstallationPlan.prepare(
                currentAppURL: current,
                stagedAppURL: staged,
                expectedVersion: "v0.2.0"
            )
            let installed = try CrabAppUpdateInstaller.install(plan)
            try expect(installed == current, "The updated app must remain at the original path")
            let installedVersion = try CrabUpdatePackageValidator.applicationVersion(at: current)
            try expect(
                installedVersion == "0.2.0",
                "The replacement app version must be installed"
            )
        }
    }),
    ("Crab update installer refuses a current application changed after preparation", {
        try withTemporaryHome { root in
            let currentRoot = root.appendingPathComponent("Current", isDirectory: true)
            let stagedRoot = root.appendingPathComponent("Staged", isDirectory: true)
            try FileManager.default.createDirectory(at: currentRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stagedRoot, withIntermediateDirectories: true)
            let current = try makeSignedCrabApplication(in: currentRoot, version: "0.1.0")
            let staged = try makeSignedCrabApplication(in: stagedRoot, version: "0.2.0")
            let plan = try CrabUpdateInstallationPlan.prepare(
                currentAppURL: current,
                stagedAppURL: staged,
                expectedVersion: "v0.2.0"
            )
            try Data("changed".utf8).write(
                to: current.appendingPathComponent("Contents/change-marker")
            )
            try expectThrows("A changed current application must not be replaced") {
                _ = try CrabAppUpdateInstaller.install(plan)
            }
            let preservedVersion = try CrabUpdatePackageValidator.applicationVersion(at: current)
            try expect(
                preservedVersion == "0.1.0",
                "The original application must remain after rejected replacement"
            )
        }
    }),
    ("Crab update installer verifies and extracts a downloaded release archive", {
        try withTemporaryHome { root in
            let currentRoot = root.appendingPathComponent("Current", isDirectory: true)
            let payloadRoot = root.appendingPathComponent("Payload", isDirectory: true)
            try FileManager.default.createDirectory(at: currentRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
            let current = try makeSignedCrabApplication(in: currentRoot, version: "0.1.0")
            _ = try makeSignedCrabApplication(in: payloadRoot, version: "0.2.0")
            let architecture = CrabAppUpdateChecker.currentArchitecture
            let assetName = "Crab-0.2.0-macOS-\(architecture).zip"
            let archive = root.appendingPathComponent(assetName)
            try makeZipArchive(from: payloadRoot.appendingPathComponent("Crab.app"), at: archive)
            let size = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as! NSNumber
            let digest = try CrabUpdateDigest.sha256Hex(ofFileAt: archive)
            let offer = CrabAppUpdateOffer(
                latestVersion: "v0.2.0",
                releaseURL: URL(string: "https://github.com/qinthqod/Crab/releases/tag/v0.2.0")!,
                assetURL: URL(string: "https://github.com/qinthqod/Crab/releases/download/v0.2.0/\(assetName)")!,
                assetName: assetName,
                assetSize: size.int64Value,
                sha256: digest
            )
            let plan = try CrabAppUpdateInstaller.prepareDownloadedArchive(
                archive,
                offer: offer,
                currentAppURL: current
            )
            _ = try CrabAppUpdateInstaller.install(plan)
            let installedVersion = try CrabUpdatePackageValidator.applicationVersion(at: current)
            try expect(
                installedVersion == "0.2.0",
                "A verified downloaded archive must install its expected Crab version"
            )

            let wrongDigestOffer = CrabAppUpdateOffer(
                latestVersion: offer.latestVersion,
                releaseURL: offer.releaseURL,
                assetURL: offer.assetURL,
                assetName: offer.assetName,
                assetSize: offer.assetSize,
                sha256: String(repeating: "0", count: 64)
            )
            try expectThrows("A downloaded archive with a mismatched digest must fail closed") {
                _ = try CrabAppUpdateInstaller.prepareDownloadedArchive(
                    archive,
                    offer: wrongDigestOffer,
                    currentAppURL: current
                )
            }

            let unsafeNameOffer = CrabAppUpdateOffer(
                latestVersion: offer.latestVersion,
                releaseURL: offer.releaseURL,
                assetURL: offer.assetURL,
                assetName: "../Crab-0.2.0-macOS-arm64.zip",
                assetSize: offer.assetSize,
                sha256: offer.sha256
            )
            try expectThrows("An update asset name must not escape the staging directory") {
                _ = try CrabAppUpdateInstaller.prepareDownloadedArchive(
                    archive,
                    offer: unsafeNameOffer,
                    currentAppURL: current
                )
            }
        }
    }),
    ("Rule validation accepts an exact relative trash leaf", {
        let rule = try RuleValidator.decode(data: validRuleData())
        try expect(rule.id.rawValue == "dev.crab.fixture.cache.v1", "Unexpected rule id")
        try expect(rule.leaf == "Library/Caches/CrabFixture/Cache", "Unexpected rule leaf")
    }),
    ("Rule validation rejects an unsupported schema", {
        try expectThrows("Expected unsupported schema to fail") {
            _ = try RuleValidator.decode(data: validRuleData(replacing: "\"schema\": 1", with: "\"schema\": 2"))
        }
    }),
    ("Rule validation rejects parent traversal", {
        try expectThrows("Expected traversal to fail") {
            _ = try RuleValidator.decode(data: validRuleData(replacing: "Library/Caches/CrabFixture/Cache", with: "Library/Caches/../Documents"))
        }
    }),
    ("Rule validation rejects an absolute leaf", {
        try expectThrows("Expected absolute path to fail") {
            _ = try RuleValidator.decode(data: validRuleData(replacing: "Library/Caches/CrabFixture/Cache", with: "/Users/example/Documents"))
        }
    }),
    ("Rule validation rejects an empty leaf", {
        try expectThrows("Expected empty leaf to fail") {
            _ = try RuleValidator.decode(data: validRuleData(replacing: "Library/Caches/CrabFixture/Cache", with: ""))
        }
    }),
    ("Rule validation rejects AI session paths even below Caches", {
        try expectThrows("Expected AI session content to fail closed") {
            _ = try RuleValidator.decode(
                data: validRuleData(replacing: "Library/Caches/CrabFixture/Cache", with: "Library/Caches/CrabFixture/sessions")
            )
        }
    }),
    ("Rule validation rejects model stores even below Caches", {
        try expectThrows("Expected local model content to fail closed") {
            _ = try RuleValidator.decode(
                data: validRuleData(replacing: "Library/Caches/CrabFixture/Cache", with: "Library/Caches/CrabFixture/Models")
            )
        }
    }),
    ("Rule validation rejects app data markers even below Caches", {
        for marker in ["Local Storage", "IndexedDB", "credentials", "file-history", "Containers"] {
            try expectThrows("Expected protected marker \(marker) to fail closed") {
                _ = try RuleValidator.decode(
                    data: validRuleData(
                        replacing: "Library/Caches/CrabFixture/Cache",
                        with: "Library/Caches/CrabFixture/\(marker)"
                    )
                )
            }
        }
    }),
    ("Rule validation rejects a non-trash action", {
        try expectThrows("Expected permanent action to fail") {
            _ = try RuleValidator.decode(data: validRuleData(replacing: "\"action\": \"trash\"", with: "\"action\": \"delete\""))
        }
    }),
    ("Rule validation rejects unknown fields", {
        try expectThrows("Expected unknown field to fail") {
            _ = try RuleValidator.decode(data: validRuleData(replacing: "\"schema\": 1", with: "\"schema\": 1, \"unexpected\": true"))
        }
    }),
    ("Safe scanner reports metadata without reading file contents", {
        try withTemporaryHome { home in
            let cache = try makeFixtureCache(in: home)
            let unreadable = cache.appendingPathComponent("unreadable.bin")
            try Data([0, 1, 2, 3, 4]).write(to: unreadable)
            guard chmod(unreadable.path, 0) == 0 else {
                throw TestFailure(description: "Could not make fixture unreadable")
            }
            defer { _ = chmod(unreadable.path, S_IRUSR | S_IWUSR) }

            let candidate = try SafeScanner().scan(rule: fixtureRule(), homeURL: home)
            try expect(candidate.logicalBytes == 5, "Expected five logical bytes")
            try expect(candidate.fileCount == 1, "Expected one file")
            try expect(candidate.safety == .verifiedSafe, "Expected verified-safe candidate")
        }
    }),
    ("Safe scanner rejects a symbolic-link target", {
        try withTemporaryHome { home in
            let caches = home.appendingPathComponent("Library/Caches/CrabFixture", isDirectory: true)
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let outside = home.appendingPathComponent("Outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            guard symlink(outside.path, caches.appendingPathComponent("Cache").path) == 0 else {
                throw TestFailure(description: "Could not create target symlink")
            }

            try expectThrows("Expected target symlink to fail closed") {
                _ = try SafeScanner().scan(rule: fixtureRule(), homeURL: home)
            }
        }
    }),
    ("Safe scanner rejects a symbolic-link ancestor", {
        try withTemporaryHome { home in
            let realLibrary = home.appendingPathComponent("RealLibrary", isDirectory: true)
            let cache = realLibrary.appendingPathComponent("Caches/CrabFixture/Cache", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            guard symlink(realLibrary.path, home.appendingPathComponent("Library").path) == 0 else {
                throw TestFailure(description: "Could not create ancestor symlink")
            }

            try expectThrows("Expected ancestor symlink to fail closed") {
                _ = try SafeScanner().scan(rule: fixtureRule(), homeURL: home)
            }
        }
    }),
    ("Safe scanner ignores a nested symbolic link without following it", {
        try withTemporaryHome { home in
            let cache = try makeFixtureCache(in: home)
            let outside = home.appendingPathComponent("outside.bin")
            try Data(repeating: 1, count: 64).write(to: outside)
            guard symlink(outside.path, cache.appendingPathComponent("framework-link").path) == 0 else {
                throw TestFailure(description: "Could not create nested symlink")
            }
            let candidate = try SafeScanner().scan(rule: fixtureRule(), homeURL: home)
            try expect(candidate.fileCount == 0, "Nested links must not be followed or counted")
            try expect(candidate.logicalBytes == 0, "Linked outside data must not affect size")
        }
    }),
    ("Safe scanner does not double-count hard-linked bytes", {
        try withTemporaryHome { home in
            let cache = try makeFixtureCache(in: home)
            let original = cache.appendingPathComponent("original.bin")
            let duplicate = cache.appendingPathComponent("duplicate.bin")
            try Data([1, 2, 3, 4]).write(to: original)
            guard link(original.path, duplicate.path) == 0 else {
                throw TestFailure(description: "Could not create hard link")
            }

            let candidate = try SafeScanner().scan(rule: fixtureRule(), homeURL: home)
            try expect(candidate.fileCount == 2, "Expected two directory entries")
            try expect(candidate.logicalBytes == 4, "Expected hard-linked bytes to be counted once")
        }
    }),
    ("Plan builder keeps an empty selection empty", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [],
                now: Date(timeIntervalSince1970: 1_000)
            )
            try expect(plan.entries.isEmpty, "Empty selection must not add candidates")
        }
    }),
    ("Plan builder includes only explicitly selected candidates", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id],
                now: Date(timeIntervalSince1970: 1_000)
            )
            try expect(plan.entries.count == 1, "Expected one selected entry")
            try expect(plan.entries[0].relativeLeaf == candidate.rule.leaf, "Plan must store a redacted relative leaf")
            try expect(plan.entries[0].identity == candidate.identity, "Plan must bind file identity")
        }
    }),
    ("Plan builder rejects a selection missing from the scan", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            try expectThrows("Expected an unknown selection to fail") {
                _ = try PlanBuilder().build(
                    candidates: [candidate],
                    selectedRuleIDs: [RuleID(rawValue: "missing.rule")],
                    now: Date(timeIntervalSince1970: 1_000)
                )
            }
        }
    }),
    ("Plan builder creates a fresh id and ten-minute expiry", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let now = Date(timeIntervalSince1970: 1_000)
            let first = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id],
                now: now
            )
            let second = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id],
                now: now
            )
            try expect(first.planID != second.planID, "Each generated plan needs a fresh id")
            try expect(first.expiresAt == now.addingTimeInterval(600), "Expected ten-minute expiry")
        }
    }),
    ("App scan snapshot starts with no selected items", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let snapshot = AppScanSnapshot(candidates: [candidate])
            try expect(snapshot.selectedRuleIDs.isEmpty, "The app must never select scan results by default")
            try expect(snapshot.selectedBytes == 0, "An empty selection must report zero selected bytes")
        }
    }),
    ("Cache space summary separates immediately available and running-app cache", {
        try withTemporaryHome { home in
            let available = try makeScannedCandidate(in: home)
            let blockedRuleData = validRuleData()
                .replacingUTF8("dev.crab.fixture.cache.v1", with: "dev.crab.fixture.cache.running.v1")
                .replacingUTF8("Library/Caches/CrabFixture/Cache", with: "Library/Caches/CrabFixture/Running")
            let blockedRule = try RuleValidator.decode(data: blockedRuleData)
            let blockedCache = home.appendingPathComponent(blockedRule.leaf, isDirectory: true)
            try FileManager.default.createDirectory(at: blockedCache, withIntermediateDirectories: true)
            try Data([4, 5, 6, 7, 8]).write(to: blockedCache.appendingPathComponent("running.bin"))
            let blocked = try SafeScanner().scan(rule: blockedRule, homeURL: home)

            let summary = CacheActionableSpaceSummary(
                candidates: [available, blocked],
                blockedRuleIDs: [blocked.rule.id]
            )

            try expect(
                summary.discoveredBytes == available.logicalBytes + blocked.logicalBytes,
                "Discovered bytes must include every verified cache"
            )
            try expect(
                summary.availableNowBytes == available.logicalBytes,
                "Available-now bytes must exclude running applications"
            )
            try expect(
                summary.blockedByRunningAppsBytes == blocked.logicalBytes,
                "Running application bytes must be reported separately"
            )
        }
    }),
    ("App scan snapshot selects only an explicit item", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            var snapshot = AppScanSnapshot(candidates: [candidate])
            snapshot.setSelected(candidate.rule.id, selected: true)
            try expect(snapshot.selectedRuleIDs == [candidate.rule.id], "Expected the explicit selection")
            try expect(snapshot.selectedBytes == candidate.logicalBytes, "Expected selected byte total")
        }
    }),
    ("App scan snapshot bulk selection affects only requested cache items", {
        try withTemporaryHome { home in
            let first = try makeScannedCandidate(in: home)
            let secondRuleData = validRuleData()
                .replacingUTF8("dev.crab.fixture.cache.v1", with: "dev.crab.fixture.cache.secondary.v1")
                .replacingUTF8("Library/Caches/CrabFixture/Cache", with: "Library/Caches/CrabFixture/Secondary")
            let secondRule = try RuleValidator.decode(data: secondRuleData)
            let secondCache = home.appendingPathComponent(secondRule.leaf, isDirectory: true)
            try FileManager.default.createDirectory(at: secondCache, withIntermediateDirectories: true)
            let second = try SafeScanner().scan(rule: secondRule, homeURL: home)
            var snapshot = AppScanSnapshot(candidates: [first, second])

            snapshot.setSelected([first.rule.id], selected: true)
            try expect(snapshot.selectedRuleIDs == [first.rule.id], "A product selection must not affect another product")

            snapshot.setSelected([first.rule.id], selected: false)
            try expect(snapshot.selectedRuleIDs.isEmpty, "A product deselection should clear only its requested items")
        }
    }),
    ("App scan snapshot bulk selection ignores unknown rule ids", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            var snapshot = AppScanSnapshot(candidates: [candidate])

            snapshot.setSelected([candidate.rule.id, RuleID(rawValue: "missing.rule")], selected: true)
            try expect(snapshot.selectedRuleIDs == [candidate.rule.id], "Select all must stay inside verified scan results")
        }
    }),
    ("App recommended selection includes a verified risk-A cache", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            var snapshot = AppScanSnapshot(candidates: [candidate])
            snapshot.selectRecommended()
            try expect(snapshot.selectedRuleIDs == [candidate.rule.id], "Expected verified risk-A cache to be recommended")
        }
    }),
    ("App scan snapshot groups multiple cache rules under one product", {
        try withTemporaryHome { home in
            let first = try makeScannedCandidate(in: home)
            let secondRuleData = validRuleData()
                .replacingUTF8("dev.crab.fixture.cache.v1", with: "dev.crab.fixture.cache.secondary.v1")
                .replacingUTF8("Library/Caches/CrabFixture/Cache", with: "Library/Caches/CrabFixture/Secondary")
            let secondRule = try RuleValidator.decode(data: secondRuleData)
            let secondCache = home.appendingPathComponent(secondRule.leaf, isDirectory: true)
            try FileManager.default.createDirectory(at: secondCache, withIntermediateDirectories: true)
            try Data([4, 5]).write(to: secondCache.appendingPathComponent("secondary.bin"))
            let second = try SafeScanner().scan(rule: secondRule, homeURL: home)
            let groups = AppScanSnapshot(candidates: [first, second]).productGroups
            try expect(groups.count == 1, "Rules from one product must render as one product group")
            try expect(groups[0].candidates.count == 2, "Both second-level cache items must remain reviewable")
            try expect(groups[0].totalBytes == first.logicalBytes + second.logicalBytes, "Product size must summarize its children")
        }
    }),
    ("App cache scanner skips tools that are not installed", {
        try withTemporaryHome { home in
            let rule = try fixtureRule()
            let result = AppCacheScanner().scan(rules: [rule], homeURL: home)
            try expect(result.candidates.isEmpty, "A missing optional cache must not become a candidate")
            try expect(result.skippedRuleIDs == [rule.id], "Expected the missing rule to be reported as skipped")
        }
    }),
    ("App scan overview keeps supported products with no cache results", {
        try withTemporaryHome { home in
            let populated = try makeScannedCandidate(in: home)
            let cleanRuleData = validRuleData()
                .replacingUTF8("dev.crab.fixture.cache.v1", with: "dev.crab.clean-product.cache.v1")
                .replacingUTF8("crab-fixture", with: "dev.crab.clean-product")
                .replacingUTF8("Library/Caches/CrabFixture/Cache", with: "Library/Caches/CleanProduct/Cache")
            let cleanRule = try RuleValidator.decode(data: cleanRuleData)
            let result = AppScanResult(
                candidates: [populated],
                skippedRuleIDs: [cleanRule.id],
                issues: []
            )

            let overview = AppScanOverview(
                rules: [populated.rule, cleanRule],
                result: result,
                installedAppIDs: [populated.rule.appID, cleanRule.appID]
            )

            try expect(overview.products.count == 2, "Every supported product must remain visible after scanning")
            try expect(overview.productsWithCacheCount == 1, "Expected one product with cache candidates")
            try expect(overview.cleanProductCount == 1, "Expected the empty product to be reported as clean")
            let cleanProduct = overview.products.first { $0.appID == cleanRule.appID }
            try expect(cleanProduct?.status == .clean, "A fully checked product with no cache should be marked clean")
            try expect(cleanProduct?.candidates.isEmpty == true, "A clean product must not invent cache candidates")
        }
    }),
    ("App scan overview never reports a scan issue as clean", {
        let rule = try fixtureRule()
        let result = AppScanResult(
            candidates: [],
            skippedRuleIDs: [],
            issues: [AppScanIssue(ruleID: rule.id, message: "permission denied")]
        )

        let overview = AppScanOverview(
            rules: [rule],
            result: result,
            installedAppIDs: [rule.appID]
        )

        try expect(overview.products.count == 1, "The limited product must remain visible")
        try expect(overview.products[0].status == .limited, "Scan errors must be shown as limited, never clean")
        try expect(overview.limitedProductCount == 1, "Expected one product with limited scan coverage")
    }),
    ("App scan overview keeps installed command-line products without unsafe cache rules", {
        let appID = "ai.anthropic.claude-code"
        let overview = AppScanOverview(
            rules: [],
            result: AppScanResult(candidates: [], skippedRuleIDs: [], issues: []),
            installedAppIDs: [appID]
        )

        try expect(overview.products.map(\.appID) == [appID], "An installed CLI product must remain visible in cache results")
        try expect(overview.products[0].status == .protected, "A CLI product without reviewed cache rules must be marked protected, not clean")
        try expect(overview.protectedProductCount == 1, "Expected one installed product with protected user data")
        try expect(overview.cleanProductCount == 0, "An unscanned CLI data directory must never be reported as clean")
    }),
    ("App scan category filters partition every scanned product", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let products = [
                AppProductScanSummary(
                    appID: "app.cache",
                    candidates: [candidate],
                    configuredRuleCount: 1,
                    skippedRuleCount: 0,
                    issueCount: 0
                ),
                AppProductScanSummary(
                    appID: "app.clean",
                    candidates: [],
                    configuredRuleCount: 1,
                    skippedRuleCount: 1,
                    issueCount: 0
                ),
                AppProductScanSummary(
                    appID: "app.limited",
                    candidates: [],
                    configuredRuleCount: 1,
                    skippedRuleCount: 0,
                    issueCount: 1
                ),
                AppProductScanSummary(
                    appID: "app.protected",
                    candidates: [],
                    configuredRuleCount: 0,
                    skippedRuleCount: 0,
                    issueCount: 0
                ),
            ]

            try expect(AppProductScanFilter.all.products(in: products).count == 4, "All must include every product")
            try expect(AppProductScanFilter.cleanable.products(in: products).map(\.appID) == ["app.cache"], "Cleanable must include cache products")
            try expect(AppProductScanFilter.clean.products(in: products).map(\.appID) == ["app.clean"], "Clean must include verified clean products")
            try expect(
                AppProductScanFilter.protectedData.products(in: products).map(\.appID) == ["app.limited", "app.protected"],
                "Protected must include both limited and no-safe-rule products"
            )
        }
    }),
    ("Harness catalog uses unique bundle identities", {
        let definitions = HarnessCatalog.supported
        try expect(!definitions.isEmpty, "The supported Harness catalog must not be empty")
        try expect(Set(definitions.map(\.appID)).count == definitions.count, "Harness bundle identifiers must be unique")
        try expect(definitions.contains { $0.appID == "com.openai.codex" && $0.displayName == "Codex" }, "Codex must have a stable catalog identity")
        try expect(definitions.contains { $0.appID == "ai.anthropic.claude-code" }, "Claude Code must have a stable catalog identity")
        try expect(
            definitions.contains {
                $0.appID == "ai.deepseek.dsh" && $0.displayName == "DeepSeek Harness"
            },
            "DeepSeek Harness must have a stable, unambiguous catalog identity"
        )
    }),
    ("App scan overview hides Harness products that are not installed", {
        try withTemporaryHome { home in
            let installed = try makeScannedCandidate(in: home)
            let absentRuleData = validRuleData()
                .replacingUTF8("dev.crab.fixture.cache.v1", with: "dev.crab.absent.cache.v1")
                .replacingUTF8("crab-fixture", with: "dev.crab.absent")
                .replacingUTF8("Library/Caches/CrabFixture/Cache", with: "Library/Caches/Absent/Cache")
            let absentRule = try RuleValidator.decode(data: absentRuleData)
            let result = AppScanResult(
                candidates: [installed],
                skippedRuleIDs: [absentRule.id],
                issues: []
            )

            let overview = AppScanOverview(
                rules: [installed.rule, absentRule],
                result: result,
                installedAppIDs: [installed.rule.appID]
            )

            try expect(overview.products.map(\.appID) == [installed.rule.appID], "Uninstalled Harness products must not appear in results")
        }
    }),
    ("Harness inventory reports only installed matching app bundles", {
        try withTemporaryHome { home in
            let applications = home.appendingPathComponent("Applications", isDirectory: true)
            let definition = HarnessDefinition(
                appID: "dev.crab.fixture-harness",
                displayName: "Fixture Harness",
                bundleNames: ["Fixture Harness.app"]
            )
            let absent = HarnessDefinition(
                appID: "dev.crab.absent-harness",
                displayName: "Absent Harness",
                bundleNames: ["Absent Harness.app"]
            )
            let appURL = try makeFixtureApplication(
                in: applications,
                name: "Fixture Harness.app",
                bundleIdentifier: definition.appID,
                version: "3.2.1"
            )
            let lastUsedAt = Date(timeIntervalSince1970: 1_900_000_000)

            let inventory = HarnessInventoryScanner().scan(
                definitions: [definition, absent],
                applicationRoots: [applications],
                lastUsedDateProvider: { url in url == appURL ? lastUsedAt : nil }
            )

            try expect(inventory.installations.count == 1, "Only installed Harness applications should enter inventory")
            try expect(inventory.installedAppIDs == [definition.appID], "Inventory must expose the installed bundle identity")
            let installation = inventory.installations[0]
            try expect(installation.bundleURL == appURL, "Inventory must retain the exact installed app URL")
            try expect(installation.version == "3.2.1", "Inventory must report the application version")
            try expect(installation.installedBytes > 0, "Inventory must report the application bundle size")
            try expect(installation.lastUsedAt == lastUsedAt, "Inventory must report the metadata last-used date")
        }
    }),
    ("Harness inventory can defer recursive size measurement for a fast first result", {
        try withTemporaryHome { home in
            let applications = home.appendingPathComponent("Applications", isDirectory: true)
            let definition = HarnessDefinition(
                appID: "dev.crab.fast-harness",
                displayName: "Fast Harness",
                bundleNames: ["Fast Harness.app"]
            )
            _ = try makeFixtureApplication(
                in: applications,
                name: "Fast Harness.app",
                bundleIdentifier: definition.appID,
                version: "1.0.0"
            )
            let scanner = HarnessInventoryScanner()
            let fastInventory = scanner.scan(
                definitions: [definition],
                applicationRoots: [applications],
                measureInstalledBytes: false,
                lastUsedDateProvider: { _ in nil }
            )

            try expect(
                fastInventory.installations.first?.installedBytes == 0,
                "Fast inventory must not recursively measure an application bundle"
            )
            let lastUsedAt = Date(timeIntervalSince1970: 1_900_000_000)
            let activityEnriched = scanner.measuringLastUsedDates(
                in: fastInventory,
                lastUsedDateProvider: { _ in lastUsedAt }
            )
            try expect(
                activityEnriched.installations.first?.lastUsedAt == lastUsedAt,
                "Deferred enrichment must restore the application activity date"
            )
            let enriched = scanner.measuringInstalledBytes(in: activityEnriched)
            try expect(
                enriched.installations.first?.installedBytes ?? 0 > 0,
                "Deferred enrichment must restore the real installed size"
            )
        }
    }),
    ("Harness inventory detects supported npm command-line applications", {
        try withTemporaryHome { home in
            let binRoot = home.appendingPathComponent("bin", isDirectory: true)
            let packageRoot = home.appendingPathComponent(
                "lib/node_modules/@anthropic-ai/claude-code",
                isDirectory: true
            )
            let executable = packageRoot.appendingPathComponent("bin/claude.exe")
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
            try Data(repeating: 9, count: 4_096).write(to: executable)
            try Data(#"{"name":"@anthropic-ai/claude-code","version":"2.1.221"}"#.utf8)
                .write(to: packageRoot.appendingPathComponent("package.json"))
            guard symlink(executable.path, binRoot.appendingPathComponent("claude").path) == 0 else {
                throw TestFailure(description: "Could not create command-line fixture symlink")
            }

            let definition = HarnessDefinition(
                appID: "ai.anthropic.claude-code",
                displayName: "Claude Code",
                bundleNames: [],
                commandLine: HarnessCommandLineDefinition(
                    executableNames: ["claude"],
                    npmPackageName: "@anthropic-ai/claude-code"
                )
            )
            let inventory = HarnessInventoryScanner().scan(
                definitions: [definition],
                applicationRoots: [],
                executableRoots: [binRoot],
                lastUsedDateProvider: { _ in nil }
            )

            try expect(inventory.installations.count == 1, "The installed CLI application must enter inventory")
            let installation = inventory.installations[0]
            try expect(installation.kind == .commandLineTool, "Inventory must distinguish CLI tools from app bundles")
            try expect(installation.bundleURL == packageRoot.standardizedFileURL, "Inventory must retain the npm package root")
            try expect(installation.executableURL == executable.standardizedFileURL, "Inventory must retain the resolved executable")
            try expect(installation.version == "2.1.221", "Inventory must report the npm package version")
            try expect(
                installation.versionDisplayText == "CLI v2.1.221",
                "Command-line package versions must be labelled as CLI versions"
            )
            try expect(installation.installedBytes > 0, "Inventory must report the package size")
        }
    }),
    ("Harness inventory sorts installed applications by most recent use", {
        try withTemporaryHome { home in
            let applications = home.appendingPathComponent("Applications", isDirectory: true)
            let older = HarnessDefinition(
                appID: "dev.crab.older-harness",
                displayName: "Older Harness",
                bundleNames: ["Older Harness.app"]
            )
            let recent = HarnessDefinition(
                appID: "dev.crab.recent-harness",
                displayName: "Recent Harness",
                bundleNames: ["Recent Harness.app"]
            )
            let unknown = HarnessDefinition(
                appID: "dev.crab.unknown-harness",
                displayName: "Unknown Harness",
                bundleNames: ["Unknown Harness.app"]
            )
            let olderURL = try makeFixtureApplication(
                in: applications,
                name: "Older Harness.app",
                bundleIdentifier: older.appID,
                version: "1.0.0"
            )
            let recentURL = try makeFixtureApplication(
                in: applications,
                name: "Recent Harness.app",
                bundleIdentifier: recent.appID,
                version: "1.0.0"
            )
            _ = try makeFixtureApplication(
                in: applications,
                name: "Unknown Harness.app",
                bundleIdentifier: unknown.appID,
                version: "1.0.0"
            )
            let olderDate = Date(timeIntervalSince1970: 1_800_000_000)
            let recentDate = Date(timeIntervalSince1970: 1_900_000_000)

            let inventory = HarnessInventoryScanner().scan(
                definitions: [older, unknown, recent],
                applicationRoots: [applications],
                lastUsedDateProvider: { url in
                    if url == recentURL { return recentDate }
                    if url == olderURL { return olderDate }
                    return nil
                }
            )

            try expect(
                inventory.installations.map(\.appID) == [recent.appID, older.appID, unknown.appID],
                "Recently used applications must appear first and missing usage dates must appear last"
            )
        }
    }),
    ("Harness inventory keeps running applications ahead of recent inactive applications", {
        try withTemporaryHome { home in
            let applications = home.appendingPathComponent("Applications", isDirectory: true)
            let recent = HarnessDefinition(
                appID: "dev.crab.recent-inactive",
                displayName: "Recent Inactive",
                bundleNames: ["Recent Inactive.app"]
            )
            let olderRunning = HarnessDefinition(
                appID: "dev.crab.older-running",
                displayName: "Older Running",
                bundleNames: ["Older Running.app"]
            )
            let recentURL = try makeFixtureApplication(
                in: applications,
                name: "Recent Inactive.app",
                bundleIdentifier: recent.appID,
                version: "1.0.0"
            )
            let olderURL = try makeFixtureApplication(
                in: applications,
                name: "Older Running.app",
                bundleIdentifier: olderRunning.appID,
                version: "1.0.0"
            )
            let inventory = HarnessInventoryScanner().scan(
                definitions: [recent, olderRunning],
                applicationRoots: [applications],
                lastUsedDateProvider: { url in
                    url == recentURL
                        ? Date(timeIntervalSince1970: 1_900_000_000)
                        : url == olderURL
                            ? Date(timeIntervalSince1970: 1_800_000_000)
                            : nil
                }
            )

            try expect(
                inventory.orderedInstallations(runningAppIDs: [olderRunning.appID]).map(\.appID)
                    == [olderRunning.appID, recent.appID],
                "A running application must sort before a more recently used inactive application"
            )
            try expect(
                inventory.orderedInstallations(runningAppIDs: [recent.appID, olderRunning.appID]).map(\.appID)
                    == [recent.appID, olderRunning.appID],
                "Running applications must retain their recent-use ordering"
            )
        }
    }),
    ("Harness inventory refresh is single-flight unless explicitly forced", {
        try expect(
            HarnessInventoryLoadState.idle.permitsRefresh(force: false),
            "An idle inventory must admit its first refresh"
        )
        try expect(
            !HarnessInventoryLoadState.loading.permitsRefresh(force: false),
            "A loading inventory must reject a duplicate refresh"
        )
        try expect(
            !HarnessInventoryLoadState.ready.permitsRefresh(force: false),
            "A ready inventory must not refresh again on repeated navigation"
        )
        try expect(
            HarnessInventoryLoadState.loading.permitsRefresh(force: true),
            "An explicit retry must be able to replace in-flight work"
        )
    }),
    ("Harness usage counts Codex conversations without following links", {
        try withTemporaryHome { home in
            let sessions = home.appendingPathComponent(".codex/sessions/2026/09", isDirectory: true)
            let archived = home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
            try Data("private conversation".utf8).write(to: sessions.appendingPathComponent("one.jsonl"))
            try Data("another private conversation".utf8).write(to: archived.appendingPathComponent("two.jsonl"))
            let outside = home.appendingPathComponent("outside.jsonl")
            try Data("must not count".utf8).write(to: outside)
            guard symlink(outside.path, sessions.appendingPathComponent("linked.jsonl").path) == 0 else {
                throw TestFailure(description: "Could not create session symlink fixture")
            }

            let summaries = HarnessUsageScanner().scan(
                installedAppIDs: ["com.openai.codex"],
                projectInventory: ProjectInventoryResult(),
                homeURL: home
            )
            let usage = summaries["com.openai.codex"]
            try expect(usage?.conversationCount == 2, "Only regular Codex session records should count")
            try expect(usage?.projectCount == 0, "An empty inventory should report zero projects")
            try expect(usage?.tokenCount == nil, "Token usage must remain unavailable without a trusted aggregate")
        }
    }),
    ("Harness usage reads the Codex metadata database without scanning transcripts", {
        try withTemporaryHome { home in
            try makeCodexStateDatabase(in: home, tokenCounts: [125, 75])
            let sessions = home.appendingPathComponent(".codex/sessions/2026/09", isDirectory: true)
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let transcript = sessions.appendingPathComponent("one.jsonl")
            try Data(#"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":999}}}}"#.utf8)
                .write(to: transcript)

            let summaries = HarnessUsageScanner().scan(
                installedAppIDs: ["com.openai.codex"],
                projectInventory: ProjectInventoryResult(),
                homeURL: home
            )

            try expect(
                summaries["com.openai.codex"]?.tokenCount == 200,
                "Codex Token usage must come from the indexed metadata database, never transcript contents"
            )
        }
    }),
    ("Harness usage hides Codex Tokens when no trusted metadata database exists", {
        try withTemporaryHome { home in
            let summaries = HarnessUsageScanner().scan(
                installedAppIDs: ["com.openai.codex"],
                projectInventory: nil,
                homeURL: home
            )

            try expect(
                summaries["com.openai.codex"]?.tokenCount == nil,
                "Crab must hide Token usage when Codex has no trusted aggregate"
            )
        }
    }),
    ("Harness usage presentation omits unavailable metrics instead of placeholders", {
        let usage = HarnessUsageSummary(
            appID: "fixture",
            projectCount: 4,
            conversationCount: nil,
            tokenCount: nil
        )

        try expect(
            usage.availableMetrics.map(\.kind) == [.projects],
            "Unavailable conversation and Token metrics must not reserve visible UI slots"
        )
    }),
    ("Harness usage presentation omits zero-value fields", {
        let usage = HarnessUsageSummary(
            appID: "fixture",
            projectCount: 0,
            conversationCount: 0,
            tokenCount: 0
        )

        try expect(
            usage.availableMetrics.isEmpty,
            "Zero projects, conversations, and Tokens must collapse the entire usage field"
        )
    }),
    ("Harness usage counts only exact DeepSeek session records", {
        try withTemporaryHome { home in
            let session = home.appendingPathComponent(".dsh/sessions/project-a/session-a", isDirectory: true)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
            try Data([1]).write(to: session.appendingPathComponent("session.jsonl.zstd"))
            try Data([2]).write(to: session.appendingPathComponent("other.jsonl.zstd"))

            let summaries = HarnessUsageScanner().scan(
                installedAppIDs: ["ai.deepseek.dsh"],
                projectInventory: ProjectInventoryResult(),
                homeURL: home
            )
            try expect(
                summaries["ai.deepseek.dsh"]?.conversationCount == 1,
                "DeepSeek usage must count only the documented session record name"
            )
        }
    }),
    ("Harness usage attributes projects to every related application", {
        try withTemporaryHome { home in
            let root = home.appendingPathComponent("Work", isDirectory: true)
            let project = root.appendingPathComponent("Shared", isDirectory: true)
            try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: project.appendingPathComponent(".claude"), withIntermediateDirectories: true)
            try Data(#"{"name":"fixture"}"#.utf8).write(to: project.appendingPathComponent("package.json"))
            let installed: Set<String> = ["com.openai.codex", "ai.anthropic.claude-code"]
            let inventory = try ProjectInventoryScanner(maxEntries: 1_000).scan(
                rootURLs: [root],
                rules: ProjectAssociationCatalog.rules(for: installed),
                installedAppIDs: installed
            )
            let summaries = HarnessUsageScanner().scan(
                installedAppIDs: installed,
                projectInventory: inventory,
                homeURL: home
            )
            try expect(summaries["com.openai.codex"]?.projectCount == 1, "Codex should receive the shared project")
            try expect(summaries["ai.anthropic.claude-code"]?.projectCount == 1, "Claude Code should receive the shared project")
        }
    }),
    ("Harness update comparison detects a newer semantic version", {
        let result = HarnessUpdateChecker.evaluate(
            installedVersion: "2.1.221",
            latestVersion: "2.2.0",
            updateURL: URL(string: "https://www.npmjs.com/package/example")!
        )
        try expect(
            result == .available(latestVersion: "2.2.0", updateURL: URL(string: "https://www.npmjs.com/package/example")!),
            "A larger semantic version must be reported as available"
        )
    }),
    ("Harness update comparison understands prerelease versions", {
        let updateURL = URL(string: "https://www.npmjs.com/package/example")!
        try expect(
            HarnessUpdateChecker.evaluate(
                installedVersion: "1.0.0-alpha.4",
                latestVersion: "1.0.0-alpha.5",
                updateURL: updateURL
            ) == .available(latestVersion: "1.0.0-alpha.5", updateURL: updateURL),
            "A later prerelease must be reported as available"
        )
        try expect(
            HarnessUpdateChecker.evaluate(
                installedVersion: "1.0.0",
                latestVersion: "1.0.0-beta.1",
                updateURL: updateURL
            ) == .upToDate,
            "A stable release must sort after its prerelease"
        )
    }),
    ("Harness update metadata rejects malformed versions", {
        let updateURL = URL(string: "https://www.npmjs.com/package/example")!
        try expect(
            HarnessUpdateChecker.evaluate(
                installedVersion: "not-a-version",
                latestVersion: "2.0.0",
                updateURL: updateURL
            ) == .unavailable,
            "Untrusted malformed version input must fail closed"
        )
    }),
    ("Harness update planner creates an exact in-Crab npm update command", {
        try withTemporaryHome { home in
            let prefix = home.appendingPathComponent("npm-prefix", isDirectory: true)
            let binRoot = prefix.appendingPathComponent("bin", isDirectory: true)
            let packageRoot = prefix.appendingPathComponent(
                "lib/node_modules/@anthropic-ai/claude-code",
                isDirectory: true
            )
            let packageExecutable = packageRoot.appendingPathComponent("bin/claude.js")
            let npmExecutable = binRoot.appendingPathComponent("npm")
            try FileManager.default.createDirectory(
                at: packageExecutable.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
            try Data().write(to: packageExecutable)
            try Data().write(to: npmExecutable)
            try Data(#"{"name":"@anthropic-ai/claude-code","version":"2.1.221"}"#.utf8)
                .write(to: packageRoot.appendingPathComponent("package.json"))
            guard chmod(npmExecutable.path, S_IRUSR | S_IWUSR | S_IXUSR) == 0,
                  symlink(packageExecutable.path, binRoot.appendingPathComponent("claude").path) == 0
            else { throw TestFailure(description: "Could not prepare npm update fixture") }

            let definition = HarnessDefinition(
                appID: "ai.anthropic.claude-code",
                displayName: "Claude Code",
                bundleNames: [],
                commandLine: HarnessCommandLineDefinition(
                    executableNames: ["claude"],
                    npmPackageName: "@anthropic-ai/claude-code"
                )
            )
            let installation = HarnessInventoryScanner().scan(
                definitions: [definition],
                applicationRoots: [],
                executableRoots: [binRoot],
                lastUsedDateProvider: { _ in nil }
            ).installations[0]

            let plan = try HarnessUpdatePlanner().build(
                installation: installation,
                latestVersion: "2.2.0",
                npmExecutableURLs: [npmExecutable]
            )

            try expect(plan.executableURL == npmExecutable.standardizedFileURL, "The exact npm executable must be pinned")
            try expect(
                plan.arguments == [
                    "install", "--global", "--prefix", prefix.standardizedFileURL.path,
                    "--no-audit", "--no-fund", "@anthropic-ai/claude-code@2.2.0",
                ],
                "The update must pin the official package, version, and original installation prefix"
            )
            try expect(!plan.arguments.contains("sh") && !plan.arguments.contains("open"), "The plan must not invoke a shell or open another app")
        }
    }),
    ("Harness uninstall moves only the revalidated app bundle", {
        try withTemporaryHome { home in
            let applications = home.appendingPathComponent("Applications", isDirectory: true)
            let definition = HarnessDefinition(
                appID: "dev.crab.fixture-harness",
                displayName: "Fixture Harness",
                bundleNames: ["Fixture Harness.app"]
            )
            let appURL = try makeFixtureApplication(
                in: applications,
                name: "Fixture Harness.app",
                bundleIdentifier: definition.appID,
                version: "1.0"
            )
            let userData = home.appendingPathComponent("Library/Application Support/Fixture Harness/profile.json")
            try FileManager.default.createDirectory(at: userData.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: userData)
            let installation = HarnessInventoryScanner().scan(
                definitions: [definition],
                applicationRoots: [applications],
                lastUsedDateProvider: { _ in nil }
            ).installations[0]
            let mover = RecordingTrashMover()
            let checker = RecordingApplicationChecker(responses: [false])

            let receipt = try HarnessUninstaller(
                trashMover: mover,
                applicationChecker: checker
            ).uninstall(installation: installation, allowedApplicationRoots: [applications])

            try expect(receipt.bundleURL == appURL, "The receipt must identify only the application bundle")
            try expect(mover.urls == [appURL], "Only the .app bundle may cross the Trash boundary")
            try expect(FileManager.default.fileExists(atPath: userData.path), "Uninstall must preserve all associated user data")
        }
    }),
    ("Harness uninstall refuses a running application", {
        try withTemporaryHome { home in
            let applications = home.appendingPathComponent("Applications", isDirectory: true)
            let definition = HarnessDefinition(
                appID: "dev.crab.running-harness",
                displayName: "Running Harness",
                bundleNames: ["Running Harness.app"]
            )
            _ = try makeFixtureApplication(
                in: applications,
                name: "Running Harness.app",
                bundleIdentifier: definition.appID,
                version: "1.0"
            )
            let installation = HarnessInventoryScanner().scan(
                definitions: [definition],
                applicationRoots: [applications],
                lastUsedDateProvider: { _ in nil }
            ).installations[0]
            let mover = RecordingTrashMover()
            let checker = RecordingApplicationChecker(responses: [true])

            try expectThrows("A running Harness must not be uninstalled") {
                _ = try HarnessUninstaller(
                    trashMover: mover,
                    applicationChecker: checker
                ).uninstall(installation: installation, allowedApplicationRoots: [applications])
            }
            try expect(mover.urls.isEmpty, "A rejected uninstall must not call Trash")
        }
    }),
    ("Harness uninstall refuses an application outside approved roots", {
        try withTemporaryHome { home in
            let actualRoot = home.appendingPathComponent("Actual Applications", isDirectory: true)
            let allowedRoot = home.appendingPathComponent("Allowed Applications", isDirectory: true)
            try FileManager.default.createDirectory(at: allowedRoot, withIntermediateDirectories: true)
            let definition = HarnessDefinition(
                appID: "dev.crab.outside-harness",
                displayName: "Outside Harness",
                bundleNames: ["Outside Harness.app"]
            )
            _ = try makeFixtureApplication(
                in: actualRoot,
                name: "Outside Harness.app",
                bundleIdentifier: definition.appID,
                version: "1.0"
            )
            let installation = HarnessInventoryScanner().scan(
                definitions: [definition],
                applicationRoots: [actualRoot],
                lastUsedDateProvider: { _ in nil }
            ).installations[0]
            let mover = RecordingTrashMover()

            try expectThrows("An app outside approved roots must not be uninstalled") {
                _ = try HarnessUninstaller(
                    trashMover: mover,
                    applicationChecker: RecordingApplicationChecker(responses: [false])
                ).uninstall(installation: installation, allowedApplicationRoots: [allowedRoot])
            }
            try expect(mover.urls.isEmpty, "Out-of-bound apps must never reach Trash")
        }
    }),
    ("Harness uninstall refuses an app bundle changed after inventory", {
        try withTemporaryHome { home in
            let applications = home.appendingPathComponent("Applications", isDirectory: true)
            let definition = HarnessDefinition(
                appID: "dev.crab.changed-harness",
                displayName: "Changed Harness",
                bundleNames: ["Changed Harness.app"]
            )
            let appURL = try makeFixtureApplication(
                in: applications,
                name: "Changed Harness.app",
                bundleIdentifier: definition.appID,
                version: "1.0"
            )
            let installation = HarnessInventoryScanner().scan(
                definitions: [definition],
                applicationRoots: [applications],
                lastUsedDateProvider: { _ in nil }
            ).installations[0]
            try Data("changed".utf8).write(to: appURL.appendingPathComponent("changed-after-scan"))
            let mover = RecordingTrashMover()

            try expectThrows("A changed app bundle must be rescanned before uninstall") {
                _ = try HarnessUninstaller(
                    trashMover: mover,
                    applicationChecker: RecordingApplicationChecker(responses: [false])
                ).uninstall(installation: installation, allowedApplicationRoots: [applications])
            }
            try expect(mover.urls.isEmpty, "Changed app bundles must never reach Trash")
        }
    }),
    ("Harness residue catalog keeps user data review-only", {
        let definition = HarnessDefinition(
            appID: "dev.crab.fixture-harness",
            displayName: "Fixture Harness",
            bundleNames: ["Fixture Harness.app"],
            residueSupportDirectoryNames: ["Fixture Harness"]
        )
        let cacheRule = try fixtureResidueCacheRule(appID: definition.appID)
        let rules = HarnessResidueCatalog.rules(for: definition, cacheRules: [cacheRule])

        try expect(!rules.isEmpty, "Expected exact residual leaves for an app bundle")
        try expect(Set(rules.map(\.id)).count == rules.count, "Residual rule ids must be unique")
        try expect(rules.allSatisfy { !$0.relativePath.hasPrefix("/") }, "Residual leaves must stay relative to home")
        let userData = rules.filter { [.applicationData, .preferences, .webData].contains($0.category) }
        try expect(!userData.isEmpty, "Expected review-only user-data categories")
        try expect(userData.allSatisfy { $0.risk == .reviewRequired }, "User data must never be recommended")
        try expect(
            rules.filter { $0.risk == .recommended }.allSatisfy { [.cache, .logs, .savedState].contains($0.category) },
            "Only regenerable residue may be recommended"
        )
    }),
    ("Harness residue scanner measures exact files and directories", {
        try withTemporaryHome { home in
            let cache = home.appendingPathComponent("Library/Caches/dev.crab.fixture-harness", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: cache.appendingPathComponent("cache.bin"))
            let preference = home.appendingPathComponent("Library/Preferences/dev.crab.fixture-harness.plist")
            try FileManager.default.createDirectory(at: preference.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([4, 5]).write(to: preference)

            let rules = [
                fixtureResidueRule(id: "cache", category: .cache, risk: .recommended, path: "Library/Caches/dev.crab.fixture-harness"),
                fixtureResidueRule(id: "preferences", category: .preferences, risk: .reviewRequired, path: "Library/Preferences/dev.crab.fixture-harness.plist"),
            ]
            let result = HarnessResidueScanner().scan(rules: rules, homeURL: home)

            try expect(result.issues.isEmpty, "Exact fixture residue should scan without issues")
            try expect(result.candidates.count == 2, "Expected a directory and regular-file candidate")
            try expect(result.candidates.reduce(0) { $0 + $1.logicalBytes } == 5, "Expected metadata byte totals")
            try expect(result.candidates.reduce(0) { $0 + $1.fileCount } == 2, "Expected two files")
        }
    }),
    ("Harness residue scanner rejects linked path chains", {
        try withTemporaryHome { home in
            let outside = home.appendingPathComponent("Outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data([1]).write(to: outside.appendingPathComponent("data.bin"))
            let library = home.appendingPathComponent("Library", isDirectory: true)
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            guard symlink(outside.path, library.appendingPathComponent("Caches").path) == 0 else {
                throw TestFailure(description: "Could not create residue ancestor symlink")
            }

            let rule = fixtureResidueRule(
                id: "linked",
                category: .cache,
                risk: .recommended,
                path: "Library/Caches/dev.crab.fixture-harness"
            )
            let result = HarnessResidueScanner().scan(rules: [rule], homeURL: home)
            try expect(result.candidates.isEmpty, "A linked path chain must never become eligible")
            try expect(result.issues.count == 1, "A linked path chain must surface a scan issue")
        }
    }),
    ("Harness residue review starts empty and only selects recommended on request", {
        try withTemporaryHome { home in
            let cache = home.appendingPathComponent("Library/Caches/dev.crab.fixture-harness", isDirectory: true)
            let support = home.appendingPathComponent("Library/Application Support/Fixture Harness", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let rules = [
                fixtureResidueRule(id: "cache", category: .cache, risk: .recommended, path: "Library/Caches/dev.crab.fixture-harness"),
                fixtureResidueRule(id: "support", category: .applicationData, risk: .reviewRequired, path: "Library/Application Support/Fixture Harness"),
            ]
            let candidates = HarnessResidueScanner().scan(rules: rules, homeURL: home).candidates
            var snapshot = HarnessResidueSnapshot(candidates: candidates)

            try expect(snapshot.selectedRuleIDs.isEmpty, "Residual results must never be selected by default")
            snapshot.selectRecommended()
            try expect(snapshot.selectedRuleIDs == [HarnessResidueID(rawValue: "cache")], "Explicit recommendation must exclude user data")
        }
    }),
    ("Harness residue cleanup moves only selected revalidated leaves", {
        try withTemporaryHome { home in
            let cache = home.appendingPathComponent("Library/Caches/dev.crab.fixture-harness", isDirectory: true)
            let support = home.appendingPathComponent("Library/Application Support/Fixture Harness", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: cache.appendingPathComponent("cache.bin"))
            try Data([4, 5]).write(to: support.appendingPathComponent("profile.bin"))
            let rules = [
                fixtureResidueRule(id: "cache", category: .cache, risk: .recommended, path: "Library/Caches/dev.crab.fixture-harness"),
                fixtureResidueRule(id: "support", category: .applicationData, risk: .reviewRequired, path: "Library/Application Support/Fixture Harness"),
            ]
            let candidates = HarnessResidueScanner().scan(rules: rules, homeURL: home).candidates
            let now = Date(timeIntervalSince1970: 2_000)
            let plan = try HarnessResiduePlanBuilder().build(
                candidates: candidates,
                selectedRuleIDs: [HarnessResidueID(rawValue: "cache")],
                now: now
            )
            let mover = RecordingTrashMover()
            let receipt = try HarnessResidueCleanupExecutor(
                trashMover: mover,
                applicationChecker: RecordingApplicationChecker(responses: [false, false])
            ).execute(plan: plan, rules: rules, homeURL: home, now: now)

            try expect(mover.urls == [cache.standardizedFileURL], "Only the explicitly selected residue may cross Trash")
            try expect(receipt.moved.count == 1, "Expected one moved residual leaf")
            try expect(!mover.urls.contains(support.standardizedFileURL), "Unselected Application Support must remain untouched")
        }
    }),
    ("Harness residue cleanup refuses changed evidence before moving anything", {
        try withTemporaryHome { home in
            let cache = home.appendingPathComponent("Library/Caches/dev.crab.fixture-harness", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let rule = fixtureResidueRule(id: "cache", category: .cache, risk: .recommended, path: "Library/Caches/dev.crab.fixture-harness")
            let candidate = HarnessResidueScanner().scan(rules: [rule], homeURL: home).candidates[0]
            let now = Date(timeIntervalSince1970: 2_000)
            let plan = try HarnessResiduePlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [rule.id],
                now: now
            )
            try FileManager.default.removeItem(at: cache)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let mover = RecordingTrashMover()

            try expectThrows("Changed residue evidence must fail closed") {
                _ = try HarnessResidueCleanupExecutor(
                    trashMover: mover,
                    applicationChecker: RecordingApplicationChecker(responses: [false])
                ).execute(plan: plan, rules: [rule], homeURL: home, now: now)
            }
            try expect(mover.urls.isEmpty, "No residue may move after identity replacement")
        }
    }),
    ("Cleanup executor moves a revalidated cache through the trash boundary", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id]
            )
            let mover = RecordingTrashMover()
            let checker = RecordingApplicationChecker(responses: [false, false])
            let receipt = try CleanupExecutor(
                trashMover: mover,
                applicationChecker: checker
            ).execute(
                plan: plan,
                rules: [candidate.rule],
                homeURL: home
            )
            try expect(receipt.moved.count == 1, "Expected one moved cache")
            try expect(mover.urls == [candidate.path], "Executor must pass only the revalidated rule target")
        }
    }),
    ("Cleanup executor rejects a cache directory replaced after review", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id]
            )
            try FileManager.default.removeItem(at: candidate.path)
            try FileManager.default.createDirectory(at: candidate.path, withIntermediateDirectories: true)
            let mover = RecordingTrashMover()
            let checker = RecordingApplicationChecker(responses: [false])
            try expectThrows("A replaced target must fail closed") {
                _ = try CleanupExecutor(
                    trashMover: mover,
                    applicationChecker: checker
                ).execute(
                    plan: plan,
                    rules: [candidate.rule],
                    homeURL: home
                )
            }
            try expect(mover.urls.isEmpty, "Nothing may move after failed revalidation")
        }
    }),
    ("Cleanup executor refuses a cache while its owning app is running", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id]
            )
            let mover = RecordingTrashMover()
            let checker = RecordingApplicationChecker(responses: [true])

            do {
                _ = try CleanupExecutor(
                    trashMover: mover,
                    applicationChecker: checker
                ).execute(plan: plan, rules: [candidate.rule], homeURL: home)
                throw TestFailure(description: "A running owner must stop execution")
            } catch CleanupExecutionError.ownerRunning(candidate.rule.id) {
                // Expected: the executor fails closed before any Trash operation.
            }

            try expect(mover.urls.isEmpty, "A running owner must prevent every Trash call")
        }
    }),
    ("Cleanup executor rechecks the owning app immediately before Trash", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id]
            )
            let mover = RecordingTrashMover()
            let checker = RecordingApplicationChecker(responses: [false, true])

            do {
                _ = try CleanupExecutor(
                    trashMover: mover,
                    applicationChecker: checker
                ).execute(plan: plan, rules: [candidate.rule], homeURL: home)
                throw TestFailure(description: "An owner that restarts must stop execution")
            } catch CleanupExecutionError.ownerRunning(candidate.rule.id) {
                // Expected: the second execution-time check catches the restart.
            }

            try expect(checker.checkedBundleIDs.count == 2, "Expected an owner check before preflight and before Trash")
            try expect(mover.urls.isEmpty, "Nothing may move after the owner restarts")
        }
    }),
    ("Cleanup receipt counts a missing target as skipped, never moved", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id]
            )
            try FileManager.default.removeItem(at: candidate.path)
            let mover = RecordingTrashMover()
            let checker = RecordingApplicationChecker(responses: [false])

            let receipt = try CleanupExecutor(
                trashMover: mover,
                applicationChecker: checker
            ).execute(plan: plan, rules: [candidate.rule], homeURL: home)

            try expect(receipt.moved.count == 0, "A missing target cannot count as moved")
            try expect(receipt.moved.logicalBytes == 0, "A missing target cannot count as reclaimed bytes")
            try expect(receipt.skipped.count == 1, "Expected the vanished target to be skipped")
            try expect(receipt.skipped.logicalBytes == candidate.logicalBytes, "Skipped bytes should retain the reviewed estimate")
            try expect(receipt.failed.count == 0, "A missing optional target is not a Trash failure")
            try expect(mover.urls.isEmpty, "A missing target cannot reach the Trash mover")
        }
    }),
    ("Cleanup receipt separates a Trash failure from moved bytes", {
        try withTemporaryHome { home in
            let candidate = try makeScannedCandidate(in: home)
            let plan = try PlanBuilder().build(
                candidates: [candidate],
                selectedRuleIDs: [candidate.rule.id]
            )
            let checker = RecordingApplicationChecker(responses: [false, false])

            let receipt = try CleanupExecutor(
                trashMover: FailingTrashMover(),
                applicationChecker: checker
            ).execute(plan: plan, rules: [candidate.rule], homeURL: home)

            try expect(receipt.moved.count == 0, "A failed Trash call cannot count as moved")
            try expect(receipt.moved.logicalBytes == 0, "A failed Trash call cannot count as reclaimed bytes")
            try expect(receipt.skipped.count == 0, "A Trash error is not a skip")
            try expect(receipt.failed.count == 1, "Expected one failed item")
            try expect(receipt.failed.logicalBytes == candidate.logicalBytes, "Failed bytes should retain the verified estimate")
        }
    }),
    ("Archive scanner rejects protected roots", {
        try withTemporaryHome { home in
            try expectThrows("The home directory cannot be an archive root") {
                _ = try ArchiveScanner().scan(rootURL: home, homeURL: home)
            }
            let library = home.appendingPathComponent("Library", isDirectory: true)
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            try expectThrows("The Library directory cannot be an archive root") {
                _ = try ArchiveScanner().scan(rootURL: library, homeURL: home)
            }
            for directoryName in ["Pictures", "Music"] {
                let mediaRoot = home.appendingPathComponent(directoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
                try expectThrows("The \(directoryName) directory cannot be an archive root") {
                    _ = try ArchiveScanner().scan(rootURL: mediaRoot, homeURL: home)
                }
            }
        }
    }),
    ("Archive scanner ignores Photos and Apple Music library packages", {
        try withTemporaryHome { home in
            let root = home.appendingPathComponent("Documents", isDirectory: true)
            let photosLibrary = root.appendingPathComponent("Photos Library.photoslibrary", isDirectory: true)
            let musicLibrary = root.appendingPathComponent("Music Library.musiclibrary", isDirectory: true)
            try FileManager.default.createDirectory(at: photosLibrary, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: musicLibrary, withIntermediateDirectories: true)

            let now = Date(timeIntervalSince1970: 2_000_000_000)
            try setModificationDateRecursively(photosLibrary, to: now.addingTimeInterval(-200 * 86_400))
            try setModificationDateRecursively(musicLibrary, to: now.addingTimeInterval(-200 * 86_400))

            let result = try ArchiveScanner().scan(rootURL: root, homeURL: home, now: now)
            try expect(result.suggestions.isEmpty, "Media libraries must never become archive suggestions")
        }
    }),
    ("Archive scanner suggests only inactive immediate child directories", {
        try withTemporaryHome { home in
            let root = home.appendingPathComponent("Projects", isDirectory: true)
            let inactive = root.appendingPathComponent("Inactive", isDirectory: true)
            let nested = inactive.appendingPathComponent("Nested", isDirectory: true)
            let recent = root.appendingPathComponent("Recent", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: nested.appendingPathComponent("old.bin"))
            try Data([4]).write(to: recent.appendingPathComponent("new.bin"))

            let now = Date(timeIntervalSince1970: 2_000_000_000)
            try setModificationDateRecursively(inactive, to: now.addingTimeInterval(-181 * 86_400))
            try setModificationDateRecursively(recent, to: now.addingTimeInterval(-181 * 86_400))
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-10 * 86_400)],
                ofItemAtPath: recent.appendingPathComponent("new.bin").path
            )

            let result = try ArchiveScanner().scan(rootURL: root, homeURL: home, now: now)
            try expect(
                result.suggestions.count == 1 && result.suggestions[0].path.lastPathComponent == "Inactive",
                "Only the inactive direct child should be suggested; got \(result.suggestions.map { $0.path.path })"
            )
            try expect(!result.suggestions.map { $0.path.lastPathComponent }.contains("Nested"), "Nested folders must never become top-level suggestions")
        }
    }),
    ("Archive scanner rejects symbolic links instead of following them", {
        try withTemporaryHome { home in
            let root = home.appendingPathComponent("Projects", isDirectory: true)
            let outside = home.appendingPathComponent("Outside", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            guard symlink(outside.path, root.appendingPathComponent("Linked").path) == 0 else {
                throw TestFailure(description: "Could not create archive fixture symlink")
            }
            try expectThrows("A linked child must fail closed") {
                _ = try ArchiveScanner().scan(rootURL: root, homeURL: home)
            }
        }
    }),
    ("Archive scanner counts hard-linked bytes once", {
        try withTemporaryHome { home in
            let root = home.appendingPathComponent("Projects", isDirectory: true)
            let child = root.appendingPathComponent("Inactive", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            let first = child.appendingPathComponent("first.bin")
            let second = child.appendingPathComponent("second.bin")
            try Data([1, 2, 3, 4]).write(to: first)
            guard link(first.path, second.path) == 0 else {
                throw TestFailure(description: "Could not create archive fixture hard link")
            }
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            try setModificationDateRecursively(child, to: now.addingTimeInterval(-181 * 86_400))

            let suggestion = try ArchiveScanner().scan(rootURL: root, homeURL: home, now: now).suggestions.first
            try expect(suggestion?.logicalBytes == 4, "Hard-linked content must not be double-counted")
            try expect(suggestion?.fileCount == 2, "Both directory entries remain visible in the count")
        }
    }),
    ("Archive scanner counts immediate children toward its traversal cap", {
        try withTemporaryHome { home in
            let root = home.appendingPathComponent("Projects", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("One", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Two", isDirectory: true),
                withIntermediateDirectories: true
            )
            try expectThrows("Every examined entry must count toward the hard cap") {
                _ = try ArchiveScanner(maxEntries: 1).scan(rootURL: root, homeURL: home)
            }
        }
    }),
    ("Archive scanner rejects cloud-sync roots", {
        try withTemporaryHome { home in
            let cloud = home.appendingPathComponent("Library/CloudStorage/Provider", isDirectory: true)
            try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
            try expectThrows("Cloud-managed content must remain outside archive reminders") {
                _ = try ArchiveScanner().scan(rootURL: cloud, homeURL: home)
            }
        }
    }),
    ("Archive scanner accepts the fixed macOS tmp path alias", {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("crab-archive-alias-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try ArchiveScanner().scan(
            rootURL: root,
            homeURL: URL(fileURLWithPath: "/Users/crab-fixture", isDirectory: true)
        )
        try expect(result.root.path.hasPrefix("/private/tmp/"), "The fixed system alias should canonicalize before validation")
    }),
    ("Project inventory automatically groups metadata-only projects by installed application", {
        try withTemporaryHome { home in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let projects = home.appendingPathComponent("Projects", isDirectory: true)
            let claudeProject = projects.appendingPathComponent("ClaudeFixture", isDirectory: true)
            let codexProject = projects.appendingPathComponent("CodexFixture", isDirectory: true)
            try FileManager.default.createDirectory(at: claudeProject, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: codexProject, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: claudeProject.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: codexProject.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try Data().write(to: claudeProject.appendingPathComponent("CLAUDE.md"))
            try Data().write(to: codexProject.appendingPathComponent("AGENTS.md"))
            try Data().write(to: home.appendingPathComponent("AGENTS.md"))
            let unreadable = claudeProject.appendingPathComponent("source.swift")
            try Data(repeating: 5, count: 4_096).write(to: unreadable)
            guard chmod(unreadable.path, 0) == 0 else {
                throw TestFailure(description: "Could not make project fixture content unreadable")
            }
            defer { _ = chmod(unreadable.path, S_IRUSR | S_IWUSR) }

            let protectedProject = home.appendingPathComponent("Library/HiddenProject", isDirectory: true)
            try FileManager.default.createDirectory(at: protectedProject, withIntermediateDirectories: true)
            try Data().write(to: protectedProject.appendingPathComponent("CLAUDE.md"))
            let linkedProject = projects.appendingPathComponent("LinkedProject")
            guard symlink(claudeProject.path, linkedProject.path) == 0 else {
                throw TestFailure(description: "Could not create linked project fixture")
            }

            let oldDate = now.addingTimeInterval(-200 * 86_400)
            try setModificationDateRecursively(claudeProject, to: oldDate)
            try setModificationDateRecursively(codexProject, to: now.addingTimeInterval(-5 * 86_400))
            let rules = [
                ProjectApplicationRule(appID: "ai.anthropic.claude-code", displayName: "Claude Code", markerNames: [".claude", "CLAUDE.md"]),
                ProjectApplicationRule(appID: "com.openai.codex", displayName: "Codex", markerNames: [".codex", "AGENTS.md"]),
            ]

            let result = try ProjectInventoryScanner(maxEntries: 2_000).scan(
                rootURLs: [home],
                rules: rules,
                installedAppIDs: ["ai.anthropic.claude-code", "com.openai.codex"],
                now: now
            )

            try expect(result.projects.count == 2, "Only two local, unlinked project roots should be discovered")
            try expect(result.projects.map(\.path).allSatisfy { !$0.path.contains("Library") }, "Protected Library projects must stay excluded")
            let claude = result.projects.first { $0.primaryAppID == "ai.anthropic.claude-code" }
            try expect(claude?.path == claudeProject.standardizedFileURL, "Claude marker must attribute the exact project root")
            try expect(claude?.identity.kind == .directory, "Project inventory must bind the exact directory identity")
            try expect(claude?.isInactive == true, "Projects older than 180 days must be classified as inactive")
            try expect((claude?.logicalBytes ?? 0) >= 4_096, "Project size must use metadata without reading file contents")
            let codex = result.projects.first { $0.primaryAppID == "com.openai.codex" }
            try expect(codex?.isInactive == false, "Recently modified projects must remain active")
            try expect(
                ProjectCleanupPresentation.projects(
                    result.projects,
                    query: "claudefixture",
                    filter: .all,
                    sort: .recentActivity
                ).map(\.path) == [claudeProject.standardizedFileURL],
                "Project search must be case-insensitive and match project names"
            )
            try expect(
                ProjectCleanupPresentation.projects(
                    result.projects,
                    query: "",
                    filter: .inactive,
                    sort: .recentActivity
                ).map(\.path) == [claudeProject.standardizedFileURL],
                "The inactive filter must contain only six-month projects"
            )
            try expect(
                ProjectCleanupPresentation.projects(
                    result.projects,
                    query: "",
                    filter: .recent,
                    sort: .sizeDescending
                ).map(\.path) == [codexProject.standardizedFileURL],
                "The recent filter must exclude six-month projects"
            )
        }
    }),
    ("Project application groups start collapsed and expand independently", {
        var disclosure = ProjectGroupDisclosureState()

        try expect(!disclosure.isExpanded("com.openai.codex"), "Codex must be collapsed initially")
        try expect(!disclosure.isExpanded("cn.trae.app"), "TRAE must be collapsed initially")

        disclosure.toggle("com.openai.codex")
        try expect(disclosure.isExpanded("com.openai.codex"), "Toggling Codex must expand only Codex")
        try expect(!disclosure.isExpanded("cn.trae.app"), "TRAE must remain collapsed")

        disclosure.toggle("com.openai.codex")
        try expect(!disclosure.isExpanded("com.openai.codex"), "Toggling again must collapse Codex")
    }),
    ("Project inventory never scans Photos or Apple Music libraries", {
        try withTemporaryHome { home in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let regularProject = home.appendingPathComponent("Projects/VisibleProject", isDirectory: true)
            let picturesProject = home.appendingPathComponent("Pictures/PhotosProject", isDirectory: true)
            let musicProject = home.appendingPathComponent("Music/MusicProject", isDirectory: true)
            let photosLibrary = home.appendingPathComponent("Documents/Photos Library.photoslibrary", isDirectory: true)
            let musicLibrary = home.appendingPathComponent("Documents/Music Library.musiclibrary", isDirectory: true)

            for project in [regularProject, picturesProject, musicProject, photosLibrary, musicLibrary] {
                try FileManager.default.createDirectory(
                    at: project.appendingPathComponent(".git", isDirectory: true),
                    withIntermediateDirectories: true
                )
                try Data().write(to: project.appendingPathComponent("AGENTS.md"))
            }

            let rule = ProjectApplicationRule(
                appID: "com.openai.codex",
                displayName: "Codex",
                markerNames: ["AGENTS.md"]
            )
            let result = try ProjectInventoryScanner(maxEntries: 2_000).scan(
                rootURLs: [home],
                rules: [rule],
                installedAppIDs: [rule.appID],
                now: now
            )

            try expect(
                result.projects.map(\.path) == [regularProject.standardizedFileURL],
                "Only ordinary project folders may be inventoried; Photos and Apple Music data must be excluded"
            )
        }
    }),
    ("Project scan access accepts only the exact local home directory", {
        try withTemporaryHome { home in
            let child = home.appendingPathComponent("Projects", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            let authorized = try ProjectScanAccessPolicy.authorizedRoot(
                selectedURL: home,
                homeURL: home
            )
            try expect(authorized == home.standardizedFileURL, "The exact home directory should be authorized")
            try expectThrows("A child folder must not replace the full project scan root") {
                _ = try ProjectScanAccessPolicy.authorizedRoot(
                    selectedURL: child,
                    homeURL: home
                )
            }
        }
    }),
    ("Project scan access rejects a symbolic link to the home directory", {
        try withTemporaryHome { home in
            let linkURL = home.deletingLastPathComponent()
                .appendingPathComponent("crab-home-link-\(UUID().uuidString)")
            guard symlink(home.path, linkURL.path) == 0 else {
                throw TestFailure(description: "Could not create home link fixture")
            }
            defer { try? FileManager.default.removeItem(at: linkURL) }
            try expectThrows("A linked authorization root must fail closed") {
                _ = try ProjectScanAccessPolicy.authorizedRoot(
                    selectedURL: linkURL,
                    homeURL: home
                )
            }
        }
    }),
    ("Project scan restores scoped access before validating the bookmarked folder", {
        let root = URL(fileURLWithPath: "/tmp/crab-bookmark-fixture", isDirectory: true)
        var events: [String] = []

        let result = SecurityScopedResourceAccess.withAccess(
            to: root,
            startAccessing: { url in
                events.append("start:\(url.path)")
                return true
            },
            stopAccessing: { url in
                events.append("stop:\(url.path)")
            },
            operation: {
                events.append("validate")
                return root
            }
        )

        try expect(result == root, "The scoped operation should return its validation result")
        try expect(
            events == ["start:\(root.path)", "validate", "stop:\(root.path)"],
            "The bookmarked folder must be accessed before validation and released afterwards"
        )
    }),
    ("Project cleanup selection starts empty and accepts any explicit project", {
        try withTemporaryHome { home in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let projects = home.appendingPathComponent("Projects", isDirectory: true)
            let inactive = projects.appendingPathComponent("Inactive", isDirectory: true)
            let recent = projects.appendingPathComponent("Recent", isDirectory: true)
            for project in [inactive, recent] {
                try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
                try Data().write(to: project.appendingPathComponent("CLAUDE.md"))
            }
            try setModificationDateRecursively(inactive, to: now.addingTimeInterval(-200 * 86_400))
            try setModificationDateRecursively(recent, to: now.addingTimeInterval(-5 * 86_400))
            let rule = ProjectApplicationRule(
                appID: "ai.anthropic.claude-code",
                displayName: "Claude Code",
                markerNames: ["CLAUDE.md"]
            )
            let inventory = try ProjectInventoryScanner(maxEntries: 2_000).scan(
                rootURLs: [home],
                rules: [rule],
                installedAppIDs: [rule.appID],
                now: now
            )
            guard let inactiveProject = inventory.projects.first(where: { $0.path == inactive.standardizedFileURL }),
                  let recentProject = inventory.projects.first(where: { $0.path == recent.standardizedFileURL })
            else { throw TestFailure(description: "Expected both project fixtures") }

            var selection = ProjectCleanupSelection(inventory: inventory)
            try expect(selection.selectedProjectIDs.isEmpty, "Project cleanup must never preselect user projects")
            selection.setSelected(recentProject.id, selected: true)
            try expect(selection.selectedProjectIDs == [recentProject.id], "A recent project must be selectable explicitly")
            selection.setSelected(inactiveProject.id, selected: true)
            try expect(
                selection.selectedProjectIDs == [recentProject.id, inactiveProject.id],
                "Every explicitly selected project must remain selected"
            )
            let recentPlan = try ProjectCleanupPlanBuilder().build(
                inventory: inventory,
                selectedProjectIDs: [recentProject.id],
                homeURL: home,
                now: now
            )
            try expect(
                recentPlan.entries.map(\.id) == [recentProject.id],
                "A recent project must enter the same revalidated Trash plan"
            )
            let mover = RecordingTrashMover()
            let receipt = try ProjectCleanupExecutor(
                trashMover: mover,
                scanner: ProjectInventoryScanner(maxEntries: 2_000)
            ).execute(plan: recentPlan, now: now)
            try expect(
                mover.urls == [recent.standardizedFileURL] && receipt.moved.count == 1,
                "A recent project must cross the Trash boundary only after revalidation"
            )
        }
    }),
    ("Project cleanup labels identify six-month and large projects", {
        try expect(
            ProjectCleanupLabelPolicy.labels(isInactive: false, logicalBytes: 128 * 1_024 * 1_024).isEmpty,
            "A recent small project should not receive a warning label"
        )
        try expect(
            ProjectCleanupLabelPolicy.labels(isInactive: true, logicalBytes: 128 * 1_024 * 1_024) == [.inactive],
            "A project inactive for six months must receive the inactive label"
        )
        try expect(
            ProjectCleanupLabelPolicy.labels(isInactive: false, logicalBytes: 1_024 * 1_024 * 1_024) == [.large],
            "A one-gigabyte project must receive the large label"
        )
        try expect(
            ProjectCleanupLabelPolicy.labels(isInactive: true, logicalBytes: 2 * 1_024 * 1_024 * 1_024) == [.inactive, .large],
            "An old large project must display both labels"
        )
    }),
    ("Project cleanup moves an explicitly selected and revalidated project to Trash", {
        try withTemporaryHome { home in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let project = home.appendingPathComponent("Projects/Inactive", isDirectory: true)
            try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try Data().write(to: project.appendingPathComponent("CLAUDE.md"))
            try Data(repeating: 4, count: 2_048).write(to: project.appendingPathComponent("source.swift"))
            try setModificationDateRecursively(project, to: now.addingTimeInterval(-200 * 86_400))
            let rule = ProjectApplicationRule(
                appID: "ai.anthropic.claude-code",
                displayName: "Claude Code",
                markerNames: ["CLAUDE.md"]
            )
            let inventory = try ProjectInventoryScanner(maxEntries: 2_000).scan(
                rootURLs: [home],
                rules: [rule],
                installedAppIDs: [rule.appID],
                now: now
            )
            guard let candidate = inventory.projects.first else {
                throw TestFailure(description: "Expected the inactive project fixture")
            }
            let plan = try ProjectCleanupPlanBuilder().build(
                inventory: inventory,
                selectedProjectIDs: [candidate.id],
                homeURL: home,
                now: now
            )
            let mover = RecordingTrashMover()
            let receipt = try ProjectCleanupExecutor(
                trashMover: mover,
                scanner: ProjectInventoryScanner(maxEntries: 2_000)
            ).execute(plan: plan, now: now)

            try expect(mover.urls == [project.standardizedFileURL], "Only the exact selected project may reach the Trash boundary")
            try expect(receipt.moved.count == 1, "The moved project must be reported")
            try expect(receipt.moved.logicalBytes >= 2_048, "The moved size must come from fresh metadata evidence")
        }
    }),
    ("Project cleanup refuses a project changed after review", {
        try withTemporaryHome { home in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let project = home.appendingPathComponent("Projects/Changed", isDirectory: true)
            try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try Data().write(to: project.appendingPathComponent("AGENTS.md"))
            let source = project.appendingPathComponent("source.swift")
            try Data(repeating: 1, count: 16).write(to: source)
            try setModificationDateRecursively(project, to: now.addingTimeInterval(-200 * 86_400))
            let rule = ProjectApplicationRule(
                appID: "com.openai.codex",
                displayName: "Codex",
                markerNames: ["AGENTS.md"]
            )
            let inventory = try ProjectInventoryScanner(maxEntries: 2_000).scan(
                rootURLs: [home],
                rules: [rule],
                installedAppIDs: [rule.appID],
                now: now
            )
            guard let candidate = inventory.projects.first else {
                throw TestFailure(description: "Expected the inactive project fixture")
            }
            let plan = try ProjectCleanupPlanBuilder().build(
                inventory: inventory,
                selectedProjectIDs: [candidate.id],
                homeURL: home,
                now: now
            )
            try Data(repeating: 2, count: 32).write(to: source)
            let mover = RecordingTrashMover()

            try expectThrows("Changed project evidence must fail closed") {
                _ = try ProjectCleanupExecutor(
                    trashMover: mover,
                    scanner: ProjectInventoryScanner(maxEntries: 2_000)
                ).execute(plan: plan, now: now)
            }
            try expect(mover.urls.isEmpty, "A changed project must never reach the Trash boundary")
        }
    }),
    ("Archive snapshot binds stale metadata with a fresh identity and expiry", {
        try withTemporaryHome { home in
            let scannedAt = Date(timeIntervalSince1970: 2_000_000_000)
            let result = try makeArchiveScanResult(in: home, scannedAt: scannedAt)
            let first = try ArchiveSnapshotBuilder().build(from: result, now: scannedAt)
            let second = try ArchiveSnapshotBuilder().build(from: result, now: scannedAt)

            try expect(first.snapshotID != second.snapshotID, "Every read-only snapshot needs a fresh identity")
            try expect(first.expiresAt == scannedAt.addingTimeInterval(600), "Expected a ten-minute review window")
            try expect(first.entries.count == 1, "Expected the verified stale suggestion")
            try expect(first.entries[0].identity == result.suggestions[0].identity, "Snapshot must bind child identity evidence")
            try expect(first.entries[0].rootIdentity == result.rootIdentity, "Snapshot must bind root identity evidence")
        }
    }),
    ("Archive snapshot builder rejects expired scan evidence", {
        try withTemporaryHome { home in
            let scannedAt = Date(timeIntervalSince1970: 2_000_000_000)
            let result = try makeArchiveScanResult(in: home, scannedAt: scannedAt)
            try expectThrows("Old scan evidence cannot create a fresh archive snapshot") {
                _ = try ArchiveSnapshotBuilder().build(
                    from: result,
                    now: scannedAt.addingTimeInterval(601)
                )
            }
        }
    }),
    ("Archive reminder state has no root or results before user opt-in", {
        let state = ArchiveReminderState()
        try expect(state.phase == .awaitingFolder, "Archive reminders must wait for an explicit folder")
        try expect(state.rootURL == nil, "No folder may be inferred automatically")
        try expect(state.snapshot == nil, "No archive evidence exists before a scan")
        try expect(state.inactivityDays == 180, "The first release uses the approved 180-day threshold")
    }),
    ("Cache workflow waits on the home page before user opt-in", {
        let state = CacheWorkflowState()
        try expect(state.phase == .idle, "Cache scanning must not start when Crab opens")
        try expect(state.snapshot.candidates.isEmpty, "The home page must not expose stale scan results")
        try expect(state.issueCount == 0, "The home page must not expose stale scan issues")
    }),
    ("Cache workflow scans only after an explicit start and can return home", {
        try withTemporaryHome { home in
            var state = CacheWorkflowState()
            let candidate = try makeScannedCandidate(in: home)

            state.beginScan()
            try expect(state.phase == .loading, "An explicit scan should show the loading page")

            state.finish(snapshot: AppScanSnapshot(candidates: [candidate]), issueCount: 2)
            try expect(state.phase == .ready, "A completed scan should show the result page")
            try expect(state.snapshot.candidates.count == 1, "The result page should retain verified candidates")
            try expect(state.issueCount == 2, "The result page should retain scan issue metadata")

            state.returnHome()
            try expect(state.phase == .idle, "Returning home should restore the initial page")
            try expect(state.snapshot.candidates.isEmpty, "Returning home should clear scan results")
            try expect(state.issueCount == 0, "Returning home should clear scan issue metadata")
        }
    }),
    ("Desktop presence keeps the menu icon visible while Crab is running", {
        var presence = DesktopPresenceState()
        try expect(presence.phase == .mainWindow, "Crab should launch as a normal windowed app")
        try expect(presence.isMenuBarVisible, "The menu icon should be visible immediately while Crab is running")

        let handled = presence.minimizeToMenuBar(enabled: true)
        try expect(!handled, "Crab must leave minimization to the standard macOS window behavior")
        try expect(presence.phase == .mainWindow, "Minimizing must not switch Crab to an accessory-only mode")
        try expect(presence.isMenuBarVisible, "The menu icon must remain visible after minimizing")
    }),
    ("Desktop presence never intercepts standard minimization", {
        var presence = DesktopPresenceState()
        let handled = presence.minimizeToMenuBar(enabled: false)
        try expect(!handled, "Standard minimization must remain untouched")
        try expect(presence.phase == .mainWindow, "Crab must retain normal application presence")
        try expect(presence.isMenuBarVisible, "The menu icon must not depend on a minimization preference")
    }),
    ("Runtime optimizer accounts for an AI app process tree only", {
        let snapshot = AIOptimizationSnapshotBuilder().build(
            applications: [
                RunningAIApplicationSeed(
                    appID: "com.openai.chat",
                    displayName: "ChatGPT",
                    processIdentifier: 100,
                    launchedAt: Date(timeIntervalSince1970: 100)
                ),
                RunningAIApplicationSeed(
                    appID: "com.anthropic.claudefordesktop",
                    displayName: "Claude",
                    processIdentifier: 200,
                    launchedAt: Date(timeIntervalSince1970: 200)
                ),
            ],
            processes: [
                ProcessResourceSample(processIdentifier: 100, parentProcessIdentifier: 1, residentBytes: 200),
                ProcessResourceSample(processIdentifier: 101, parentProcessIdentifier: 100, residentBytes: 300),
                ProcessResourceSample(processIdentifier: 102, parentProcessIdentifier: 101, residentBytes: 400),
                ProcessResourceSample(processIdentifier: 200, parentProcessIdentifier: 1, residentBytes: 500),
                ProcessResourceSample(processIdentifier: 999, parentProcessIdentifier: 1, residentBytes: 9_999),
            ]
        )

        try expect(snapshot.applications.count == 2, "Only the supplied supported AI apps should appear")
        try expect(snapshot.applications[0].appID == "com.openai.chat", "Apps should sort by process-tree memory")
        try expect(snapshot.applications[0].residentBytes == 900, "Root and descendant RSS should be summed")
        try expect(snapshot.totalResidentBytes == 1_400, "Unrelated process memory must be excluded")
    }),
    ("Runtime optimizer reads the current process through macOS libproc", {
        let samples = try SystemProcessResourceSampler().sample()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        try expect(
            samples.contains { $0.processIdentifier == ownPID && $0.residentBytes > 0 },
            "The read-only process sampler should include the current test process"
        )
    }),
    ("Archive reminder state represents scan and read-only result phases", {
        try withTemporaryHome { home in
            let scannedAt = Date(timeIntervalSince1970: 2_000_000_000)
            let result = try makeArchiveScanResult(in: home, scannedAt: scannedAt)
            let snapshot = try ArchiveSnapshotBuilder().build(from: result, now: scannedAt)
            var state = ArchiveReminderState()

            state.beginScanning(rootURL: result.root)
            try expect(state.phase == .scanning, "Expected scanning state")
            try expect(state.rootURL == result.root, "The chosen root must remain visible")
            try expect(state.snapshot == nil, "Old results must clear when scanning starts")

            state.finish(with: snapshot)
            try expect(state.phase == .ready, "Expected a read-only result state")
            try expect(state.snapshot == snapshot, "State must expose the verified snapshot")
            try expect(state.errorMessage == nil, "A successful scan must clear errors")
        }
    }),
    ("Rule loader reads validated JSON rules from a directory", {
        try withTemporaryHome { directory in
            let file = directory.appendingPathComponent("fixture.json")
            try validRuleData().write(to: file)
            let rules = try RuleLoader().load(directory: directory)
            try expect(rules.count == 1, "Expected one loaded rule")
            try expect(rules[0].id.rawValue == "dev.crab.fixture.cache.v1", "Unexpected loaded rule")
        }
    }),
    ("Production cache catalog contains only unique exact cache leaves", {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Rules/AIApplications", isDirectory: true)
        let rules = try RuleLoader().load(directory: directory)
        let ids = rules.map(\.id)
        let leaves = rules.map(\.leaf)
        let expectedNewIDs: Set<RuleID> = [
            RuleID(rawValue: "dev.crab.trae-solo.cache.v1"),
            RuleID(rawValue: "dev.crab.trae-solo.updates.v1"),
            RuleID(rawValue: "dev.crab.claude.updates.v1"),
            RuleID(rawValue: "dev.crab.zed.bundle-cache.v1"),
            RuleID(rawValue: "dev.crab.zed.cache.v1"),
            RuleID(rawValue: "dev.crab.ollama.ui-cache.v1"),
        ]

        try expect(Set(ids).count == ids.count, "Production rule ids must be unique")
        try expect(Set(leaves).count == leaves.count, "Production cache leaves must be unique")
        try expect(expectedNewIDs.isSubset(of: Set(ids)), "Expected all verified catalog additions")
        try expect(leaves.allSatisfy { $0.hasPrefix("Library/Caches/") }, "Every production rule must stay below Library/Caches")

        let forbidden = ["applicationsupport", "models", "sessions", "conversations", "credentials", "localstorage", "indexeddb", "containers"]
        for leaf in leaves {
            let normalized = leaf.lowercased().filter(\.isLetter)
            try expect(forbidden.allSatisfy { !normalized.contains($0) }, "Protected content appeared in production catalog: \(leaf)")
        }
    }),
    ("CLI parser rejects a clean command", {
        try expectThrows("The read-only slice must not expose clean") {
            _ = try CLIParser().parse(["clean", "--force"])
        }
    }),
    ("CLI parser keeps plan selection empty by default", {
        let command = try CLIParser().parse([
            "plan",
            "--rules", "/tmp/rules",
            "--home", "/tmp/home",
            "--output", "/tmp/plan.json",
        ])
        guard case let .plan(_, _, _, selectedRuleIDs) = command else {
            throw TestFailure(description: "Expected plan command")
        }
        try expect(selectedRuleIDs.isEmpty, "Plan must not default-select candidates")
    }),
    ("CLI parser records only explicit selections", {
        let command = try CLIParser().parse([
            "plan",
            "--rules", "/tmp/rules",
            "--home", "/tmp/home",
            "--output", "/tmp/plan.json",
            "--select", "rule.one",
            "--select", "rule.two",
        ])
        guard case let .plan(_, _, _, selectedRuleIDs) = command else {
            throw TestFailure(description: "Expected plan command")
        }
        try expect(
            selectedRuleIDs == [RuleID(rawValue: "rule.one"), RuleID(rawValue: "rule.two")],
            "Expected explicit selection ids"
        )
    }),
]

private func expectThrows(
    _ message: String,
    operation: () throws -> Void
) throws {
    do {
        try operation()
        throw TestFailure(description: message)
    } catch is TestFailure {
        throw TestFailure(description: message)
    } catch {
        return
    }
}

private func validRuleData(
    replacing source: String? = nil,
    with replacement: String = ""
) -> Data {
    var json = """
    {
      "schema": 1,
      "id": "dev.crab.fixture.cache.v1",
      "appID": "crab-fixture",
      "category": "regenerable-cache",
      "risk": "A",
      "leaf": "Library/Caches/CrabFixture/Cache",
      "requiresAppStopped": true,
      "action": "trash",
      "explanation": "A fixture cache that the test app can rebuild.",
      "impact": "The fixture app may rebuild cached resources.",
      "recovery": "Restore the item from Trash before it is emptied."
    }
    """

    if let source {
        json = json.replacingOccurrences(of: source, with: replacement)
    }

    return Data(json.utf8)
}

private extension Data {
    func replacingUTF8(_ source: String, with replacement: String) -> Data {
        let text = String(data: self, encoding: .utf8) ?? ""
        return Data(text.replacingOccurrences(of: source, with: replacement).utf8)
    }
}

private func fixtureRule() throws -> AIFileRule {
    try RuleValidator.decode(data: validRuleData())
}

private func fixtureResidueCacheRule(appID: String) throws -> AIFileRule {
    let data = validRuleData()
        .replacingUTF8("dev.crab.fixture.cache.v1", with: "dev.crab.fixture-residue.cache.v1")
        .replacingUTF8("crab-fixture", with: appID)
        .replacingUTF8("Library/Caches/CrabFixture/Cache", with: "Library/Caches/\(appID)")
    return try RuleValidator.decode(data: data)
}

private func fixtureResidueRule(
    id: String,
    category: HarnessResidueCategory,
    risk: HarnessResidueRisk,
    path: String
) -> HarnessResidueRule {
    HarnessResidueRule(
        id: HarnessResidueID(rawValue: id),
        appID: "dev.crab.fixture-harness",
        category: category,
        risk: risk,
        relativePath: path,
        title: (path as NSString).lastPathComponent,
        explanation: "Fixture residual item"
    )
}

private func withTemporaryHome(_ operation: (URL) throws -> Void) throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("crab-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try operation(home)
}

private func makeFixtureCache(in home: URL) throws -> URL {
    let cache = home.appendingPathComponent(
        "Library/Caches/CrabFixture/Cache",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    return cache
}

private func makeScannedCandidate(in home: URL) throws -> ScanCandidate {
    let cache = try makeFixtureCache(in: home)
    try Data([1, 2, 3]).write(to: cache.appendingPathComponent("cache.bin"))
    return try SafeScanner().scan(rule: fixtureRule(), homeURL: home)
}

private func makeFixtureApplication(
    in applicationsRoot: URL,
    name: String,
    bundleIdentifier: String,
    version: String
) throws -> URL {
    let appURL = applicationsRoot.appendingPathComponent(name, isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    let resources = contents.appendingPathComponent("Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleName": name.replacingOccurrences(of: ".app", with: ""),
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    try Data(repeating: 7, count: 8_192).write(to: resources.appendingPathComponent("fixture.bin"))
    return appURL.standardizedFileURL
}

private func makeSignedCrabApplication(in root: URL, version: String) throws -> URL {
    let appURL = root.appendingPathComponent("Crab.app", isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(
        at: executableDirectory,
        withIntermediateDirectories: true
    )
    let executable = executableDirectory.appendingPathComponent("Crab")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )
    let plist: [String: Any] = [
        "CFBundleIdentifier": "dev.crab.cleaner",
        "CFBundleExecutable": "Crab",
        "CFBundleName": "Crab",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
    ]
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .xml,
        options: 0
    )
    try plistData.write(to: contents.appendingPathComponent("Info.plist"))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = [
        "--force", "--deep", "--sign", "-",
        "--requirements", "=designated => identifier \"dev.crab.cleaner\"",
        appURL.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw TestFailure(description: "Could not sign Crab update fixture")
    }
    return appURL
}

private func makeZipArchive(from appURL: URL, at archiveURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = [
        "-c", "-k", "--sequesterRsrc", "--keepParent",
        appURL.path,
        archiveURL.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw TestFailure(description: "Could not create Crab update archive fixture")
    }
}

private func setModificationDateRecursively(_ root: URL, to date: Date) throws {
    let manager = FileManager.default
    if let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil) {
        for case let url as URL in enumerator {
            try manager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }
    try manager.setAttributes([.modificationDate: date], ofItemAtPath: root.path)
}

private func makeCodexStateDatabase(in home: URL, tokenCounts: [UInt64]) throws {
    let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    let database = codexDirectory.appendingPathComponent("state_5.sqlite")
    let values = tokenCounts.enumerated().map { index, count in
        "('thread-\(index)', \(count))"
    }.joined(separator: ",")
    let statement = "CREATE TABLE threads (id TEXT PRIMARY KEY, tokens_used INTEGER NOT NULL); INSERT INTO threads VALUES \(values);"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [database.path, statement]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown sqlite error"
        throw TestFailure(description: "Could not create Codex metadata fixture: \(message)")
    }
}

private func makeArchiveScanResult(in home: URL, scannedAt: Date) throws -> ArchiveScanResult {
    let root = home.appendingPathComponent("Projects", isDirectory: true)
    let child = root.appendingPathComponent("Inactive", isDirectory: true)
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: child.appendingPathComponent("artifact.bin"))
    try setModificationDateRecursively(child, to: scannedAt.addingTimeInterval(-181 * 86_400))
    return try ArchiveScanner().scan(rootURL: root, homeURL: home, now: scannedAt)
}

private final class RecordingTrashMover: TrashMoving, @unchecked Sendable {
    private(set) var urls: [URL] = []

    func moveToTrash(_ url: URL) throws {
        urls.append(url)
    }
}

private struct FailingTrashMover: TrashMoving {
    private struct FixtureError: Error {}

    func moveToTrash(_ url: URL) throws {
        throw FixtureError()
    }
}

private final class RecordingApplicationChecker: ApplicationActivityChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Bool]
    private(set) var checkedBundleIDs: [String] = []

    init(responses: [Bool]) {
        self.responses = responses
    }

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        checkedBundleIDs.append(bundleIdentifier)
        return responses.isEmpty ? false : responses.removeFirst()
    }
}

var failures = 0

for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures += 1
        fputs("FAIL \(name): \(error)\n", stderr)
    }
}

guard failures == 0 else {
    exit(EXIT_FAILURE)
}

print("\(tests.count) test(s) passed")
