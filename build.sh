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

# Detect beta: a build is beta when it is not on a version tag.
# In CI, GITHUB_REF is set; locally we check whether HEAD has a vX.Y.Z tag.
IS_BETA=false
if [ -n "${GITHUB_REF:-}" ]; then
  # CI: beta unless the ref is a version tag
  if [[ "${GITHUB_REF}" != refs/tags/v* ]]; then
    IS_BETA=true
  fi
else
  # Local: beta unless HEAD is exactly at a version tag
  if ! git describe --exact-match --match "v*.*.*" HEAD >/dev/null 2>&1; then
    IS_BETA=true
  fi
fi

if [ "$IS_BETA" = true ]; then
  echo "==> Build type: BETA"
  BETA_FLAG="-D BETA_BUILD"
else
  echo "==> Build type: release"
  BETA_FLAG=""
fi

echo "==> Cleaning old build"
rm -rf "$APP"

echo "==> Creating bundle structure"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"

echo "==> Compiling"
# shellcheck disable=SC2086
swiftc \
  WaveMute/main.swift \
  WaveMute/AppDelegate.swift \
  WaveMute/ShortcutRecorder.swift \
  WaveMute/MenuBarIcons.swift \
  WaveMute/LaunchAtLogin.swift \
  WaveMute/HIDMonitor.swift \
  WaveMute/MeetSync.swift \
  $BETA_FLAG \
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

echo "==> Done: $APP"
echo ""
if [ "$IS_BETA" = true ]; then
  echo "Beta build - menu bar icon will show a β badge."
else
  echo "Drag $APP into /Applications to install."
fi
