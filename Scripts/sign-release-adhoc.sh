#!/usr/bin/env bash
# Local signatures only: never publish these as trusted updates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 1 ]] || { echo "usage: $0 Screentime++.app" >&2; exit 2; }
APP="$1"
[[ -d "$APP" && ! -L "$APP" && -x "$APP/Contents/MacOS/Screentime++" ]]
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
[[ -d "$SPARKLE" ]]
for code in "$SPARKLE/Updater.app" "$SPARKLE/XPCServices/Downloader.xpc" "$SPARKLE/XPCServices/Installer.xpc" "$SPARKLE/Autoupdate" "$SPARKLE"; do
  codesign --force --sign - --timestamp=none --options runtime     --preserve-metadata=identifier,entitlements "$code"
done
for code in "$APP/Contents/MacOS/Screentime++.debug.dylib" "$APP/Contents/MacOS/__preview.dylib"; do
  [[ ! -f "$code" ]] || codesign --force --sign - --timestamp=none --options runtime "$code"
done
codesign --force --sign - --timestamp=none --options runtime   --identifier dev.screentimepp.app --entitlements "$ROOT/Config/Screentime.entitlements"   --generate-entitlement-der "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "complete ad-hoc release signatures applied"
