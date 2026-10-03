#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
OPEN_APP="${2:-open}"
BUNDLE_ID="${BUNDLE_ID:-com.lingsmbp.StatusTrio}"
APP_NAME="${APP_NAME:-Status Trio}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SU_FEED_URL="${SU_FEED_URL:-}"
DEVELOPMENT_CODENAME="${DEVELOPMENT_CODENAME:-}"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-0}"

case "$OPEN_APP" in
    open|no-open) ;;
    *)
        echo "Usage: $0 [configuration] [open|no-open]" >&2
        exit 2
        ;;
esac

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Error: BUNDLE_ID may contain only letters, numbers, periods, and hyphens." >&2
    exit 2
fi

if [[ -z "$APP_NAME" ]]; then
    echo "Error: APP_NAME must not be empty." >&2
    exit 2
fi

if [[ -n "$APP_VERSION" && ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Error: APP_VERSION must contain dot-separated numbers, for example 1.2.0." >&2
    exit 2
fi

if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: BUILD_NUMBER must contain only digits." >&2
    exit 2
fi

if [[ -n "$SU_FEED_URL" && "$SU_FEED_URL" != https://* ]]; then
    echo "Error: SU_FEED_URL must use HTTPS." >&2
    exit 2
fi

case "$UNIVERSAL_BUILD" in
    0|1) ;;
    *)
        echo "Error: UNIVERSAL_BUILD must be 0 or 1." >&2
        exit 2
        ;;
esac

cd "$ROOT"

# SwiftPM's build system can record the deployment target in LC_BUILD_VERSION's
# `sdk` field. macOS reads that field to decide whether an app adopts the current
# design language, so building against an older SDK silently keeps the pre-Tahoe
# popover appearance. Checked before compiling on purpose: failing afterwards
# would leave a complete-looking, runnable bundle built with the wrong SDK.
#
# STATUS_TRIO_SDK_VERSION_OVERRIDE exists only so this guard can be tested.
SDK_VERSION="${STATUS_TRIO_SDK_VERSION_OVERRIDE:-$(xcrun --sdk macosx --show-sdk-version)}"
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
    echo "Error: Status Trio must be built with the macOS 26 SDK or newer; found ${SDK_VERSION}." >&2
    echo "       An older SDK silently ships the pre-Tahoe popover appearance." >&2
    exit 2
fi

SWIFT_BUILD_ARGS=(build -c "$CONFIGURATION")
if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift "${SWIFT_BUILD_ARGS[@]}"
BIN_PATH="$(swift "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$ROOT/dist/StatusTrio.app"
CONTENTS="$APP_DIR/Contents"
ICON_SOURCE="$ROOT/Support/AppIcon.png"
ICONSET_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrio.XXXXXX")"
ICONSET_DIR="$ICONSET_ROOT/AppIcon.iconset"

trap 'rm -rf "$ICONSET_ROOT"' EXIT

sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_ROOT/AppIcon.png" >/dev/null
mkdir -p "$ICONSET_DIR"

while read -r pixel filename; do
    sips -z "$pixel" "$pixel" "$ICONSET_ROOT/AppIcon.png" --out "$ICONSET_DIR/$filename" >/dev/null
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

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

CORE_RESOURCE_BUNDLE="$BIN_PATH/StatusTrio_StatusTrioCore.bundle"
if [[ ! -d "$CORE_RESOURCE_BUNDLE" ]]; then
    echo "Error: missing SwiftPM resource bundle at $CORE_RESOURCE_BUNDLE." >&2
    exit 1
fi

cp "$BIN_PATH/StatusTrio" "$CONTENTS/MacOS/StatusTrio"
cp -R "$CORE_RESOURCE_BUNDLE" "$CONTENTS/Resources/"

SPARKLE_FRAMEWORK_SOURCE="$(find "$ROOT/.build/artifacts" -path '*/Sparkle.xcframework/macos-*/Sparkle.framework' -type d -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
    echo "Error: missing Sparkle.framework under .build/artifacts." >&2
    exit 1
fi

ditto "$SPARKLE_FRAMEWORK_SOURCE" "$CONTENTS/Frameworks/Sparkle.framework"

# The mobile-device helper is built from exact upstream commits. Its runtime
# dependency graph is packaged into the app so users do not need Homebrew.
bash "$ROOT/scripts/build-mobile-battery-helper.sh"
MOBILE_BATTERY_PACKAGE="$ROOT/.build/mobile-battery/package"
mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Frameworks/MobileBattery" "$CONTENTS/Resources/MobileBatteryLicenses"
ditto "$MOBILE_BATTERY_PACKAGE/Helpers/StatusTrioMobileBatteryHelper" "$CONTENTS/Helpers/StatusTrioMobileBatteryHelper"
ditto "$MOBILE_BATTERY_PACKAGE/Frameworks/MobileBattery" "$CONTENTS/Frameworks/MobileBattery"
ditto "$MOBILE_BATTERY_PACKAGE/Resources/MobileBatteryLicenses" "$CONTENTS/Resources/MobileBatteryLicenses"

rewrite_mobile_battery_binary() {
    local binary="$1"
    local old_id
    if [[ "$binary" == *.dylib* ]]; then
        old_id="$(otool -D "$binary" | sed -n '2p' | xargs)"
        if [[ -n "$old_id" ]]; then
            install_name_tool -id "@rpath/$(basename "$old_id")" "$binary"
        fi
    fi
    while IFS= read -r dependency; do
        case "$dependency" in
            "$ROOT"/.build/mobile-battery/*)
                install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$binary"
                ;;
        esac
    done < <(otool -L "$binary" | sed -n '2,$s/^[[:space:]]*\([^[:space:]]*\)[[:space:]]*(.*/\1/p')
}

while IFS= read -r -d '' mobile_library; do
    rewrite_mobile_battery_binary "$mobile_library"
done < <(find "$CONTENTS/Frameworks/MobileBattery" -maxdepth 1 -type f -name '*.dylib*' -print0)
rewrite_mobile_battery_binary "$CONTENTS/Helpers/StatusTrioMobileBatteryHelper"

if ! otool -l "$CONTENTS/MacOS/StatusTrio" | grep -Fq 'path @executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$CONTENTS/MacOS/StatusTrio"
fi

cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS/Info.plist"

if [[ -n "$APP_VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS/Info.plist"
fi

if [[ -n "$BUILD_NUMBER" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
fi

if [[ -n "$DEVELOPMENT_CODENAME" ]]; then
    /usr/libexec/PlistBuddy -c "Add :STDevelopmentCodename string $DEVELOPMENT_CODENAME" "$CONTENTS/Info.plist"
fi

if [[ -n "$SU_FEED_URL" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $SU_FEED_URL" "$CONTENTS/Info.plist"
fi
INFO_PLIST_COUNT="$(find "$ROOT/Sources/StatusTrioCore/Resources" -name 'InfoPlist.strings' -type f | wc -l | tr -d ' ')"
if [[ "$INFO_PLIST_COUNT" -ne 12 ]]; then
    echo "Error: expected 12 localized InfoPlist.strings files, found $INFO_PLIST_COUNT." >&2
    exit 1
fi

while IFS= read -r source; do
    language_dir="$(basename "$(dirname "$source")")"
    target_dir="$CONTENTS/Resources/$language_dir"
    mkdir -p "$target_dir"
    cp "$source" "$target_dir/InfoPlist.strings"
done < <(find "$ROOT/Sources/StatusTrioCore/Resources" -name 'InfoPlist.strings' -type f | sort)

# Keep the native location and Bluetooth purpose declarations complete. Check
# the shipped bundle, including translations, before signing or opening it.
for plist in "$CONTENTS/Info.plist" "$CONTENTS/Resources/"*.lproj/InfoPlist.strings; do
    for key in NSLocationUsageDescription NSLocationWhenInUseUsageDescription NSBluetoothAlwaysUsageDescription; do
        if ! description="$(plutil -extract "$key" raw -expect string "$plist" 2>/dev/null)" ||
            [[ -z "${description//[[:space:]]/}" ]]; then
            echo "Error: $plist must declare a nonempty $key." >&2
            exit 1
        fi
    done
done

iconutil --convert icns --output "$CONTENTS/Resources/AppIcon.icns" "$ICONSET_DIR"

chmod +x "$CONTENTS/MacOS/StatusTrio"

# Carry the deployment target through unchanged instead of hardcoding it — a
# hardcoded value would silently reset it if Package.swift's platform is ever
# raised — and declare the macOS 26 design language explicitly. The SDK guard
# earlier in this script is what keeps the build off an older SDK.
BUILT_MINOS="$(vtool -show-build "$CONTENTS/MacOS/StatusTrio" | awk '/^[[:space:]]*minos[[:space:]]/ {print $2; exit}')"
if [[ -z "$BUILT_MINOS" ]]; then
    echo "Error: unable to read the deployment target from the built binary." >&2
    exit 1
fi

# The bundle tells users which macOS it supports; the binary must not require a
# newer one, or dyld refuses to launch it on a version we still claim. Comparing
# the compiled deployment target against this independent declaration is what
# makes it asserted rather than merely echoed back from the artifact.
DECLARED_MINOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist" 2>/dev/null || true)"
if [[ -z "$DECLARED_MINOS" ]]; then
    echo "Error: $CONTENTS/Info.plist declares no LSMinimumSystemVersion." >&2
    exit 1
fi
if [[ "$BUILT_MINOS" != "$DECLARED_MINOS" ]]; then
    echo "Error: the binary targets macOS ${BUILT_MINOS} but the bundle declares LSMinimumSystemVersion ${DECLARED_MINOS}." >&2
    echo "       Raising the deployment target means updating Support/Info.plist and the release notes." >&2
    exit 1
fi

VTMP_BINARY="$(mktemp "${TMPDIR:-/tmp}/StatusTrio.vtool.XXXXXX")"
xcrun vtool -set-build-version macos "$BUILT_MINOS" 26.0 -replace -output "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
mv "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
chmod +x "$CONTENTS/MacOS/StatusTrio"

# The declared minimum is the expected value for every slice, so a slice that
# alone requires a newer macOS is caught here rather than by a user.
bash "$ROOT/scripts/verify-platform-version.sh" "$CONTENTS/MacOS/StatusTrio" "$DECLARED_MINOS"

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGNING_ARGS=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    SIGNING_ARGS+=(--options runtime --timestamp)
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        SIGNING_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
fi

codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Frameworks/Sparkle.framework"
while IFS= read -r -d '' mobile_library; do
    codesign "${SIGNING_ARGS[@]}" "$mobile_library"
done < <(find "$CONTENTS/Frameworks/MobileBattery" -maxdepth 1 -type f -name '*.dylib*' -print0)
codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Helpers/StatusTrioMobileBatteryHelper"
codesign "${SIGNING_ARGS[@]}" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "$APP_DIR"

echo "Built $APP_DIR (bundle id: $BUNDLE_ID)"

if [[ "$OPEN_APP" == "open" ]]; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

    for _ in {1..20}; do
        if [[ -z "$(lsappinfo find bundleID="$BUNDLE_ID" 2>/dev/null || true)" ]]; then
            break
        fi
        sleep 0.1
    done

    if [[ -n "$(lsappinfo find bundleID="$BUNDLE_ID" 2>/dev/null || true)" ]]; then
        echo "Error: $APP_NAME ($BUNDLE_ID) is still running after the graceful quit wait; refusing to open the rebuilt bundle." >&2
        exit 1
    fi

    open "$APP_DIR"
fi
