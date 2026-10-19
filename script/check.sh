#!/bin/bash
set -euo pipefail
BRIDGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp/}MusicBridgeChecks.XXXXXX")"
trap 'rm -r "$CHECK_DIR"' EXIT
SOURCES="$BRIDGE_ROOT/MacApp/Sources/MusicBridgeApp"
swiftc -parse-as-library -swift-version 5 \
  "$SOURCES/Models.swift" "$SOURCES/BridgeModel.swift" "$SOURCES/SurfaceMotion.swift" \
  "$SOURCES/GoMusicClient.swift" "$SOURCES/AppleMusicCatalogClient.swift" \
  "$SOURCES/DownloaderRunner.swift" "$SOURCES/IPodImporter.swift" \
  "$BRIDGE_ROOT/MacApp/Tests/MusicBridgeChecks.swift" -o "$CHECK_DIR/check"
"$CHECK_DIR/check"
