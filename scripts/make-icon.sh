#!/bin/sh
# Builds Resources/AppIcon.icns from Resources/AppIcon.png (1024x1024).
# Requires macOS (sips + iconutil).
set -e
cd "$(dirname "$0")/.."

SRC="Resources/AppIcon.png"
SET="AppIcon.iconset"

[ -f "$SRC" ] || { echo "Missing $SRC"; exit 1; }

rm -rf "$SET"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$SRC" --out "$SET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z $double $double "$SRC" --out "$SET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$SET"
echo "Built Resources/AppIcon.icns"
