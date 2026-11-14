#!/usr/bin/env bash
# Offline mirror tests: no Gitee token, no network, no build.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
node --test scripts/test-sync-gitee-release.mjs scripts/test-probe-gitee-feed.mjs
python3 scripts/test-gitee-appcast.py
