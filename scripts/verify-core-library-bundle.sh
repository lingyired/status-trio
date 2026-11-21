#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?Usage: verify-core-library-bundle.sh <app> [minos]}"
MINOS="${2:-13.0}"
MAIN="$APP/Contents/MacOS/StatusTrio"
CORE="$APP/Contents/Frameworks/libStatusTrioCore.dylib"
NAME='@rpath/libStatusTrioCore.dylib'

fail() { echo "Error: $*" >&2; exit 1; }
[[ -x "$MAIN" && -f "$CORE" ]] || fail 'Status Trio launcher or core library is missing.'
main_archs="$(lipo -archs "$MAIN")"
[[ "$main_archs" == "$(lipo -archs "$CORE")" ]] || fail 'Launcher and core architectures differ.'
# The launcher is one call into Swift. This limit catches accidental static linkage.
[[ "$(stat -f '%z' "$MAIN")" -lt 1048576 ]] || fail 'Status Trio launcher exceeds 1 MiB.'

for arch in $main_archs; do
    otool -arch "$arch" -L "$MAIN" | awk -v name="$NAME" '$1 == name { found = 1 } END { exit !found }' ||
        fail "$arch launcher does not link the bundled core library."
    otool -arch "$arch" -l "$MAIN" | awk '$1 == "path" && $2 == "@executable_path/../Frameworks" { found = 1 } END { exit !found }' ||
        fail "$arch launcher cannot resolve its bundled framework directory."
    [[ "$(otool -arch "$arch" -D "$CORE" | awk 'NR == 2 { print }')" == "$NAME" ]] ||
        fail "$arch core install name is not bundle-relative."
done

bash "$ROOT/scripts/verify-platform-version.sh" "$MAIN" "$MINOS"
bash "$ROOT/scripts/verify-platform-version.sh" "$CORE" "$MINOS"
echo 'Dynamic core bundle contract passed.'
