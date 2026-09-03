# Spec: project-trash-execution safety boundary

## Objective

Allow only automatically discovered and AI-application-associated local project directories to reach Crab's Trash boundary after explicit selection and a second confirmation. Generated content outside an associated project root, conversations, session history, and arbitrary paths remain outside this boundary. Six-month inactivity and 1 GB size are informational labels, not eligibility gates.

## Tech Stack and Commands

- Swift 6 and Foundation; `CrabAppSupport` bridges verified `CrabArchive` inventory evidence to the shared `TrashMoving` boundary.
- `swift run crab-core-tests`
- `swift build`

## Project Structure and Style

- Metadata discovery and immutable project identity: `Sources/CrabArchive/ProjectInventory.swift`.
- Selection and project-specific execution: `Sources/CrabAppSupport/`.
- Second confirmation and result feedback: `Sources/CrabApp/`.
- `CrabArchive` does not depend on cache `CleanPlan` or `CleanupExecutor`.

## Testing Strategy

- Empty selections produce no executable project plan; recent projects remain selectable but receive an explicit warning.
- Reject protected roots, cloud-sync roots, AI `sessions` / `file-history` trees, chat databases, links, stale evidence, identity changes, and paths outside the scanned home root.
- Verify successful execution calls the Trash boundary only for the exact revalidated directory and never permanent deletion.
- Verify partial failure reports moved, skipped, and failed projects separately.

## Boundaries

- Always: start with no selection, warn when recent projects are selected, require a visible second confirmation, revalidate immediately before Trash, and provide a plain-language result.
- Never: `removeItem`, permanent deletion, overwrite, force, administrator privileges, cloud API deletion, chat-database edits, shell commands, or a reusable arbitrary-path deletion API.

## Success Criteria

- Project selections cannot be converted to cache `CleanPlan` entries.
- Only exact selected and revalidated project directories are passed to `TrashMoving`.
- Finder reveal remains available without mutation.
- AI conversations, session history, generated files outside an associated project root, and arbitrary paths never become executable cleanup candidates.
