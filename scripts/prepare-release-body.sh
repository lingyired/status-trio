#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:?VERSION is required}"
PUBLISH_MODE="${PUBLISH_MODE:?PUBLISH_MODE is required}"
SIGNING_KIND="${SIGNING_KIND:-developer_id}"
NOTES_DIR="${RELEASE_NOTES_DIR:-$ROOT/release-notes/$VERSION}"
OUTPUT="${OUTPUT:?OUTPUT is required}"

mkdir -p "$(dirname -- "$OUTPUT")"

if [[ -f "$NOTES_DIR/en.md" && -f "$NOTES_DIR/zh-Hans.md" ]]; then
    {
        printf '# Version %s （English + 中文， 中文在下方）\n\n' "$VERSION"
        printf '## English\n\n'
        sed -e '/^# /d' "$NOTES_DIR/en.md"
        printf '\n## 中文\n\n'
        sed -e '/^# /d' "$NOTES_DIR/zh-Hans.md"
    } > "$OUTPUT"
    if [[ "$PUBLISH_MODE" == "true" && "$SIGNING_KIND" == "ad_hoc" ]]; then
        {
            printf '\n## First Launch (Ad-hoc build)\n\n'
            printf 'This Ad-hoc build is not notarized. If macOS blocks the first launch, remove the quarantine attribute:\n\n'
            printf '```bash\n'
            printf 'xattr -dr com.apple.quarantine "/Applications/Status Trio.app"\n'
            printf 'open "/Applications/Status Trio.app"\n'
            printf '```\n'
        } >> "$OUTPUT"
    fi
elif [[ "$PUBLISH_MODE" == "true" ]]; then
    echo "::error::Release notes for publishing require $NOTES_DIR/en.md and $NOTES_DIR/zh-Hans.md." >&2
    exit 1
else
    printf -- '- Diagnostic package for Status Trio v%s. This artifact is not published.\n' \
        "$VERSION" > "$OUTPUT"
fi

echo "Prepared release body at $OUTPUT"
