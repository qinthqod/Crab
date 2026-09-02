# Spec: mac-app workflows

## Objective

Provide three focused modes: “缓存清理”, “应用管理”, and “项目清理”. No scan starts when Crab opens. Project Cleanup automatically inventories local projects after explicit navigation, groups them by installed AI application, and permits any associated project to be selected and moved to Trash after a second confirmation. Projects unused for six months and projects at least 1 GB are labels only.

## Tech Stack and Commands

- SwiftUI and AppKit on macOS 14+.
- `swift run crab-core-tests`
- `swift build`
- `./scripts/build-app-bundle.sh`

## Project Structure and Style

- App state: `Sources/CrabApp/AppModel.swift`.
- Cache UI: existing `ScanResultView` and `ProductGroupView`.
- Archive UI: new focused views under `Sources/CrabApp/`.
- Use native controls, SF Symbols, the existing ocean-purple token, and one level of grouping.

## Testing Strategy

- Core behavior is covered below SwiftUI in `CrabArchive` and `CrabAppSupport` tests.
- Runtime checks: launch on the home page, switch modes, observe automatic project scanning, inspect grouped results, verify zero default selection, select inactive projects, open and cancel the second confirmation, and rescan.

## Boundaries

- Always: explain the six-month and large-project labels, show the full local path, start every project unselected, use Trash rather than permanent deletion, and revalidate immediately before execution.
- Never: call a conversation “unused,” promise cloud deletion, auto-select, place projects in the cache total, accept arbitrary paths, or expose permanent deletion.

## Success Criteria

- Cache cleanup behavior remains unchanged and real.
- Project mode automatically scans after navigation and has loading, empty, failure, and grouped result states.
- Results show application attribution, path, size, last activity, file count, and inactivity status.
- Inactive project rows offer explicit selection and Finder reveal. The action remains disabled until selection and always opens a second confirmation.
