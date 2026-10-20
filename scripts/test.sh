#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Enforce the AGENTS.md rule the CI toolchain needs: never pass an
# actor-isolated method as a function value (docs/swift-ci-compatibility.md).
# Unconditional, so a filtered run still enforces the rule even though
# ForbiddenPatternGuardTests is filtered out.
bash "$SCRIPT_DIR/check-forbidden-patterns.sh"

if [[ $# -gt 0 ]]; then
    FILTER_LOG="$(mktemp "${TMPDIR:-/tmp}/StatusTrioFilteredTest.XXXXXX")"
    trap 'rm -f "$FILTER_LOG"' EXIT
    set +e
    swift test --filter "$1" 2>&1 | tee "$FILTER_LOG"
    TEST_STATUS="${PIPESTATUS[0]}"
    set -e
    if [[ "$TEST_STATUS" -ne 0 ]]; then
        exit "$TEST_STATUS"
    fi
    if grep -Fq "No matching test cases were run" "$FILTER_LOG"; then
        echo "Error: Swift test filter matched no test cases: $1" >&2
        exit 1
    fi
else
    swift test
fi
