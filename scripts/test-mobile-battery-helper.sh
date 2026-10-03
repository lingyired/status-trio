#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT}/.build/mobile-battery/tests"
mkdir -p "${BUILD_DIR}"

xcrun --sdk macosx clang \
    -fobjc-arc \
    -framework Foundation \
    -I "${ROOT}/Support/MobileBatteryHelper" \
    "${ROOT}/Support/MobileBatteryHelper/NativeBatteryClient.m" \
    "${ROOT}/Support/MobileBatteryHelper/tests/NativeBatteryClientTests.m" \
    -o "${BUILD_DIR}/NativeBatteryClientTests"

"${BUILD_DIR}/NativeBatteryClientTests"
