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

# Prefer the Developer ID, which notarization needs. Without it, use a stable local certificate:
# Automation permission (for selecting Terminal tabs) is tied to the signature, and an ad-hoc
# signature changes on every build.
developer_id="Developer ID Application: HMDFV Inc. (8Z6WRF99H5)"
if security find-identity -v -p codesigning | grep -q "\"$developer_id\""; then
    codesign --force --timestamp --options runtime --entitlements "$here/Lookout/Lookout.entitlements" \
        --sign "$developer_id" --identifier dev.lookout.Lookout "$app"
else
    identity=-
    for name in "Lookout Local Signing" "Tapestry Local Signing"; do
        if security find-identity -p codesigning | grep -q "\"$name\""; then identity="$name"; break; fi
    done
    codesign --force --sign "$identity" --identifier dev.lookout.Lookout "$app"
fi
echo "built $app"
