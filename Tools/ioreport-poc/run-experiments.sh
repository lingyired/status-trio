#!/usr/bin/env bash
# Reproducible measurement batch for docs/io-report-power-poc.md.
# Writes JSON lines to /tmp/ioreport-poc/experiments.jsonl plus a log header
# with machine state. No sudo, no priming, no installs.
#
# usage: bash run-experiments.sh [binary]
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="${1:-/tmp/ioreport-poc/ioreport-poc}"
OUT_DIR=/tmp/ioreport-poc
OUT="$OUT_DIR/experiments.jsonl"
LOG="$OUT_DIR/experiments.log"
GPU_LOAD="${GPU_LOAD:-/tmp/gpuload/gpuload}"
if [[ ! -x "$BIN" ]]; then
    echo "missing $BIN; run 'bash run.sh selftest' first" >&2
    exit 1
fi
mkdir -p "$OUT_DIR" /tmp/gpuload
if [[ ! -x "$GPU_LOAD" ]]; then
    xcrun swiftc -O "$HERE/gpu-load.swift" -o "$GPU_LOAD" 2>>"$LOG" || echo "gpu load tool build failed" >&2
fi
: >"$OUT"
: >"$LOG"

log() { echo "$@" | tee -a "$LOG"; }
probe() { # label flow
    local label="$1" mode="$2"
    local loadavg; loadavg=$(sysctl -n vm.loadavg)
    log "--- $label loadavg=$loadavg"
    echo "{\"meta\":\"$label\",\"loadavg\":\"$loadavg\",\"ts\":\"$(date -Iseconds)\"}" >>"$OUT"
    case "$mode" in
        idle)
            "$BIN" sample --window 5 --json 2>>"$LOG" >>"$OUT" ;;
        cpu)
            local burners=()
            for _ in $(seq 8); do
                yes >/dev/null 2>&1 &
                burners+=("$!")
            done
            sleep 0.5
            "$BIN" sample --window 5 --json 2>>"$LOG" >>"$OUT"
            # Stop only the burners this probe started; never another `yes`.
            kill "${burners[@]}" 2>/dev/null || true
            wait "${burners[@]}" 2>/dev/null || true ;;
        gpu)
            "$GPU_LOAD" 8 >/dev/null 2>&1 &
            sleep 1.5
            "$BIN" sample --window 5 --json 2>>"$LOG" >>"$OUT"
            wait $! 2>/dev/null || true ;;
    esac
    sleep 2
}

{
    log "# environment $(date -Iseconds)"
    log "# machine: $(sysctl -n machdep.cpu.brand_string), $(sw_vers -productName) $(sw_vers -productVersion) build $(sw_vers -buildVersion)"
    log "# pmset: $(pmset -g batt | tr '\n' ' ')"
    log "# power: $(pmset -g ps | head -1)"
} 2>&1

probe "idle-1" idle
probe "idle-2" idle
probe "cpu-load-1" cpu
probe "cpu-load-2" cpu
probe "gpu-load-1" gpu
probe "gpu-load-2" gpu
probe "idle-after" idle

log "# done $(date -Iseconds)"
