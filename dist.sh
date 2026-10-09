#!/bin/sh
# Builds universal (Apple Silicon + Intel) apps and packs them into dist/:
#   Butterlight-Butterfinder-<version>.dmg   (drag both apps to Applications)
#   Butterlight-Butterfinder-<version>.zip
# Usage: ./dist.sh [version]
set -e
cd "$(dirname "$0")"
export VERSION="${1:-1.0.0}"
rm -rf dist
mkdir -p dist/stage
DEST="$PWD/dist/stage" ARCHS="--arch arm64 --arch x86_64" ./package.sh
ln -s /Applications dist/stage/Applications
NAME="Butterlight-Butterfinder-$VERSION"
hdiutil create -volname "Butterlight & Butterfinder" -srcfolder dist/stage -ov -format UDZO "dist/$NAME.dmg" >/dev/null
(cd dist/stage && zip -qry "../$NAME.zip" Butterlight.app Butterfinder.app)
rm -rf dist/stage
shasum -a 256 dist/*.dmg dist/*.zip
