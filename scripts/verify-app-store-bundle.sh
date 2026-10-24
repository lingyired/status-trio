#!/usr/bin/env bash
# Static App Store bundle gate. This never launches the app or its components.
set -euo pipefail

usage() {
    echo "Usage: $0 APP_PATH [--unsigned]" >&2
}

APP=""
UNSIGNED=0
for arg in "$@"; do
    case "$arg" in
        --unsigned)
            UNSIGNED=1
            ;;
        -*)
            usage
            echo "Error: unsupported option: $arg" >&2
            exit 2
            ;;
        *)
            if [[ -n "$APP" ]]; then
                usage
                echo "Error: only one APP_PATH is accepted." >&2
                exit 2
            fi
            APP="$arg"
            ;;
    esac
done

if [[ -z "$APP" ]]; then
    usage
    exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUDITOR="$SCRIPT_DIR/app-store-bundle-audit.py"

if [[ ! -f "$AUDITOR" || ! -r "$AUDITOR" ]]; then
    echo "Error: missing readable auditor at $AUDITOR" >&2
    exit 1
fi

ARGS=("$APP")
if [[ "$UNSIGNED" == "1" ]]; then
    ARGS+=(--unsigned)
fi

exec python3 "$AUDITOR" "${ARGS[@]}"
