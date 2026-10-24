#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
"$ROOT/Scripts/verify-version.sh"
"$ROOT/Scripts/xcodegen.sh" generate
xcodebuild -project "$ROOT/Screentime.xcodeproj" -scheme ScreentimeApp   -configuration Debug -derivedDataPath "$ROOT/build/DerivedData"   -destination "platform=macOS,arch=$(uname -m)"   CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build
"$ROOT/Scripts/sign-release-adhoc.sh" "$ROOT/build/DerivedData/Build/Products/Debug/Screentime++.app"
"$ROOT/Scripts/verify-version.sh" --products "$ROOT/build/DerivedData/Build/Products/Debug"
