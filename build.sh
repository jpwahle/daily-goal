#!/bin/bash
# Build Daily Goal.app into ./dist. Pass --run to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"

# Pin the sysroot explicitly. Without it, clang also scans /usr/local/include,
# which on some machines holds stray SDK header copies that break module builds.
export SDKROOT="$(xcrun --show-sdk-path)"

echo "▸ Compiling (release)…"
swift build -c release

APP="dist/Daily Goal.app"
BIN=".build/release/DailyGoal"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DailyGoal"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "▸ Generating app icon…"
  rm -rf .build/AppIcon.iconset
  mkdir -p .build/AppIcon.iconset
  swift Scripts/MakeIcon.swift .build/AppIcon.iconset
  iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "✓ Built $APP"

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
