#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Browsair.app"
STAGE="$DIST/dmg-root"
ICON_SRC="${1:-}"
BUILD="$ROOT/.build/release"

cd "$ROOT"

if [[ -z "$ICON_SRC" ]]; then
  for candidate in \
    "$ROOT/Sources/Browsair/Resources/AppIcon.png" \
    "$ROOT/Design/AppIcon.png"
  do
    if [[ -f "$candidate" ]]; then
      ICON_SRC="$candidate"
      break
    fi
  done
fi

if [[ -z "$ICON_SRC" || ! -f "$ICON_SRC" ]]; then
  echo "No app icon PNG found. Pass a 1024x1024 image as the first argument." >&2
  exit 1
fi

echo "Building release..."
swift build -c release --product Browsair

mkdir -p "$DIST"
rm -rf "$APP" "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Assembling app bundle..."
cp "$BUILD/Browsair" "$APP/Contents/MacOS/Browsair"
chmod +x "$APP/Contents/MacOS/Browsair"
if [[ -d "$BUILD/Browsair_Browsair.bundle" ]]; then
  cp -R "$BUILD/Browsair_Browsair.bundle" "$APP/Contents/Resources/Browsair_Browsair.bundle"
fi
cp "$ROOT/Sources/Browsair/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "Making AppIcon.icns from ${ICON_SRC}"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
MASTER="$DIST/AppIcon-1024.png"
sips -s format png "$ICON_SRC" --out "$MASTER" >/dev/null
sips -z 16 16     "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$MASTER" "$ROOT/Sources/Browsair/Resources/AppIcon.png"
cp "$APP/Contents/Resources/AppIcon.icns" "$ROOT/Sources/Browsair/Resources/AppIcon.icns"

echo "Ad-hoc signing..."
codesign --force --sign - "$APP/Contents/MacOS/Browsair"
codesign --force --sign - "$APP"

echo "Creating DMG..."
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Browsair.app"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Browsair-0.2.0.dmg"
rm -f "$DMG"
hdiutil create -volname "Browsair" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "Built:"
ls -lh "$APP/Contents/MacOS/Browsair" "$DMG"
echo "$DMG"
