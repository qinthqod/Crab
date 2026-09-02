#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$repo_root/build/Crab.app"
app_binary="$app_bundle/Contents/MacOS/Crab"

if [[ ! -x "$app_binary" ]]; then
    echo "Crab app bundle is missing; run scripts/build-app-bundle.sh first."
    exit 1
fi

pkill -x Crab 2>/dev/null || true
open -n "$app_bundle"

app_pid=""
for _ in 1 2 3 4 5; do
    app_pid="$(pgrep -f "^$app_binary$" | tail -1 || true)"
    [[ -n "$app_pid" ]] && break
    sleep 1
done

if [[ -z "$app_pid" ]]; then
    echo "Crab did not launch."
    exit 1
fi

cleanup() {
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
}
trap cleanup EXIT

sleep 4

if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "Crab exited during launch."
    exit 1
fi

cpu_usage="$(ps -p "$app_pid" -o %cpu= | tr -d ' ')"
cpu_integer="${cpu_usage%%.*}"

if (( cpu_integer >= 80 )); then
    echo "Crab launch is stuck at ${cpu_usage}% CPU."
    exit 1
fi

echo "Crab launch is responsive (${cpu_usage}% CPU)."
