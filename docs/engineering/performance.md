# Crab Performance Architecture

## Budgets

- The main window must remain responsive while filesystem work is active.
- Application Management should show the installed-app list within 1.5 seconds on the reference Mac.
- No full-home project traversal may run as a dependency of Application Management or Cache Cleaning.
- Conversation and Token metrics must inspect metadata only and must not parse transcript contents.
- Recursive application-size measurement must run after the application list is visible.

## September 2026 investigation

The reported freeze was reproduced as a long loading state, not a main-thread deadlock. A 15-second process timeline measured 0.6% average CPU and 20.6% peak CPU. Thread samples showed the main thread waiting normally in the AppKit event loop.

A second Loading-specific investigation found two navigation paths could request the same inventory simultaneously: the menu-bar command initiated a refresh directly and the main window initiated another refresh when the selected mode changed. The previous admission condition also allowed a second request while `.loading` whenever usage data was still empty. The refresh state is now single-flight, and mode loading is owned only by the main window lifecycle.

The original Application Management pipeline was serial:

1. discover applications and recursively measure every installed bundle;
2. scan the authorized home directory for projects;
3. count conversation metadata and query trusted Token metadata;
4. publish the first usable list.

Measured on the reference Mac:

| Stage | Baseline |
| --- | ---: |
| Installed-app discovery plus recursive sizes | 4.329 s |
| Full-home project inventory | 10.144 s |
| Conversation and Token metadata | 0.097 s |
| First-result blocking work | about 14.57 s |

## Current pipeline

Application Management now uses progressive enrichment:

1. lightweight app and CLI discovery without Spotlight activity lookup or recursive sizes;
2. conversation and trusted Token metadata;
3. publish the installed-app list;
4. enrich recent-use dates in the background;
5. enrich installed sizes in the background.

The project inventory is reused only when a completed in-memory Project Cleaning result already exists. Application Management never starts a full-home project scan.

Measured stage costs after the split:

| Stage | Result | Scheduling |
| --- | ---: | --- |
| Lightweight app discovery | 0.168 s | first result |
| Conversation and Token metadata | 0.100 s | first result |
| Recent-use metadata | about 1.9 s | background |
| Recursive installed sizes | 3.7–4.9 s | background |
| Full-home project inventory | 9–11 s | Project Cleaning only |

The optimized lightweight critical path measured about 0.268 seconds before SwiftUI publication. In the native cold-start interaction check, the click returned in 0.719 seconds and the automation capture reached the fully enriched stable state in 3.066 additional seconds. The automation waits for visible progress indicators to settle, so this latter number represents completed enrichment rather than first-list paint. The UI remains interactive and shows explicit progressive states while dates or sizes are still being enriched.

After the single-flight correction, unified performance logging recorded exactly one cold-start refresh and `inventoryState = ready` after 0.190 seconds on the reference Mac.

## Regression guards

- `HarnessInventoryScanner.scan(..., measureInstalledBytes: false)` must not traverse bundle contents and returns zero as the pending-size sentinel.
- `measuringLastUsedDates` and `measuringInstalledBytes` are explicit enrichment phases.
- Application, project, and cache workflows use lightweight inventory discovery when they only need installed identities.
- Repeated navigation cannot start another inventory refresh while the current refresh is loading or already ready; only an explicit forced retry may replace it.
- Codex Token usage uses a fixed read-only SQLite metadata query and never scans JSONL transcripts.

## Optimization ledger

| Change | Before → after | Verdict |
| --- | --- | --- |
| Remove full project scan from Application Management | 14.57 s blocking → project scan not on critical path | kept |
| Defer Spotlight recent-use lookup | about 2.1 s discovery → 0.168 s lightweight discovery | kept |
| Defer recursive bundle-size measurement | 4.329 s on critical path → background enrichment | kept |
| Parallelize all filesystem walks | not attempted | rejected in advance; parallel disk traversal increases contention and weakens predictable safety limits |
