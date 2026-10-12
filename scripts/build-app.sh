#!/bin/bash
# Builds build/Doorstep.app. Usage: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

# With only Command Line Tools installed, the macOS 27 SDK's SwiftUI needs a macro
# plugin that ships with Xcode, so build against the 26.x SDK instead.
if ! xcode-select -p | grep -q Xcode.app; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1)
  export SDKROOT="$SDK"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Doorstep"

[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift

APP=build/Doorstep.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Doorstep"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f Resources/client_secret.json ] && cp Resources/client_secret.json "$APP/Contents/Resources/"

# A stable local identity keeps the Keychain from re-asking after every rebuild.
# Create one with scripts/make-signing-cert.sh; otherwise sign ad hoc.
if security find-certificate -c "Doorstep Local Signing" >/dev/null 2>&1; then
  codesign --force --sign "Doorstep Local Signing" "$APP" >/dev/null
else
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x Doorstep 2>/dev/null || true
  rm -rf "$HOME/Applications/Doorstep.app"
  mkdir -p "$HOME/Applications"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/Doorstep.app"
  echo "Installed to ~/Applications and launched"
fi
