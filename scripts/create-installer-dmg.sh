#!/usr/bin/env bash
# Creates the installation layout only; signing/notarization belongs to package-release.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
die() { echo "DMG installer error: $*" >&2; exit 1; }
command -v create-dmg >/dev/null 2>&1 || die 'create-dmg 1.3.0 is required (brew install create-dmg).'
TOOL_VERSION="$(create-dmg --version)"
[[ "$TOOL_VERSION" == 'create-dmg 1.3.0' ]] || die "Expected create-dmg 1.3.0; found $TOOL_VERSION."
BACKGROUND="$ROOT/assets/dmg/background@2x.png"
[[ -f "$BACKGROUND" ]] || die "Missing background: $BACKGROUND"
if [[ "${1:-}" == --check && "$#" == 1 ]]; then exit 0; fi
[[ "$#" == 2 ]] || die 'Usage: create-installer-dmg.sh APP_DIR OUTPUT_DMG'
[[ -d "$1" ]] || die "App directory does not exist: $1"
APP_DIR="$(cd "$1" && pwd -P)"
[[ "$APP_DIR" == *.app ]] || die 'App directory must end with .app.'
APP_NAME="${DMG_APP_NAME:-$(basename "$APP_DIR" .app)}"
[[ "$APP_NAME" != */* && -n "$APP_NAME" ]] || die 'Invalid app display name.'
APP_FILE="$APP_NAME.app"
[[ -f "$APP_DIR/Contents/Resources/AppIcon.icns" ]] || die 'AppIcon.icns is missing.'
[[ -d "$(dirname "$2")" ]] || die 'Output parent directory does not exist.'
OUTPUT_DIR="$(cd "$(dirname "$2")" && pwd -P)"
OUTPUT="$OUTPUT_DIR/$(basename "$2")"
[[ "$OUTPUT" == *.dmg ]] || die 'Output filename must end with .dmg.'
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || die "Output already exists: $OUTPUT"
# Use a private directory beside the final output, so image-path ownership is exact
# and the final rename stays on the same filesystem.
TEMP_ROOT="$(mktemp -d "$OUTPUT_DIR/.StatusTrioDMG.XXXXXX")"
TEMP_ROOT="$(cd "$TEMP_ROOT" && pwd -P)"
cleanup() {
    local status=$? devices device cleanup_failed=0
    trap - EXIT
    # Only disk images whose image-path is inside this invocation's private
    # directory are ours. Never use a volume name or a broad before/after diff.
    if hdiutil info -plist > "$TEMP_ROOT/mounts.plist"; then
        if devices="$(ruby -rrexml/document -e '
          doc = REXML::Document.new(File.read(ARGV[0]))
          def fields(node)
            children = node.elements.to_a
            children.each_slice(2).to_h { |key, value| [key.text, value] }
          end
          root = fields(doc.elements["plist/dict"])
          root.fetch("images").elements.each("dict") do |image|
            data = fields(image)
            path = data["image-path"]&.text
            next unless path && File.expand_path(path).start_with?(ARGV[1] + "/")
            devices = data.fetch("system-entities").elements.to_a("dict").map do |entity|
              dev = fields(entity)["dev-entry"]&.text
              dev if dev && dev.match?(%r{\A/dev/[a-zA-Z0-9_-]+\z})
            end.compact
            # Detach the whole disk once, rather than detaching its partitions
            # after the first detach has already removed them.
            puts(devices.find { |dev| dev.match?(%r{\A/dev/disk\d+\z}) } || devices.first)
          end
        ' "$TEMP_ROOT/mounts.plist" "$TEMP_ROOT")"; then
            while IFS= read -r device; do
                [[ -n "$device" ]] || continue
                hdiutil detach "$device" || cleanup_failed=1
            done <<< "$devices"
        else cleanup_failed=1; fi
    else cleanup_failed=1; fi
    if [[ "$cleanup_failed" == 0 ]]; then
        [[ "$TEMP_ROOT" == "$OUTPUT_DIR"/.StatusTrioDMG.* ]] || exit 1
        rm -rf -- "$TEMP_ROOT"
    else
        echo "Preserving temporary files for mount cleanup: $TEMP_ROOT" >&2
        [[ "$status" != 0 ]] || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$TEMP_ROOT/staging" "$TEMP_ROOT/tool-tmp"
ditto "$APP_DIR" "$TEMP_ROOT/staging/$APP_FILE"
TMPDIR="$TEMP_ROOT/tool-tmp/" create-dmg \
    --volname "$APP_NAME" \
    --volicon "$APP_DIR/Contents/Resources/AppIcon.icns" \
    --background "$BACKGROUND" \
    --window-size 660 420 \
    --icon-size 104 --text-size 13 \
    --icon "$APP_FILE" 180 230 \
    --app-drop-link 480 230 \
    --hide-extension "$APP_FILE" \
    --no-internet-enable --format UDZO \
    "$TEMP_ROOT/installer.dmg" "$TEMP_ROOT/staging"
[[ -s "$TEMP_ROOT/installer.dmg" ]] || die 'create-dmg did not produce a nonempty image.'
# Recheck immediately before moving, and refuse to overwrite concurrent output.
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || die "Output appeared during packaging: $OUTPUT"
mv -n "$TEMP_ROOT/installer.dmg" "$OUTPUT"
[[ ! -e "$TEMP_ROOT/installer.dmg" ]] || die 'Output was not moved; destination may have appeared.'
