#!/usr/bin/env bash
# Regenerates the macOS slots of native/TodoNative's AppIcon.appiconset from the master art.
# The iOS 1024 slot uses the master directly and is not touched. Run from the repo root.
set -euo pipefail
SRC=_appicon/appIcon_1024.png
SET=native/TodoNative/TodoNative/Assets.xcassets/AppIcon.appiconset

cp "$SRC" "$SET/appIcon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC" --out "$SET/mac_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC" --out "$SET/mac_${s}x${s}@2x.png" >/dev/null
done
