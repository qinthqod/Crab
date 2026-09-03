# Runtime Optimization

## Objective

Help users reclaim active memory held by supported AI desktop applications
without pretending that macOS needs a generic "memory cleaner." Crab measures
the running applications it already knows, explains their footprint, and lets
the user explicitly request a normal application quit.

## User Flow

1. Opening **运行优化 / Optimize** starts a lightweight process snapshot.
2. The result lists only supported AI desktop applications that are currently
   running, ordered by estimated resident memory.
3. No application is selected by default. The user selects one or more rows.
4. Crab shows a second confirmation naming the selected applications and the
   estimated memory they currently hold.
5. Crab revalidates each bundle identifier and process identifier, then sends
   the standard macOS terminate request. Applications may show their own save
   dialogs or refuse to quit.
6. Crab refreshes the snapshot and reports requests and skips separately.

The menu-bar menu exposes **优化运行内存… / Optimize Memory…**. It opens this
same review flow and never quits applications immediately from the menu.

## Measurement

- The snapshot uses macOS's read-only `libproc` interfaces and retains only PID,
  parent PID, and resident set size. It does not launch a shell command or read
  process arguments.
- A desktop application's estimate includes its recorded root process and
  descendants, so Electron helper processes are not silently omitted.
- Unrelated processes and command-line arguments are neither collected nor
  displayed.
- Memory values are point-in-time estimates, not a promise of bytes that macOS
  will make immediately available.

## Safety Boundaries

- Scope is limited to exact bundle identifiers in `HarnessCatalog`.
- Selection always starts empty and cannot contain an app outside the snapshot.
- Execution plans expire after 30 seconds and bind exact process identifiers.
- A changed, exited, or relaunched process is skipped.
- Crab never uses `kill -9`, `forceTerminate`, `purge`, administrator access, or
  a privileged helper.
- Crab never terminates itself, system services, security software, or unknown
  processes.
- No files, caches, conversations, projects, models, credentials, or settings
  are changed by Runtime Optimization.
- Optimization runs only when requested and has no background polling cost.

## Verification

- Unit tests cover process-tree accounting, exclusion of unrelated processes,
  zero default selection, stale-PID refusal, plan expiry, and graceful-request
  receipts.
- App tests and smoke tests prove the new page does not block launch or the main
  actor.
- The menu item opens the review page instead of executing immediately.
