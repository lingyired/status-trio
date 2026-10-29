#!/usr/bin/env bash
# Builds, signs, notarizes, and packages one frozen source SHA. Publication is
# intentionally impossible from this script.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/build-timing.sh"
trap 'build_timing_finish "$?"' EXIT
build_phase package-preflight
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist/release-package}"
SOURCE_SHA="${SOURCE_SHA:?SOURCE_SHA is required}"
VERSION="${VERSION:?VERSION is required}"
BUILD="${BUILD:?BUILD is required}"
TAG="${TAG:?TAG is required}"
PUBLISH_MODE="${PUBLISH_MODE:-false}"
NOTARIZE="${NOTARIZE:-false}"
RELEASE_REPO="${RELEASE_REPO:-}"
RELEASE_BRANCH="${RELEASE_BRANCH:-}"
RELEASE_NOTES_DIR="${RELEASE_NOTES_DIR:-release-notes/$VERSION}"
APP_NAME="${APP_NAME:-Status Trio}"
BUNDLE_ID="${BUNDLE_ID:-com.lingsmbp.StatusTrio}"
SIGNING_KIND="ad_hoc"
if [[ "${CODE_SIGN_IDENTITY:--}" != "-" ]]; then
    SIGNING_KIND="developer_id"
fi
NOTARIZATION_STATUS="not_requested"

die() {
    echo "Package error: $*" >&2
    exit 1
}

[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || die "SOURCE_SHA must be a lowercase 40-character SHA."
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "VERSION is invalid."
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "BUILD is invalid."
[[ "$TAG" == "v${VERSION}" ]] || die "TAG '$TAG' does not match VERSION '$VERSION'."
[[ "$PUBLISH_MODE" == "true" || "$PUBLISH_MODE" == "false" ]] ||
    die "PUBLISH_MODE must be true or false."
[[ "$NOTARIZE" == "true" || "$NOTARIZE" == "false" ]] ||
    die "NOTARIZE must be true or false."
if [[ "$PUBLISH_MODE" == "true" && -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    die "SPARKLE_PRIVATE_KEY is required for a publishable package."
fi
if [[ "$PUBLISH_MODE" == "false" && -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "Warning: diagnostic package has no Sparkle private key; its appcast signature is not publishable." >&2
fi
if [[ "$NOTARIZE" == "true" ]]; then
    [[ -n "${CODE_SIGN_IDENTITY:-}" && "$CODE_SIGN_IDENTITY" != "-" ]] ||
        die "NOTARIZE=true requires a Developer ID Application identity."
    [[ -n "${NOTARY_PROFILE:-}" ]] ||
        die "NOTARIZE=true requires NOTARY_PROFILE."
fi
if [[ -n "${NOTARY_PROFILE:-}" && "$SIGNING_KIND" != "developer_id" ]]; then
    die "NOTARY_PROFILE requires a Developer ID signature."
fi
if [[ "$PUBLISH_MODE" == "true" && "$SIGNING_KIND" == "developer_id" && -z "${NOTARY_PROFILE:-}" ]]; then
    die "A Developer ID package must be notarized before publication."
fi

if [[ -z "$RELEASE_REPO" || -z "$RELEASE_BRANCH" ]]; then
    CONFIG_REPO="$(
        ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("github_repo")' \
            "$ROOT/release.json"
    )"
    CONFIG_BRANCH="$(
        ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("git_branch")' \
            "$ROOT/release.json"
    )"
    RELEASE_REPO="${RELEASE_REPO:-$CONFIG_REPO}"
    RELEASE_BRANCH="${RELEASE_BRANCH:-$CONFIG_BRANCH}"
fi

if [[ "$PUBLISH_MODE" == "true" ]]; then
    [[ -n "$RELEASE_REPO" ]] || die "RELEASE_REPO is required for a publishable package."
    [[ -n "$RELEASE_BRANCH" ]] || die "RELEASE_BRANCH is required for a publishable package."
fi
ACTUAL_SHA="$(
    cd "$ROOT"
    git rev-parse HEAD
)"
[[ "$ACTUAL_SHA" == "$SOURCE_SHA" ]] ||
    die "checked-out SHA $ACTUAL_SHA differs from requested source $SOURCE_SHA."
WORKTREE_STATUS="$(
    cd "$ROOT"
    git status --porcelain=v1 --untracked-files=all
)"
[[ -z "$WORKTREE_STATUS" ]] ||
    die "release packaging requires a clean committed worktree; found local changes."

for command in git ruby shasum swift xcrun hdiutil plutil /usr/libexec/PlistBuddy; do
    command -v "$command" >/dev/null 2>&1 || die "required command '$command' is not available."
done

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
XCODE_VERSION="$(xcodebuild -version | tr '\n' ' ' | sed 's/ $//')"
SWIFT_VERSION="$(swift --version 2>&1)"
SWIFT_VERSION="${SWIFT_VERSION%%$'\n'*}"
case "$XCODE_VERSION" in
    "Xcode 27"|"Xcode 27."*) ;;
    *) die "Xcode 27 is required; found $XCODE_VERSION." ;;
esac
[[ "${SDK_VERSION%%.*}" -ge 26 ]] || die "macOS SDK 26+ is required; found $SDK_VERSION."

cd "$ROOT"
case "$PUBLISH_MODE" in
    true) NOTES_MODE="publish" ;;
    false) NOTES_MODE="package" ;;
esac
case "$RELEASE_NOTES_DIR" in
    /*) NOTES_DIR_ABSOLUTE="$RELEASE_NOTES_DIR" ;;
    *) NOTES_DIR_ABSOLUTE="$ROOT/$RELEASE_NOTES_DIR" ;;
esac
HAS_RELEASE_NOTES=false
if [[ -d "$NOTES_DIR_ABSOLUTE" ]]; then
    HAS_RELEASE_NOTES=true
    VERSION="$VERSION" BUILD="$BUILD" PUBLISH="$PUBLISH_MODE" NOTES_MODE="$NOTES_MODE" \
        RELEASE_NOTES_DIR="$NOTES_DIR_ABSOLUTE" \
        APPCAST_FILE="appcast.xml" \
        bash "$ROOT/scripts/validate-appcast-notes.sh"
elif [[ "$PUBLISH_MODE" == "true" ]]; then
    die "release notes directory is missing: $NOTES_DIR_ABSOLUTE"
else
    echo "Package-only run has no release-notes directory; release notes validation and appcast generation are skipped."
fi

mkdir -p "$OUTPUT_DIR"
APPCAST_PATH="$ROOT/appcast.xml"
ruby -e '
    build = ARGV[0].to_i
    appcast = File.read(ARGV[1])
    max = appcast.scan(%r{<sparkle:version>\s*(\d+)\s*</sparkle:version>}).flatten.map(&:to_i).max || 0
    abort("Build #{build} must exceed the latest appcast build #{max}.") unless build > max
' "$BUILD" "$APPCAST_PATH"

DMG_BASENAME="$(
    ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("dmg_name").sub(/\.dmg\z/, "")' \
        "$ROOT/release.json"
)"
MINIMUM_SYSTEM_VERSION="$(
    ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).fetch("min_system_version")' \
        "$ROOT/release.json"
)"

printf 'Building %s %s (%s) at %s...\n' "$APP_NAME" "$VERSION" "$BUILD" "$SOURCE_SHA"
build_phase app-build-sign-and-verify
env -u GH_TOKEN -u SPARKLE_PRIVATE_KEY \
    APP_VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD" \
    SU_FEED_URL="https://raw.githubusercontent.com/$RELEASE_REPO/$RELEASE_BRANCH/appcast.xml" \
    UNIVERSAL_BUILD=1 \
    PRIVILEGED_HELPER=1 \
    TELEMETRY_PRODUCTION=1 \
    BUNDLE_ID="$BUNDLE_ID" \
    APP_NAME="$APP_NAME" \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
    KEYCHAIN_PATH="${KEYCHAIN_PATH:-}" \
    bash "$ROOT/scripts/build-app.sh" release no-open

APP_DIR="$ROOT/dist/StatusTrio.app"
build_phase universal-package-contracts
for binary in \
    "$APP_DIR/Contents/MacOS/StatusTrio" \
    "$APP_DIR/Contents/Helpers/StatusTrioPowerHelper"; do
    [[ -f "$binary" ]] || die "required binary is missing: $binary"
    bash "$ROOT/scripts/verify-platform-version.sh" "$binary" "$MINIMUM_SYSTEM_VERSION" 26
    ARCHS="$(lipo -archs "$binary")"
    for arch in arm64 x86_64; do
        [[ " $ARCHS " == *" $arch "* ]] || die "$binary is missing the $arch slice."
    done
done
UNIVERSAL_BUILD=1 bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "$APP_DIR"
UNIVERSAL_BUILD=1 bash "$ROOT/scripts/verify-privileged-helper-bundle.sh" "$APP_DIR"
bash "$ROOT/scripts/test-macos13-sparkle-metadata.sh" "$APP_DIR"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioPackage.XXXXXX")"
trap 'build_timing_finish "$?"; rm -rf "$TEMP_ROOT"' EXIT
build_phase dmg-staging
STAGING_DIR="$TEMP_ROOT/dmg"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    build_phase app-notarization
    if [[ "${CODE_SIGN_IDENTITY:--}" == "-" ]]; then
        die "NOTARY_PROFILE requires a Developer ID signature."
    fi
    APP_ARCHIVE="$TEMP_ROOT/app.zip"
    ditto -c -k --keepParent "$STAGING_DIR/$APP_NAME.app" "$APP_ARCHIVE"
    APP_NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        APP_NOTARY_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
    xcrun notarytool submit "$APP_ARCHIVE" \
        "${APP_NOTARY_ARGS[@]}" \
        --wait --output-format json > "$TEMP_ROOT/app-notary.json"
    ruby -rjson -e '
        result = JSON.parse(File.read(ARGV[0]))
        abort("App notarization status was #{result["status"]}.") unless result["status"] == "Accepted"
    ' "$TEMP_ROOT/app-notary.json"
    xcrun stapler staple "$STAGING_DIR/$APP_NAME.app"
    xcrun stapler validate "$STAGING_DIR/$APP_NAME.app"
fi

DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME-$VERSION.dmg"
build_phase dmg-creation
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING_DIR" \
    -ov -format UDZO "$DMG_PATH"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    build_phase dmg-codesign
    DMG_SIGN_ARGS=(--force --sign "${CODE_SIGN_IDENTITY:?}" --timestamp)
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        DMG_SIGN_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
    /usr/bin/codesign "${DMG_SIGN_ARGS[@]}" "$DMG_PATH"
    /usr/bin/codesign --verify --strict --verbose=2 "$DMG_PATH"
    DMG_NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        DMG_NOTARY_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
    build_phase dmg-notarization
    xcrun notarytool submit "$DMG_PATH" "${DMG_NOTARY_ARGS[@]}" \
        --wait --output-format json > "$TEMP_ROOT/dmg-notary.json"
    ruby -rjson -e '
        result = JSON.parse(File.read(ARGV[0]))
        abort("DMG notarization status was #{result["status"]}.") unless result["status"] == "Accepted"
    ' "$TEMP_ROOT/dmg-notary.json"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
    spctl --assess --type execute --verbose=2 "$STAGING_DIR/$APP_NAME.app"
fi

DMG_FILENAME="$(basename "$DMG_PATH")"
build_phase sparkle-signature-and-manifest
ACTUAL_DMG_LENGTH="$(stat -f '%z' "$DMG_PATH")"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
    [[ -x "$SIGN_UPDATE" ]] || die "Sparkle sign_update was not found at $SIGN_UPDATE."
    SIGN_OUTPUT="$(
        printf '%s' "$SPARKLE_PRIVATE_KEY" |
            env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - "$DMG_PATH"
    )"
    ED_SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    DMG_LENGTH="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*length="\([0-9][0-9]*\)".*/\1/p')"
    [[ -n "$ED_SIGNATURE" && -n "$DMG_LENGTH" ]] ||
        die "Could not parse Sparkle signature output."
    [[ "$DMG_LENGTH" == "$ACTUAL_DMG_LENGTH" ]] ||
        die "Sparkle signature length $DMG_LENGTH differs from the actual DMG length $ACTUAL_DMG_LENGTH."
else
    [[ "$PUBLISH_MODE" == "false" ]] ||
        die "SPARKLE_PRIVATE_KEY is required for a publishable package."
    ED_SIGNATURE="diagnostic-not-for-publication"
    DMG_LENGTH="$ACTUAL_DMG_LENGTH"
    echo "Diagnostic package has no Sparkle signature; manifest is marked non-publishable." >&2
fi
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$DMG_FILENAME" > "$DMG_FILENAME.sha256"
)
DMG_SHA256="$(awk '{print $1}' "$OUTPUT_DIR/$DMG_FILENAME.sha256")"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    if [[ "${CODE_SIGN_IDENTITY:--}" == "-" ]]; then
        die "NOTARY_PROFILE requires a Developer ID signature."
    fi
    NOTARIZATION_STATUS="accepted_and_stapled"
fi

if [[ "$HAS_RELEASE_NOTES" == "true" ]]; then
    mkdir -p "$OUTPUT_DIR/release-notes/$VERSION"
    ditto "$NOTES_DIR_ABSOLUTE" "$OUTPUT_DIR/release-notes/$VERSION"
fi
VERSION="$VERSION" \
    PUBLISH_MODE="$PUBLISH_MODE" \
    SIGNING_KIND="$SIGNING_KIND" \
    RELEASE_NOTES_DIR="$NOTES_DIR_ABSOLUTE" \
    OUTPUT="$OUTPUT_DIR/release-body.md" \
    bash "$ROOT/scripts/prepare-release-body.sh"

ruby -rjson -e '
    require "time"
    output, source_sha, version, build, tag, dmg, sha, length, signature,
      repo, branch, appcast, body, notes, signing, notarization, app_name, bundle_id,
      minimum_system_version, xcode, swift, sdk = ARGV
    File.write(
      File.join(output, "release-manifest.json"),
      JSON.pretty_generate(
        schema_version: 1,
        generated_at: Time.now.utc.iso8601,
        source_sha: source_sha,
        version: version,
        build: build,
        tag: tag,
        app_name: app_name,
        bundle_id: bundle_id,
        minimum_system_version: minimum_system_version,
        toolchain: { xcode: xcode, swift: swift, sdk: sdk, runner: "xcode-27" },
        dmg: {
          filename: dmg,
          sha256: sha,
          length: length,
          ed_signature: signature
        },
        signing: { kind: signing },
        notarization: { status: notarization },
        release: {
          repo: repo,
          branch: branch,
          appcast_file: appcast,
          body_file: body,
          notes_dir: notes
        }
      ) + "\n"
    )
' "$OUTPUT_DIR" "$SOURCE_SHA" "$VERSION" "$BUILD" "$TAG" "$DMG_FILENAME" \
    "$DMG_SHA256" "$DMG_LENGTH" "$ED_SIGNATURE" "$RELEASE_REPO" \
    "$RELEASE_BRANCH" "appcast.xml" "release-body.md" "release-notes/$VERSION" \
    "$SIGNING_KIND" "$NOTARIZATION_STATUS" "$APP_NAME" "$BUNDLE_ID" \
    "$MINIMUM_SYSTEM_VERSION" "$XCODE_VERSION" "$SWIFT_VERSION" \
    "$SDK_VERSION"

echo "Package ready: $DMG_FILENAME ($DMG_SHA256), signing=$SIGNING_KIND, notarization=$NOTARIZATION_STATUS"
