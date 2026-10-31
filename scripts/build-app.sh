#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${TEMPCHECK_BUILD_ROOT:-$ROOT/.build/package}"
DEST="${TEMPCHECK_OUTPUT_DIR:-$ROOT/dist}"
mkdir -p "$BUILD_ROOT" "$DEST"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"
ARCHS=(arm64 x86_64)
if [[ "${1:-}" == "--native" ]]; then ARCHS=("$(uname -m)"); fi
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    TRIPLE="$ARCH-apple-macosx12.0"
    swift build --build-system native --package-path "$ROOT" -c release --triple "$TRIPLE" --scratch-path "$BUILD_ROOT/$ARCH-native" --cache-path "$BUILD_ROOT/cache" --disable-sandbox
    BIN_DIR="$(swift build --build-system native --package-path "$ROOT" -c release --triple "$TRIPLE" --scratch-path "$BUILD_ROOT/$ARCH-native" --cache-path "$BUILD_ROOT/cache" --disable-sandbox --show-bin-path)"
    BINARIES+=("$BIN_DIR/TempCheck")
done
APP="$DEST/TempCheck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ${#BINARIES[@]} -eq 2 ]]; then
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/TempCheck"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/TempCheck"
fi
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/scripts/make-icon.swift" "$BUILD_ROOT/AppIcon.iconset"
iconutil -c icns "$BUILD_ROOT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DEST/TempCheck-macOS.zip"
echo "Gotowe: $APP"
