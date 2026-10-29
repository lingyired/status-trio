#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioPowerUITest.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun clang -fobjc-arc -Wall -Wextra -mmacosx-version-min=13.0 \
    -I "$ROOT/Sources/PowerUIPrivateAPI/include" \
    -framework Foundation \
    "$ROOT/Tests/PowerUIPrivateAPITests/RestoreChargeLimitTests.m" \
    -o "$TEST_DIR/restore-tests"
"$TEST_DIR/restore-tests"
