#!/usr/bin/env bash
# Publishes an already verified package. This script deliberately has no build,
# package, sign, or notarize path: those operations belong to package-release.sh.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${MANIFEST_PATH:-}"
PACKAGE_DIR="${PACKAGE_DIR:-}"

die() {
    echo "Publish error: $*" >&2
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "required command '$1' is not available."
    fi
}

manifest_value() {
    local key="$1"
    ruby -rjson -e '
        value = JSON.parse(File.read(ARGV[0]))
        ARGV[1].split(".").each { |part| value = value.fetch(part) }
        print value
    ' "$MANIFEST" "$key"
}

if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
    die "MANIFEST_PATH must name an existing package manifest."
fi
if [[ -z "$PACKAGE_DIR" || ! -d "$PACKAGE_DIR" ]]; then
    die "PACKAGE_DIR must name the downloaded package directory."
fi

for command in ruby gh shasum xmllint curl; do
    require_command "$command"
done

SCHEMA_VERSION="$(manifest_value schema_version)"
[[ "$SCHEMA_VERSION" == "1" ]] ||
    die "unsupported manifest schema_version '$SCHEMA_VERSION'."

SOURCE_SHA="$(manifest_value source_sha)"
VERSION="$(manifest_value version)"
BUILD="$(manifest_value build)"
TAG="$(manifest_value tag)"
DMG_FILENAME="$(manifest_value dmg.filename)"
DMG_SHA256="$(manifest_value dmg.sha256)"
DMG_LENGTH="$(manifest_value dmg.length)"
ED_SIGNATURE="$(manifest_value dmg.ed_signature)"
RELEASE_REPO="$(manifest_value release.repo)"
RELEASE_BRANCH="$(manifest_value release.branch)"
APPCAST_FILE="$(manifest_value release.appcast_file)"
RELEASE_BODY_FILE="$(manifest_value release.body_file)"
RELEASE_NOTES_DIR="$(manifest_value release.notes_dir)"
SIGNING_KIND="$(manifest_value signing.kind)"
NOTARIZATION_STATUS="$(manifest_value notarization.status)"
TOOLCHAIN_RUNNER="$(manifest_value toolchain.runner)"
TOOLCHAIN_XCODE="$(manifest_value toolchain.xcode)"
TOOLCHAIN_SWIFT="$(manifest_value toolchain.swift)"
TOOLCHAIN_SDK="$(manifest_value toolchain.sdk)"
MINIMUM_SYSTEM_VERSION="$(
    ruby -rjson -e '
        value = JSON.parse(File.read(ARGV[0]))
        print value.fetch("minimum_system_version", "13.0")
    ' "$MANIFEST"
)"

[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || die "manifest source_sha is not a 40-character SHA."
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "manifest version is invalid."
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "manifest build is invalid."
[[ "$TAG" == "v${VERSION}" ]] || die "manifest tag '$TAG' does not match version '$VERSION'."
[[ "$DMG_FILENAME" == "$(basename "$DMG_FILENAME")" ]] ||
    die "manifest DMG filename must not contain a path."
[[ "$DMG_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "manifest DMG SHA-256 is invalid."
[[ "$DMG_LENGTH" =~ ^[0-9]+$ ]] || die "manifest DMG length is invalid."
[[ "$ED_SIGNATURE" != "diagnostic-not-for-publication" ]] ||
    die "diagnostic packages cannot be published."
[[ "$RELEASE_REPO" =~ ^[^/]+/[^/]+$ ]] || die "manifest release repository is invalid."
[[ -n "$RELEASE_BRANCH" ]] || die "manifest release branch is missing."
[[ "$APPCAST_FILE" == "$(basename "$APPCAST_FILE")" ]] ||
    die "manifest appcast filename must not contain a path."
[[ "$RELEASE_BODY_FILE" == "$(basename "$RELEASE_BODY_FILE")" ]] ||
    die "manifest release body filename must not contain a path."
[[ "$RELEASE_NOTES_DIR" == "release-notes/$VERSION" ]] ||
    die "manifest release notes path '$RELEASE_NOTES_DIR' does not match version '$VERSION'."
[[ "$TOOLCHAIN_RUNNER" == "xcode-27" ]] ||
    die "manifest release runner must be xcode-27, not '$TOOLCHAIN_RUNNER'."
case "$TOOLCHAIN_XCODE" in
    "Xcode 27"|"Xcode 27."*) ;;
    *) die "manifest Xcode must be 27.x, not '$TOOLCHAIN_XCODE'." ;;
esac
[[ -n "$TOOLCHAIN_SWIFT" ]] || die "manifest Swift toolchain is missing."
[[ "$TOOLCHAIN_SDK" =~ ^[0-9]+(\.[0-9]+)*$ ]] ||
    die "manifest SDK version '$TOOLCHAIN_SDK' is invalid."
[[ "${TOOLCHAIN_SDK%%.*}" -ge 26 ]] ||
    die "manifest SDK must be 26 or newer, not '$TOOLCHAIN_SDK'."
case "$SIGNING_KIND:$NOTARIZATION_STATUS" in
    developer_id:accepted_and_stapled)
        ;;
    ad_hoc:not_requested)
        echo "Warning: publishing an Ad-hoc package without notarization." >&2
        ;;
    *)
        die "unsupported signing/notarization state '$SIGNING_KIND:$NOTARIZATION_STATUS'."
        ;;
esac
[[ "$MINIMUM_SYSTEM_VERSION" == "13.0" ]] ||
    die "manifest minimum system version must remain 13.0."

[[ "$MANIFEST" == "$PACKAGE_DIR/release-manifest.json" ]] ||
    die "manifest must be the release-manifest.json inside PACKAGE_DIR."
[[ -f "$PACKAGE_DIR/$DMG_FILENAME" ]] || die "packaged DMG is missing: $DMG_FILENAME"
[[ -f "$PACKAGE_DIR/$DMG_FILENAME.sha256" ]] ||
    die "packaged DMG checksum is missing: $DMG_FILENAME.sha256"
[[ -f "$PACKAGE_DIR/release-manifest.json" ]] ||
    die "packaged manifest is missing: release-manifest.json"
[[ -f "$PACKAGE_DIR/$RELEASE_BODY_FILE" ]] || die "release body is missing: $RELEASE_BODY_FILE"
[[ -d "$PACKAGE_DIR/$RELEASE_NOTES_DIR" ]] || die "release notes are missing: $RELEASE_NOTES_DIR"

PACKAGE_SHA256="$(
    cd "$PACKAGE_DIR"
    shasum -a 256 "$DMG_FILENAME" | awk '{print $1}'
)"
[[ "$PACKAGE_SHA256" == "$DMG_SHA256" ]] ||
    die "DMG SHA-256 mismatch: manifest $DMG_SHA256, artifact $PACKAGE_SHA256."

PACKAGE_LENGTH="$(stat -f '%z' "$PACKAGE_DIR/$DMG_FILENAME")"
[[ "$PACKAGE_LENGTH" == "$DMG_LENGTH" ]] ||
    die "DMG length mismatch: manifest $DMG_LENGTH, artifact $PACKAGE_LENGTH."

EXPECTED_CHECKSUM_LINE="$DMG_SHA256  $DMG_FILENAME"
ACTUAL_CHECKSUM_LINE="$(<"$PACKAGE_DIR/$DMG_FILENAME.sha256")"
[[ "$ACTUAL_CHECKSUM_LINE" == "$EXPECTED_CHECKSUM_LINE" ]] ||
    die "DMG checksum file does not match the manifest and artifact."

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    [[ "${GITHUB_SHA:-}" == "$SOURCE_SHA" ]] ||
        die "workflow SHA ${GITHUB_SHA:-<unset>} differs from manifest source_sha $SOURCE_SHA."
fi

if [[ -n "${GH_TOKEN:-}" ]]; then
    :
elif ! gh auth status >/dev/null 2>&1; then
    die "gh is not authenticated. Set GH_TOKEN or run 'gh auth login'."
fi

api_get_or_empty() {
    local endpoint="$1"
    shift
    local body output status
    set +e
    output="$(gh api --include "$endpoint" "$@" 2>&1)"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        if [[ "$output" == HTTP/* ]]; then
            body="$(
                printf '%s' "$output" |
                    ruby -e '
                        source = STDIN.read
                        match = source.match(/\r?\n\r?\n/)
                        print(match ? source[match.end(0)..] : source)
                    '
            )"
        else
            body="$output"
        fi
        if [[ "$body" != "null" ]]; then
            printf '%s' "$body"
        fi
    elif [[ "$output" == *"HTTP/2.0 404 Not Found"* || "$output" == *"HTTP/1.1 404 Not Found"* ]]; then
        # A missing object is expected while a release is being created. Every
        # later write re-reads the object before mutating it.
        :
    else
        die "GitHub API read failed for $endpoint (exit $status): $output"
    fi
}

TAG_JSON="$(api_get_or_empty "repos/$RELEASE_REPO/git/ref/tags/$TAG")"
TAG_OBJECT_SHA=""
TAG_OBJECT_TYPE=""
if [[ -n "$TAG_JSON" ]]; then
    TAG_OBJECT_SHA="$(
        printf '%s' "$TAG_JSON" |
            ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("object").fetch("sha")'
    )"
    TAG_OBJECT_TYPE="$(
        printf '%s' "$TAG_JSON" |
            ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("object").fetch("type")'
    )"
fi

if [[ -n "$TAG_OBJECT_SHA" ]]; then
    case "$TAG_OBJECT_TYPE" in
        commit)
            [[ "$TAG_OBJECT_SHA" == "$SOURCE_SHA" ]] ||
                die "Tag $TAG points at $TAG_OBJECT_SHA, not the verified SHA $SOURCE_SHA."
            ;;
        tag)
            TAG_COMMIT_SHA="$(
            gh api "repos/$RELEASE_REPO/git/tags/$TAG_OBJECT_SHA" --jq '.object.sha'
            )"
            TAG_COMMIT_TYPE="$(
            gh api "repos/$RELEASE_REPO/git/tags/$TAG_OBJECT_SHA" --jq '.object.type'
            )"
            [[ "$TAG_COMMIT_TYPE" == "commit" ]] ||
                die "Tag $TAG peels to a $TAG_COMMIT_TYPE, not a commit."
            [[ "$TAG_COMMIT_SHA" == "$SOURCE_SHA" ]] ||
                die "Tag $TAG peels to $TAG_COMMIT_SHA, not the verified SHA $SOURCE_SHA."
            ;;
        *)
            die "Tag $TAG points at unsupported object type '$TAG_OBJECT_TYPE'."
            ;;
    esac
fi

RELEASE_JSON="$(api_get_or_empty "repos/$RELEASE_REPO/releases/tags/$TAG")"
RELEASE_EXISTS=false
RELEASE_DRAFT=""
if [[ -n "$RELEASE_JSON" ]]; then
    RELEASE_EXISTS=true
    RELEASE_DRAFT="$(
        printf '%s' "$RELEASE_JSON" |
            ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("draft")'
    )"
    [[ "$RELEASE_DRAFT" == "true" || "$RELEASE_DRAFT" == "false" ]] ||
        die "Release $TAG has an invalid draft state '$RELEASE_DRAFT'."
    [[ -n "$TAG_OBJECT_SHA" ]] ||
        die "Release $TAG exists but its Tag is missing."
fi

APPCAST_API_PATH="repos/$RELEASE_REPO/contents/$APPCAST_FILE"
APPCAST_BLOB_SHA="$(api_get_or_empty "$APPCAST_API_PATH?ref=$RELEASE_BRANCH" --jq .sha)"
[[ -n "$APPCAST_BLOB_SHA" ]] ||
    die "Could not read the appcast blob from $RELEASE_REPO/$RELEASE_BRANCH/$APPCAST_FILE."

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioPublish.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
APPCAST_PATH="$TEMP_ROOT/appcast.xml"

gh api "$APPCAST_API_PATH?ref=$RELEASE_BRANCH" \
    -H "Accept: application/vnd.github.raw" > "$APPCAST_PATH"
xmllint --noout "$APPCAST_PATH" || die "Remote appcast is not valid XML."

DMG_URL="https://github.com/$RELEASE_REPO/releases/download/$TAG/$DMG_FILENAME"

file_sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

SHA_ASSET_FILENAME="$DMG_FILENAME.sha256"
MANIFEST_ASSET_FILENAME="release-manifest.json"
SHA_ASSET_SHA256="$(file_sha256 "$PACKAGE_DIR/$SHA_ASSET_FILENAME")"
SHA_ASSET_LENGTH="$(stat -f '%z' "$PACKAGE_DIR/$SHA_ASSET_FILENAME")"
MANIFEST_ASSET_SHA256="$(file_sha256 "$PACKAGE_DIR/$MANIFEST_ASSET_FILENAME")"
MANIFEST_ASSET_LENGTH="$(stat -f '%z' "$PACKAGE_DIR/$MANIFEST_ASSET_FILENAME")"

refresh_release_json() {
    RELEASE_JSON="$(gh api "repos/$RELEASE_REPO/releases/tags/$TAG")"
    [[ -n "$RELEASE_JSON" ]] || die "GitHub returned an empty Release response for $TAG."
}

verify_release_assets() {
    local release_path="$TEMP_ROOT/release.json"
    printf '%s' "$RELEASE_JSON" > "$release_path"
    ruby -rjson -e '
        release_path, dmg_name, dmg_digest, dmg_length, checksum_name,
          checksum_digest, checksum_length, manifest_name, manifest_digest,
          manifest_length = ARGV
        release = JSON.parse(File.read(release_path))
        assets = release.fetch("assets")
        expected = {
          dmg_name => ["sha256:#{dmg_digest}", Integer(dmg_length)],
          checksum_name => ["sha256:#{checksum_digest}", Integer(checksum_length)],
          manifest_name => ["sha256:#{manifest_digest}", Integer(manifest_length)]
        }
        expected.each do |name, (digest, length)|
          matches = assets.select { |asset| asset["name"] == name }
          abort("Release has #{matches.length} assets named #{name}, expected one.") unless matches.length == 1
          asset = matches.first
          abort("Release asset #{name} digest is #{asset["digest"].inspect}, expected #{digest.inspect}.") unless asset["digest"] == digest
          abort("Release asset #{name} size is #{asset["size"].inspect}, expected #{length}.") unless asset["size"] == length
        end
    ' "$release_path" "$DMG_FILENAME" "$DMG_SHA256" "$DMG_LENGTH" \
        "$SHA_ASSET_FILENAME" "$SHA_ASSET_SHA256" "$SHA_ASSET_LENGTH" \
        "$MANIFEST_ASSET_FILENAME" "$MANIFEST_ASSET_SHA256" "$MANIFEST_ASSET_LENGTH"
}

verify_existing_draft_assets_are_same_artifact() {
    local release_path="$TEMP_ROOT/existing-draft-release.json"
    printf '%s' "$RELEASE_JSON" > "$release_path"
    ruby -rjson -e '
        release_path, dmg_name, dmg_digest, dmg_length, checksum_name,
          checksum_digest, checksum_length, manifest_name, manifest_digest,
          manifest_length = ARGV
        release = JSON.parse(File.read(release_path))
        assets = release.fetch("assets")
        expected = {
          dmg_name => ["sha256:#{dmg_digest}", Integer(dmg_length)],
          checksum_name => ["sha256:#{checksum_digest}", Integer(checksum_length)],
          manifest_name => ["sha256:#{manifest_digest}", Integer(manifest_length)]
        }
        expected.each do |name, (digest, length)|
          matches = assets.select { |asset| asset["name"] == name }
          abort("Draft Release has #{matches.length} assets named #{name}, expected at most one.") if matches.length > 1
          next if matches.empty?
          asset = matches.first
          unless asset["digest"] == digest && asset["size"] == length
            abort(
              "Existing Draft asset #{name} is #{asset["digest"].inspect}/#{asset["size"].inspect}, " \
              "not the verified package #{digest.inspect}/#{length.inspect}."
            )
          end
        end
    ' "$release_path" "$DMG_FILENAME" "$DMG_SHA256" "$DMG_LENGTH" \
        "$SHA_ASSET_FILENAME" "$SHA_ASSET_SHA256" "$SHA_ASSET_LENGTH" \
        "$MANIFEST_ASSET_FILENAME" "$MANIFEST_ASSET_SHA256" "$MANIFEST_ASSET_LENGTH"
}

ensure_tag() {
    [[ -n "$TAG_OBJECT_SHA" ]] && return 0
    gh api --method POST "repos/$RELEASE_REPO/git/refs" \
        -f "ref=refs/tags/$TAG" \
        -f "sha=$SOURCE_SHA" >/dev/null
    local created_sha
    created_sha="$(
        gh api "repos/$RELEASE_REPO/git/ref/tags/$TAG" --jq .object.sha
    )"
    [[ "$created_sha" == "$SOURCE_SHA" ]] ||
        die "Created Tag $TAG resolves to $created_sha instead of $SOURCE_SHA."
    TAG_OBJECT_SHA="$created_sha"
    TAG_OBJECT_TYPE="commit"
}

ensure_draft_release() {
    ensure_tag
    if [[ "$RELEASE_EXISTS" == "true" && "$RELEASE_DRAFT" != "true" ]]; then
        die "Release $TAG is already public; refusing to replace its assets."
    fi
    if [[ "$RELEASE_EXISTS" == "true" ]]; then
        verify_existing_draft_assets_are_same_artifact
    fi
    if [[ "$RELEASE_EXISTS" == "false" ]]; then
        gh release create "$TAG" \
            --repo "$RELEASE_REPO" \
            --draft \
            --verify-tag \
            --title "$(manifest_value app_name) v$VERSION" \
            --notes-file "$PACKAGE_DIR/$RELEASE_BODY_FILE"
        RELEASE_EXISTS=true
        RELEASE_DRAFT=true
    fi
    gh release upload "$TAG" \
        "$PACKAGE_DIR/$DMG_FILENAME" \
        "$PACKAGE_DIR/$SHA_ASSET_FILENAME" \
        "$PACKAGE_DIR/$MANIFEST_ASSET_FILENAME" \
        --repo "$RELEASE_REPO" \
        --clobber
    refresh_release_json
    verify_release_assets
}

APPCAST_ITEM="$TEMP_ROOT/item.xml"
ruby -e '
    path, build = ARGV
    source = File.read(path)
    block = source.scan(%r{[ \t]*<item>.*?</item>}m)
                  .find { |candidate| candidate.include?("<sparkle:version>#{build}</sparkle:version>") }
    print block if block
' "$APPCAST_PATH" "$BUILD" > "$APPCAST_ITEM"

verify_appcast_item() {
    local appcast_path="$1"
    ruby -rrexml/document -e '
        path, build, version, url, signature, length = ARGV
        doc = REXML::Document.new(File.read(path))
        item = doc.elements.to_a("rss/channel/item").find do |candidate|
          candidate.elements["sparkle:version"]&.text == build
        end
        abort("Published appcast item for build #{build} is missing.") unless item
        checks = {
          "shortVersionString" => [item.elements["sparkle:shortVersionString"]&.text, version],
          "minimumSystemVersion" => [item.elements["sparkle:minimumSystemVersion"]&.text, "13.0"],
          "enclosure URL" => [item.elements["enclosure"]&.attributes&.[]("url"), url],
          "EdDSA signature" => [
            item.elements["enclosure"]&.attributes&.[]("sparkle:edSignature"),
            signature
          ],
          "length" => [item.elements["enclosure"]&.attributes&.[]("length"), length]
        }
        checks.each do |name, (actual, expected)|
          abort("Published appcast #{name} is #{actual.inspect}, expected #{expected.inspect}.") unless actual == expected
        end
        abort("Published appcast item has no en title.") unless item.elements["title[@xml:lang=\"en\"]"]
    ' "$appcast_path" "$BUILD" "$VERSION" "$DMG_URL" "$ED_SIGNATURE" "$DMG_LENGTH"
}

MAX_APPCAST_BUILD="$(
    ruby -e '
        source = File.read(ARGV[0])
        builds = source.scan(%r{<sparkle:version>\s*(\d+)\s*</sparkle:version>}).flatten
        print(builds.map(&:to_i).max || 0)
    ' "$APPCAST_PATH"
)"
if [[ ! -s "$APPCAST_ITEM" && "$BUILD" -le "$MAX_APPCAST_BUILD" ]]; then
    die "Build $BUILD must exceed the current published appcast build $MAX_APPCAST_BUILD."
fi
if [[ -s "$APPCAST_ITEM" ]]; then
    verify_appcast_item "$APPCAST_PATH"
fi

if [[ "$RELEASE_EXISTS" == "true" && "$RELEASE_DRAFT" == "false" ]]; then
    # A retry may only verify the already-public release. It must never edit
    # public metadata or rewrite the feed.
    verify_release_assets
else
    ensure_draft_release
    if [[ ! -s "$APPCAST_ITEM" ]]; then
        ruby "$ROOT/scripts/update-appcast.rb" \
            --version "$VERSION" \
            --build "$BUILD" \
            --minimum-system-version "$MINIMUM_SYSTEM_VERSION" \
            --dmg-url "$DMG_URL" \
            --ed-signature "$ED_SIGNATURE" \
            --length "$DMG_LENGTH" \
            --notes-dir "$PACKAGE_DIR/$RELEASE_NOTES_DIR" \
            --appcast "$APPCAST_PATH"
        xmllint --noout "$APPCAST_PATH"

        APPCAST_COMMIT="$(
            ruby -rjson -rbase64 -e '
                puts JSON.generate(
                    message: ARGV[0],
                    content: Base64.strict_encode64(File.binread(ARGV[1])),
                    sha: ARGV[2],
                    branch: ARGV[3]
                )
            ' "Release $TAG appcast" "$APPCAST_PATH" "$APPCAST_BLOB_SHA" "$RELEASE_BRANCH" \
                | gh api --method PUT "$APPCAST_API_PATH" \
                    -H "Accept: application/vnd.github+json" \
                    --input - \
                    --jq '.commit.sha'
        )"
        [[ -n "$APPCAST_COMMIT" ]] || die "Appcast update returned no commit SHA."

        REMOTE_APPCAST="$TEMP_ROOT/published-appcast.xml"
        gh api "$APPCAST_API_PATH?ref=$APPCAST_COMMIT" \
            -H "Accept: application/vnd.github.raw" > "$REMOTE_APPCAST"
        ruby -rrexml/document -e '
            path, build = ARGV
            doc = REXML::Document.new(File.read(path))
            item = doc.elements.to_a("rss/channel/item").find do |candidate|
              candidate.elements["sparkle:version"]&.text == build
            end
            abort("Published appcast commit does not contain build #{build}.") unless item
        ' "$REMOTE_APPCAST" "$BUILD"
    fi
fi

if [[ "$RELEASE_EXISTS" == "true" && "$RELEASE_DRAFT" == "true" ]]; then
    gh release edit "$TAG" \
        --repo "$RELEASE_REPO" \
        --draft=false
fi

refresh_release_json
RELEASE_DRAFT="$(
    printf '%s' "$RELEASE_JSON" |
        ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("draft")'
)"
[[ "$RELEASE_DRAFT" == "false" ]] ||
    die "Release $TAG is still a draft after publication."
verify_release_assets

PUBLIC_VERIFY_ATTEMPTS="${PUBLIC_VERIFY_ATTEMPTS:-6}"
PUBLIC_VERIFY_DELAY_SECONDS="${PUBLIC_VERIFY_DELAY_SECONDS:-5}"
[[ "$PUBLIC_VERIFY_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] ||
    die "PUBLIC_VERIFY_ATTEMPTS must be a positive integer."
[[ "$PUBLIC_VERIFY_DELAY_SECONDS" =~ ^[0-9]+$ ]] ||
    die "PUBLIC_VERIFY_DELAY_SECONDS must be a non-negative integer."

REMOTE_FEED="$TEMP_ROOT/public-appcast.xml"
PUBLIC_DMG_PATH="$TEMP_ROOT/public.dmg"
PUBLIC_FEED_URL="https://raw.githubusercontent.com/$RELEASE_REPO/$RELEASE_BRANCH/$APPCAST_FILE"
PUBLIC_DMG_SHA256=""
PUBLIC_ERROR="$TEMP_ROOT/public-error.log"
PUBLIC_VERIFIED=false

for ((attempt = 1; attempt <= PUBLIC_VERIFY_ATTEMPTS; attempt++)); do
    : > "$PUBLIC_ERROR"
    if curl -fsSL --connect-timeout 15 --max-time 300 "$DMG_URL" > "$PUBLIC_DMG_PATH" 2>"$PUBLIC_ERROR"; then
        PUBLIC_DMG_SHA256="$(file_sha256 "$PUBLIC_DMG_PATH")"
        if [[ "$PUBLIC_DMG_SHA256" == "$DMG_SHA256" ]] &&
            curl -fsSL --connect-timeout 15 --max-time 300 "$PUBLIC_FEED_URL" > "$REMOTE_FEED" 2>>"$PUBLIC_ERROR" &&
            verify_appcast_item "$REMOTE_FEED" 2>>"$PUBLIC_ERROR"; then
            PUBLIC_VERIFIED=true
            break
        fi
    fi
    if ((attempt < PUBLIC_VERIFY_ATTEMPTS)); then
        printf 'Public artifact verification attempt %d/%d did not match; retrying in %ss.\n' \
            "$attempt" "$PUBLIC_VERIFY_ATTEMPTS" "$PUBLIC_VERIFY_DELAY_SECONDS" >&2
        sleep "$PUBLIC_VERIFY_DELAY_SECONDS"
    fi
done

[[ "$PUBLIC_VERIFIED" == "true" ]] || {
    cat "$PUBLIC_ERROR" >&2
    die "Public DMG or appcast did not match the verified package after $PUBLIC_VERIFY_ATTEMPTS attempts."
}

echo "Published $TAG from source $SOURCE_SHA with package SHA-256 $DMG_SHA256."
echo "Signing: $SIGNING_KIND; notarization: $NOTARIZATION_STATUS."
