# Spec: Harness management

## Objective

Crab should show only supported Harness applications that are actually installed on this Mac. Each installed Harness exposes its application version, application-bundle size, currently discovered cache size, last-opened timestamp, and a human-readable inactivity interval. A user may uninstall the Harness application bundle after explicit confirmation.

## Capability map

| Module id | Responsibility | Depends on |
|---|---|---|
| `harness-catalog` | Stable supported-product identity, display names, bundle identifiers | — |
| `harness-inventory` | Locate installed app bundles and collect metadata-only usage signals | `harness-catalog` |
| `harness-overview` | Show installed Harness status and filter cache results to installed products | `harness-inventory` |
| `safe-uninstall` | Revalidate and move only the selected `.app` bundle to Trash | `harness-inventory` |
| `usage-adapters` | Metadata-only project/conversation counts and vendor-authorized Token aggregates | `harness-catalog`, `project-inventory` |
| `residue-catalog` | Exact, reviewed per-application residual leaves and risk classification | `harness-catalog` |
| `residue-review` | Metadata-only scan, explicit selection, short-lived plan, and revalidated Trash execution | `residue-catalog`, `safe-uninstall` |

Build order: `harness-catalog` → `harness-inventory` → `harness-overview` → `safe-uninstall` → `usage-adapters`.

## Product contract

- Cache results include only installed supported Harness applications. An installed Harness with no cache remains visible as “干净”.
- Harness management shows last opened time, time since last use, app version, app-bundle size, cache size, and combined local disk usage.
- Last opened time comes from public Spotlight metadata and may truthfully be unavailable.
- Project totals come from Crab's metadata-only project inventory and are attributed to the matching installed application.
- Conversation totals count only known session record files in a product's public local session directory. Crab does not open those records or read prompts and responses.
- Token totals may come only from an explicit vendor-provided aggregate file or official API. They are never inferred from conversation content. When no trustworthy aggregate is available, the metric is hidden.
- Uninstall requires explicit confirmation and moves only the revalidated application bundle to Trash.
- Uninstall itself never removes caches, Application Support, preferences, chats, projects, generated files, models, credentials, account data, or Crab scan history.
- After the application bundle reaches Trash, Crab may scan only reviewed exact residual leaves associated with that application's bundle identifier and catalog entry.
- Residual scan results always begin unselected. Regenerable caches/logs and user-data-bearing preferences/Application Support are visibly separated.
- Residual cleanup is a second, optional action. It requires explicit item selection and a second confirmation, then moves only the revalidated selected leaves to Trash.
- Application Support, preferences, web storage, and other user data are never recommended or selected automatically. Projects, chats, generated files, models, credentials, Containers, Group Containers, Photos, Music, cloud-sync roots, and arbitrary name matches are never admitted to the residual catalog.
- Running Harness applications cannot be uninstalled.
- Crab does not check or install application updates.

## Tech stack and commands

- Swift 6, SwiftUI, AppKit, Foundation, CoreServices Spotlight metadata.
- Test: `swift run crab-core-tests`
- Build: `swift build`
- Package: `scripts/build-app-bundle.sh`
- Safety: `scripts/check-dangerous-apis.sh`

## Project structure

- `Sources/CrabAppSupport`: catalog, inventory value types, scanners, uninstall safety boundary.
- `Sources/CrabApp`: system state, confirmation flow, and SwiftUI Harness overview.
- `Sources/CrabCoreTests/main.swift`: deterministic catalog, inventory, filtering, and uninstall tests.

## Testing strategy

- Unit tests prove catalog uniqueness and installed-only overview filtering.
- Temporary fake `.app` bundles prove inventory metadata collection without depending on the developer Mac.
- Fake Trash movers prove safe uninstall moves exactly one app bundle and rejects running, mismatched, linked, or out-of-bound targets.
- Residual fixtures prove empty-by-default selection, exact-leaf admission, file/directory metadata scanning, symlink rejection, traversal/mount rejection, identity binding, expiry, and immediate pre-Trash revalidation.
- Release verification covers build, signature, dangerous-API scan, and launch responsiveness.

## Boundaries

- Always: metadata-only inventory, count fixed record names without opening them, explicit confirmation, Trash rather than permanent deletion, revalidate immediately before uninstall and each residual move.
- Ask first: adding vendor credentials or connecting a cloud usage API.
- Never: parse chat/session/project contents for usage, estimate Token usage from content, follow symbolic links while counting, automatically select associated user data, accept arbitrary residual paths, uninstall arbitrary paths, or elevate privileges silently.

## Success criteria

- Unsupported or uninstalled Harness products do not appear in cache results or Harness management.
- Installed Harness products show truthful metadata and local disk usage.
- Supported installed products show truthful project and conversation counts; unavailable Token totals are hidden.
- Uninstalling moves only the `.app` bundle. Associated data remains untouched unless the user separately selects reviewed residual leaves and confirms moving them to Trash.
- Unknown Token usage is hidden rather than estimated.
- All tests, builds, safety checks, bundle validation, and signature checks pass.
