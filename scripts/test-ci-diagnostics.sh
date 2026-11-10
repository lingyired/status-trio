#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioCIDiagnostics.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export CI_LOG_DIR="$WORK/logs"
export GITHUB_STEP_SUMMARY="$WORK/summary.md"

rc=0
bash "$ROOT/scripts/ci-run-stage.sh" tests bash -c \
    'printf "%s\n" "/repo/Tests/FixtureTests.swift:42: error: FixtureTests.testTimeout : XCTAssertTrue failed"; exit 23' \
    >"$WORK/output" 2>&1 || rc=$?
[[ "$rc" == 23 ]] || { cat "$WORK/output"; echo "FAIL: command exit $rc != 23"; exit 1; }
python3 - "$CI_LOG_DIR/tests.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["exit_code"] == 23, d
assert d["classification"] == "unit-test", d
assert "FixtureTests.swift:42" in d["failure"], d
assert d["duration_seconds"] >= 0, d
assert not d["resource_failure"], d
PY
[[ -f "$CI_LOG_DIR/tests.log" ]] || exit 1
if grep -q 'resource bundle diagnostics' "$WORK/output"; then
    echo "FAIL: non-resource failure dumped bundles"; exit 1
fi

rc=0
bash "$ROOT/scripts/ci-run-stage.sh" compile bash -c \
    'printf "%s\n" "/repo/Sources/A.swift:3:2: error: cannot find x in scope"; exit 7' \
    >"$WORK/output" 2>&1 || rc=$?
[[ "$rc" == 7 ]] || exit 1
python3 - "$CI_LOG_DIR/compile.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["classification"] == "compile", d
PY
rc=0
bash "$ROOT/scripts/ci-run-stage.sh" swift-issue bash -c \
    'echo "Test waitForEvent() recorded an issue at FixtureTests.swift:17:9: Issue recorded: no event"; exit 1' \
    >"$WORK/output" 2>&1 || rc=$?
[[ "$rc" == 1 ]] || exit 1
python3 - "$CI_LOG_DIR/swift-issue.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["classification"] == "unit-test" and "waitForEvent()" in d["failure"], d
PY

rc=0
bash "$ROOT/scripts/ci-run-stage.sh" native bash -c 'echo "FAIL: missing architecture"; exit 9' \
    >"$WORK/output" 2>&1 || rc=$?
[[ "$rc" == 9 ]] || exit 1
bash "$ROOT/scripts/ci-run-stage.sh" successful bash -c 'echo okay' >"$WORK/output" 2>&1
python3 - "$CI_LOG_DIR/native.json" "$CI_LOG_DIR/successful.json" <<'PY'
import json, sys
a, b = [json.load(open(p)) for p in sys.argv[1:]]
assert a["classification"] == "native-contract", a
assert b["classification"] == "passed" and b["exit_code"] == 0, b
PY
rc=0
bash "$ROOT/scripts/ci-run-stage.sh" resources bash -c \
    'echo "Fatal error: unable to find bundle named StatusTrio_StatusTrioCore"; exit 1' \
    >"$WORK/output" 2>&1 || rc=$?
[[ "$rc" == 1 ]] || exit 1
grep -q 'resource bundle diagnostics' "$WORK/output"

# Keep unrecognized failures honest and escape Markdown/HTML in summaries.
rc=0
bash "$ROOT/scripts/ci-run-stage.sh" unknown bash -c \
    'echo "<script> | Failure `quoted`"; exit 8' >"$WORK/output" 2>&1 || rc=$?
[[ "$rc" == 8 ]] || exit 1
GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=fixture/repo GITHUB_RUN_ID=123 \
    JOB_STATUS=failure python3 "$ROOT/scripts/ci-diagnostics.py" summary "$CI_LOG_DIR"
grep -q 'unit-test' "$GITHUB_STEP_SUMMARY"
grep -q 'unknown' "$GITHUB_STEP_SUMMARY"
if grep -q '<script>' "$GITHUB_STEP_SUMMARY"; then exit 1; fi
GITHUB_STEP_SUMMARY="$WORK/native-summary.md" CI_DIAGNOSTIC_JOB=native JOB_STATUS=failure \
    python3 "$ROOT/scripts/ci-diagnostics.py" summary "$CI_LOG_DIR"
grep -q '### Native diagnostics (failure)' "$WORK/native-summary.md"
grep -q 'Raw native logs are retained in the native-diagnostics artifact' "$WORK/native-summary.md"
mkdir "$WORK/empty"
GITHUB_STEP_SUMMARY="$WORK/early.md" JOB_STATUS=failure \
    python3 "$ROOT/scripts/ci-diagnostics.py" summary "$WORK/empty"
grep -q 'before a recorded stage' "$WORK/early.md"

# Recovery checks out the old candidate as cwd and current trusted tooling
# separately. The old checkout need not contain any of the new CI scripts.
mkdir -p "$WORK/old-candidate/scripts"
printf '#!/usr/bin/env bash\necho old-candidate-tests\nexit 0\n' \
    > "$WORK/old-candidate/scripts/test.sh"
(
    cd "$WORK/old-candidate"
    CI_LOG_DIR="$WORK/recovery-logs" bash "$ROOT/scripts/ci-run-stage.sh" \
        tests bash scripts/test.sh >"$WORK/recovery-output"
)
grep -q 'old-candidate-tests' "$WORK/recovery-logs/tests.log"
printf '{incomplete\n' > "$CI_LOG_DIR/broken.json"
printf '{"stage": "partial"}\n' > "$CI_LOG_DIR/partial.json"
GITHUB_STEP_SUMMARY="$WORK/corrupt-summary.md" JOB_STATUS=failure \
    python3 "$ROOT/scripts/ci-diagnostics.py" summary "$CI_LOG_DIR"
grep -q 'Unreadable diagnostic record' "$WORK/corrupt-summary.md"
grep -q 'unit-test' "$WORK/corrupt-summary.md"

# Capture all producer output under pipefail, including a large failed log.
rc=0
bash "$ROOT/scripts/ci-run-stage.sh" large bash -c \
    'for ((i=0;i<20000;i++)); do echo "line $i"; done; exit 19' \
    >"$WORK/output" 2>&1 || rc=$?
[[ "$rc" == 19 ]] || exit 1
[[ "$(wc -l < "$CI_LOG_DIR/large.log" | tr -d ' ')" == 20000 ]] || exit 1
echo "CI diagnostics: exit codes, classifications, resource gating, summaries and full logs passed"
