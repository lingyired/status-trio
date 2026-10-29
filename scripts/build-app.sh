#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/build-timing.sh"
trap 'build_timing_finish "$?"' EXIT
CONFIGURATION="${1:-release}"
OPEN_APP="${2:-open}"
BUNDLE_ID="${BUNDLE_ID:-com.lingsmbp.StatusTrio}"
APP_NAME="${APP_NAME:-Status Trio}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SU_FEED_URL="${SU_FEED_URL:-}"
DEVELOPMENT_CODENAME="${DEVELOPMENT_CODENAME:-}"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-0}"
TELEMETRY_PRODUCTION="${TELEMETRY_PRODUCTION:-0}"
PRIVILEGED_HELPER="${PRIVILEGED_HELPER:-1}"

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

case "$TELEMETRY_PRODUCTION" in
    0|1) ;;
    *)
        echo "Error: TELEMETRY_PRODUCTION must be 0 or 1." >&2
        exit 2
        ;;
esac

case "$UNIVERSAL_BUILD" in
    0|1) ;;
    *)
        echo "Error: UNIVERSAL_BUILD must be 0 or 1." >&2
        exit 2
        ;;
esac

# 0 excludes the privileged power helper and its LaunchDaemon property list from
# the bundle, which is what an App-Store-style build needs: a root LaunchDaemon
# cannot ship there. The app reads STIncludesPrivilegedHelper at runtime and
# hides the Low Power Mode control when the helper is absent.
case "$PRIVILEGED_HELPER" in
    0|1) ;;
    *)
        echo "Error: PRIVILEGED_HELPER must be 0 or 1." >&2
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

build_phase swift-release-build
swift "${SWIFT_BUILD_ARGS[@]}"
BIN_PATH="$(swift "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
build_phase bundle-assembly
APP_DIR="$ROOT/dist/StatusTrio.app"
CONTENTS="$APP_DIR/Contents"

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
build_phase mobile-battery-total
bash "$ROOT/scripts/build-mobile-battery-helper.sh"
build_phase bundle-assembly-and-icon-assets
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
            */.build/mobile-battery/*)
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

# The privileged power helper is a SwiftPM executable target copied next to the
# app binary. Its LaunchDaemon property list goes into Contents/Library/LaunchDaemons
# so SMAppService can register it and System Settings can attribute it to the app.
# PRIVILEGED_HELPER=0 skips both so an App-Store-style build ships neither.
if [[ "$PRIVILEGED_HELPER" == "1" ]]; then
    if [[ ! -x "$BIN_PATH/StatusTrioPowerHelper" ]]; then
        echo "Error: missing privileged helper at $BIN_PATH/StatusTrioPowerHelper." >&2
        exit 1
    fi
    mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Library/LaunchDaemons"
    cp "$BIN_PATH/StatusTrioPowerHelper" "$CONTENTS/Helpers/StatusTrioPowerHelper"
    chmod +x "$CONTENTS/Helpers/StatusTrioPowerHelper"
    # SwiftPM records the deployment target in LC_BUILD_VERSION's `sdk` field,
    # so the daemon needs the same correction the app binary gets: declare the
    # macOS 26 design language while keeping the real deployment target.
    HELPER_MINOS="$(vtool -show-build "$CONTENTS/Helpers/StatusTrioPowerHelper" | awk '/^[[:space:]]*minos[[:space:]]/ {print $2; exit}')"
    if [[ -z "$HELPER_MINOS" ]]; then
        echo "Error: unable to read the deployment target from the built privileged helper." >&2
        exit 1
    fi
    HELPER_VTMP="$(mktemp "${TMPDIR:-/tmp}/StatusTrioPowerHelper.vtool.XXXXXX")"
    xcrun vtool -set-build-version macos "$HELPER_MINOS" "$SDK_VERSION" -replace -output "$HELPER_VTMP" "$CONTENTS/Helpers/StatusTrioPowerHelper"
    mv "$HELPER_VTMP" "$CONTENTS/Helpers/StatusTrioPowerHelper"
    chmod +x "$CONTENTS/Helpers/StatusTrioPowerHelper"
    cp "$ROOT/Support/StatusTrioPowerHelper.plist" \
        "$CONTENTS/Library/LaunchDaemons/com.lingsmbp.StatusTrio.PowerHelper.plist"
    /usr/libexec/PlistBuddy -c "Set :AssociatedBundleIdentifiers:0 $BUNDLE_ID" \
        "$CONTENTS/Library/LaunchDaemons/com.lingsmbp.StatusTrio.PowerHelper.plist"
fi

cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
if [[ "$TELEMETRY_PRODUCTION" == "1" ]]; then
    /usr/libexec/PlistBuddy -c "Set :STTelemetryProduction true" "$CONTENTS/Info.plist"
fi
if [[ "$PRIVILEGED_HELPER" == "1" ]]; then
    /usr/libexec/PlistBuddy -c "Set :STIncludesPrivilegedHelper true" "$CONTENTS/Info.plist"
else
    /usr/libexec/PlistBuddy -c "Set :STIncludesPrivilegedHelper false" "$CONTENTS/Info.plist"
fi
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

# Icon Composer is the source of truth for the bundle icon: actool writes an
# appearance-aware Assets.car plus the legacy .icns fallback that macOS 13-15
# still read. The deployment target stays whatever Support/Info.plist declares,
# so a future minimum raises the fallback set with it instead of being pinned
# here. Assets.car/AppIcon.icns land in Contents/Resources alongside the other
# resources; nothing is allowed to silently ship without them.
ICON_DOCUMENT="$ROOT/Support/AppIcon.icon"
if [[ ! -d "$ICON_DOCUMENT" ]]; then
    echo "Error: missing Icon Composer document at $ICON_DOCUMENT." >&2
    exit 1
fi
ICON_DEPLOYMENT_TARGET="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT/Support/Info.plist" 2>/dev/null || true)"
if [[ -z "$ICON_DEPLOYMENT_TARGET" ]]; then
    echo "Error: Support/Info.plist declares no LSMinimumSystemVersion for the app icon." >&2
    exit 1
fi
ICON_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrio.XXXXXX")"
trap 'build_timing_finish "$?"; rm -rf "$ICON_WORK_DIR"' EXIT
ICON_PARTIAL_PLIST="$ICON_WORK_DIR/AppIcon.partial.plist"

xcrun actool "$ICON_DOCUMENT" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target "$ICON_DEPLOYMENT_TARGET" \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_PARTIAL_PLIST" >/dev/null

for icon_artifact in Assets.car AppIcon.icns; do
    if [[ ! -f "$CONTENTS/Resources/$icon_artifact" ]]; then
        echo "Error: actool did not produce Contents/Resources/$icon_artifact for $ICON_DOCUMENT." >&2
        exit 1
    fi
done

# actool's legacy .icns only carries the 16 and 128 px representations, but
# macOS 13-15 draw the bundle icon from it at every Finder and Dock size.
# Rebuild it from the light artwork the Aqua appearance uses; Assets.car stays
# the appearance-aware source for macOS 26 and later.
rm -f "$CONTENTS/Resources/AppIcon.icns"
bash "$ROOT/scripts/generate-app-icon-icns.sh" \
    "$ICON_DOCUMENT/Assets/AppIcon-light.png" \
    "$CONTENTS/Resources/AppIcon.icns"
if [[ ! -s "$CONTENTS/Resources/AppIcon.icns" ]]; then
    echo "Error: failed to generate the legacy AppIcon.icns fallback." >&2
    exit 1
fi

# The partial Info.plist names the compiled catalog. Merge it instead of
# assuming the shape, and refuse a document that stopped declaring the icon.
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$ICON_PARTIAL_PLIST" 2>/dev/null || true)"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$ICON_PARTIAL_PLIST" 2>/dev/null || true)"
if [[ "$ICON_NAME" != "AppIcon" || "$ICON_FILE" != "AppIcon" ]]; then
    echo "Error: actool partial Info.plist must declare CFBundleIconName=AppIcon and CFBundleIconFile=AppIcon (found '${ICON_NAME:-}' and '${ICON_FILE:-}')." >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleIconName $ICON_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $ICON_FILE" "$CONTENTS/Info.plist"

FINAL_ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$CONTENTS/Info.plist")"
FINAL_ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$CONTENTS/Info.plist")"
if [[ "$FINAL_ICON_NAME" != "AppIcon" || "$FINAL_ICON_FILE" != "AppIcon" ]]; then
    echo "Error: $CONTENTS/Info.plist must declare CFBundleIconName=AppIcon and CFBundleIconFile=AppIcon (found '$FINAL_ICON_NAME' and '$FINAL_ICON_FILE')." >&2
    exit 1
fi

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
xcrun vtool -set-build-version macos "$BUILT_MINOS" "$SDK_VERSION" -replace -output "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
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

# The daemon only accepts an Apple-anchored client, so an Ad-hoc build's helper
# can never be registered or talked to. The bundle still ships it (the static
# contract holds), but the feature will not work until it is signed with a
# Developer ID identity — warn rather than ship a silently dead toggle.
if [[ "$PRIVILEGED_HELPER" == "1" && "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Warning: the privileged helper is bundled but Ad-hoc signed; Low Power Mode control will not work until it is signed with a Developer ID identity." >&2
fi

build_phase app-codesign
codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Frameworks/Sparkle.framework"
while IFS= read -r -d '' mobile_library; do
    codesign "${SIGNING_ARGS[@]}" "$mobile_library"
done < <(find "$CONTENTS/Frameworks/MobileBattery" -maxdepth 1 -type f -name '*.dylib*' -print0)
codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Helpers/StatusTrioMobileBatteryHelper"
if [[ "$PRIVILEGED_HELPER" == "1" ]]; then
    codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Helpers/StatusTrioPowerHelper"
fi
codesign "${SIGNING_ARGS[@]}" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
build_phase signed-bundle-contracts
bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "$APP_DIR"
bash "$ROOT/scripts/verify-privileged-helper-bundle.sh" "$APP_DIR"

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
