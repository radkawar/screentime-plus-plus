#!/usr/bin/env bash
# Verify the one-source product version across source, tags, and built artifacts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_CONFIG="$ROOT/Config/Version.xcconfig"
APP_INFO_SOURCE="$ROOT/Config/Info.plist"
PRODUCTS_PATH=""
RELEASE_TAG="${SCREENTIME_RELEASE_TAG:-}"

usage() {
  echo "usage: $0 [--products PATH] [--tag vMAJOR.MINOR.PATCH]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --products)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      PRODUCTS_PATH="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      RELEASE_TAG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$VERSION_CONFIG" || -L "$VERSION_CONFIG" ]]; then
  echo "error: authoritative product version config is missing or is a symlink" >&2
  exit 1
fi

read_setting() {
  local key="$1"
  /usr/bin/awk -v key="$key" '
    {
      sub(/\/\/.*/, "", $0)
      split($0, fields, "=")
      setting = fields[1]
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", setting)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (setting == key && value != "") {
        matches += 1
        result = value
      }
    }
    END {
      if (matches != 1) exit 1
      print result
    }
  ' "$VERSION_CONFIG"
}

MARKETING_VERSION="$(read_setting MARKETING_VERSION)" || {
  echo "error: Version.xcconfig must define MARKETING_VERSION exactly once" >&2
  exit 1
}
BUILD_VERSION="$(read_setting CURRENT_PROJECT_VERSION)" || {
  echo "error: Version.xcconfig must define CURRENT_PROJECT_VERSION exactly once" >&2
  exit 1
}

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION must be a three-component semantic version" >&2
  exit 1
fi
if [[ ! "$BUILD_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: CURRENT_PROJECT_VERSION must be a positive integer" >&2
  exit 1
fi

INFO_MARKETING="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP_INFO_SOURCE")"
INFO_BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$APP_INFO_SOURCE")"
if [[ "$INFO_MARKETING" != "\$(MARKETING_VERSION)" ]]; then
  echo "error: Config/Info.plist does not substitute MARKETING_VERSION" >&2
  exit 1
fi
if [[ "$INFO_BUILD" != "\$(CURRENT_PROJECT_VERSION)" ]]; then
  echo "error: Config/Info.plist does not substitute CURRENT_PROJECT_VERSION" >&2
  exit 1
fi

if ! /usr/bin/grep -Fq \
  'Debug: Config/Version.xcconfig' \
  "$ROOT/project.yml" \
  || ! /usr/bin/grep -Fq \
    'Release: Config/Version.xcconfig' \
    "$ROOT/project.yml"; then
  echo "error: project.yml does not use the authoritative version config for every configuration" >&2
  exit 1
fi

if [[ -z "$RELEASE_TAG" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  RELEASE_TAG="${GITHUB_REF_NAME:-}"
fi
if [[ -n "$RELEASE_TAG" && "$RELEASE_TAG" != "v$MARKETING_VERSION" ]]; then
  echo "error: release tag $RELEASE_TAG does not match v$MARKETING_VERSION" >&2
  exit 1
fi

verify_plist() {
  local plist="$1"
  local label="$2"
  if [[ ! -f "$plist" ]]; then
    echo "error: $label Info.plist is missing: $plist" >&2
    exit 1
  fi
  local actual_marketing actual_build
  actual_marketing="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null || true)"
  actual_build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$plist" 2>/dev/null || true)"
  if [[ "$actual_marketing" != "$MARKETING_VERSION" || "$actual_build" != "$BUILD_VERSION" ]]; then
    echo "error: $label version is ${actual_marketing:-missing} (${actual_build:-missing}); expected $MARKETING_VERSION ($BUILD_VERSION)" >&2
    exit 1
  fi
}

if [[ -n "$PRODUCTS_PATH" ]]; then
  APP="$PRODUCTS_PATH/Screentime++.app"
  verify_plist "$APP/Contents/Info.plist" "Screentime++.app"
fi

echo "ok: Screentime++ version $MARKETING_VERSION ($BUILD_VERSION)"
if [[ -n "$RELEASE_TAG" ]]; then
  echo "ok: release tag $RELEASE_TAG"
fi
