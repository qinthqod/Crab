# Spec: project-inventory and project-attribution

## Objective

The first time the user enters Project Cleanup, Crab asks the user to authorize their exact local home directory and stores a security-scoped bookmark. Later scans restore that authorization without showing the folder picker again. Scanning remains metadata-only; write access is used only after the user explicitly selects inactive projects and confirms moving them to the macOS Trash.

## Tech Stack and Commands

- Swift 6, Foundation and Darwin metadata APIs; no dependency and no network access.
- Test: `swift run crab-core-tests`
- Build: `swift build`
- Package: `./scripts/build-app-bundle.sh`

## Project Structure and Style

- Metadata scanner and immutable value types: `Sources/CrabArchive/ProjectInventory.swift`.
- Application marker catalog: `Sources/CrabAppSupport/ProjectAssociationCatalog.swift`.
- Background workflow: `Sources/CrabApp/AppModel.swift`.
- Native grouped results: `Sources/CrabApp/ArchiveReminderView.swift`.
- Deterministic filesystem tests: `Sources/CrabCoreTests/main.swift`.

```swift
public struct ProjectInventoryItem: Equatable, Sendable {
    public let path: URL
    public let primaryAppID: String
    public let relatedAppIDs: [String]
    public let latestActivity: Date
    public let logicalBytes: UInt64
}
```

## Testing Strategy

- Regression tests cover explicit-marker association, path deduplication, installed-application filtering, project-root/ancestor symlink refusal, nested-link no-follow handling, protected-directory skipping, metadata-only inspection, and cancellation.
- App state must enter loading only after Project Cleanup is selected and finish with grouped results whose eligible items start unselected.
- Runtime verification covers selection, a disabled empty-selection action, a second confirmation, safe Trash execution, result feedback, and Finder reveal.

## Threat Model and Boundaries

- Trust boundary: every filesystem entry and application marker is untrusted.
- Always: use `lstat`, never follow symbolic links, stay on the starting filesystem, and run off the main actor. Discovery excludes protected, cloud-sync and dependency/build locations; inspecting an identified project includes its dependencies and build output. Normal scans finish without default entry/depth caps; explicitly budgeted callers keep fail-closed partial-result behavior.
- Cleanup boundary: only an associated project's actual directory tree is in scope. A nested symbolic-link entry belongs to that tree; its destination is not added to the scan or cleanup set, whether internal, external, missing, cyclic, or a media library. Record the raw destination and link identity without opening the target; count only the link's own metadata bytes. Actual ordinary files under the project root are still counted by normal traversal.
- Before Trash, compare every nested link's path, raw destination, device, inode, size, modification time and change time against the scan snapshot, in addition to existing root/content checks. A replaced link invalidates the snapshot even if project totals are unchanged. Move the selected root directory through the existing Trash API, never move resolved link targets individually.
- Root and ancestor links remain forbidden; an actual protected directory, mount boundary or unreadable content is not made safe by application association. Such exceptions include concrete locations and next-step advice. Normal nested links do not block selection or cleanup.
- Association evidence: an exact AI marker such as `.claude`, `CLAUDE.md`, `.cursor`, `.cursorrules`, `.codex`, `AGENTS.md`, `.trae`, `.windsurf`, `.zed`, or `.dsh` must coexist with a project boundary such as `.git`, `Package.swift`, `package.json`, or another recognized build manifest. Never infer an application from project contents, and never treat the scan root itself as a project.
- Multiple markers are retained as related applications; the most recently modified explicit marker determines the single primary group so a project path appears once.
- Project Trash eligibility requires all of: automatic association with an installed AI application, explicit selection, scan evidence no older than ten minutes, a path strictly below the scanned home root, a directory identity match immediately before execution, and a second user confirmation. Inactivity for at least 180 days and size of at least 1 GB are informational labels only.
- Never: read regular-file contents, inspect Git history, parse chat/session databases, request Full Disk Access, scan system or cloud data, permanently delete, follow links, accept arbitrary authorization roots, or select projects by default.

## Success Criteria

- The first entry shows a clear one-time authorization screen. After the home-directory bookmark is saved, entering Project Cleanup automatically begins scanning without another folder chooser.
- The exact security-scoped URL returned by the folder picker or bookmark resolver is retained through validation and scanning; Crab must not reconstruct an equivalent path and discard the attached grant. If scoped access cannot start, scanning stops and shows a reauthorization action instead of remaining on an unchanged screen.
- Results contain each project path once and are grouped by an installed AI application.
- Every row shows path, metadata-derived latest activity, approximate logical size, and an inactive indicator after 180 days.
- Unreadable/protected entries are skipped without blocking the complete scan.
- Both recent and inactive projects can be explicitly selected and moved to Trash after a second confirmation; age and size are labels, not permission to delete.
- A changed, missing, root-linked, expired, outside-root, protected, cloud-backed, or otherwise ineligible project is skipped or refused with actionable advice. A valid associated project containing only ordinary nested links remains eligible.
- Cache cleanup and application uninstall safety boundaries remain unchanged.

## Open Questions

- External volumes and vendor-authorized session-history adapters remain out of scope for this slice. The automatic scan covers the current user's local home directory while excluding protected and cloud-backed areas.
