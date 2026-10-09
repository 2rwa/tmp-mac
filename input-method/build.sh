#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT="$ROOT/dist"
if [ "$#" -gt 0 ]; then OUTPUT="$1"; fi
APP="$OUTPUT/InputMethodStatus.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/input-method/Info.plist" "$APP/Contents/Info.plist"
xcrun swiftc -O -framework AppKit -framework Carbon \
  "$ROOT/input-method/Sources/InputMethodStatus.swift" \
  -o "$APP/Contents/MacOS/InputMethodStatus"
plutil -lint "$APP/Contents/Info.plist"
echo "Built: $APP"
