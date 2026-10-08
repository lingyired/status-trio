#!/usr/bin/env bash
# Validates release note coverage and the appcast item those notes generate.
#
# Runs on every release dispatch, including publish=false preflights, which is
# what gives this path CI coverage: the appcast is only written when publishing.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="${VERSION:?VERSION is required}"
BUILD="${BUILD:?BUILD is required}"
PUBLISH="${PUBLISH:-false}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-15.0}"
NOTES_DIR="${RELEASE_NOTES_DIR:-$ROOT/release-notes/$VERSION}"
APPCAST_FILE="${APPCAST_FILE:-appcast.xml}"
APPCAST_PATH="$ROOT/$APPCAST_FILE"

SUPPORTED=(en ar de es fr it ja ko pt-BR ru zh-Hans zh-Hant)
REQUIRED=(en zh-Hans)

if [[ ! -d "$NOTES_DIR" ]]; then
    if [[ "$PUBLISH" == "true" ]]; then
        echo "::error::Release notes directory does not exist: $NOTES_DIR"
        exit 1
    fi
    echo "::notice::Release notes directory does not exist yet: $NOTES_DIR — skipping validation."
    exit 0
fi

present=()
missing=()
for language in "${SUPPORTED[@]}"; do
    if [[ -f "$NOTES_DIR/$language.md" ]]; then
        present+=("$language")
    else
        missing+=("$language")
    fi
done

echo "Release notes coverage for $VERSION: ${#present[@]}/${#SUPPORTED[@]} languages"
printf '  present: %s\n' "${present[*]}"
printf '  missing: %s\n' "${missing[*]:-none}"

fail=0
if [[ "$PUBLISH" == "true" ]]; then
    for language in "${REQUIRED[@]}"; do
        if [[ ! -f "$NOTES_DIR/$language.md" ]]; then
            echo "::error::Required release notes missing: $NOTES_DIR/$language.md"
            fail=1
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "::error::Release notes missing for: ${missing[*]}"
        fail=1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioNotes.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cp "$APPCAST_PATH" "$TEMP_DIR/appcast.xml"
OUTPUT="$TEMP_DIR/generated.xml"

ARGS=(
    --version "$VERSION"
    --build "$BUILD"
    --minimum-system-version "$MINIMUM_SYSTEM_VERSION"
    --notes-dir "$NOTES_DIR"
    --appcast "$TEMP_DIR/appcast.xml"
    --output "$OUTPUT"
)

if grep -qF "<sparkle:version>$BUILD</sparkle:version>" "$TEMP_DIR/appcast.xml"; then
    ARGS+=(--replace-existing)
else
    ARGS+=(--dmg-url "https://example.invalid/StatusTrio-$VERSION.dmg")
    ARGS+=(--ed-signature "validation-only")
    ARGS+=(--length "1")
fi

ruby "$ROOT/scripts/update-appcast.rb" "${ARGS[@]}"
xmllint --noout "$OUTPUT"

ITEM="$TEMP_DIR/item.xml"
ruby -e '
  build = ARGV[1]
  block = File.read(ARGV[0]).scan(%r{[ \t]*<item>.*?</item>}m)
              .find { |candidate| candidate.include?("<sparkle:version>#{build}</sparkle:version>") }
  abort("No appcast item found for build #{build}.") unless block
  print block
' "$OUTPUT" "$BUILD" > "$ITEM"

expected="${#present[@]}"
titles="$(grep -c '<title xml:lang=' "$ITEM" || true)"
descriptions="$(grep -c '<description xml:lang=' "$ITEM" || true)"

if [[ "$titles" -ne "$expected" ]]; then
    echo "::error::Expected $expected localized titles for build $BUILD, found $titles."
    fail=1
fi
if [[ "$descriptions" -ne "$expected" ]]; then
    echo "::error::Expected $expected localized descriptions for build $BUILD, found $descriptions."
    fail=1
fi

first_language="$(grep -o '<title xml:lang="[^"]*"' "$ITEM" | head -1 | sed 's/.*="//; s/"$//')"
if [[ "$first_language" != "en" ]]; then
    echo "::error::The first language variant must be en (Sparkle's fallback is document order), found '${first_language}'."
    fail=1
fi

if grep -qE '%(VERSION|BUILD)%' "$ITEM"; then
    echo "::error::Unsubstituted placeholders remain in the appcast item for build $BUILD."
    fail=1
fi

if grep -qE '<description xml:lang="[^"]*"><!\[CDATA\[\]\]></description>' "$ITEM"; then
    echo "::error::An empty localized description was generated for build $BUILD."
    fail=1
fi

for language in "${present[@]}"; do
    if ! grep -qF "<title xml:lang=\"$language\">" "$ITEM"; then
        echo "::error::Missing appcast title variant for '$language'."
        fail=1
    fi
    if ! grep -qF "<description xml:lang=\"$language\">" "$ITEM"; then
        echo "::error::Missing appcast description variant for '$language'."
        fail=1
    fi
done

PRIVACY_URL="https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md"
if grep -qF "$PRIVACY_URL" "$NOTES_DIR"/*.md; then
    privacy_link_count="$( (grep -oF "<a href=\"$PRIVACY_URL\">" "$ITEM" || true) | wc -l | tr -d ' ')"
    if [[ "$privacy_link_count" -ne "$expected" ]]; then
        echo "::error::Expected a clickable privacy link in each localized description, found $privacy_link_count of $expected."
        fail=1
    fi
fi

[[ "$fail" -eq 0 ]] || exit 1
echo "Appcast notes OK: $titles titles and $descriptions descriptions, en first."
