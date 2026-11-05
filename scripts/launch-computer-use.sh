#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DISPLAY="automatic"
PANEL_MODE="settings"
REUSE=0
usage() {
    echo "Usage: bash scripts/launch-computer-use.sh [--reuse] [--display secondary] [--panel]" >&2
    exit 2
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reuse)
            [[ "$REUSE" == 0 ]] || usage
            REUSE=1
            shift
            ;;
        --display)
            [[ $# -ge 2 && "$2" == secondary && "$TEST_DISPLAY" == automatic ]] || usage
            TEST_DISPLAY="secondary"
            shift 2
            ;;
        --panel)
            [[ "$PANEL_MODE" == settings ]] || usage
            PANEL_MODE="panel"
            shift
            ;;
        *) usage ;;
    esac
done

BRANCH="$(git -C "$ROOT" branch --show-current)"
if [[ -z "$BRANCH" || "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    echo "Error: run this from a named development branch in an isolated worktree." >&2
    exit 2
fi
SUFFIX="$(
    printf '%s' "$BRANCH" | sed -E 's#^codex/##' | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
)"
if [[ -z "$SUFFIX" ]]; then
    echo "Error: branch has no usable development identity." >&2
    exit 2
fi
BUNDLE_ID="com.lingsmbp.StatusTrio.dev.$SUFFIX"
APP_PATH="$ROOT/dist/StatusTrio.app"

mkdir -p "$ROOT/.build"
LOCK_DIR="$ROOT/.build/computer-use-launch.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Error: a Computer Use launch already owns $LOCK_DIR; inspect the owner before retrying." >&2
    exit 1
fi
printf '%s\n' "$$" > "$LOCK_DIR/owner.pid"
release_lock() {
    rm -f "$LOCK_DIR/owner.pid"
    rmdir "$LOCK_DIR"
}
trap release_lock EXIT

# Reuse is read-only: it neither rebuilds nor sends a reopen to the process.
if [[ "$REUSE" == 1 ]]; then
    swift "$ROOT/scripts/computer-use-instance.swift" reuse "$BUNDLE_ID" "$APP_PATH" "$TEST_DISPLAY" "$PANEL_MODE"
    exit 0
fi

# Inspect before building so any running bundle, including another run's test
# instance, is preserved. Its owner must explicitly close it before rebuilding.
swift "$ROOT/scripts/computer-use-instance.swift" prepare "$BUNDLE_ID" "$APP_PATH"
BUNDLE_ID="$BUNDLE_ID" bash "$ROOT/scripts/build-worktree.sh" debug no-open

PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -x "$APP_PATH/Contents/MacOS/StatusTrio" ]]; then
    echo "Error: development app executable is missing: $APP_PATH" >&2
    exit 1
fi
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }
if [[ "$(read_plist CFBundleIdentifier)" != "$BUNDLE_ID" \
    || "$(read_plist STBackgroundUITestingSupported)" != "true" \
    || "$(read_plist STBuildCommit)" != "$(git -C "$ROOT" rev-parse HEAD)" \
    || -z "$(read_plist STDevelopmentCodename)" ]]; then
    echo "Error: bundle must be this branch's Debug dev app with current-SHA testing capability." >&2
    exit 1
fi

swift "$ROOT/scripts/computer-use-instance.swift" launch "$BUNDLE_ID" "$APP_PATH" "$TEST_DISPLAY" "$PANEL_MODE"
shasum -a 256 "$APP_PATH/Contents/MacOS/StatusTrio"
