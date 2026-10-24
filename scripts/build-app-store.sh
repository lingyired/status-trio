#!/usr/bin/env bash
# Build the isolated App Store app without touching the Direct output.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
OPEN_APP="${2:-no-open}"
ARCHIVE_PATH="${APP_STORE_ARCHIVE_PATH:-}"
UNSIGNED="${APP_STORE_UNSIGNED:-0}"
SIGNING_IDENTITY="${APP_STORE_SIGNING_IDENTITY:--}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
GENERATED_ROOT="$ROOT/.build/app-store"
PROJECT_SPEC="$ROOT/AppStore/project.json"
PROJECT_DIR="$GENERATED_ROOT/XcodeProject"
XCODE_PROJECT="$PROJECT_DIR/StatusTrioAppStore.xcodeproj"
DERIVED_DATA="$GENERATED_ROOT/DerivedData"
STORE_APP="$ROOT/dist/AppStore/StatusTrio.app"
ENTITLEMENTS="$ROOT/Distribution/AppStore.entitlements"
PRIVACY_MANIFEST="$ROOT/AppStore/PrivacyInfo.xcprivacy"
VERIFIER="$ROOT/scripts/verify-app-store-bundle.sh"
DSYM_VERIFIER="$ROOT/scripts/verify-app-store-archive-dsyms.sh"
XCODEGEN_REQUIRED_VERSION="2.46.0"
APP_LOCALIZATION_DIRECTORIES=(
    ar.lproj
    de.lproj
    en.lproj
    es.lproj
    fr.lproj
    it.lproj
    ja.lproj
    ko.lproj
    pt-BR.lproj
    ru.lproj
    zh-Hans.lproj
    zh-Hant.lproj
)

fail() {
    echo "Error: $*" >&2
    exit 1
}

case "$CONFIGURATION" in
    Debug|debug) CONFIGURATION="Debug" ;;
    Release|release) CONFIGURATION="Release" ;;
    *)
        fail "usage: $0 [debug|release] [open|no-open]"
        ;;
esac

case "$OPEN_APP" in
    open|no-open) ;;
    *)
        fail "usage: $0 [debug|release] [open|no-open]"
        ;;
esac

case "$UNSIGNED" in
    0|1) ;;
    *)
        fail "APP_STORE_UNSIGNED must be 0 or 1."
        ;;
esac

if [[ -n "$APP_VERSION" && ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    fail "APP_VERSION must contain dot-separated numbers, for example 1.7.0."
fi

if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    fail "BUILD_NUMBER must contain only digits."
fi

if [[ "$UNSIGNED" == "1" && "$SIGNING_IDENTITY" != "-" ]]; then
    fail "APP_STORE_UNSIGNED=1 cannot be combined with a signing identity."
fi

if [[ -n "$ARCHIVE_PATH" ]]; then
    ARCHIVE_PATH="$(
        /usr/bin/python3 - "$ROOT" "$ARCHIVE_PATH" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve(strict=True)
raw = Path(sys.argv[2])
if any(part == ".." for part in raw.parts):
    raise SystemExit("APP_STORE_ARCHIVE_PATH must not contain '..'")
candidate = raw if raw.is_absolute() else root / raw
resolved = candidate.resolve(strict=False)
try:
    resolved.relative_to(root)
except ValueError:
    raise SystemExit("APP_STORE_ARCHIVE_PATH must stay inside the repository")
if resolved == root:
    raise SystemExit("APP_STORE_ARCHIVE_PATH must not be the repository root")
protected_roots = (
    root / "dist",
    root / ".build" / "app-store" / "DerivedData",
    root / ".build" / "app-store" / "XcodeProject",
)
for protected in protected_roots:
    protected = protected.resolve(strict=False)
    if resolved == protected or protected in resolved.parents:
        raise SystemExit(
            "APP_STORE_ARCHIVE_PATH must not use build or distribution output paths"
        )
print(resolved)
PY
    )"
fi

cd "$ROOT"

[[ -f "$VERIFIER" && -r "$VERIFIER" ]] ||
    fail "missing readable Store bundle verifier at $VERIFIER."
[[ -f "$ENTITLEMENTS" && -r "$ENTITLEMENTS" ]] ||
    fail "missing readable Store entitlements at $ENTITLEMENTS."
[[ -f "$PRIVACY_MANIFEST" && -r "$PRIVACY_MANIFEST" ]] ||
    fail "missing readable Store privacy manifest at $PRIVACY_MANIFEST."
python3 "$ROOT/scripts/generate-app-store-project.py" \
    --repo-root "$ROOT" \
    --check-privacy-manifest "$PRIVACY_MANIFEST" >/dev/null ||
    fail "Store privacy manifest failed its tracking/data contract."

SDK_VERSION="${STATUS_TRIO_SDK_VERSION_OVERRIDE:-$(xcrun --sdk macosx --show-sdk-version)}"
SDK_MAJOR="${SDK_VERSION%%.*}"
if [[ ! "$SDK_MAJOR" =~ ^[0-9]+$ ]] || (( SDK_MAJOR < 26 )); then
    fail "Status Trio requires the macOS 26 SDK or newer; found ${SDK_VERSION}."
fi

XCODEGEN="${XCODEGEN:-/opt/homebrew/bin/xcodegen}"
if [[ ! -x "$XCODEGEN" ]]; then
    fail "xcodegen $XCODEGEN_REQUIRED_VERSION is required exactly at $XCODEGEN."
fi

mkdir -p "$GENERATED_ROOT" "$PROJECT_DIR"

env_args=()
if [[ -n "$APP_VERSION" ]]; then
    env_args+=("APP_VERSION=$APP_VERSION")
fi
if [[ -n "$BUILD_NUMBER" ]]; then
    env_args+=("BUILD_NUMBER=$BUILD_NUMBER")
fi
env_args+=("XCODEGEN=$XCODEGEN")

env "${env_args[@]}" /usr/bin/python3 "$ROOT/scripts/generate-app-store-project.py" \
    --repo-root "$ROOT" \
    --project "$PROJECT_SPEC" \
    --output-root "$GENERATED_ROOT" \
    --require-xcodegen

SOURCE_TREE_SHA256="$(
    /usr/bin/python3 - "$GENERATED_ROOT/source-membership.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle).get("source_tree_sha256")
if not isinstance(value, str) or len(value) != 64:
    raise SystemExit("generated source membership has no source tree digest")
print(value)
PY
)"

"$XCODEGEN" generate \
    --spec "$PROJECT_SPEC" \
    --project "$PROJECT_DIR" \
    --project-root "$ROOT" \
    --quiet

if [[ ! -d "$XCODE_PROJECT" ]]; then
    fail "xcodegen did not generate $XCODE_PROJECT."
fi

/usr/bin/python3 "$ROOT/scripts/generate-app-store-project.py" \
    --repo-root "$ROOT" \
    --validate-xcode-project "$XCODE_PROJECT" ||
    fail "generated Store Xcode project failed resource path validation."
xcodebuild -project "$XCODE_PROJECT" -list >/dev/null
trap 'if [[ -n "${SIGNED_ENTITLEMENTS:-}" ]]; then /bin/rm -f "$SIGNED_ENTITLEMENTS"; fi' EXIT

# Bundle IDs are target-specific and live in the generated spec. Passing a
# global PRODUCT_BUNDLE_IDENTIFIER here would overwrite the Core framework ID.
xcode_args=(
    -project "$XCODE_PROJECT"
    -scheme "StatusTrio (App Store)"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA"
)

if [[ "$UNSIGNED" == "1" ]]; then
    xcode_args+=(
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGN_IDENTITY=
    )
else
    xcode_args+=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGNING_REQUIRED=YES
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
        CODE_SIGN_STYLE=Manual
    )
fi

if [[ -n "$ARCHIVE_PATH" ]]; then
    [[ -f "$DSYM_VERIFIER" && -r "$DSYM_VERIFIER" ]] ||
        fail "missing readable archive dSYM verifier at $DSYM_VERIFIER."
    if [[ -e "$ARCHIVE_PATH" ]]; then
        fail "APP_STORE_ARCHIVE_PATH already exists; remove it before archiving: $ARCHIVE_PATH"
    fi
    xcodebuild "${xcode_args[@]}" \
        -archivePath "$ARCHIVE_PATH" \
        archive
    BUILT_APP="$ARCHIVE_PATH/Products/Applications/StatusTrio.app"
    if [[ ! -d "$BUILT_APP" ]]; then
        fail "archive did not contain Products/Applications/StatusTrio.app: $ARCHIVE_PATH"
    fi
    bash "$DSYM_VERIFIER" "$ARCHIVE_PATH"
    BUILD_ACTION="archive"
else
    xcodebuild "${xcode_args[@]}" build
    BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/StatusTrio.app"
    if [[ ! -d "$BUILT_APP" ]]; then
        fail "xcodebuild did not produce StatusTrio.app at $BUILT_APP."
    fi
    BUILD_ACTION="build"
fi

STORE_CORE_BUILD_DIR="$(
    /usr/bin/find "$DERIVED_DATA/Build/Intermediates.noindex" \
        -type d -name 'StatusTrioCore.build' -print -quit 2>/dev/null || true
)"
[[ -n "$STORE_CORE_BUILD_DIR" ]] ||
    fail "no StatusTrioCore.build directory was produced under DerivedData."

# The generated audit is a claim until it is checked against the file list
# Xcode actually compiled. The pre-build digest prevents a source edit during
# compilation from being silently attributed to the finished binary.
env "${env_args[@]}" /usr/bin/python3 "$ROOT/scripts/generate-app-store-project.py" \
    --repo-root "$ROOT" \
    --project "$PROJECT_SPEC" \
    --output-root "$GENERATED_ROOT" \
    --record-compiled-sources "$DERIVED_DATA" \
    --record-configuration "$CONFIGURATION" \
    --record-build-action "$BUILD_ACTION" \
    --expected-source-tree-sha256 "$SOURCE_TREE_SHA256" \
    --verify-closure-audit

mkdir -p "$(dirname "$STORE_APP")"
if [[ -e "$STORE_APP" ]]; then
    /bin/rm -rf "$STORE_APP"
fi
ditto "$BUILT_APP" "$STORE_APP"

if [[ ! -f "$STORE_APP/Contents/Info.plist" ]]; then
    fail "missing Store Info.plist in $STORE_APP."
fi
if [[ ! -f "$STORE_APP/Contents/Frameworks/StatusTrioCore.framework/StatusTrioCore" ]]; then
    fail "missing embedded StatusTrioCore.framework in $STORE_APP."
fi

RESOURCE_DIR="$STORE_APP/Contents/Resources"
PRIVACY_MANIFEST_IN_BUNDLE="$RESOURCE_DIR/PrivacyInfo.xcprivacy"
[[ -f "$PRIVACY_MANIFEST_IN_BUNDLE" && -r "$PRIVACY_MANIFEST_IN_BUNDLE" ]] ||
    fail "Store app is missing readable Contents/Resources/PrivacyInfo.xcprivacy."
python3 "$ROOT/scripts/generate-app-store-project.py" \
    --repo-root "$ROOT" \
    --check-privacy-manifest "$PRIVACY_MANIFEST_IN_BUNDLE" >/dev/null ||
    fail "bundled Store privacy manifest failed its tracking/data contract."
INFO_PLIST_COUNT="$(
    /usr/bin/find "$RESOURCE_DIR" -type f \
        -path '*.lproj/InfoPlist.strings' -print | wc -l | tr -d '[:space:]'
)"
if [[ "$INFO_PLIST_COUNT" -ne "${#APP_LOCALIZATION_DIRECTORIES[@]}" ]]; then
    fail "expected ${#APP_LOCALIZATION_DIRECTORIES[@]} localized app InfoPlist.strings files, found $INFO_PLIST_COUNT."
fi
for locale in "${APP_LOCALIZATION_DIRECTORIES[@]}"; do
    localized_info="$RESOURCE_DIR/$locale/InfoPlist.strings"
    [[ -f "$localized_info" ]] ||
        fail "Store app is missing $locale/InfoPlist.strings."
    plutil -lint "$localized_info" >/dev/null ||
        fail "Store app has an invalid $locale/InfoPlist.strings."
    for key in \
        NSLocationUsageDescription \
        NSLocationWhenInUseUsageDescription \
        NSBluetoothAlwaysUsageDescription; do
        description="$(
            plutil -extract "$key" raw -expect string "$localized_info" \
                2>/dev/null || true
        )"
        [[ -n "${description//[[:space:]]/}" ]] ||
            fail "Store app $locale/InfoPlist.strings must declare nonempty $key."
    done
done

EXPECTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Support/Info.plist")"
EXPECTED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Support/Info.plist")"
if [[ -n "$APP_VERSION" ]]; then EXPECTED_VERSION="$APP_VERSION"; fi
if [[ -n "$BUILD_NUMBER" ]]; then EXPECTED_BUILD="$BUILD_NUMBER"; fi

ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STORE_APP/Contents/Info.plist")"
ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$STORE_APP/Contents/Info.plist")"
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STORE_APP/Contents/Info.plist")"

[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] ||
    fail "Store version $ACTUAL_VERSION does not match expected $EXPECTED_VERSION."
[[ "$ACTUAL_BUILD" == "$EXPECTED_BUILD" ]] ||
    fail "Store build $ACTUAL_BUILD does not match expected $EXPECTED_BUILD."
[[ "$ACTUAL_BUNDLE_ID" == "com.lingsmbp.StatusTrio.AppStore" ]] ||
    fail "Store Bundle ID is $ACTUAL_BUNDLE_ID."

plutil -lint "$STORE_APP/Contents/Info.plist" "$ENTITLEMENTS" >/dev/null
for key in SUFeedURL SUPublicEDKey SUEnableInstallerLauncherService; do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$STORE_APP/Contents/Info.plist" >/dev/null 2>&1; then
        fail "Store Info.plist contains forbidden Sparkle key $key."
    fi
done

if ! find "$STORE_APP" -type f -name '*.swift' -print -quit | grep -q .; then
    :
else
    fail "Store bundle contains Swift source files."
fi

APP_ICON_ICNS="$STORE_APP/Contents/Resources/StatusTrioAppStore.icns"
[[ -f "$APP_ICON_ICNS" && -s "$APP_ICON_ICNS" ]] ||
    fail "Store app icon was not generated at $APP_ICON_ICNS."
ICON_TYPE="$(file -b "$APP_ICON_ICNS")"
case "$ICON_TYPE" in
    *"Apple Icon Image"*|*"Mac OS X icon"*) ;;
    *) fail "Store app icon is not an ICNS file: $ICON_TYPE" ;;
esac
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$STORE_APP/Contents/Info.plist")"
[[ "$ICON_NAME" == "StatusTrioAppStore" ]] ||
    fail "Store Info.plist CFBundleIconFile is $ICON_NAME, expected StatusTrioAppStore."

MAIN_BINARY="$STORE_APP/Contents/MacOS/StatusTrio"
[[ -f "$MAIN_BINARY" ]] || fail "missing Store main executable at $MAIN_BINARY."
DECLARED_MINOS="$(
    /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
        "$STORE_APP/Contents/Info.plist"
)"
[[ "$DECLARED_MINOS" == "13.0" ]] ||
    fail "Store app declares LSMinimumSystemVersion $DECLARED_MINOS, expected 13.0."
bash "$ROOT/scripts/verify-platform-version.sh" \
    "$MAIN_BINARY" "$DECLARED_MINOS" 26
CORE_BINARY="$STORE_APP/Contents/Frameworks/StatusTrioCore.framework/StatusTrioCore"
bash "$ROOT/scripts/verify-platform-version.sh" \
    "$CORE_BINARY" "$DECLARED_MINOS" 26

if [[ "$UNSIGNED" == "1" ]]; then
    echo "Built $STORE_APP (unsigned compile/static only; sandbox entitlement NOT verified)"
else
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        echo "Signing with local ad-hoc identity (not Developer ID or Apple Distribution)." >&2
    else
        echo "Signing with explicitly selected identity: $SIGNING_IDENTITY" >&2
    fi
    FRAMEWORKS_DIR="$STORE_APP/Contents/Frameworks"
    if [[ -d "$FRAMEWORKS_DIR" ]]; then
        while IFS= read -r -d '' framework; do
            codesign --force --sign "$SIGNING_IDENTITY" "$framework"
        done < <(/usr/bin/find "$FRAMEWORKS_DIR" -depth -type d -name '*.framework' -print0)
    fi

    codesign --force --sign "$SIGNING_IDENTITY" \
        --entitlements "$ENTITLEMENTS" "$STORE_APP"
    codesign --verify --deep --strict --verbose=2 "$STORE_APP"

    SIGNED_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/StatusTrioAppStore.entitlements.XXXXXX")"
    codesign -d --entitlements :- "$STORE_APP" > "$SIGNED_ENTITLEMENTS" 2>/dev/null
    SANDBOX="$(
        /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' \
            "$SIGNED_ENTITLEMENTS" 2>/dev/null || true
    )"
    [[ "$SANDBOX" == "true" ]] ||
        fail "signed Store app does not carry com.apple.security.app-sandbox=true."
    echo "Built $STORE_APP (sandbox entitlement present in local signature)"
fi

if [[ "$UNSIGNED" == "1" ]]; then
    bash "$VERIFIER" "$STORE_APP" --unsigned
else
    bash "$VERIFIER" "$STORE_APP"
fi

if [[ "$OPEN_APP" == "open" ]]; then
    open "$STORE_APP"
fi
