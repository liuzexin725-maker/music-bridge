#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MusicBridgeApp"
BUNDLE_ID="cn.unmeta.musicbridge"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/MacApp"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$PACKAGE_DIR/Resources/MusicBridgeIcon.png"
ICON_FILE="$APP_RESOURCES/MusicBridge.icns"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing application icon: $ICON_SOURCE" >&2
  exit 1
fi
command -v magick >/dev/null 2>&1 || { echo "ImageMagick is required to package the application icon." >&2; exit 1; }
command -v iconutil >/dev/null 2>&1 || { echo "macOS iconutil is required to package the application icon." >&2; exit 1; }
if [[ "$(magick identify -format '%wx%h' "$ICON_SOURCE")" != "1024x1024" ]]; then
  echo "The application icon must be a square 1024x1024 PNG." >&2
  exit 1
fi

swift build --package-path "$PACKAGE_DIR"
BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_NAME"

# Resize the approved raster directly: SVG conversion previously lost its
# gradient background. Keep packaging intermediates out of the project.
ICON_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp/}MusicBridge-icon.XXXXXX")"
ICONSET_DIR="$ICON_BUILD_DIR/MusicBridge.iconset"
trap 'rm -rf -- "$ICON_BUILD_DIR"' EXIT
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  magick "$ICON_SOURCE" -colorspace sRGB -filter Lanczos -resize "${size}x${size}" "PNG32:$ICONSET_DIR/icon_${size}x${size}.png"
  retina_size=$((size * 2))
  magick "$ICON_SOURCE" -colorspace sRGB -filter Lanczos -resize "${retina_size}x${retina_size}" "PNG32:$ICONSET_DIR/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET_DIR" -o "$ICON_BUILD_DIR/MusicBridge.icns"

# Finish the build and icon conversion before replacing the runnable bundle.
pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_BUILD_DIR/MusicBridge.icns" "$ICON_FILE"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Music Bridge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>MusicBridge.icns</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

case "$MODE" in
  run)
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
  --verify|verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --logs|logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  *)
    echo "usage: $0 [run|--verify|--logs]" >&2
    exit 2
    ;;
esac
