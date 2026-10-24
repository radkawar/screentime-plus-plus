#!/usr/bin/env bash
# Submit one signed release artifact to Apple's notary service and require acceptance.
set -euo pipefail

KEYCHAIN_PROFILE="${SCREENTIME_NOTARY_PROFILE:-}"
KEY_PATH="${SCREENTIME_NOTARY_KEY_PATH:-}"
KEY_ID="${SCREENTIME_NOTARY_KEY_ID:-}"
ISSUER_ID="${SCREENTIME_NOTARY_ISSUER_ID:-}"
ARTIFACT=""

usage() {
  cat <<EOF
Usage: $0 [authentication options] artifact

Authentication options:
  --keychain-profile NAME  Use a notarytool credential profile.
  --key PATH               Use an App Store Connect API private key.
  --key-id ID              App Store Connect API key ID.
  --issuer ID              App Store Connect API issuer ID.

The same values may be supplied through SCREENTIME_NOTARY_PROFILE or the
SCREENTIME_NOTARY_KEY_PATH, SCREENTIME_NOTARY_KEY_ID, and
SCREENTIME_NOTARY_ISSUER_ID environment variables.
EOF
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
    --keychain-profile)
      require_value "$1" "${2:-}"
      KEYCHAIN_PROFILE="$2"
      shift 2
      ;;
    --key)
      require_value "$1" "${2:-}"
      KEY_PATH="$2"
      shift 2
      ;;
    --key-id)
      require_value "$1" "${2:-}"
      KEY_ID="$2"
      shift 2
      ;;
    --issuer)
      require_value "$1" "${2:-}"
      ISSUER_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$ARTIFACT" ]]; then
        echo "error: expected one artifact" >&2
        exit 2
      fi
      ARTIFACT="$1"
      shift
      ;;
  esac
done

if [[ -z "$ARTIFACT" || ! -f "$ARTIFACT" || -L "$ARTIFACT" ]]; then
  echo "error: notarization artifact is missing, linked, or not a file: $ARTIFACT" >&2
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun is required for notarization" >&2
  exit 1
fi

AUTHENTICATION=()
if [[ -n "$KEYCHAIN_PROFILE" ]]; then
  if [[ -n "$KEY_PATH" || -n "$KEY_ID" || -n "$ISSUER_ID" ]]; then
    echo "error: choose a Keychain profile or API key authentication, not both" >&2
    exit 2
  fi
  AUTHENTICATION=(--keychain-profile "$KEYCHAIN_PROFILE")
else
  if [[ -z "$KEY_PATH" || -z "$KEY_ID" || -z "$ISSUER_ID" ]]; then
    echo "error: complete notarytool authentication is required" >&2
    exit 2
  fi
  if [[ ! -f "$KEY_PATH" || -L "$KEY_PATH" ]]; then
    echo "error: App Store Connect private key is missing or linked: $KEY_PATH" >&2
    exit 1
  fi
  AUTHENTICATION=(--key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID")
fi

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/screentime-plus-plus-notary.XXXXXX")"
cleanup_notary_work() {
  rm -rf -- "$WORK_ROOT"
}
trap cleanup_notary_work EXIT INT TERM

RESULT_JSON="$WORK_ROOT/result.json"
if ! xcrun notarytool submit "$ARTIFACT" \
  "${AUTHENTICATION[@]}" \
  --wait \
  --output-format json >"$RESULT_JSON"; then
  echo "error: notarytool submission failed: $ARTIFACT" >&2
  exit 1
fi

STATUS="$(plutil -extract status raw -o - "$RESULT_JSON" 2>/dev/null || true)"
SUBMISSION_ID="$(plutil -extract id raw -o - "$RESULT_JSON" 2>/dev/null || true)"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "error: Apple notarization status was ${STATUS:-unknown}: $ARTIFACT" >&2
  if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" "${AUTHENTICATION[@]}" >&2 || true
  fi
  exit 1
fi

echo "Apple notarization accepted: $ARTIFACT"
echo "submission: $SUBMISSION_ID"
