#!/usr/bin/env bash
# Local signatures only: never publish these as trusted updates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 1 ]] || { echo "usage: $0 Screentime++.app" >&2; exit 2; }
APP="$1"
[[ -d "$APP" && ! -L "$APP" && -x "$APP/Contents/MacOS/Screentime++" ]]
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
[[ -d "$SPARKLE" ]]
WIDGET="$APP/Contents/PlugIns/ScreentimeWidget.appex"
[[ -d "$WIDGET" && ! -L "$WIDGET" ]]
codesign --force --sign - --timestamp=none --options runtime \
  --identifier dev.screentimepp.app.widget --entitlements "$ROOT/Config/ScreentimeWidget.entitlements" \
  --generate-entitlement-der "$WIDGET"
codesign --force --sign - --timestamp=none --options runtime \
  --identifier dev.screentimepp.guard "$APP/Contents/MacOS/screentime-guard"
for code in "$SPARKLE/Updater.app" "$SPARKLE/XPCServices/Downloader.xpc" "$SPARKLE/XPCServices/Installer.xpc" "$SPARKLE/Autoupdate" "$SPARKLE"; do
  codesign --force --sign - --timestamp=none --options runtime     --preserve-metadata=identifier,entitlements "$code"
done
for code in "$APP/Contents/MacOS/Screentime++.debug.dylib" "$APP/Contents/MacOS/__preview.dylib"; do
  [[ ! -f "$code" ]] || codesign --force --sign - --timestamp=none --options runtime "$code"
done
codesign --force --sign - --timestamp=none --options runtime   --identifier dev.screentimepp.app --entitlements "$ROOT/Config/Screentime.entitlements"   --generate-entitlement-der "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$WIDGET"
echo "complete ad-hoc release signatures applied"
