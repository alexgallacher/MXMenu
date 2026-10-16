#!/bin/bash
# Builds MXMenu.app (and MXMenu.zip for releases) into ./build.
# Requires Xcode or the Command Line Tools (Swift 5.9+).
#   VERSION=1.2.0 ./build-app.sh   stamps that version into the app.
set -euo pipefail
cd "$(dirname "$0")"

# The native build system also works on Command Line Tools-only setups.
swift build -c release --build-system native
BIN="$(swift build -c release --build-system native --show-bin-path)/MXMenu"

APP="build/MXMenu.app"
rm -rf "$APP" build/MXMenu.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MXMenu"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

# Ad-hoc sign so macOS will run it.
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" build/MXMenu.zip

echo "Built $(pwd)/$APP"
echo "Install with:  cp -R \"$APP\" /Applications/ && open /Applications/MXMenu.app"
