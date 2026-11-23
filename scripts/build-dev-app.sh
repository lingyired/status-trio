#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_BUNDLE_ID="${DEV_BUNDLE_ID:-com.lingsmbp.StatusTrio.Dev}"
DEV_APP_NAME="${DEV_APP_NAME:-Status Trio Dev}"
DEV_APP_VERSION="${DEV_APP_VERSION:-2.0.0}"
DEV_BUILD_NUMBER="${DEV_BUILD_NUMBER:-19}"
DEV_CODENAME="${DEV_CODENAME:-Icon Designer}"
DEV_APP_PATH="$ROOT/dist-dev/Status Trio Dev.app"

if [[ "$DEV_BUNDLE_ID" == "com.lingsmbp.StatusTrio" ]]; then
    echo "Error: developer build bundle ID must differ from production." >&2
    exit 2
fi
if [[ "$DEV_APP_PATH" == "$ROOT/dist/StatusTrio.app" ]]; then
    echo "Error: developer build output path must differ from production." >&2
    exit 2
fi

# Resolve exactly one valid Developer ID identity unless the caller explicitly
# supplies CODE_SIGN_IDENTITY (including "-" for intentional ad-hoc signing).
SIGNING_IDENTITY="$(bash "$ROOT/scripts/resolve-local-dev-signing-identity.sh")"

exec env \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    BUNDLE_ID="$DEV_BUNDLE_ID" \
    APP_NAME="$DEV_APP_NAME" \
    APP_VERSION="$DEV_APP_VERSION" \
    BUILD_NUMBER="$DEV_BUILD_NUMBER" \
    APP_OUTPUT_PATH="$DEV_APP_PATH" \
    DEVELOPMENT_CODENAME="$DEV_CODENAME" \
    DISABLE_PRODUCTION_UPDATES=1 \
    bash "$ROOT/scripts/build-app.sh" "${1:-release}" "${2:-open}"
