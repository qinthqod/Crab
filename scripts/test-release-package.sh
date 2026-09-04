#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Packaging/Info.plist")"
ARCH="$(uname -m)"
RELEASE_ROOT="$PROJECT_ROOT/release"
DMG_NAME="Crab-$VERSION-macOS-$ARCH.dmg"
ZIP_NAME="Crab-$VERSION-macOS-$ARCH.zip"
DMG_PATH="$RELEASE_ROOT/$DMG_NAME"
ZIP_PATH="$RELEASE_ROOT/$ZIP_NAME"
CHECKSUM_PATH="$RELEASE_ROOT/SHA256SUMS.txt"
MANIFEST_PATH="$RELEASE_ROOT/update.json"
MOUNT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/crab-dmg-test.XXXXXX")"
MOUNT_POINT="$MOUNT_ROOT/volume"
ATTACHED=0

cleanup() {
  if [[ "$ATTACHED" -eq 1 ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$MOUNT_ROOT"
}
trap cleanup EXIT

fail() {
  echo "release package verification failed: $1" >&2
  exit 1
}

[[ -f "$DMG_PATH" ]] || fail "missing $DMG_NAME"
[[ -f "$ZIP_PATH" ]] || fail "missing $ZIP_NAME required by in-app updates"
[[ -f "$CHECKSUM_PATH" ]] || fail "missing SHA256SUMS.txt"
[[ -f "$MANIFEST_PATH" ]] || fail "missing update.json required by rate-limit-free update checks"

mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" -quiet
ATTACHED=1

[[ -d "$MOUNT_POINT/Crab.app" ]] || fail "DMG does not contain Crab.app"
[[ -L "$MOUNT_POINT/Applications" ]] || fail "Applications is not a symbolic link"
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || \
  fail "Applications link does not target /Applications"

TOP_LEVEL_ITEMS="$(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 \
  ! -name '.DS_Store' -print | sed 's#.*/##' | LC_ALL=C sort)"
[[ "$TOP_LEVEL_ITEMS" == $'Applications\nCrab.app' ]] || fail "DMG contains unexpected top-level items"

codesign --verify --deep --strict "$MOUNT_POINT/Crab.app"

grep -Fq "  $DMG_NAME" "$CHECKSUM_PATH" || fail "checksum file omits $DMG_NAME"
grep -Fq "  $ZIP_NAME" "$CHECKSUM_PATH" || fail "checksum file omits $ZIP_NAME"
grep -Fq "  update.json" "$CHECKSUM_PATH" || fail "checksum file omits update.json"

[[ "$(plutil -extract version raw "$MANIFEST_PATH")" == "v$VERSION" ]] || fail "manifest version mismatch"
[[ "$(plutil -extract release_url raw "$MANIFEST_PATH")" == "https://github.com/qinthqod/Crab/releases/tag/v$VERSION" ]] || fail "manifest release URL mismatch"
[[ "$(plutil -extract assets.0.name raw "$MANIFEST_PATH")" == "$ZIP_NAME" ]] || fail "manifest ZIP name mismatch"
[[ "$(plutil -extract assets.0.content_type raw "$MANIFEST_PATH")" == "application/zip" ]] || fail "manifest content type mismatch"
[[ "$(plutil -extract assets.0.browser_download_url raw "$MANIFEST_PATH")" == "https://github.com/qinthqod/Crab/releases/download/v$VERSION/$ZIP_NAME" ]] || fail "manifest download URL mismatch"
ZIP_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
[[ "$(plutil -extract assets.0.digest raw "$MANIFEST_PATH")" == "sha256:$ZIP_SHA256" ]] || fail "manifest digest mismatch"
(cd "$RELEASE_ROOT" && shasum -a 256 -c "$(basename "$CHECKSUM_PATH")")

echo "Verified drag-to-install DMG and in-app update ZIP for Crab $VERSION ($ARCH)."
