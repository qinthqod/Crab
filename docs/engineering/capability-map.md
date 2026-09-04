# Capability Map: Crab

| Module id | Responsibility | Depends on |
|---|---|---|
| `rule-contract` | Versioned, declarative, code-free allowlist rules and validation | — |
| `safe-scan` | Metadata-only traversal of exact rule leaves without following symbolic links | `rule-contract` |
| `cache-app-catalog` | Verified cache-only rules for additional AI applications; excludes models, chats, projects, credentials, and Application Support | `rule-contract`, `safe-scan` |
| `immutable-plan` | Convert explicit user selections into expiring, immutable plans bound to file identity | `safe-scan` |
| `trash-execution` | Revalidate a plan and move targets to Trash without overwrite or permanent-delete fallback | `immutable-plan` |
| `archive-suggestion-core` | Scan only user-selected parent folders, classify immediate child folders by metadata-only inactivity, and default to zero selection | — |
| `archive-plan` | Produce a content-free, read-only review snapshot for stale-content suggestions; it has no cleanup action | `archive-suggestion-core` |
| `archive-trash-execution` | Convert explicit project selections into expiring plans, revalidate them, and move them to Trash after second confirmation; six-month and large-project signals remain labels only | `project-inventory`, `project-attribution`, `trash-execution` |
| `project-inventory` | Automatically discover local projects from metadata-only directory markers after explicit Project Cleanup navigation | `harness-inventory` |
| `project-attribution` | Associate each discovered project with installed AI applications using explicit project-local markers | `project-inventory`, `harness-catalog` |
| `runtime-optimization` | On-demand, whole-Mac refresh of a fixed allowlist of rebuildable system services; never deletes files or closes third-party apps | — |
| `audit-restore` | Store content-free receipts and restore without overwriting an existing path | `trash-execution` |
| `cli-surface` | Developer-facing scan, inspect, plan, dry-run, rules, and history commands | `safe-scan`, `immutable-plan`, `audit-restore` |
| `mac-app` | Native SwiftUI cache cleanup and opt-in archive-suggestion experience | `safe-scan`, `immutable-plan`, `archive-trash-execution`, `audit-restore` |
| `brand-assets` | Crab mascot on a pale-lavender app icon and matching bundled macOS icon resources | — |

Build order: `rule-contract` → `safe-scan` → `cache-app-catalog`; `harness-inventory` → `project-inventory` → `project-attribution` → `archive-trash-execution`; `runtime-optimization`; then `mac-app` and `brand-assets`; finally `audit-restore`.

Project Cleanup starts with zero selection. Every project requires explicit selection, a second confirmation, fresh metadata evidence, and immediate identity revalidation before Trash. Recent and large-project signals are informational labels only.

The native application now covers `rule-contract`, `safe-scan`, `immutable-plan`, `trash-execution`, and `mac-app`. The immutable plan remains an internal safety boundary; the UI exposes only review, explicit selection, confirmation, and Move to Trash. Permanent deletion and automatic selection remain structurally unavailable.

Crab never discovers or inspects cloud conversation databases. Generic generated-content suggestions remain read-only. Only local project roots attributed through explicit AI markers and project boundaries can enter project cleanup; home, Library, system, application, Trash, cloud-sync, linked, changed, and arbitrary paths remain ineligible.
