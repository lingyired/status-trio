#!/usr/bin/env bash
# Regenerates the legacy AppIcon.icns from the Icon Composer light artwork.
#
# actool's own .icns fallback only carries the 16 and 128 px representations.
# macOS 13-15 still read that fallback for the bundle icon, and Finder and the
# Dock ask for every size up to 512@2x, so shipping actool's thin set would leave
# those systems with an upscaled small icon. This script rebuilds the full
# macOS iconset from the same light artwork the Aqua appearance uses; the
# appearance-aware Assets.car stays the source for macOS 26 and later.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <light-artwork.png> <output.icns>" >&2
    exit 2
fi

ARTWORK="$1"
OUTPUT="$2"

if [[ ! -f "$ARTWORK" ]]; then
    echo "Error: missing app icon light artwork at $ARTWORK." >&2
    exit 1
fi

SOURCE_SIZE="$(sips -g pixelWidth "$ARTWORK" | awk '$1 == "pixelWidth:" { print $2; exit }')"
if [[ "$SOURCE_SIZE" != "1024" ]]; then
    echo "Error: app icon light artwork must be 1024x1024, found '${SOURCE_SIZE:-unknown}'." >&2
    exit 1
fi

ICONSET_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioIconset.XXXXXX")"
trap 'rm -rf "$ICONSET_ROOT"' EXIT
ICONSET_DIR="$ICONSET_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

while read -r pixel filename; do
    sips -z "$pixel" "$pixel" "$ARTWORK" --out "$ICONSET_DIR/$filename" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

iconutil --convert icns --output "$OUTPUT" "$ICONSET_DIR"
