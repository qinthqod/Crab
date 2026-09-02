# Spec: archive-suggestion-core

## Objective

Allow users to opt into metadata-only discovery of inactive local projects or generated-content folders. The user selects a parent folder; only its immediate child directories can become suggestions. The default inactivity threshold is 180 days and every result starts unselected.

## Tech Stack and Commands

- Swift 6, Foundation, Darwin metadata APIs; no dependencies or network.
- `swift run crab-core-tests`
- `swift build`

## Project Structure and Style

- Models and scanner: `Sources/CrabArchive/`.
- App selection state: `Sources/CrabAppSupport/`.
- Tests: `Sources/CrabCoreTests/main.swift` using temporary fixture roots.
- Value types are immutable and `Sendable`; errors identify invariants without reading content.

```swift
public struct ArchiveSuggestion: Equatable, Sendable {
    public let root: URL
    public let path: URL
    public let identity: FileIdentity
    public let latestActivity: Date
    public let logicalBytes: UInt64
}
```

## Testing Strategy

- RED tests first for protected-root rejection, direct-child scope, symlink rejection, metadata-only accounting, hard-link deduplication, 180-day cutoff, and zero selection.
- The scanner must not open regular files for content reads.

## Threat Model and Boundaries

- Trust boundary: user-selected path and every directory entry are untrusted.
- Always: standardize paths, `lstat` each component, reject links, cap traversal at 250,000 entries, and skip unreadable children.
- Never eligible as selected roots: `/`, the home directory itself, `~/Library`, `~/Desktop`, `/System`, `/Library`, `/Applications`, Trash, or a cloud-sync root.
- Never: infer inactivity from access time alone, read file contents, inspect chat databases, search the full disk, or default-select suggestions.

## Success Criteria

- An explicitly selected safe fixture root yields only inactive immediate children.
- Recent activity anywhere inside a child prevents it from being suggested.
- Protected roots, linked roots, and linked children fail closed.
- No mutation API exists in this module.

## Open Questions

- First release uses a fixed 180-day threshold in UI; 90/365-day choices may follow.
