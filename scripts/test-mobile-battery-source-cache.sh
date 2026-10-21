#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioMobileBatterySources.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

REMOTE="$WORK/remote.git"
SEED="$WORK/seed"
CACHE="$WORK/sources/fixture"
MANIFEST="$WORK/dependencies.json"

git init --bare --quiet "$REMOTE"
git init --quiet "$SEED"
git -C "$SEED" config user.name "Status Trio Tests"
git -C "$SEED" config user.email "tests@status-trio.invalid"
printf 'first\n' > "$SEED/source.txt"
git -C "$SEED" add source.txt
git -C "$SEED" commit --quiet -m "first pinned source"
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push --quiet origin HEAD:main

mkdir -p "$WORK/sources"
git clone --quiet "$REMOTE" "$CACHE"
first_commit="$(git -C "$CACHE" rev-parse HEAD)"

cat > "$MANIFEST" <<JSON
{
  "sourceBuildOrder": ["fixture"],
  "dependencies": [
    {
      "name": "fixture",
      "repository": "$REMOTE",
      "commit": "$first_commit",
      "version": "1.0.0"
    }
  ]
}
JSON

# A valid local pin must not contact the remote. Pointing origin at a missing
# repository makes the old unconditional fetch fail deterministically.
git -C "$CACHE" remote set-url origin "$WORK/missing-remote.git"
GIT_TERMINAL_PROMPT=0 bash "$ROOT/scripts/prepare-mobile-battery-sources.sh" \
    "$MANIFEST" "$WORK"
if [[ "$(git -C "$CACHE" rev-parse HEAD)" != "$first_commit" ]]; then
    echo "FAIL: cached pinned source was not checked out." >&2
    exit 1
fi

# A missing pin must still fetch and check out the declared commit.
printf 'second\n' >> "$SEED/source.txt"
git -C "$SEED" add source.txt
git -C "$SEED" commit --quiet -m "second pinned source"
git -C "$SEED" push --quiet origin HEAD:main
second_commit="$(git -C "$SEED" rev-parse HEAD)"
python3 - "$MANIFEST" "$second_commit" <<'PY'
import json
import sys

path, commit = sys.argv[1:]
with open(path) as handle:
    manifest = json.load(handle)
manifest["dependencies"][0]["commit"] = commit
with open(path, "w") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
git -C "$CACHE" remote set-url origin "$REMOTE"
bash "$ROOT/scripts/prepare-mobile-battery-sources.sh" "$MANIFEST" "$WORK"
if [[ "$(git -C "$CACHE" rev-parse HEAD)" != "$second_commit" ]]; then
    echo "FAIL: missing pinned source was not fetched and checked out." >&2
    exit 1
fi

echo "mobile battery source cache: local pins stay offline; missing pins fetch"
