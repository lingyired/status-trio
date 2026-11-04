#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioComputerUse.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
TEST_ROOT="$FIXTURE/worktree with spaces"
mkdir -p "$TEST_ROOT/scripts" "$FIXTURE/bin"
cp "$ROOT/scripts/launch-computer-use.sh" "$TEST_ROOT/scripts/"
export ST_CUA_FIXTURE_ROOT="$TEST_ROOT"
export ST_CUA_FIXTURE_LOG="$FIXTURE/calls"

cat > "$FIXTURE/bin/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *"branch --show-current") echo "${ST_CUA_FIXTURE_BRANCH:-codex/launch-fixture}" ;;
    *"rev-parse HEAD") echo 0123456789012345678901234567890123456789 ;;
    *) exit 1 ;;
esac
EOF
cat > "$FIXTURE/bin/swift" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$ST_CUA_FIXTURE_LOG"
if [[ "$2" == "prepare" && "${ST_CUA_FIXTURE_BUSY:-0}" == 1 ]]; then exit 1; fi
if [[ ( "$2" == "launch" || "$2" == "reuse" ) && "$5" != "${ST_CUA_FIXTURE_DISPLAY:-automatic}" ]]; then exit 1; fi
if [[ "$2" == "reuse" && "${ST_CUA_FIXTURE_REUSE_MISSING:-0}" == 1 ]]; then exit 1; fi
EOF
cat > "$TEST_ROOT/scripts/build-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == debug && "$2" == no-open ]]
echo build >> "$ST_CUA_FIXTURE_LOG"
mkdir -p "$ST_CUA_FIXTURE_ROOT/dist/StatusTrio.app/Contents/MacOS"
export ST_CUA_FIXTURE_BUNDLE_ID="$BUNDLE_ID"
python3 - <<'PY'
import os, plistlib
from pathlib import Path
root = Path(os.environ["ST_CUA_FIXTURE_ROOT"])/"dist/StatusTrio.app/Contents"
mode = os.environ.get("ST_CUA_FIXTURE_MODE", "")
data = {
 "CFBundleIdentifier": os.environ["ST_CUA_FIXTURE_BUNDLE_ID"],
 "STBackgroundUITestingSupported": mode != "release",
 "STBuildCommit": "0123456789012345678901234567890123456789",
 "STDevelopmentCodename": "Fixture"
}
if mode == "wrong-id": data["CFBundleIdentifier"] = "com.lingsmbp.StatusTrio"
if mode == "stale": data["STBuildCommit"] = "0"*40
with (root/"Info.plist").open("wb") as stream: plistlib.dump(data, stream)
exe=root/"MacOS/StatusTrio"
exe.write_text("#!/bin/sh\nexit 0\n")
exe.chmod(0o644 if mode == "non-executable" else 0o755)
PY
EOF
chmod +x "$FIXTURE/bin/"*
export PATH="$FIXTURE/bin:$PATH"

expect_failure() {
    : > "$ST_CUA_FIXTURE_LOG"
    if "$@" > "$FIXTURE/output" 2>&1; then
        echo "FAIL: unexpectedly succeeded: $*" >&2
        exit 1
    fi
    if rg -q '^launch$' "$ST_CUA_FIXTURE_LOG"; then
        echo "FAIL: launched a rejected fixture" >&2
        exit 1
    fi
}

mkdir -p "$TEST_ROOT/.build/computer-use-launch.lock"
expect_failure bash "$TEST_ROOT/scripts/launch-computer-use.sh"
rmdir "$TEST_ROOT/.build/computer-use-launch.lock"
for mode in release wrong-id stale non-executable; do
    expect_failure env ST_CUA_FIXTURE_MODE="$mode" bash "$TEST_ROOT/scripts/launch-computer-use.sh"
done
expect_failure env ST_CUA_FIXTURE_BUSY=1 bash "$TEST_ROOT/scripts/launch-computer-use.sh"
if rg -q '^build$' "$ST_CUA_FIXTURE_LOG"; then
    echo "FAIL: replaced a busy bundle before preflight" >&2
    exit 1
fi
expect_failure env ST_CUA_FIXTURE_BRANCH=main bash "$TEST_ROOT/scripts/launch-computer-use.sh"
expect_failure bash "$TEST_ROOT/scripts/launch-computer-use.sh" --display primary
expect_failure bash "$TEST_ROOT/scripts/launch-computer-use.sh" --reuse --reuse
expect_failure bash "$TEST_ROOT/scripts/launch-computer-use.sh" --display secondary --display secondary
expect_failure env ST_CUA_FIXTURE_REUSE_MISSING=1 bash "$TEST_ROOT/scripts/launch-computer-use.sh" --reuse
[[ "$(cat "$ST_CUA_FIXTURE_LOG")" == "reuse" ]]
for display in automatic secondary; do
    : > "$ST_CUA_FIXTURE_LOG"
    if [[ "$display" == secondary ]]; then
        ST_CUA_FIXTURE_DISPLAY="$display" bash "$TEST_ROOT/scripts/launch-computer-use.sh" --display secondary > "$FIXTURE/output"
    else
        bash "$TEST_ROOT/scripts/launch-computer-use.sh" > "$FIXTURE/output"
    fi
    [[ "$(cat "$ST_CUA_FIXTURE_LOG")" == $'prepare\nbuild\nlaunch' ]]
done
for display in automatic secondary; do
    : > "$ST_CUA_FIXTURE_LOG"
    if [[ "$display" == secondary ]]; then
        ST_CUA_FIXTURE_DISPLAY="$display" bash "$TEST_ROOT/scripts/launch-computer-use.sh" --reuse --display secondary > "$FIXTURE/output"
    else
        bash "$TEST_ROOT/scripts/launch-computer-use.sh" --reuse > "$FIXTURE/output"
    fi
    [[ "$(cat "$ST_CUA_FIXTURE_LOG")" == "reuse" ]]
done
echo "Computer Use launcher: 15 isolation, lock, capability, argument, reuse and ordering cases passed."
