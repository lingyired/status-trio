#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
    echo "Usage: $0 <generated Info.plist>" >&2
    exit 2
fi

PLIST="$1"
for key in SUFeedURL SUPublicEDKey SUEnableInstallerLauncherService; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST"
done
