#!/usr/bin/env bash
# Builds Nook.app (Apple Silicon + Intel) and packs it into a DMG.
# Runs on macOS (GitHub Actions or your own Mac).
set -euo pipefail

APP_NAME="Nook"
PRODUCT="Uthon"   # Swift package product (the binary SwiftPM builds)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ARCHS=(--arch arm64 --arch x86_64)

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

echo "==> Assembling app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Making app icon"
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
# Both icons in the bundle: the app shows the one that matches Light or Dark mode.
cp Resources/AppIcon.png "$APP/Contents/Resources/AppIcon-Dark.png"
cp Resources/AppIcon-Light.png "$APP/Contents/Resources/AppIcon-Light.png"

# macOS 26 can swap app icons with the appearance itself: compile an asset catalog with
# a light (any) and a dark icon. Optional: older Xcode just keeps the .icns above.
XCASSETS="$DIST/Assets.xcassets"
SET="$XCASSETS/AppIcon.appiconset"
mkdir -p "$SET"
printf '{"info":{"author":"xcode","version":1}}' > "$XCASSETS/Contents.json"
IMAGES=""
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((size * scale))
        sips -z "$px" "$px" Resources/AppIcon-Light.png --out "$SET/light_${size}@${scale}x.png" >/dev/null
        sips -z "$px" "$px" Resources/AppIcon.png --out "$SET/dark_${size}@${scale}x.png" >/dev/null
        IMAGES="$IMAGES{\"idiom\":\"mac\",\"size\":\"${size}x${size}\",\"scale\":\"${scale}x\",\"filename\":\"light_${size}@${scale}x.png\"},"
        IMAGES="$IMAGES{\"idiom\":\"mac\",\"size\":\"${size}x${size}\",\"scale\":\"${scale}x\",\"filename\":\"dark_${size}@${scale}x.png\",\"appearances\":[{\"appearance\":\"luminosity\",\"value\":\"dark\"}]},"
    done
done
printf '{"images":[%s],"info":{"author":"xcode","version":1}}' "${IMAGES%,}" > "$SET/Contents.json"
if xcrun actool --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
        --app-icon AppIcon --output-partial-info-plist "$DIST/assets-info.plist" "$XCASSETS" >/dev/null 2>"$DIST/actool.log" \
        && [ -f "$APP/Contents/Resources/Assets.car" ]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
    echo "    asset catalog with light + dark icon: OK"
else
    echo "    asset catalog skipped (using AppIcon.icns only)"; cat "$DIST/actool.log" || true
fi
rm -rf "$XCASSETS"

echo "==> Signing (ad-hoc, no Apple Developer account needed)"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> Creating DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# The app used to be called Uthon. Older versions update by copying "Uthon.app" out of
# the DMG, so a hidden copy keeps their one-click update working; the new updater then
# renames the installed app to Nook.app.
cp -R "$APP" "$STAGE/Uthon.app"
chflags hidden "$STAGE/Uthon.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
# Same DMG under the old name, for older versions that build the download link themselves.
cp "$DMG" "$DIST/Uthon-$VERSION.dmg"

echo "==> Done: $DMG"
