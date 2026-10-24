#!/usr/bin/env bash
# Build, sign, validate, and package a universal Screenlogger release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/releases"
PRODUCTS=""
EXPECTED_TAG=""
SIGNING_MODE="ad-hoc"
SIGNING_IDENTITY="${SCREENTIME_SIGNING_IDENTITY:-}"
SIGNING_TEAM_ID="${SCREENTIME_TEAM_ID:-3UX5N7Y8TY}"
NOTARY_PROFILE="${SCREENTIME_NOTARY_PROFILE:-}"
NOTARY_KEY_PATH="${SCREENTIME_NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${SCREENTIME_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${SCREENTIME_NOTARY_ISSUER_ID:-}"

usage() {
  cat <<'USAGE'
Usage: Scripts/package-release.sh [options]

Options:
  --products DIR       Package existing universal Release products instead of building.
  --output DIR         Write release assets here (default: build/releases).
  --expected-tag TAG   Require TAG to equal v<app marketing version>.
  --signing MODE       Use ad-hoc or developer-id signing (default: ad-hoc).
  --identity NAME      Developer ID Application identity for production signing.
  --team-id ID         Require this Developer ID Team ID in every signature.
  --notary-profile ID  Use a local notarytool Keychain credential profile.
  --notary-key PATH    Use an App Store Connect API private key.
  --notary-key-id ID   App Store Connect API key ID.
  --notary-issuer ID   App Store Connect API issuer ID.
  -h, --help           Show this help.

Developer ID mode signs every nested executable with Hardened Runtime and a
secure timestamp, notarizes and staples the app and DMG,  Packaging never publishes or replaces an installed application.
USAGE
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "error: $option requires a value" >&2
    exit 2
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --products)
      require_value "$1" "${2:-}"
      PRODUCTS="$2"
      shift 2
      ;;
    --output)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --expected-tag)
      require_value "$1" "${2:-}"
      EXPECTED_TAG="$2"
      shift 2
      ;;
    --signing)
      require_value "$1" "${2:-}"
      SIGNING_MODE="$2"
      shift 2
      ;;
    --identity)
      require_value "$1" "${2:-}"
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --team-id)
      require_value "$1" "${2:-}"
      SIGNING_TEAM_ID="$2"
      shift 2
      ;;
    --notary-profile)
      require_value "$1" "${2:-}"
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --notary-key)
      require_value "$1" "${2:-}"
      NOTARY_KEY_PATH="$2"
      shift 2
      ;;
    --notary-key-id)
      require_value "$1" "${2:-}"
      NOTARY_KEY_ID="$2"
      shift 2
      ;;
    --notary-issuer)
      require_value "$1" "${2:-}"
      NOTARY_ISSUER_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$SIGNING_MODE" != "ad-hoc" && "$SIGNING_MODE" != "developer-id" ]]; then
  echo "error: --signing must be ad-hoc or developer-id" >&2
  exit 2
fi
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "error: Developer ID mode requires --identity" >&2
    exit 2
  fi
  if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ -n "$NOTARY_KEY_PATH" || -n "$NOTARY_KEY_ID" || -n "$NOTARY_ISSUER_ID" ]]; then
      echo "error: choose a notary Keychain profile or API key authentication" >&2
      exit 2
    fi
  elif [[ -z "$NOTARY_KEY_PATH" || -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER_ID" ]]; then
    echo "error: Developer ID mode requires complete notarytool authentication" >&2
    exit 2
  fi
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$ROOT/$OUTPUT_DIR"
fi
if [[ "$OUTPUT_DIR" == "/" || "$OUTPUT_DIR" == *$'\n'* ]]; then
  echo "error: output directory must be a non-root path without newlines" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ -z "${DEVELOPER_DIR:-}" || ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: a complete Xcode installation is required" >&2
  exit 1
fi

required_commands=(codesign ditto find hdiutil lipo otool plutil shasum stat xcodebuild)
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  required_commands+=(security spctl xcrun)
fi
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required tool is unavailable: $command_name" >&2
    exit 1
  fi
done

SOURCE_EPOCH="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$SOURCE_EPOCH" ]] && command -v git >/dev/null 2>&1; then
  SOURCE_EPOCH="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || true)"
fi
if [[ ! "$SOURCE_EPOCH" =~ ^[0-9]+$ ]]; then
  echo "error: SOURCE_DATE_EPOCH must be an integer (or package from a Git checkout)" >&2
  exit 1
fi
export SOURCE_DATE_EPOCH="$SOURCE_EPOCH"

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/screentime-package.XXXXXX")"
DMG_VERIFY_MOUNT=""
cleanup_package_work() {
  if [[ -n "$DMG_VERIFY_MOUNT" ]]; then
    /usr/bin/hdiutil detach "$DMG_VERIFY_MOUNT" -force >/dev/null 2>&1 || true
  fi
  rm -rf -- "$WORK_ROOT"
}
trap cleanup_package_work EXIT INT TERM

if [[ -z "$PRODUCTS" ]]; then
  "$ROOT/Scripts/xcodegen.sh" generate

  DERIVED_DATA="$WORK_ROOT/DerivedData"
  xcodebuild \
    -project "$ROOT/Screentime.xcodeproj" \
    -scheme ScreentimeApp \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build
  PRODUCTS="$DERIVED_DATA/Build/Products/Release"
elif [[ "$PRODUCTS" != /* ]]; then
  PRODUCTS="$ROOT/$PRODUCTS"
fi

if [[ ! -d "$PRODUCTS" ]]; then
  echo "error: Release products directory not found: $PRODUCTS" >&2
  exit 1
fi
PRODUCTS="$(cd "$PRODUCTS" && pwd -P)"

VERSION_VERIFICATION_ARGS=(--products "$PRODUCTS")
if [[ -n "$EXPECTED_TAG" ]]; then
  VERSION_VERIFICATION_ARGS+=(--tag "$EXPECTED_TAG")
fi
"$ROOT/Scripts/verify-version.sh" "${VERSION_VERIFICATION_ARGS[@]}"

APP="$PRODUCTS/Screentime++.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
PACKAGE_NAME="ScreentimePlusPlus-v$VERSION-macos-universal"
for output in "$OUTPUT_DIR/$PACKAGE_NAME.dmg" "$OUTPUT_DIR/$PACKAGE_NAME.dmg.sha256"; do
  [[ ! -e "$output" && ! -L "$output" ]] || { echo "error: refusing to overwrite $output" >&2; exit 1; }
done
STAGE="$WORK_ROOT/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Screentime++.app"
APP="$STAGE/Screentime++.app"
# Validate every Mach-O, including Sparkle helper executables, before signing.
while IFS= read -r -d '' binary; do
  if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    # Xcode 27's lipo accepts a single architecture per -verify_arch.
    for arch in arm64 x86_64; do lipo "$binary" -verify_arch "$arch"; done
  fi
done < <(find "$APP" -type f -print0)
ARCHIVE_TIMESTAMP="$(/bin/date -r "$SOURCE_EPOCH" '+%Y%m%d%H%M.%S')"
find -s "$STAGE" -depth -exec touch -h -t "$ARCHIVE_TIMESTAMP" {} +
notarize_artifact() {
  SCREENTIME_NOTARY_PROFILE="$NOTARY_PROFILE"   SCREENTIME_NOTARY_KEY_PATH="$NOTARY_KEY_PATH"   SCREENTIME_NOTARY_KEY_ID="$NOTARY_KEY_ID"   SCREENTIME_NOTARY_ISSUER_ID="$NOTARY_ISSUER_ID"     "$ROOT/Scripts/notarize-release-artifact.sh" "$1"
}
verify_app() {
  codesign --verify --deep --strict --verbose=2 "$1"
  codesign --verify --strict --verbose=2 "$1/Contents/PlugIns/ScreentimeWidget.appex"
  if [[ "$SIGNING_MODE" == developer-id ]]; then
    xcrun stapler validate "$1"
    spctl --assess --type execute --verbose=4 "$1"
  fi
}
if [[ "$SIGNING_MODE" == developer-id ]]; then
  "$ROOT/Scripts/sign-release-developer-id.sh" --identity "$SIGNING_IDENTITY" --team-id "$SIGNING_TEAM_ID" "$APP"
  ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$APP" "$WORK_ROOT/app-notary.zip"
  notarize_artifact "$WORK_ROOT/app-notary.zip"
  xcrun stapler staple "$APP"
else
  "$ROOT/Scripts/sign-release-adhoc.sh" "$APP"
fi
verify_app "$APP"
DMG_TMP="$WORK_ROOT/$PACKAGE_NAME.dmg"
"$ROOT/Scripts/create-dmg.sh" --app "$APP" --output "$DMG_TMP" --volume-name 'Screentime++'
if [[ "$SIGNING_MODE" == developer-id ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_TMP"
  codesign --verify --strict --verbose=2 "$DMG_TMP"
  notarize_artifact "$DMG_TMP"
  xcrun stapler staple "$DMG_TMP"
  xcrun stapler validate "$DMG_TMP"
  codesign --verify --strict --verbose=2 "$DMG_TMP"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_TMP"
fi
DMG_VERIFY_MOUNT="$WORK_ROOT/dmg-verify"
mkdir -p "$DMG_VERIFY_MOUNT"
hdiutil attach -readonly -nobrowse -owners off -mountpoint "$DMG_VERIFY_MOUNT" "$DMG_TMP" >/dev/null
verify_app "$DMG_VERIFY_MOUNT/Screentime++.app"
cmp "$APP/Contents/MacOS/Screentime++" "$DMG_VERIFY_MOUNT/Screentime++.app/Contents/MacOS/Screentime++"
hdiutil detach "$DMG_VERIFY_MOUNT" >/dev/null
DMG_VERIFY_MOUNT=""
# Hash only the final stapled bytes.
(cd "$WORK_ROOT" && shasum -a 256 "$PACKAGE_NAME.dmg" >"$PACKAGE_NAME.dmg.sha256")
# Never overwrite existing release assets.
cp -n "$DMG_TMP" "$OUTPUT_DIR/$PACKAGE_NAME.dmg"
cp -n "$WORK_ROOT/$PACKAGE_NAME.dmg.sha256" "$OUTPUT_DIR/$PACKAGE_NAME.dmg.sha256"
echo "release package verified: $OUTPUT_DIR/$PACKAGE_NAME.dmg ($SIGNING_MODE)"
