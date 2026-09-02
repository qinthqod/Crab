# Crab task list

## Task 1: Initialize the safe Swift workspace

**Description:** Create the Swift package, module boundaries, repository ignore rules, and empty buildable targets.

**Acceptance criteria:**
- [x] `CrabCore` is a library and `crab` is an executable depending on it.
- [x] No third-party dependencies or write-capable filesystem module exists.
- [x] Build output, IDE state, environment files, and prototype dependencies are ignored.

**Verification:**
- [x] `swift build`

**Dependencies:** None

**Files likely touched:** `Package.swift`, `.gitignore`, `Sources/CrabCore/CrabCore.swift`, `Sources/crab/main.swift`

**Estimated scope:** Medium

## Task 2: Implement the strict rule contract

**Description:** Test and implement schema-v1 rule decoding and fail-closed validation.

**Acceptance criteria:**
- [x] Valid exact-leaf trash rules are accepted.
- [x] Unsupported schema, traversal, absolute leaf, empty leaf, and unsupported action are rejected.
- [x] Rules contain user-facing safety, impact, and recovery explanations.

**Verification:**
- [x] `swift run crab-core-tests`

**Dependencies:** Task 1

**Files likely touched:** `Sources/CrabCore/Rule.swift`, `Sources/CrabCore/RuleValidator.swift`, `Tests/CrabCoreTests/RuleValidationTests.swift`

**Estimated scope:** Medium

## Task 3: Implement metadata-only safe scanning

**Description:** Test and implement exact-leaf scanning, link rejection, file identity capture, and hard-link-aware accounting.

**Acceptance criteria:**
- [x] Scanner reads metadata only and returns a candidate for a valid fixture leaf.
- [x] Target and ancestor symbolic links fail closed.
- [x] Hard links are counted once and paths outside the rule root are unreachable.

**Verification:**
- [x] `swift run crab-core-tests`

**Dependencies:** Task 2

**Files likely touched:** `Sources/CrabCore/FileIdentity.swift`, `Sources/CrabCore/SafeScanner.swift`, `Tests/CrabCoreTests/SafeScannerTests.swift`

**Estimated scope:** Medium

## Task 4: Implement immutable plan generation

**Description:** Test and implement explicit candidate selection, immutable identities, unique plan IDs, and expiration.

**Acceptance criteria:**
- [x] Only explicitly selected verified-safe candidates enter a plan.
- [x] Empty selection remains empty and selection changes produce a new plan ID.
- [x] Plan entries preserve rule and file identity evidence with an expiry.

**Verification:**
- [x] `swift run crab-core-tests`

**Dependencies:** Task 3

**Files likely touched:** `Sources/CrabCore/CleanPlan.swift`, `Sources/CrabCore/PlanBuilder.swift`, `Tests/CrabCoreTests/PlanBuilderTests.swift`

**Estimated scope:** Medium

## Task 5: Add the read-only CLI

**Description:** Connect `rules validate`, `scan`, and `plan` commands to `CrabCore` with redacted output defaults.

**Acceptance criteria:**
- [x] CLI never accepts arbitrary clean targets and exposes no write command.
- [x] Scan output distinguishes logical and allocated bytes.
- [x] Plan output is versioned JSON and contains no default selections.

**Verification:**
- [x] `swift run crab --help`
- [x] `swift run crab rules validate Fixtures/Rules/example.json`
- [x] `swift run crab scan --rules Fixtures/Rules --home Fixtures/Home`

**Dependencies:** Task 4

**Files likely touched:** `Sources/crab/main.swift`, `Fixtures/Rules/example.json`, `README.md`

**Estimated scope:** Medium

## Task 6: First-slice checkpoint

**Description:** Run the full safety gate and document the first runnable developer workflow.

**Acceptance criteria:**
- [x] All tests pass without skips.
- [x] Build succeeds with no third-party dependencies.
- [x] Test fixtures remain unchanged after scan and plan commands.

**Verification:**
- [x] `swift run crab-core-tests`
- [x] `swift build`
- [x] `git diff --check`

**Dependencies:** Tasks 1–5

**Files likely touched:** `README.md`, `tasks/todo.md`

**Estimated scope:** Small

## Task 7: Native macOS application

**Description:** Connect the safe core to a minimal SwiftUI window and menu-bar extra, then package a locally runnable application bundle.

**Acceptance criteria:**
- [x] Main screen matches the selected Crab hierarchy and ocean-purple palette.
- [x] Current-user AI cache results are scanned from reviewed exact leaves and begin unselected.
- [x] Review moves only revalidated selections to Trash; permanent deletion is unavailable.
- [x] Protective Orbit artwork is used for the app icon and interface.
- [x] A signed `build/Crab.app` is generated without requiring Xcode.

**Verification:**
- [x] `swift run crab-core-tests` (27 tests)
- [x] `swift build`
- [x] `scripts/check-dangerous-apis.sh`
- [x] `plutil -lint build/Crab.app/Contents/Info.plist`
- [x] `codesign --verify --deep --strict build/Crab.app`
- [x] Launch process confirmed after `open -n build/Crab.app`

**Dependencies:** Tasks 1–6

**Estimated scope:** Large

## Task 8: Reject protected cache-path markers

**Acceptance criteria:** protected conversation, model, credential, local-storage, database, container, and shared-container markers are rejected; existing exact cache rules remain valid. [x]

**Verification:** focused rule tests, then `swift run crab-core-tests` (31 tests). [x]

**Dependencies:** Task 2. **Files:** `RuleValidator.swift`, `main.swift`. **Scope:** Small.

## Task 9: Recheck owning-app state at execution time

**Acceptance criteria:** an app that starts after plan creation prevents every move; owner state is checked again immediately before each Trash call. [x]

**Verification:** recording owner checker and Trash mover tests; full harness (33 tests). [x]

**Dependencies:** Task 8. **Files:** `CleanupExecutor.swift`, `AppModel.swift`, `main.swift`. **Scope:** Medium.

## Task 10: Add truthful cleanup outcome accounting

**Acceptance criteria:** moved, skipped, and failed counts/bytes are distinct; missing targets never count as moved. [x]

**Verification:** focused receipt tests; full harness (35 tests) and build. [x]

**Dependencies:** Task 9. **Files:** `CleanupExecutor.swift`, `AppModel.swift`, `MainView.swift`, `main.swift`. **Scope:** Medium.

## Task 11: Implement metadata-only archive scanning

**Acceptance criteria:** only immediate inactive children of a user-selected safe root are suggested; protected/cloud/linked/recent roots fail closed; no contents are read. [x]

**Verification:** temporary-filesystem abuse tests and build (41-test checkpoint). [x]

**Dependencies:** None. **Files:** `Package.swift`, `Sources/CrabArchive/ArchiveSuggestion.swift`, `Sources/CrabArchive/ArchiveScanner.swift`, `main.swift`. **Scope:** Medium.

## Task 12: Enforce the read-only archive snapshot boundary

**Acceptance criteria:** snapshots bind metadata evidence but expose no Trash action; archive types cannot enter `CleanPlan` or `CleanupExecutor`. [x]

**Verification:** API/refusal tests, architecture guard, and build (43 tests). [x]

**Dependencies:** Task 11. **Files:** `Sources/CrabArchive/ArchiveSnapshot.swift`, `Sources/CrabArchive/ArchiveSnapshotBuilder.swift`, `main.swift`. **Scope:** Medium.

## Task 13: Add archive reminder application state

**Acceptance criteria:** selected root, scanning state, threshold, results, and errors are represented; no selection or mutation state exists. [x]

**Verification:** state tests and build (45 tests). [x]

**Dependencies:** Task 12. **Files:** `Package.swift`, `Sources/CrabAppSupport/ArchiveReminderState.swift`, `main.swift`. **Scope:** Medium.

## Task 14: Build the dual-mode native workflow

**Acceptance criteria:** Cache remains automatic; Archive Reminder requires a folder picker and exposes Finder/owning-app actions only; copy distinguishes reminders from safe cleanup. [x]

**Verification:** build, package, native runtime and accessibility inspection. [x]

**Dependencies:** Tasks 10 and 13. **Files:** `AppModel.swift`, `MainView.swift`, `ScanResultView.swift`, `ArchiveReminderView.swift`, `CrabApp.swift`. **Scope:** Medium.

## Task 15: Add first verified cache catalog expansion

**Status:** TRAE SOLO and Claude supplemental cache rules shipped. Kimi remains research-only because its bundle identifier is corroborated but its exact regenerable cache leaf is not.

**Acceptance criteria:** TRAE SOLO, Kimi Code Desktop, and Claude supplemental exact cache leaves validate; no model/user-content paths ship.

**Verification:** catalog tests and full harness.

**Dependencies:** Task 8. **Files:** three rule JSON files and `main.swift`. **Scope:** Medium.

## Task 16: Add remaining verified cache catalog expansion

**Status:** Ollama desktop UI and both documented Zed cache leaves shipped. LM Studio remains research-only because no second trustworthy exact cache-path signal was found.

**Acceptance criteria:** LM Studio, Ollama, and Zed exact regenerable UI cache leaves validate; local model repositories remain explicitly absent.

**Verification:** catalog integrity tests and full harness.

**Dependencies:** Task 15. **Files:** three rule JSON files and `main.swift`. **Scope:** Medium.

## Task 17: Replace the app icon

**Acceptance criteria:** the coral mascot is optically centered on an opaque pale-lavender 1024px source and renders into a valid signed `Crab.icns` bundle. [x]

**Verification:** pixel/alpha checks, `iconutil`, `plutil`, and `codesign --verify --deep --strict`. [x]

**Dependencies:** None. **Files:** icon PNG asset, `build-app-bundle.sh`, `Info.plist`. **Scope:** Medium.

## Task 18: Add the Harness catalog and installed-only cache results [x]

**Acceptance criteria:** catalog identities are unique; cache results contain installed supported products only; installed products with no cache show as clean.

**Verification:** failing catalog/filter tests, then `swift run crab-core-tests`.

**Dependencies:** Task 15. **Files:** catalog, scan overview, app model, core tests. **Scope:** Medium.

## Task 19: Collect installed Harness metadata [x]

**Acceptance criteria:** standard application roots are scanned for matching bundle identifiers; version, bundle size, and Spotlight last-used date are represented truthfully.

**Verification:** temporary fake-app inventory tests and full build.

**Dependencies:** Task 18. **Files:** inventory scanner, app model, core tests. **Scope:** Medium.

## Task 20: Build the Harness overview [x]

**Acceptance criteria:** only installed products appear; each row shows last opened time, inactivity, version, app/cache/combined disk usage, and Token connection state.

**Verification:** build, launch smoke test, accessibility inspection when the Mac is unlocked.

**Dependencies:** Task 19. **Files:** main view, Harness overview view, app model. **Scope:** Medium.

## Task 21: Add app-only safe uninstall [x]

**Acceptance criteria:** explicit confirmation is required; running/mismatched/linked/out-of-bound apps are rejected; exactly the `.app` bundle enters Trash; all user data remains untouched.

**Verification:** fake Trash-mover tests, build, dangerous-API scan, signed release bundle.

**Dependencies:** Tasks 19–20. **Files:** uninstall boundary, app model, overview view, core tests. **Scope:** Medium.
- [x] Project cleanup: bind scan results to directory identity and freshness.
- [x] Project cleanup: implement explicit inactive-project selection and safe Trash execution.
- [x] Project cleanup: add second-confirmation UI and per-result feedback.
- [x] Project cleanup: run full verification and package the native app.
