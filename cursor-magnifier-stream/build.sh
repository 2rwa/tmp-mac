#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/build}"
APP="$OUT/CursorMagnifierStream.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
xcrun swiftc -O -swift-version 5 \
  -target arm64-apple-macos15.2 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework AppKit -framework CoreGraphics \
  -framework ScreenCaptureKit -framework CoreImage \
  "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/CursorMagnifierStream"
codesign --force --sign - "$APP"
echo "Built $APP"
