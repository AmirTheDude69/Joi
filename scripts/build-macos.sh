#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_ROOT="$ROOT/apps/macos"
DIST="$ROOT/dist"
APP="$DIST/Joi.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MACOS_ROOT/Info.plist")"
DMG="$DIST/Joi-${VERSION}-macOS-Universal.dmg"
ICON_WORK="$MACOS_ROOT/.icon-build"
ARM_BUILD="$MACOS_ROOT/.build-arm64"
X86_BUILD="$MACOS_ROOT/.build-x86_64"

echo "Building Joi for Apple Silicon…"
swift build \
    --configuration release \
    --package-path "$MACOS_ROOT" \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$ARM_BUILD"

echo "Building Joi for Intel…"
swift build \
    --configuration release \
    --package-path "$MACOS_ROOT" \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$X86_BUILD"

ARM_BINARY="$ARM_BUILD/arm64-apple-macosx/release/Joi"
X86_BINARY="$X86_BUILD/x86_64-apple-macosx/release/Joi"
if [[ "$(uname -m)" == "arm64" ]]; then
    "$ARM_BINARY" --self-test
else
    "$X86_BINARY" --self-test
fi

rm -rf "$APP" "$DIST/dmg-staging" "$ICON_WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST/dmg-staging"

/usr/bin/lipo -create "$ARM_BINARY" "$X86_BINARY" -output "$APP/Contents/MacOS/Joi"
cp "$MACOS_ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/spritesheet.webp" "$APP/Contents/Resources/spritesheet.webp"
cp "$MACOS_ROOT/Resources/JoiDance"/joi-dance-*.png "$APP/Contents/Resources/"

python3 "$ROOT/scripts/make-macos-icon.py" \
    "$ROOT/spritesheet.webp" \
    "$APP/Contents/Resources/Joi.icns" \
    "$ICON_WORK"

/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

ditto "$APP" "$DIST/dmg-staging/Joi.app"
ln -s /Applications "$DIST/dmg-staging/Applications"
rm -f "$DMG"
/usr/bin/hdiutil create \
    -volname "Joi" \
    -srcfolder "$DIST/dmg-staging" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$DIST/dmg-staging" "$ICON_WORK"
echo "Created $DMG"
