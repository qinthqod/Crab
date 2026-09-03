#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Packaging/Info.plist")"
ARCH="$(uname -m)"
RELEASE_ROOT="$PROJECT_ROOT/release"
ARCHIVE_NAME="Crab-$VERSION-macOS-$ARCH.zip"
ARCHIVE_PATH="$RELEASE_ROOT/$ARCHIVE_NAME"
DMG_NAME="Crab-$VERSION-macOS-$ARCH.dmg"
DMG_PATH="$RELEASE_ROOT/$DMG_NAME"
CHECKSUM_PATH="$RELEASE_ROOT/SHA256SUMS.txt"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/crab-release.XXXXXX")"
DMG_STAGING="$STAGING_ROOT/dmg"

cleanup() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

"$PROJECT_ROOT/scripts/build-app-bundle.sh"
codesign --verify --deep --strict "$PROJECT_ROOT/build/Crab.app"

mkdir -p "$RELEASE_ROOT"
rm -f "$ARCHIVE_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT/build/Crab.app" "$ARCHIVE_PATH"

mkdir -p "$DMG_STAGING"
ditto "$PROJECT_ROOT/build/Crab.app" "$DMG_STAGING/Crab.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "Crab $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

cd "$RELEASE_ROOT"
shasum -a 256 "$DMG_NAME" "$ARCHIVE_NAME" > "$(basename "$CHECKSUM_PATH")"

echo "$DMG_PATH"
echo "$ARCHIVE_PATH"
echo "$CHECKSUM_PATH"
