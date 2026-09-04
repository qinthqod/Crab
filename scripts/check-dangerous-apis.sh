#!/bin/sh
set -eu

scan_roots="Sources/CrabCore Sources/CrabArchive Sources/CrabCLI Sources/CrabAppSupport Sources/CrabApp"
dangerous_pattern='FileManager[^\n]*removeItem|\.trashItem|unmountAndEjectDevice|(^|[^A-Za-z.])(unlink|rmdir|remove|rename|system)\(|Process\('

count_matches() {
  pattern="$1"
  file="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -c "$pattern" "$file" || true
  else
    grep -Ec "$pattern" "$file" || true
  fi
}

if command -v rg >/dev/null 2>&1; then
  dangerous_matches() {
    rg -n --glob '*.swift' \
      --glob '!SystemTrashMover.swift' \
      --glob '!HarnessUpdate.swift' \
      --glob '!HarnessUsage.swift' \
      --glob '!CrabAppInstaller.swift' \
      --glob '!MacOptimization.swift' \
      --glob '!MountedDiskImageEjector.swift' \
      "$dangerous_pattern" $scan_roots
  }
else
  dangerous_matches() {
    find $scan_roots -type f -name '*.swift' \
      ! -name 'SystemTrashMover.swift' \
      ! -name 'HarnessUpdate.swift' \
      ! -name 'HarnessUsage.swift' \
      ! -name 'CrabAppInstaller.swift' \
      ! -name 'MacOptimization.swift' \
      ! -name 'MountedDiskImageEjector.swift' \
      -exec grep -nEH "$dangerous_pattern" {} +
  }
fi

if dangerous_matches; then
  echo "Dangerous filesystem or process API found outside a reviewed boundary." >&2
  exit 1
fi

mounted_image_eject_count="$(count_matches 'NSWorkspace\.shared\.unmountAndEjectDevice' Sources/CrabAppSupport/MountedDiskImageEjector.swift)"
if [ "$mounted_image_eject_count" != "1" ]; then
  echo "The reviewed mounted-image eject boundary must contain exactly one system eject call." >&2
  exit 1
fi

optimizer_boundary="Sources/CrabAppSupport/MacOptimization.swift"
optimizer_process_count="$(count_matches 'let process = Process\(\)' "$optimizer_boundary")"
optimizer_child_terminate_count="$(count_matches 'process\.terminate\(\)' "$optimizer_boundary")"
if [ "$optimizer_process_count" != "1" ] || [ "$optimizer_child_terminate_count" != "1" ]; then
  echo "Reviewed Mac optimization process boundary changed; inspect it before release." >&2
  exit 1
fi

if command -v rg >/dev/null 2>&1; then
  optimizer_forbidden_matches() {
    rg -n '/bin/(sh|bash)|sudo|NSRunningApplication|forceTerminate|removeItem|trashItem|(^|[^A-Za-z.])(kill|unlink|rmdir|rename|system)\(' \
      "$optimizer_boundary" \
      Sources/CrabApp/RuntimeOptimizerModel.swift \
      Sources/CrabApp/RuntimeOptimizerView.swift
  }
else
  optimizer_forbidden_matches() {
    grep -nEH '/bin/(sh|bash)|sudo|NSRunningApplication|forceTerminate|removeItem|trashItem|(^|[^A-Za-z.])(kill|unlink|rmdir|rename|system)\(' \
      "$optimizer_boundary" \
      Sources/CrabApp/RuntimeOptimizerModel.swift \
      Sources/CrabApp/RuntimeOptimizerView.swift
  }
fi

if optimizer_forbidden_matches; then
  echo "Mac optimization must not use shells, sudo, or arbitrary process termination." >&2
  exit 1
fi

trash_api_count="$(count_matches 'FileManager\.default\.trashItem' Sources/CrabCore/SystemTrashMover.swift)"
if [ "$trash_api_count" != "1" ]; then
  echo "The reviewed Trash boundary must contain exactly one system Trash call." >&2
  exit 1
fi

update_process_count="$(count_matches 'let process = Process\(\)' Sources/CrabAppSupport/HarnessUpdate.swift)"
usage_process_count="$(count_matches 'let process = Process\(\)' Sources/CrabAppSupport/HarnessUsage.swift)"
app_update_process_count="$(count_matches 'let process = Process\(\)' Sources/CrabAppSupport/CrabAppInstaller.swift)"
app_update_cleanup_count="$(count_matches 'FileManager\.default\.removeItem|manager\.removeItem' Sources/CrabAppSupport/CrabAppInstaller.swift)"
if [ "$update_process_count" != "1" ] || [ "$usage_process_count" != "1" ] \
  || [ "$app_update_process_count" != "1" ] || [ "$app_update_cleanup_count" != "2" ]; then
  echo "Reviewed process boundaries changed; inspect Harness update and usage execution before release." >&2
  exit 1
fi

if command -v rg >/dev/null 2>&1; then
  archive_matches() {
    rg -n 'TrashMoving|CleanPlan|CleanupExecutor|RuleAction' Sources/CrabArchive
  }
else
  archive_matches() {
    grep -rnE 'TrashMoving|CleanPlan|CleanupExecutor|RuleAction' Sources/CrabArchive
  }
fi

if archive_matches; then
  echo "The read-only archive module must remain disconnected from cleanup execution types." >&2
  exit 1
fi

echo "Dangerous API check passed."
