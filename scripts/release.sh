#!/bin/zsh
# Builds Lookout, packages it as a disk image, notarizes it, and publishes a GitHub release.
#
#     scripts/release.sh "What changed, in a sentence or two."
#
# Bump CFBundleShortVersionString and CFBundleVersion in Lookout/Info.plist and commit first.
#
# One-time setup on a new Mac: the HMDFV Inc. Developer ID Application certificate must be in the
# login keychain, and a notarytool profile named "ramihmd-notary" must exist:
# `xcrun notarytool store-credentials ramihmd-notary --apple-id <id> --team-id 8Z6WRF99H5`
set -euo pipefail

repo=HMDRAMS-DEV/lookout
notary=ramihmd-notary

cd "$(dirname "$0")/.."
notes="${1:?Usage: scripts/release.sh \"release notes\"}"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Lookout/Info.plist)
tag="v$version"
dmg=build/Lookout.dmg

[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first."; exit 1; }
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then echo "$tag is already released."; exit 1; fi

./build.sh
signature=$(codesign -dvv build/Lookout.app 2>&1)
[[ $signature == *"Authority=Developer ID Application"* ]] || { echo "Not signed with the Developer ID."; exit 1; }

stage=build/dmg
rm -rf "$stage" "$dmg"
mkdir -p "$stage"
ditto build/Lookout.app "$stage/Lookout.app"
ln -s /Applications "$stage/Applications"
hdiutil create -srcfolder "$stage" -volname Lookout -fs HFS+ -format UDZO -ov "$dmg" -quiet
rm -rf "$stage"
codesign --timestamp --sign "Developer ID Application: HMDFV Inc. (8Z6WRF99H5)" "$dmg"

# Stapling fails unless Apple accepted the image, which stops the release there.
xcrun notarytool submit "$dmg" --keychain-profile "$notary" --wait
xcrun stapler staple "$dmg"

gh release create "$tag" "$dmg" -R "$repo" --target main --title "Lookout $version" --notes "$notes"
