#!/usr/bin/env bash
# Exercise only the real helper's version probe; no compiler or dependency build.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
# Always exercise the launcher's adverse signal state, including local runs.
trap '' PIPE

# Non-interactive Bash cannot reset a signal ignored when it starts. Use a
# native producer that owns SIGPIPE even when the CI launcher ignores it.
cat > "$TEST_ROOT/clang.c" <<'CLANG'
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    if (signal(SIGPIPE, SIG_DFL) == SIG_ERR) return 70;
    const char header[] = "Apple clang version fixture\n";
    if (write(STDOUT_FILENO, header, sizeof(header) - 1) != sizeof(header) - 1) return 71;
    const char *status = getenv("PRODUCER_STATUS");
    if (status && atoi(status) != 0) return atoi(status);
    char payload[4097];
    memset(payload, ' ', sizeof(payload));
    payload[sizeof(payload) - 1] = '\n';
    for (int line = 0; line < 1024; ++line) {
        if (write(STDOUT_FILENO, payload, sizeof(payload)) != sizeof(payload)) return 72;
    }
    return 0;
}
CLANG
xcrun clang "$TEST_ROOT/clang.c" -o "$TEST_ROOT/clang"

# Keep the old pipeline as a control: output exceeds pipe capacity, so head
# closes the read end while the producer is still writing.
status=0
CLANG="$TEST_ROOT/clang" /bin/bash -euo pipefail -c \
    'CLANG_VERSION="$("$CLANG" --version | head -n 1)"' \
    > "$TEST_ROOT/legacy.log" 2>&1 || status=$?
if [[ "$status" != 141 ]]; then
    echo "FAIL: legacy truncating pipeline exited $status instead of SIGPIPE (141)." >&2
    cat "$TEST_ROOT/legacy.log" >&2
    exit 1
fi

# Extract the production assignments up to BUILD_KEY rather than duplicating
# the fix, and stop before any SDK, cache, architecture, or build operations.
ruby -e '
  source = File.read(ARGV[0])
  start = source.index(/^    CLANG_VERSION=/) or abort "missing version probe"
  finish = source.index(/^    BUILD_KEY=/, start) or abort "missing build-key boundary"
  File.write(ARGV[1], source[start...finish] + %q{printf "%s\n" "$CLANG_VERSION"} + "\n")
' "$ROOT/scripts/build-mobile-battery-helper.sh" "$TEST_ROOT/probe.sh"

status=0
CLANG="$TEST_ROOT/clang" /bin/bash -euo pipefail "$TEST_ROOT/probe.sh" \
    > "$TEST_ROOT/version.log" 2>&1 || status=$?
if [[ "$status" != 0 || "$(<"$TEST_ROOT/version.log")" != 'Apple clang version fixture' ]]; then
    echo "FAIL: production version capture exited $status or changed the first line." >&2
    exit 1
fi

status=0
CLANG="$TEST_ROOT/clang" PRODUCER_STATUS=23 /bin/bash -euo pipefail "$TEST_ROOT/probe.sh" \
    > "$TEST_ROOT/failure.log" 2>&1 || status=$?
if [[ "$status" != 23 || -s "$TEST_ROOT/failure.log" ]]; then
    echo "FAIL: producer failure was not preserved (exit $status)." >&2
    exit 1
fi
echo 'clang version capture: legacy SIGPIPE reproduced, first line preserved, producer failure propagated'
