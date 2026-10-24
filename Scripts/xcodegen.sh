#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PINNED_VERSION="2.45.4"
EXPECTED_VERSION_OUTPUT="Version: $PINNED_VERSION"
ARCHIVE_URL="https://github.com/yonaskolb/XcodeGen/releases/download/$PINNED_VERSION/xcodegen.zip"
ARCHIVE_SHA256="090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef"
CACHE_ROOT="$ROOT/build/Tools"
CACHE_PACKAGE="$CACHE_ROOT/xcodegen-$PINNED_VERSION"
CACHED_TOOL="$CACHE_PACKAGE/bin/xcodegen"

tool_is_pinned() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  [[ "$("$candidate" --version 2>/dev/null | head -n 1)" == "$EXPECTED_VERSION_OUTPUT" ]]
}

resolve_existing_tool() {
  local candidate=""

  if command -v xcodegen >/dev/null 2>&1; then
    candidate="$(command -v xcodegen)"
    if tool_is_pinned "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if tool_is_pinned "$ROOT/.tools/xcodegen"; then
    printf '%s\n' "$ROOT/.tools/xcodegen"
    return 0
  fi

  if tool_is_pinned "$CACHED_TOOL"; then
    printf '%s\n' "$CACHED_TOOL"
    return 0
  fi

  return 1
}

download_pinned_tool() {
  command -v curl >/dev/null 2>&1 || {
    echo "error: curl is required to download pinned XcodeGen" >&2
    return 1
  }
  command -v unzip >/dev/null 2>&1 || {
    echo "error: unzip is required to unpack pinned XcodeGen" >&2
    return 1
  }
  command -v shasum >/dev/null 2>&1 || {
    echo "error: shasum is required to verify pinned XcodeGen" >&2
    return 1
  }

  mkdir -p "$CACHE_ROOT"
  local staging
  staging="$(mktemp -d "$CACHE_ROOT/xcodegen-download.XXXXXX")"
  local archive="$staging/xcodegen.zip"
  local extracted="$staging/extracted"

  # Invoked by the EXIT/INT/TERM trap below.
  # shellcheck disable=SC2329
  cleanup_xcodegen_download() {
    rm -rf -- "$staging"
  }
  trap cleanup_xcodegen_download EXIT INT TERM

  echo "xcodegen: downloading pinned $PINNED_VERSION" >&2
  curl --fail --location --silent --show-error "$ARCHIVE_URL" --output "$archive"

  local actual_sha256
  actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$ARCHIVE_SHA256" ]]; then
    echo "error: XcodeGen archive checksum mismatch" >&2
    return 1
  fi

  mkdir -p "$extracted"
  unzip -q "$archive" -d "$extracted"
  if ! tool_is_pinned "$extracted/xcodegen/bin/xcodegen"; then
    echo "error: downloaded XcodeGen has an unexpected version or layout" >&2
    return 1
  fi

  if [[ -e "$CACHE_PACKAGE" ]]; then
    echo "error: invalid cached XcodeGen exists at $CACHE_PACKAGE" >&2
    return 1
  fi
  mv "$extracted/xcodegen" "$CACHE_PACKAGE"
  chmod 755 "$CACHED_TOOL"

  trap - EXIT INT TERM
  rm -rf -- "$staging"
  printf '%s\n' "$CACHED_TOOL"
}

if [[ -n "${SCREENTIME_XCODEGEN:-}" ]]; then
  if ! tool_is_pinned "$SCREENTIME_XCODEGEN"; then
    echo "error: SCREENTIME_XCODEGEN must point to XcodeGen $PINNED_VERSION" >&2
    exit 1
  fi
  XCODEGEN_TOOL="$SCREENTIME_XCODEGEN"
else
  XCODEGEN_TOOL="$(resolve_existing_tool || download_pinned_tool)"
fi
cd "$ROOT"
exec "$XCODEGEN_TOOL" "$@"
