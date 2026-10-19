#!/bin/bash
set -euo pipefail
BRIDGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-run}"
APP="$BRIDGE_ROOT/dist/MusicBridgeApp.app"
swift build --package-path "$BRIDGE_ROOT/MacApp"
BIN="$(swift build --package-path "$BRIDGE_ROOT/MacApp" --show-bin-path)/MusicBridgeApp"
# Stop only this checkout's build, leaving the Muse installation untouched.
while IFS= read -r pid; do
  if [[ -n "$pid" ]]; then kill "$pid"; fi
done < <(pgrep -f "^$APP/Contents/MacOS/MusicBridgeApp$" || true)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MusicBridgeApp"
if [[ -f "$BRIDGE_ROOT/MacApp/Resources/MusicBridgeIcon.png" ]]; then
  cp "$BRIDGE_ROOT/MacApp/Resources/MusicBridgeIcon.png" "$APP/Contents/Resources/MusicBridgeIcon.png"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MusicBridgeApp</string>
<key>CFBundleIdentifier</key><string>cn.unmeta.musicbridge.rebuilt</string>
<key>CFBundleName</key><string>Music Bridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>MusicBridgeIcon.png</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
case "$MODE" in
  --build-only) ;;
  run) /usr/bin/open -n "$APP" ;;
  --verify)
    /usr/bin/open -n "$APP"
    sleep 1
    pgrep -fl "^$APP/Contents/MacOS/MusicBridgeApp$"
    ;;
  --logs)
    /usr/bin/open -n "$APP"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "cn.unmeta.musicbridge.rebuilt"'
    ;;
  *) echo "usage: $0 [run|--verify|--build-only|--logs]" >&2; exit 2 ;;
esac
