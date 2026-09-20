#!/usr/bin/env bash
set -euo pipefail
SRC=_appicon/appIcon_1024.png
OUT=_appicon/AppIcon.iconset
rm -rf "$OUT" && mkdir -p "$OUT"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC" --out "$OUT/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC" --out "$OUT/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$OUT" -o _appicon/AppIcon.icns
