#!/bin/sh
set -eu

scan_roots="Sources/CrabCore Sources/CrabArchive Sources/CrabCLI Sources/CrabAppSupport Sources/CrabApp"
dangerous_pattern='FileManager[^\n]*removeItem|\.trashItem|(^|[^A-Za-z.])(unlink|rmdir|remove|rename|system)\(|Process\('

if rg -n --glob '*.swift' \
  --glob '!SystemTrashMover.swift' \
  --glob '!HarnessUpdate.swift' \
  --glob '!HarnessUsage.swift' \
  "$dangerous_pattern" $scan_roots; then
  echo "Dangerous filesystem or process API found outside a reviewed boundary." >&2
  exit 1
fi

trash_api_count="$(rg -c 'FileManager\.default\.trashItem' Sources/CrabCore/SystemTrashMover.swift || true)"
if [ "$trash_api_count" != "1" ]; then
  echo "The reviewed Trash boundary must contain exactly one system Trash call." >&2
  exit 1
fi

update_process_count="$(rg -c 'let process = Process\(\)' Sources/CrabAppSupport/HarnessUpdate.swift || true)"
usage_process_count="$(rg -c 'let process = Process\(\)' Sources/CrabAppSupport/HarnessUsage.swift || true)"
if [ "$update_process_count" != "1" ] || [ "$usage_process_count" != "1" ]; then
  echo "Reviewed process boundaries changed; inspect Harness update and usage execution before release." >&2
  exit 1
fi

if rg -n 'TrashMoving|CleanPlan|CleanupExecutor|RuleAction' Sources/CrabArchive; then
  echo "The read-only archive module must remain disconnected from cleanup execution types." >&2
  exit 1
fi

echo "Dangerous API check passed."
