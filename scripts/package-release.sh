#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Packaging/Info.plist")"
ARCH="$(uname -m)"
RELEASE_ROOT="$PROJECT_ROOT/release"
ARCHIVE_NAME="Crab-$VERSION-macOS-$ARCH.zip"
ARCHIVE_PATH="$RELEASE_ROOT/$ARCHIVE_NAME"
CHECKSUM_PATH="$RELEASE_ROOT/SHA256SUMS.txt"

"$PROJECT_ROOT/scripts/build-app-bundle.sh"
codesign --verify --deep --strict "$PROJECT_ROOT/build/Crab.app"

mkdir -p "$RELEASE_ROOT"
rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT/build/Crab.app" "$ARCHIVE_PATH"

cd "$RELEASE_ROOT"
shasum -a 256 "$ARCHIVE_NAME" > "$(basename "$CHECKSUM_PATH")"

echo "$ARCHIVE_PATH"
echo "$CHECKSUM_PATH"
