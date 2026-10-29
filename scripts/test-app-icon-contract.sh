#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioAppIconContract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "app icon contract failed: $*" >&2
    exit 1
}

ICON_DOCUMENT="$ROOT/Support/AppIcon.icon"
ICON_JSON="$ICON_DOCUMENT/icon.json"
LIGHT_ARTWORK="$ICON_DOCUMENT/Assets/AppIcon-light.png"
DARK_ARTWORK="$ICON_DOCUMENT/Assets/AppIcon-dark.png"

[[ -f "$ICON_JSON" ]] || fail "missing Icon Composer document at $ICON_JSON"
for artwork in "$LIGHT_ARTWORK" "$DARK_ARTWORK"; do
    [[ -f "$artwork" ]] || fail "missing app icon artwork $artwork"
    format="$(sips -g format "$artwork" | awk '$1 == "format:" { print $2; exit }')"
    [[ "$format" == "png" ]] || fail "$artwork must be a PNG, found '$format'"
    width="$(sips -g pixelWidth "$artwork" | awk '$1 == "pixelWidth:" { print $2; exit }')"
    height="$(sips -g pixelHeight "$artwork" | awk '$1 == "pixelHeight:" { print $2; exit }')"
    [[ "$width" == "1024" && "$height" == "1024" ]] ||
        fail "$artwork must be 1024x1024, found "$width"x"$height""
done

# Compile the Icon Composer document for the bundle's declared deployment
# target. The same actool invocation backs scripts/build-app.sh, so the legacy
# .icns fallback and the appearance-aware Assets.car are asserted together.
DEPLOYMENT_TARGET="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT/Support/Info.plist")"
[[ -n "$DEPLOYMENT_TARGET" ]] || fail "Support/Info.plist declares no LSMinimumSystemVersion"
mkdir -p "$WORK/Resources"
if ! xcrun actool "$ICON_DOCUMENT" \
    --compile "$WORK/Resources" \
    --platform macosx \
    --minimum-deployment-target "$DEPLOYMENT_TARGET" \
    --app-icon AppIcon \
    --output-partial-info-plist "$WORK/AppIcon.partial.plist" >"$WORK/actool.log" 2>&1; then
    cat "$WORK/actool.log" >&2
    fail "actool failed to compile $ICON_DOCUMENT for macOS $DEPLOYMENT_TARGET"
fi

for artifact in Assets.car AppIcon.icns; do
    [[ -f "$WORK/Resources/$artifact" ]] || fail "actool did not produce $artifact"
done

for key in CFBundleIconName CFBundleIconFile; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$WORK/AppIcon.partial.plist" 2>/dev/null || true)"
    [[ "$value" == "AppIcon" ]] || fail "actool partial Info.plist $key must be AppIcon, found '$value'"
done

# The catalog, not the icon.json, is what macOS reads. Assert both appearance
# stacks exist so a document that only shipped one rendering fails here.
/usr/bin/assetutil --info "$WORK/Resources/Assets.car" >"$WORK/assets.json"
cat >"$WORK/check-asset-catalog.py" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    entries = json.load(handle)

appearances = {
    entry.get("Appearance")
    for entry in entries
    if entry.get("AssetType") in {"IconGroup", "IconImageStack"}
}
for expected in ("NSAppearanceNameAqua", "NSAppearanceNameDarkAqua"):
    if expected not in appearances:
        print(f"missing {expected} IconGroup in Assets.car", file=sys.stderr)
        sys.exit(1)
PY
python3 "$WORK/check-asset-catalog.py" "$WORK/assets.json" ||
    fail "Assets.car does not carry the Aqua and DarkAqua icon group stacks"

# macOS 13-15 cannot read Icon Composer data, so the fallback .icns must still
# decode into every legacy representation Finder and Launchpad use. The build
# replaces actool's thin 16/128 px fallback with one rebuilt from the light
# artwork, so assert the shared generator produces the full set.
bash "$ROOT/scripts/generate-app-icon-icns.sh" \
    "$LIGHT_ARTWORK" \
    "$WORK/Resources/AppIcon-legacy.icns"
iconutil --convert iconset --output "$WORK/AppIcon.iconset" "$WORK/Resources/AppIcon-legacy.icns"
for representation in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
    icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
    icon_512x512.png icon_512x512@2x.png; do
    [[ -f "$WORK/AppIcon.iconset/$representation" ]] ||
        fail "generated AppIcon.icns is missing the $representation fallback"
done

echo "app icon contract passed"
