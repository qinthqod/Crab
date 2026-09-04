# Runtime Optimization

## Objective

Run a small, reviewed set of macOS maintenance actions that refresh rebuildable
system state. This feature serves the whole Mac rather than only supported AI
applications. It does not pretend to "release RAM", close third-party apps, or
delete user files.

## User Flow

1. Opening **运行优化 / Optimize Mac** shows an idle home page. Nothing runs
   automatically.
2. The page names the reviewed tasks and explains that Finder windows may
   briefly refresh.
3. **开始运行 / Start** enters a dedicated loading page with the animated Crab
   mascot and the current task.
4. Tasks continue independently when one is unavailable, fails, or times out.
5. The result page shows one receipt per task and offers **重新运行 / Run Again**
   and **返回首页 / Back**.

The menu-bar menu exposes **运行优化… / Optimize Mac…** and opens the idle page;
it never starts maintenance from the menu by itself.

## Default Task Catalog

- **Quick Look**: `/usr/bin/qlmanage -r` resets the Quick Look server and its
  generator cache.
- **App Associations**: the fixed system `lsregister -gc` executable asks
  LaunchServices to garbage-collect stale registration state.
- **Finder**: `/usr/bin/killall -HUP Finder` restarts only the current user's
  Finder shell. This can briefly refresh Finder windows.

DNS cache flushing is intentionally excluded. The macOS `dscacheutil` manual
states that whole-cache flushing should be used only in extreme cases, and the
complete DNS refresh used by Mole also requires administrator access.

## Safety Boundaries

- Scope is limited to the immutable `MacOptimizationCatalog`; callers cannot
  supply an executable or arguments.
- Commands use fixed absolute system paths and fixed arguments. Crab never uses
  a shell, `sudo`, administrator access, or a privileged helper.
- Crab never closes third-party apps, AI apps, security software, or arbitrary
  processes. Only the fixed Finder restart task signals a named system shell.
- `Process.terminate()` is reserved for a timed-out maintenance child started by
  Crab itself; it is never applied to another existing process.
- No user files, conversations, projects, models, credentials, or settings are
  read or deleted by Runtime Optimization.
- Optimization runs only when requested and has no background polling cost.

## Verification

- Unit tests lock the task order, executable allowlist, no-admin policy, and
  continue-on-failure receipts.
- The dangerous-API gate permits exactly one reviewed `Process` boundary and
  rejects shells, `sudo`, arbitrary kill APIs, and app termination APIs.
- Every task has a finite timeout and executes off the main actor.
- The menu item opens the home page instead of executing immediately.
