#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_ROOT/Crab.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
SOURCE_LOGO="$PROJECT_ROOT/Assets/Brand/crab-protective-orbit.png"
SOURCE_APP_ICON="$PROJECT_ROOT/Assets/Brand/crab-app-icon.png"
SOURCE_LOADING_MASCOT="$PROJECT_ROOT/Assets/Brand/crab-loading-mascot.png"

if [[ "$APP_BUNDLE" != "$PROJECT_ROOT/build/Crab.app" ]]; then
    echo "Refusing to replace an unexpected app path: $APP_BUNDLE" >&2
    exit 1
fi

swift build --package-path "$PROJECT_ROOT" -c release --product CrabApp
BIN_DIR="$(swift build --package-path "$PROJECT_ROOT" -c release --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BIN_DIR/CrabApp" "$MACOS_DIR/Crab"
install -m 644 "$PROJECT_ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
install -m 644 "$SOURCE_LOGO" "$RESOURCES_DIR/crab-protective-orbit.png"
install -m 644 "$SOURCE_LOADING_MASCOT" "$RESOURCES_DIR/crab-loading-mascot.png"
ditto "$PROJECT_ROOT/Rules/AIApplications" "$RESOURCES_DIR/Rules"
ditto "$PROJECT_ROOT/Sources/CrabApp/Resources/en.lproj" "$RESOURCES_DIR/en.lproj"
ditto "$PROJECT_ROOT/Sources/CrabApp/Resources/zh-Hans.lproj" "$RESOURCES_DIR/zh-Hans.lproj"

ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/crab-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK"' EXIT
ICONSET="$ICON_WORK/Crab.iconset"
mkdir -p "$ICONSET"

while read -r points suffix pixels; do
    if [[ "$suffix" == "base" ]]; then
        suffix=""
    fi
    sips -z "$pixels" "$pixels" "$SOURCE_APP_ICON" --out "$ICONSET/icon_${points}x${points}${suffix}.png" >/dev/null
done <<'SIZES'
16  base 16
16  @2x 32
32  base 32
32  @2x 64
128 base 128
128 @2x 256
256 base 256
256 @2x 512
512 base 512
512 @2x 1024
SIZES

iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/Crab.icns"
# Keep a stable designated requirement for local builds. Security-scoped
# bookmarks are bound to the signing identity; the default ad-hoc requirement
# is a cdhash that changes whenever the executable is rebuilt.
codesign \
    --force \
    --deep \
    --sign - \
    --requirements '=designated => identifier "dev.crab.cleaner"' \
    "$APP_BUNDLE"

echo "$APP_BUNDLE"
