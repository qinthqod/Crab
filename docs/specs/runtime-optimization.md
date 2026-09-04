# Runtime Optimization

## Objective

Diagnose the conditions that actually make a Mac feel slow, then run only a
small, reviewed set of relevant maintenance actions. This feature serves the
whole Mac rather than only supported AI applications. It does not pretend to
"release RAM", close third-party apps, or delete user files.

The approved capability boundaries and dependency order are recorded in
`runtime-optimization-map.md`.

## User Flow

1. Opening **运行优化 / Optimize Mac** shows an idle home page. Nothing runs
   automatically.
2. **开始运行 / Start** immediately enters a dedicated loading page with the
   animated Crab mascot. Diagnostics and maintenance never block the main actor.
3. Crab samples the system for a bounded interval and locally derives disk,
   memory-pressure, swap, uptime, thermal, and sustained-process findings.
4. Crab automatically refreshes only Quick Look and Launch Services. Tasks
   continue independently when one is unavailable, fails, or times out.
5. The result page separates health findings, completed maintenance, optional
   system refreshes, and mounted disk images.
6. Finder and Dock refreshes run only after the user clicks the corresponding
   action. Ejecting a mounted disk image requires a second confirmation and a
   fresh identity check.
7. The result page offers **重新运行 / Run Again** and **返回首页 / Back**.

The menu-bar menu exposes **运行优化… / Optimize Mac…** and opens the idle page;
it never starts maintenance from the menu by itself.

## Runtime Diagnosis

- Diagnostics stay entirely on the Mac and are discarded when a new run starts.
- The snapshot contains aggregate system values and short process display names;
  it never reads process arguments, environment variables, open files, or user
  document contents.
- Process activity uses two native samples separated by no more than one second.
- At most five sustained high-resource processes are shown.
- Memory health follows macOS memory-pressure state and swap usage, not the
  misleading amount of unused RAM. Cached memory is never described as waste.
- A disk warning appears below 15 GB or 10% available space; a critical warning
  appears below 5 GB or 5%.
- Uptime is informational until 14 days, and thermal state is reported only when
  elevated.

## Maintenance Catalog

- **Quick Look**: `/usr/bin/qlmanage -r` resets the Quick Look server and its
  generator cache.
- **App Associations**: the fixed system `lsregister -gc` executable asks
  LaunchServices to garbage-collect stale registration state.
- **Finder** (optional): `/usr/bin/killall -HUP Finder` restarts only the current
  user's Finder shell. This can briefly refresh Finder windows.
- **Dock** (optional): `/usr/bin/killall -HUP Dock` restarts only the current
  user's Dock. This can briefly hide and restore the Dock.

DNS cache flushing is intentionally excluded. The macOS `dscacheutil` manual
states that whole-cache flushing should be used only in extreme cases, and the
complete DNS refresh used by Mole also requires administrator access.

## Safety Boundaries

- Scope is limited to the immutable `MacOptimizationCatalog`; callers cannot
  supply an executable or arguments.
- Commands use fixed absolute system paths and fixed arguments. Crab never uses
  a shell, `sudo`, administrator access, or a privileged helper.
- Crab never closes third-party apps, AI apps, security software, or arbitrary
  processes. Only explicit Finder and Dock actions signal those named system
  shells.
- `Process.terminate()` is reserved for a timed-out maintenance child started by
  Crab itself; it is never applied to another existing process.
- No user files, conversations, projects, models, credentials, or settings are
  read or deleted by Runtime Optimization.
- A mounted image can be ejected only when its mount URL is present in a fresh
  `hdiutil info -plist` result and the user confirms the exact displayed item.
- Optimization runs only when requested and has no background polling cost.

## Verification

- Unit tests lock the automatic/optional task split, executable allowlist,
  no-admin policy, diagnostic thresholds, bounded result counts, mounted-image
  parsing/revalidation, and continue-on-failure receipts.
- The dangerous-API gate permits exactly one reviewed `Process` boundary and
  rejects shells, `sudo`, arbitrary kill APIs, and app termination APIs.
- Every task has a finite timeout and executes off the main actor.
- The menu item opens the home page instead of executing immediately.
