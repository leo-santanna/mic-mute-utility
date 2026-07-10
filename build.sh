#!/bin/bash
set -e

APP="WaveMute.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
BINARY="$MACOS/WaveMute"
HIDAPI_SRC="/opt/homebrew/lib/libhidapi.dylib"
HIDAPI_DST="$FRAMEWORKS/libhidapi.dylib"

cd "$(dirname "$0")"

echo "==> Cleaning old build"
rm -rf "$APP"

echo "==> Creating bundle structure"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"

echo "==> Compiling"
swiftc \
  WaveMute/main.swift \
  WaveMute/AppDelegate.swift \
  WaveMute/ShortcutRecorder.swift \
  WaveMute/MenuBarIcons.swift \
  WaveMute/LaunchAtLogin.swift \
  WaveMute/HIDMonitor.swift \
  -o "$BINARY" \
  -framework Cocoa \
  -framework CoreAudio \
  -framework Carbon

echo "==> Bundling libhidapi"
cp "$HIDAPI_SRC" "$HIDAPI_DST"

# Make the dylib's install name point to @rpath so the binary can find it
install_name_tool -id "@rpath/libhidapi.dylib" "$HIDAPI_DST"

# Add an rpath entry pointing at the Frameworks folder relative to the binary
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY"

echo "==> Copying Info.plist and icon"
cp WaveMute/Info.plist "$CONTENTS/Info.plist"
cp WaveMute/AppIcon.icns "$RESOURCES/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP/Contents/Frameworks/libhidapi.dylib"
codesign --force --sign - "$APP/Contents/MacOS/WaveMute"
codesign --force --sign - "$APP"

echo "==> Clearing quarantine"
xattr -cr "$APP"

echo "==> Done — $APP"
echo ""
echo "Drag $APP into /Applications to install."
