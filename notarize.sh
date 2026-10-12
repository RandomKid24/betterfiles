#!/bin/sh
# Signs both apps with your Developer ID, builds the DMG, has Apple notarize it, and staples the ticket,
# so the apps open on any Mac with no warning. Needs a paid Apple Developer account. See docs/NOTARIZING.md.
#
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="butter-notary" ./notarize.sh 1.3.0
set -e
cd "$(dirname "$0")"
: "${SIGN_ID:?Set SIGN_ID to your \"Developer ID Application: ...\" certificate name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile (see docs/NOTARIZING.md)}"
VERSION="${1:-1.0.0}"
export SIGN_ID

./dist.sh "$VERSION"
DMG="dist/Butterlight-Butterfinder-$VERSION.dmg"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "Notarized: $DMG"
