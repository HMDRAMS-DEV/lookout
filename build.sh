#!/bin/bash
# Compiles Lookout.app into build/ with the Command Line Tools. No Xcode project.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/build/Lookout.app"
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk

[ -d "$here/Lookout/AppIcon.iconset" ] || "$here/scripts/make-icon.sh"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/Lookout/Info.plist" "$app/Contents/Info.plist"
iconutil -c icns "$here/Lookout/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

xcrun swiftc -O -sdk "$sdk" -parse-as-library -swift-version 6 -target arm64-apple-macos15.0 \
    -module-name Lookout -o "$app/Contents/MacOS/Lookout" \
    $(find "$here/Lookout" -name '*.swift')

# Automation permission (for selecting Terminal tabs) is tied to the signature. An ad-hoc signature
# changes on every build, so prefer a stable local certificate when one exists.
identity=-
for name in "Lookout Local Signing" "Tapestry Local Signing"; do
    if security find-identity -p codesigning | grep -q "\"$name\""; then identity="$name"; break; fi
done
codesign --force --sign "$identity" --identifier dev.lookout.Lookout "$app"
echo "built $app"
