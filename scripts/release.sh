#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$ROOT/release.json"

read_config() {
    ruby -rjson -e '
        value = JSON.parse(File.read(ARGV[0]))
        ARGV[1].split(".").each { |key| value = value.fetch(key) }
        print value
    ' "$CONFIG_PATH" "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: required command '$1' is not available." >&2
        exit 1
    fi
}

for command in ruby swift hdiutil shasum plutil xmllint ditto /usr/bin/codesign /usr/bin/xcrun; do
    require_command "$command"
done

cd "$ROOT"

APP_NAME="${APP_NAME:-$(read_config app_name)}"
BUNDLE_ID="${BUNDLE_ID:-$(read_config bundle_id)}"
RELEASE_REPO="${RELEASE_REPO:-$(read_config github_repo)}"
RELEASE_BRANCH="${RELEASE_BRANCH:-$(read_config git_branch)}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-$(read_config min_system_version)}"
APPCAST_FILE="${APPCAST_FILE:-$(read_config appcast_file)}"
DMG_BASENAME="$(read_config dmg_name)"
DMG_BASENAME="${DMG_BASENAME%.dmg}"

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Support/Info.plist")}"
BUILD="${BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Support/Info.plist")}"
TAG="${TAG:-v$VERSION}"
PUBLISH="${PUBLISH:-true}"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
SU_FEED_URL="${SU_FEED_URL:-https://raw.githubusercontent.com/$RELEASE_REPO/$RELEASE_BRANCH/$APPCAST_FILE}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Error: VERSION must contain dot-separated numbers, for example 1.2.0." >&2
    exit 2
fi

if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "Error: BUILD must contain only digits." >&2
    exit 2
fi

case "$PUBLISH" in
    true|false) ;;
    *)
        echo "Error: PUBLISH must be true or false." >&2
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

if [[ "$SU_FEED_URL" != https://* ]]; then
    echo "Error: SU_FEED_URL must use HTTPS." >&2
    exit 2
fi

if [[ -n "$NOTARY_PROFILE" && "$CODE_SIGN_IDENTITY" == "-" ]]; then
    echo "Error: NOTARY_PROFILE requires a Developer ID signature via CODE_SIGN_IDENTITY." >&2
    exit 2
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioRelease.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

APPCAST_PATH="$TEMP_ROOT/appcast.xml"
APPCAST_SHA=""

if [[ "$PUBLISH" == "true" ]]; then
    require_command gh

    if [[ -z "${GH_TOKEN:-}" ]] && ! gh auth status >/dev/null 2>&1; then
        echo "Error: gh is not authenticated. Set GH_TOKEN or run 'gh auth login'." >&2
        exit 1
    fi

    VISIBILITY="$(gh repo view "$RELEASE_REPO" --json visibility --jq .visibility)"
    if [[ "$VISIBILITY" != "PUBLIC" ]]; then
        cat >&2 <<EOF
Error: release repository '$RELEASE_REPO' is $VISIBILITY.

Sparkle must download the appcast and DMG anonymously. Use either:
  1. Make $RELEASE_REPO public, or
  2. Create a public update repository and set RELEASE_REPO to its owner/name.
EOF
        exit 1
    fi

    APPCAST_SHA="$(gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" --jq .sha)"
    gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" \
        -H "Accept: application/vnd.github.raw" > "$APPCAST_PATH"
else
    cp "$ROOT/$APPCAST_FILE" "$APPCAST_PATH"
fi

ruby -e '
    build = ARGV[0].to_i
    max_build = File.read(ARGV[1]).scan(%r{<sparkle:version>\s*(\d+)\s*</sparkle:version>}).flatten.map(&:to_i).max || 0
    abort("Error: build #{build} must be greater than the latest published build #{max_build}.") unless build > max_build
' "$BUILD" "$APPCAST_PATH"

if [[ -z "${RELEASE_NOTES_FILE:-}" ]]; then
    RELEASE_NOTES_FILE="$TEMP_ROOT/release-notes.md"
    printf '%s\n' "- Release v$VERSION." > "$RELEASE_NOTES_FILE"
fi

if [[ -z "${RELEASE_BODY_FILE:-}" ]]; then
    RELEASE_BODY_FILE="$RELEASE_NOTES_FILE"
fi

if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
    echo "Error: release notes file does not exist: $RELEASE_NOTES_FILE" >&2
    exit 1
fi

if [[ ! -f "$RELEASE_BODY_FILE" ]]; then
    echo "Error: GitHub release body file does not exist: $RELEASE_BODY_FILE" >&2
    exit 1
fi

RELEASE_NOTES_DIR="${RELEASE_NOTES_DIR:-$ROOT/release-notes/$VERSION}"

if [[ ! -d "$RELEASE_NOTES_DIR" ]]; then
    echo "Error: release notes directory does not exist: $RELEASE_NOTES_DIR" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Building $APP_NAME $VERSION ($BUILD) for $RELEASE_REPO..."
env -u GH_TOKEN -u SPARKLE_PRIVATE_KEY \
    APP_VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD" \
    SU_FEED_URL="$SU_FEED_URL" \
    UNIVERSAL_BUILD="$UNIVERSAL_BUILD" \
    TELEMETRY_PRODUCTION=1 \
    BUNDLE_ID="$BUNDLE_ID" \
    APP_NAME="$APP_NAME" \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    KEYCHAIN_PATH="$KEYCHAIN_PATH" \
    bash "$ROOT/scripts/build-app.sh" release no-open

STAGING_DIR="$TEMP_ROOT/dmg"
mkdir -p "$STAGING_DIR"
ditto "$ROOT/dist/StatusTrio.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME-$VERSION.dmg"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

hdiutil create \
    -quiet \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "Submitting $DMG_PATH for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SIGN_UPDATE="${SIGN_UPDATE:-$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update}"
ED_SIGNATURE=""
DMG_LENGTH=""

if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "Error: Sparkle sign_update was not found at $SIGN_UPDATE." >&2
    exit 1
fi

if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
    SIGN_OUTPUT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | env -u SPARKLE_PRIVATE_KEY "$SIGN_UPDATE" --ed-key-file - "$DMG_PATH")"
elif [[ "$PUBLISH" == "true" ]]; then
    SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")"
else
    SIGN_OUTPUT=""
fi

if [[ -n "$SIGN_OUTPUT" ]]; then
    ED_SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    DMG_LENGTH="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*length="\([0-9][0-9]*\)".*/\1/p')"

    if [[ -z "$ED_SIGNATURE" || -z "$DMG_LENGTH" ]]; then
        echo "Error: could not parse Sparkle signature output: $SIGN_OUTPUT" >&2
        exit 1
    fi
fi

DMG_FILENAME="$(basename "$DMG_PATH")"
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$DMG_FILENAME" > "$DMG_FILENAME.sha256"
)

DMG_URL="https://github.com/$RELEASE_REPO/releases/download/$TAG/$(basename "$DMG_PATH")"

{
    printf 'VERSION=%q\n' "$VERSION"
    printf 'BUILD=%q\n' "$BUILD"
    printf 'TAG=%q\n' "$TAG"
    printf 'APP_NAME=%q\n' "$APP_NAME"
    printf 'BUNDLE_ID=%q\n' "$BUNDLE_ID"
    printf 'RELEASE_REPO=%q\n' "$RELEASE_REPO"
    printf 'SU_FEED_URL=%q\n' "$SU_FEED_URL"
    printf 'DMG_PATH=%q\n' "$DMG_PATH"
    printf 'DMG_URL=%q\n' "$DMG_URL"
    printf 'ED_SIGNATURE=%q\n' "$ED_SIGNATURE"
    printf 'DMG_LENGTH=%q\n' "$DMG_LENGTH"
} > "$OUTPUT_DIR/release.env"

if [[ "$PUBLISH" == "false" ]]; then
    echo "Built $DMG_PATH without publishing."
    exit 0
fi

if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "Error: GitHub Release $TAG already exists in $RELEASE_REPO." >&2
    exit 1
fi

echo "Creating GitHub Release $TAG..."
RELEASE_ARGS=(
    "$DMG_PATH"
    "$DMG_PATH.sha256"
    --repo "$RELEASE_REPO"
    --title "$APP_NAME v$VERSION"
    --notes-file "$RELEASE_BODY_FILE"
)
if ! gh api "repos/$RELEASE_REPO/git/ref/tags/$TAG" >/dev/null 2>&1; then
    RELEASE_ARGS+=(--target "$RELEASE_BRANCH")
fi
gh release create "$TAG" "${RELEASE_ARGS[@]}"

ruby "$ROOT/scripts/update-appcast.rb" \
    --version "$VERSION" \
    --build "$BUILD" \
    --minimum-system-version "$MINIMUM_SYSTEM_VERSION" \
    --dmg-url "$DMG_URL" \
    --ed-signature "$ED_SIGNATURE" \
    --length "$DMG_LENGTH" \
    --notes-dir "$RELEASE_NOTES_DIR" \
    --appcast "$APPCAST_PATH"

xmllint --noout "$APPCAST_PATH"

if [[ -z "$APPCAST_SHA" ]]; then
    echo "Error: missing appcast SHA for $RELEASE_REPO/$APPCAST_FILE." >&2
    exit 1
fi

appcast_commit="$(
    ruby -rjson -rbase64 -e '
        puts JSON.generate(
            message: ARGV[0],
            content: Base64.strict_encode64(File.binread(ARGV[1])),
            sha: ARGV[2],
            branch: ARGV[3]
        )
    ' "Release $TAG appcast" "$APPCAST_PATH" "$APPCAST_SHA" "$RELEASE_BRANCH" \
        | gh api --method PUT "repos/$RELEASE_REPO/contents/$APPCAST_FILE" \
            -H "Accept: application/vnd.github+json" \
            --input - \
            --jq '.commit.sha'
)"

# The write above is synchronous: the PUT reports the commit it created. The
# `contents` read path, however, can serve the pre-PUT blob for minutes — run
# 35718713396 read the stale copy 2s after a successful PUT, and 35740301886
# still read it 30s after, while the commit was already on main. Waiting on that
# copy therefore cannot be sized: the lag is at least 30s with no measured upper
# bound. So the verdict comes from the git layer — `git/ref` must point at the
# commit the PUT reported — and a contents read stays as a second opinion for the
# case where the PUT response carried no commit.
appcast_verified=false
appcast_attempts="${APPCAST_READBACK_ATTEMPTS:-24}"
appcast_sleep="${APPCAST_READBACK_SLEEP:-10}"
for ((attempt = 1; attempt <= appcast_attempts; attempt++)); do
    branch_head="$(
        gh api "repos/$RELEASE_REPO/git/ref/heads/$RELEASE_BRANCH" \
            --jq '.object.sha' 2>/dev/null || true
    )"
    if [[ -n "$appcast_commit" && "$branch_head" == "$appcast_commit" ]]; then
        appcast_verified=true
        break
    fi
    if gh api "repos/$RELEASE_REPO/contents/$APPCAST_FILE?ref=$RELEASE_BRANCH" \
        -H "Accept: application/vnd.github.raw" 2>/dev/null \
        | grep -Fq "<sparkle:version>$BUILD</sparkle:version>"; then
        appcast_verified=true
        break
    fi
    if ((attempt < appcast_attempts)); then
        echo "Published appcast read-back missed build $BUILD (attempt $attempt/$appcast_attempts); retrying in ${appcast_sleep}s..." >&2
        sleep "$appcast_sleep"
    fi
done
if [[ "$appcast_verified" != true ]]; then
    echo "Error: published appcast does not contain build $BUILD." >&2
    exit 1
fi

echo "Published $DMG_URL"
echo "Sparkle feed: $SU_FEED_URL"
