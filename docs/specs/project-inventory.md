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

- RED tests first for explicit-marker association, path deduplication, installed-application filtering, symlink refusal, protected-directory skipping, metadata-only handling of unreadable file contents, inactivity classification, and traversal caps.
- App state must enter loading only after Project Cleanup is selected and finish with grouped results whose eligible items start unselected.
- Runtime verification covers selection, a disabled empty-selection action, a second confirmation, safe Trash execution, result feedback, and Finder reveal.

## Threat Model and Boundaries

- Trust boundary: every filesystem entry and application marker is untrusted.
- Always: use `lstat`, never follow symbolic links, stay on the starting filesystem, skip `~/Library`, Applications, Trash, cloud-sync and dependency/build directories, cap traversal, and run off the main actor.
- Association evidence: an exact AI marker such as `.claude`, `CLAUDE.md`, `.cursor`, `.cursorrules`, `.codex`, `AGENTS.md`, `.trae`, `.windsurf`, `.zed`, or `.dsh` must coexist with a project boundary such as `.git`, `Package.swift`, `package.json`, or another recognized build manifest. Never infer an application from project contents, and never treat the scan root itself as a project.
- Multiple markers are retained as related applications; the most recently modified explicit marker determines the single primary group so a project path appears once.
- Project Trash eligibility requires all of: automatic association with an installed AI application, explicit selection, scan evidence no older than ten minutes, a path strictly below the scanned home root, a directory identity match immediately before execution, and a second user confirmation. Inactivity for at least 180 days and size of at least 1 GB are informational labels only.
- Never: read regular-file contents, inspect Git history, parse chat/session databases, request Full Disk Access, scan system or cloud data, permanently delete, follow links, accept arbitrary authorization roots, or select projects by default.

## Success Criteria

- The first entry shows a clear one-time authorization screen. After the home-directory bookmark is saved, entering Project Cleanup automatically begins scanning without another folder chooser.
- Results contain each project path once and are grouped by an installed AI application.
- Every row shows path, metadata-derived latest activity, approximate logical size, and an inactive indicator after 180 days.
- Unreadable/protected entries are skipped without blocking the complete scan.
- Recent projects remain view-only. Inactive projects can be selected individually or by application and moved to the macOS Trash after a second confirmation.
- A changed, missing, linked, expired, outside-root, protected, cloud-backed, or otherwise ineligible project is skipped or refused rather than moved.
- Cache cleanup and application uninstall safety boundaries remain unchanged.

## Open Questions

- External volumes and vendor-authorized session-history adapters remain out of scope for this slice. The automatic scan covers the current user's local home directory while excluding protected and cloud-backed areas.
