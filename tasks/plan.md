# Implementation Plan: Crab Safe Scan Foundation

## Overview

Deliver the first read-only Crab vertical slice. The package will validate declarative rules, scan fixture cache leaves without following links, produce immutable plans from explicit selection, and expose these capabilities through a small CLI. Write operations remain structurally impossible.

## Architecture Decisions

- One Swift package owns `CrabCore` and the `crab` executable so App and CLI cannot diverge on safety logic.
- Rules use strict JSON and exact relative leaf paths; unknown fields and unsupported schema versions fail closed.
- Scanner receives an injected home/root URL for deterministic tests and never searches the full disk.
- File identity is a value captured from `lstat` metadata. Plans store identity and expiry for later execution-time revalidation.
- No third-party command parser is added; the first CLI uses a small explicit argument parser.
- Trash execution is isolated behind one reviewed system boundary and always requires execution-time revalidation.

## Dependency Graph

```text
Rule schema + validation
        ↓
Path boundary + metadata identity
        ↓
Safe scanner + accounting
        ↓
Immutable plan builder
        ↓
Read-only CLI commands
```

## Task List

### Phase 1: Foundation

- [x] Task 1: Initialize Swift package, Git ignore rules, and safe module boundaries.
- [x] Task 2: Add failing rule-validation tests, then implement the strict rule contract.

### Checkpoint: Rule contract

- [x] Focused validation tests pass.
- [x] Package builds without third-party dependencies.

### Phase 2: Safe scanning

- [x] Task 3: Add failing path/symlink/size tests, then implement metadata-only scanning.
- [x] Task 4: Add failing explicit-selection and expiry tests, then implement immutable plans.

### Checkpoint: Core

- [x] Full `crab-core-tests` harness passes.
- [x] Fixture tree is unchanged after scan and planning.

### Phase 3: CLI vertical slice

- [x] Task 5: Implement `rules validate`, `scan`, and `plan` against `CrabCore`.
- [x] Task 6: Add CLI smoke tests and usage documentation.

### Checkpoint: First runnable build

- [x] `swift run crab-core-tests` passes.
- [x] `swift build` succeeds.
- [x] CLI produces a redacted scan report and JSON plan from fixtures.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Foundation APIs accidentally follow symbolic links | High | `lstat` each component and cover target/ancestor links with real filesystem tests |
| Rule format is too expressive | High | Exact relative leaves only; no glob, regex, command, script, or negative-list cleanup |
| Size reporting overstates reclaimable bytes | Medium | Report logical and allocated bytes separately; deduplicate hard links |
| CLI becomes a backdoor for arbitrary paths | High | Commands take rule/plan artifacts only; no path list or force flag |
| macOS-only metadata makes tests brittle | Medium | Isolate Darwin metadata adapter behind a small protocol and use real temporary fixtures |

## Open Questions

- CLI write commands, Application Support rules, and permanent deletion remain intentionally out of scope.

## Native macOS application slice

- [x] Add testable application selection state with empty defaults.
- [x] Build the minimal SwiftUI main window and menu-bar panel.
- [x] Package, sign, verify, and launch a native `Crab.app`.

## Real-cache correction

- [x] Replace bundled demo-home scanning with the current user's real cache root.
- [x] Add reviewed exact-leaf rules for supported AI applications.
- [x] Keep immutable planning internal and expose a direct Move to Trash flow.
- [x] Revalidate every selected root before the first move.
- [x] Group multiple cache rules under a single product with second-level cache items.
- [x] Expand the native main window into a spacious, resizable Mac application layout.
- [x] Recompose the main window as an Apple-style landscape experience with material hierarchy and reduced-motion support.
- [x] Add explicit idle → animated loading → result states; show rescan only after an attempted scan.

# Implementation Plan: Refusal-list cleanup and archive reminders

## Overview

Strengthen the existing cache-only Trash pipeline with Mole-style refusal gates, add metadata-only read-only archive reminders for user-selected local folders, expand the exact-leaf AI cache catalog, and update the app icon and SwiftUI navigation without allowing user content into cleanup plans.

## Architecture Decisions

- `CrabCore` remains the only write-capable planning boundary and accepts only risk-A regenerable cache rules below `Library/Caches`.
- Protected path markers are rejected by rule validation even when a path name includes “Cache.”
- Cleanup execution receives an owner-state checker and rechecks the owning app immediately before each Trash move.
- `CrabArchive` is a separate read-only module with no dependency on `CleanPlan`, `CleanupExecutor`, or `TrashMoving`.
- Archive reminders scan only immediate children of an explicitly selected safe local root and provide reveal/open actions only.
- Real application catalog additions require exact leaves and explicit negative tests for models, conversations, credentials, and Application Support.

## Dependency Graph

```text
rule refusal tests → owner recheck → outcome accounting → cache catalog

archive scanner → read-only snapshot/refusal boundary → app state → SwiftUI mode

mascot source → pale-lavender icon source → iconset packaging
```

## Task List

### Phase 1: Cache safety hardening

- [x] Task 8: Reject protected cache-path markers in the strict rule contract.
- [x] Task 9: Recheck owning-app state at execution time.
- [x] Task 10: Report moved, skipped, and failed outcomes truthfully.

### Checkpoint: Cache boundary

- [x] New abuse tests fail before implementation and pass afterward.
- [x] Existing tests remain green and `swift build` succeeds.

### Phase 2: Read-only archive reminders

- [x] Task 11: Add protected-root validation and metadata-only stale-folder scanning.
- [x] Task 12: Add read-only archive snapshots and prove they cannot become clean plans.
- [x] Task 13: Add app-support state for selected roots and reminder results.

### Checkpoint: Archive boundary

- [x] Tests prove no archive API can move, rename, trash, or permanently delete a suggestion.
- [x] Protected, cloud-sync, linked, and recent roots fail closed.

### Phase 3: Native product surface and catalog

- [x] Task 14: Add the Cache / Archive Reminder native segmented workflow.
- [ ] Task 15: Add the first verified additional AI cache rules.
- [ ] Task 16: Add the remaining verified cache rules and catalog integrity tests.
- [x] Task 17: Build the mascot-on-lavender macOS app icon.

### Checkpoint: Complete

- [x] Full safety harness and release build pass.
- [x] Runtime verifies automatic cache scan, read-only archive reminders, Finder reveal, and zero default selection.
- [x] Bundle metadata, icon resources, and code signature verify.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Cache-named path contains user content | High | Hard marker refusal plus exact reviewed rules and risk/category gates |
| App relaunches during confirmation | High | Owner-state checks before preflight and immediately before every Trash move |
| Age is mistaken for delete safety | High | Archive module is read-only and structurally disconnected from Trash APIs |
| User chooses a broad or synced root | High | Reject protected exact roots, cloud-sync ancestors, symlinks, and home/system roots |
| New vendor path is wrong | High | Two-source corroboration, exact leaf, missing-path skip, and catalog negative tests |
| Result metrics overclaim recovery | Medium | Separate moved/skipped/failed accounting and never count missing paths as reclaimed |

## Open Questions

- None. The user approved the read-only archive boundary and the specifications on 2026-09-02.

# Implementation Plan: Installed Harness management

## Overview

Implement the approved `harness-catalog → harness-inventory → harness-overview → safe-uninstall` path. Token/project adapters remain fail-closed until a vendor-authorized aggregate source exists.

## Architecture decisions

- Bundle identifiers are the stable identity shared by cache rules, inventory, icons, running-state checks, and uninstall validation.
- Inventory reads application-bundle metadata and Spotlight last-used time only; it does not inspect user content.
- Cache scan output is intersected with installed inventory before constructing the result overview.
- Safe uninstall is a separate typed boundary that accepts a scanned installation record, revalidates it, and moves only its `.app` URL to Trash.

## Task list

1. Add the stable Harness catalog and installed-only overview filtering.
2. Add deterministic installed-app inventory with size and last-used metadata.
3. Build the native Harness overview and connect cache usage.
4. Add confirmation-driven, app-only Trash uninstall and refresh.
5. Add the explicit unavailable state for vendor Token aggregates.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Wrong app is uninstalled | High | Bundle-id, path-boundary, link, running-state, and identity revalidation |
| User data is mistaken for uninstall residue | High | Only the `.app` URL crosses the Trash boundary |
| Last-used metadata is absent | Medium | Show “暂无系统记录”; never substitute modification time |
| Token usage is fabricated | High | Explicit unavailable state until an authorized aggregate adapter exists |
# Project cleanup Trash execution

- Bind each discovered project to immutable filesystem identity and fresh scan evidence.
- Add a project-specific selection and Trash execution boundary; do not reuse cache plans.
- Expose only inactive projects as selectable, with no default selection.
- Require a second confirmation before execution and rescan after completion.
- Verify with filesystem fixtures, full tests, build, dangerous-API scan, bundle packaging, and launch smoke testing.
