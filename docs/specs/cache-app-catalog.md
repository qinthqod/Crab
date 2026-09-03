# Spec: cache-app-catalog

## Objective

Expand Crab's reviewed AI application catalog without expanding the cleanup boundary beyond exact, regenerable cache leaves. Initial targets are TRAE SOLO, Kimi Code Desktop, LM Studio, Ollama, Zed, and an additional Claude cache location. A rule ships only when its bundle identity and cache leaf are independently corroborated.

## Tech Stack and Commands

- Strict schema-v1 JSON rules loaded by `CrabCore`.
- `swift run crab-core-tests`
- `swift run crab rules validate Rules/AIApplications`
- `swift build`

## Project Structure and Style

- Production rules: `Rules/AIApplications/*.json`.
- Validation and negative cases: `Sources/CrabCoreTests/main.swift`.
- One exact leaf per rule; stable IDs end in `.v1`; user-facing Chinese explanations identify only regenerable data.

## Testing Strategy

- Validate the complete production directory.
- Assert every rule stays under `Library/Caches`.
- Assert stable IDs and exact leaves are unique.
- Assert model stores, conversations, credentials, `Application Support`, and arbitrary dot-directories are absent.
- Assert protected markers such as `sessions`, `file-history`, `history`, `models`, `credentials`, `tokens`, `Local Storage`, `IndexedDB`, `Containers`, and `Group Containers` are rejected even when nested under a path whose name contains “Cache.”
- Assert cleanup eligibility comes from category, risk, exact leaf, and owner evidence—not size or filename.

## Boundaries

- Always: exact cache leaves, Trash action, stopped-app requirement, fail closed.
- Always: every installed supported product remains visible in scan results. A desktop or command-line product with no reviewed cache rule is labelled “user data protected,” not “clean,” and exposes no selection or cleanup action.
- Ask first: any non-cache leaf or local model rule.
- Never: rules for `.ollama/models`, `.lmstudio/models`, chat databases, project folders, credentials, logs containing prompts, or an entire application-support directory.
- Never: infer safety from `Cache`, `tmp`, `Temp`, `.db`, or `.sqlite` in a name.

## Success Criteria

- At least five additional reviewed cache leaves validate and scan safely when present.
- Missing applications remain silently skipped.
- Existing rules and all safety tests continue to pass.
- Installed CLI products such as Claude Code and DeepSeek Harness appear even when their only known local directories contain sessions, settings, credentials, plugins, or other protected data.
- Execution rechecks that the owning app is still stopped immediately before crossing the Trash boundary.
- Receipts distinguish moved, skipped, and failed entries; a missing path is not counted as reclaimed.

## Open Questions

- A candidate without two trustworthy path signals remains research-only and does not ship.
