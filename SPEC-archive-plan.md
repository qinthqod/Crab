# Spec: archive-plan

## Objective

Create a content-free, read-only review snapshot bound to the user-selected root, exact child path, filesystem identity, latest activity, and scan evidence. This snapshot exists only to explain and revisit suggestions; it is not a cleanup plan.

## Tech Stack and Commands

- Swift 6 value types in `Sources/CrabArchive/`.
- `swift run crab-core-tests`
- `swift build`

## Project Structure and Style

- `ArchivePlan.swift` and `ArchivePlanBuilder.swift` under `Sources/CrabArchive/`.
- Public builders accept suggestions only and expose no write action or arbitrary destination path.

## Testing Strategy

- Unknown, recent, linked, or outside-root suggestions are rejected.
- Snapshot IDs are unique and expire after ten minutes.
- Entries bind root identity and child identity but contain no `RuleAction`.
- Compile-time/API tests prove no conversion exists from an archive suggestion to `CleanPlan` or `PlanEntry`.

## Boundaries

- Always: direct-child relationship, safe-root evidence, and a fresh snapshot ID.
- Never: implicit “select all,” arbitrary URL lists, expired evidence, Trash instructions, or permanent-delete instructions.

## Success Criteria

- Only verified stale suggestions enter a read-only review snapshot.
- Any inconsistency fails the snapshot.
- No archive snapshot can be executed by `CleanupExecutor`.
