# Runtime Optimization

## Objective

Help users understand active memory held by supported AI desktop applications
without pretending that macOS needs a generic "memory cleaner" or that Crab can
force another application to release private memory while it remains running.
Crab measures the running applications it already knows and explains their
point-in-time footprint through a read-only view.

## User Flow

1. Opening **运行优化 / Optimize** starts a lightweight process snapshot.
2. The result lists only supported AI desktop applications that are currently
   running, ordered by estimated resident memory.
3. Each row shows the application, running duration when available, and the
   estimated resident memory held by its process tree.
4. The page explains that the snapshot is read-only and offers only refresh.
5. Crab never presents a selection, quit, pause, kill, or fake memory-release
   action.

The menu-bar menu exposes **查看运行占用… / View Runtime Usage…** and opens the
same read-only view.

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
- Crab never uses `terminate`, `kill`, `forceTerminate`, `purge`, process
  suspension, administrator access, or a privileged helper for this feature.
- Crab never closes or ends supported apps, their child processes, itself,
  system services, security software, or unknown processes.
- No files, caches, conversations, projects, models, credentials, or settings
  are changed by Runtime Optimization.
- Optimization runs only when requested and has no background polling cost.

## Verification

- Unit tests cover process-tree accounting and exclusion of unrelated processes.
- The dangerous-API gate fails if runtime optimization introduces termination,
  process launching, or force-quit APIs.
- App tests and smoke tests prove the new page does not block launch or the main
  actor.
- The menu item opens the review page instead of executing immediately.
