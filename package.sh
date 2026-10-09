#!/bin/sh
# Builds release apps and installs Butterlight.app and Butterfinder.app into ~/Applications.
set -e
cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
DEST="$HOME/Applications"
mkdir -p "$DEST"

make_app() { # name  bundle-id  extra-plist
  APP="$DEST/$1.app"
  rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
  cp "$BIN/$1" "$APP/Contents/MacOS/$1"
  mkdir -p "$APP/Contents/Resources"
  swift Tools/makeicon.swift "$4" "$5" "$6" "$APP/Contents/Resources/AppIcon.icns"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$1</string>
<key>CFBundleExecutable</key><string>$1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
$3
</dict></plist>
PLIST
  codesign --force --sign - "$APP"
}

make_app Butterlight com.butterlight.app '<key>LSUIElement</key><true/>' magnifyingglass 7B61FF 3B82F6
make_app Butterfinder com.butterfinder.app '<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Folder</string><key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSItemContentTypes</key><array><string>public.folder</string></array></dict></array>' folder.fill 38BDF8 2563EB

echo "Installed to $DEST. Start with: open $DEST/Butterlight.app $DEST/Butterfinder.app"
