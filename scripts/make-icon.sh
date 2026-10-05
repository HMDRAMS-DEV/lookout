#!/bin/bash
# Renders scripts/make-icon.swift into Lookout/AppIcon.iconset at every size macOS asks for.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
set="$here/Lookout/AppIcon.iconset"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

xcrun swiftc -O -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
    -o "$work/make-icon" "$here/scripts/make-icon.swift"
"$work/make-icon" "$work/icon.png"

mkdir -p "$set"
for size in 16 32 128 256 512; do
    sips -z $size $size "$work/icon.png" --out "$set/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$work/icon.png" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
echo "wrote $set"
