#!/usr/bin/env bash
set -euo pipefail

RPATH="${1:?runpath required}"
LIBRARY_DIR="${2:?bundled library directory required}"

case "$RPATH" in
    @executable_path/../Frameworks/MobileBattery)
        [[ -d "$LIBRARY_DIR" ]]
        ;;
    /usr/lib/*|/System/Library/*|/System/Volumes/Preboot/Cryptexes/OS/System/Library/*)
        ;;
    *)
        echo "unbundled or non-relocatable LC_RPATH: $RPATH" >&2
        exit 1
        ;;
esac
