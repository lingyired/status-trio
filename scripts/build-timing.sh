#!/usr/bin/env bash
# Source in build scripts. Phase names are fixed labels, never command arguments.
BUILD_PHASE_NAME=""
BUILD_PHASE_STARTED="$SECONDS"

build_timing_finish() {
    local result="${1:-0}"
    if [[ -n "$BUILD_PHASE_NAME" ]]; then
        local elapsed="$((SECONDS - BUILD_PHASE_STARTED))"
        printf 'BUILD_TIMING phase=%s seconds=%s exit=%s\n' \
            "$BUILD_PHASE_NAME" "$elapsed" "$result" >&2 || :
        if [[ -n "${BUILD_TIMING_FILE:-}" ]]; then
            if ! printf '%s\t%s\t%s\n' "$BUILD_PHASE_NAME" "$elapsed" "$result" \
                >> "$BUILD_TIMING_FILE"; then
                printf 'Warning: could not record build timing for %s.\n' \
                    "$BUILD_PHASE_NAME" >&2 || :
            fi
        fi
        BUILD_PHASE_NAME=""
    fi
    return 0
}

build_phase() {
    build_timing_finish 0
    BUILD_PHASE_NAME="$1"
    BUILD_PHASE_STARTED="$SECONDS"
}
