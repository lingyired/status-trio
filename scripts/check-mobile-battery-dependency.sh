#!/usr/bin/env bash
set -euo pipefail

DEPENDENCY="${1:?dependency path required}"
LIBRARY_DIR="${2:?bundled library directory required}"

case "$DEPENDENCY" in
    /opt/homebrew/*|/usr/local/*|*/.build/mobile-battery/*)
        echo "non-system external dependency: $DEPENDENCY" >&2
        exit 1
        ;;
    @rpath/*)
        bundled="$LIBRARY_DIR/${DEPENDENCY#@rpath/}"
        if [[ ! -e "$bundled" ]]; then
            echo "missing bundled library: $DEPENDENCY" >&2
            exit 1
        fi
        ;;
    /*)
        case "$DEPENDENCY" in
            /usr/lib/*|/System/Library/*|/System/Volumes/Preboot/Cryptexes/OS/System/Library/*) ;;
            *) echo "unapproved absolute dependency: $DEPENDENCY" >&2; exit 1 ;;
        esac
        ;;
esac
