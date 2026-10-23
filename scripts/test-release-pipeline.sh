#!/usr/bin/env bash
# Exercises publish orchestration with fake GitHub, curl, and package data. It
# never contacts GitHub or Apple and never creates a real Tag or Release.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioReleasePipeline.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "release pipeline regression failed: $*" >&2
    exit 1
}

expect_failure() {
    local label="$1"
    shift
    if "$@" >"$WORK/output.log" 2>&1; then
        fail "$label was accepted"
    fi
}

assert_contains() {
    local path="$1"
    local text="$2"
    grep -Fq -- "$text" "$path" || fail "$path must contain: $text"
}

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

make_manifest() {
    local path="$1"
    local dmg_path="$2"
    local sha="$3"
    local length="$4"
    local signature="$5"
    local signing="${6:-developer_id}"
    local notarization="${7:-accepted_and_stapled}"
    ruby -rjson -e '
        path, dmg, sha, length, signature, signing, notarization = ARGV
        File.write(
          path,
          JSON.pretty_generate(
            schema_version: 1,
            source_sha: "a" * 40,
            version: "1.0.0",
            build: "99",
            tag: "v1.0.0",
            app_name: "Status Trio",
            minimum_system_version: "13.0",
            toolchain: {
              xcode: "Xcode 27.0 Build version 27A100",
              swift: "Apple Swift version 6.4",
              sdk: "27.0",
              runner: "xcode-27"
            },
            dmg: {
              filename: File.basename(dmg),
              sha256: sha,
              length: length,
              ed_signature: signature
            },
            signing: { kind: signing },
            notarization: { status: notarization },
            release: {
              repo: "example/status-trio",
              branch: "main",
              appcast_file: "appcast.xml",
              body_file: "release-body.md",
              notes_dir: "release-notes/1.0.0"
            }
          ) + "\n"
        )
    ' "$path" "$dmg_path" "$sha" "$length" "$signature" "$signing" "$notarization"
}

[[ -f "$ROOT/scripts/package-release.sh" ]] || fail "missing package-release.sh"
[[ -f "$ROOT/scripts/publish-release.sh" ]] || fail "missing publish-release.sh"

PACKAGE="$WORK/package"
mkdir -p "$PACKAGE/release-notes/1.0.0"
printf 'fixture package\n' > "$PACKAGE/StatusTrio-1.0.0.dmg"
DMG_SHA="$(sha256 "$PACKAGE/StatusTrio-1.0.0.dmg")"
DMG_LENGTH="$(stat -f '%z' "$PACKAGE/StatusTrio-1.0.0.dmg")"
printf '%s  StatusTrio-1.0.0.dmg\n' "$DMG_SHA" > "$PACKAGE/StatusTrio-1.0.0.dmg.sha256"
printf '# Version %%VERSION%% (Build %%BUILD%%)\n- English.\n' > "$PACKAGE/release-notes/1.0.0/en.md"
printf '# 版本 %%VERSION%%（构建 %%BUILD%%）\n- 中文。\n' > "$PACKAGE/release-notes/1.0.0/zh-Hans.md"
printf '# Version 1.0.0 （English + 中文， 中文在下方）\n\n## English\n\n- English.\n\n## 中文\n\n- 中文。\n' > "$PACKAGE/release-body.md"
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"

mkdir -p "$WORK/bin" "$WORK/github"
cat > "$WORK/github/appcast" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Status Trio</title>
  </channel>
</rss>
XML

cat > "$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

state="${FAKE_GITHUB_ROOT:?}"
package="${FAKE_PACKAGE_DIR:?}"
mkdir -p "$state"

record_write() {
    printf '%s\n' "$*" >> "$state/writes"
}

record_read() {
    printf '%s\n' "$*" >> "$state/reads"
}

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

asset_json() {
    local name="$1"
    local path="$2"
    local digest
    digest="$(sha256 "$path")"
    if [[ -f "$state/digest-override" && "$name" == "StatusTrio-1.0.0.dmg" ]]; then
        digest="$(<"$state/digest-override")"
    fi
    printf '{"name":"%s","size":%s,"digest":"sha256:%s"}' \
        "$name" "$(stat -f '%z' "$path")" "$digest"
}

release_json() {
    local draft="$1"
    local id="123"
    local dmg="$package/StatusTrio-1.0.0.dmg"
    local checksum="$package/StatusTrio-1.0.0.dmg.sha256"
    local manifest="$package/release-manifest.json"
    local assets
    if [[ -f "$state/release-id" ]]; then
        id="$(<"$state/release-id")"
    fi
    if [[ -f "$state/assets" ]]; then
        assets="[$(asset_json StatusTrio-1.0.0.dmg "$dmg"),$(asset_json StatusTrio-1.0.0.dmg.sha256 "$checksum"),$(asset_json release-manifest.json "$manifest")]"
    else
        assets="[]"
    fi
    printf '{"draft":%s,"id":%s,"tag_name":"v1.0.0","assets":%s}\n' \
        "$draft" "$id" "$assets"
}

api_response() {
    local body="$1"
    printf 'HTTP/2.0 200 OK\r\ncontent-type: application/json\r\n\r\n%s' "$body"
}

if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
fi

if [[ "$1" == "api" ]]; then
    shift
    method="GET"
    include=false
    input=false
    paginate=false
    slurp=false
    endpoint=""
    jq_filter=""
    accept=""
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --method) method="$2"; shift 2 ;;
            --include) include=true; shift ;;
            --input) input=true; shift ;;
            --paginate) paginate=true; shift ;;
            --slurp) slurp=true; shift ;;
            --jq) jq_filter="$2"; shift 2 ;;
            -H) accept="$2"; shift 2 ;;
            -f) shift 2 ;;
            *) [[ -n "$endpoint" ]] || endpoint="$1"; shift ;;
        esac
    done
    record_read "$method $endpoint paginate=$paginate slurp=$slurp"

    if [[ -n "${FAKE_API_FAIL_ENDPOINT:-}" && "$endpoint" == "${FAKE_API_FAIL_ENDPOINT}" ]]; then
        if [[ "$include" == "true" ]]; then
            printf 'HTTP/2.0 500 Internal Server Error\r\ncontent-type: application/json\r\n\r\n{"message":"fixture failure"}' >&2
        else
            printf '{"message":"fixture failure"}\n' >&2
        fi
        exit 95
    fi

    body=""
    status="200"
    case "$method:$endpoint" in
        GET:repos/example/status-trio/git/ref/tags/v1.0.0)
            if [[ -f "$state/tag" ]]; then
                body="$(cat "$state/tag")"
                if [[ "$jq_filter" == ".object.sha" ]]; then
                    body="$(printf '%s' "$body" | ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("object").fetch("sha")')"
                elif [[ "$jq_filter" == ".object.type" ]]; then
                    body="$(printf '%s' "$body" | ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("object").fetch("type")')"
                fi
            else
                status="404"
                body='{"message":"Not Found"}'
            fi
            ;;
        POST:repos/example/status-trio/git/refs)
            record_write "api POST git/refs"
            tag_sha="${FAKE_TAG_SHA:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
            printf '{"object":{"sha":"%s","type":"commit"}}\n' "$tag_sha" > "$state/tag"
            body="{\"ref\":\"refs/tags/v1.0.0\",\"object\":{\"sha\":\"$tag_sha\",\"type\":\"commit\"}}"
            ;;
        GET:repos/example/status-trio/contents/appcast.xml?ref=*)
            if [[ "$accept" == *"raw"* ]]; then
                body="$(cat "$state/appcast")"
            elif [[ "$jq_filter" == ".sha" ]]; then
                body="$(shasum -a 1 "$state/appcast" | awk '{print $1}')"
            else
                body="$(cat "$state/appcast")"
            fi
            ;;
        PUT:repos/example/status-trio/contents/appcast.xml)
            record_write "api PUT appcast"
            if [[ "${FAKE_APPCAST_PUT_FAILS:-false}" == "true" && ! -f "$state/appcast-failed-once" ]]; then
                touch "$state/appcast-failed-once"
                exit 93
            fi
            cat > "$state/appcast-input.json"
            ruby -rjson -rbase64 -e '
                payload = JSON.parse(File.read(ARGV[0]))
                File.binwrite(ARGV[1], Base64.strict_decode64(payload.fetch("content")))
                File.write(ARGV[2], "b" * 40 + "\n")
            ' "$state/appcast-input.json" "$state/appcast" "$state/appcast-commit"
            body="$(cat "$state/appcast-commit")"
            ;;
        GET:repos/example/status-trio/releases/tags/v1.0.0)
            if [[ ! -f "$state/release" ]] ||
                { [[ -f "$state/draft-by-tag-404" ]] && [[ "$(cat "$state/release-draft")" == "true" ]]; }; then
                status="404"
                body='{"message":"Not Found"}'
            else
                draft="$(cat "$state/release-draft")"
                body="$(release_json "$draft")"
                if [[ "$jq_filter" == ".draft" ]]; then
                    body="$draft"
                elif [[ "$jq_filter" == *".assets[]"* ]]; then
                    if [[ -f "$state/assets" ]]; then
                        body="sha256:$(sha256 "$package/StatusTrio-1.0.0.dmg")"
                    else
                        body=""
                    fi
                fi
            fi
            ;;
        GET:repos/example/status-trio/releases?per_page=100)
            if [[ "$paginate" != "true" || "$slurp" != "true" ]]; then
                printf 'release listing must use --paginate --slurp\n' >&2
                exit 89
            fi
            if [[ -f "$state/releases-pages.json" ]]; then
                body="$(<"$state/releases-pages.json")"
            elif [[ -f "$state/release" ]]; then
                body="[[$(release_json "$(cat "$state/release-draft")")]]"
            else
                body='[[]]'
            fi
            ;;
        GET:repos/example/status-trio/releases/[0-9]*)
            if [[ ! -f "$state/release" ]]; then
                status="404"
                body='{"message":"Not Found"}'
            else
                body="$(release_json "$(cat "$state/release-draft")")"
            fi
            ;;
        *)
            printf 'unexpected gh api: %s %s\n' "$method" "$endpoint" >&2
            exit 90
            ;;
    esac

    if [[ "$status" == "404" ]]; then
        if [[ "$include" == "true" ]]; then
            printf 'HTTP/2.0 404 Not Found\r\ncontent-type: application/json\r\n\r\n%s' "$body" >&2
        else
            printf '%s\n' "$body" >&2
        fi
        exit 1
    fi
    if [[ "$include" == "true" ]]; then
        api_response "$body"
    else
        printf '%s\n' "$body"
    fi
    exit 0
fi

if [[ "$1" == "release" ]]; then
    shift
    case "$1" in
        create)
            record_write "release create $2"
            printf 'draft\n' > "$state/release"
            printf 'true\n' > "$state/release-draft"
            printf '123\n' > "$state/release-id"
            ;;
        upload)
            record_write "release upload $2"
            touch "$state/assets"
            if [[ "${FAKE_UPLOAD_FAIL_ONCE:-false}" == "true" && ! -f "$state/upload-failed" ]]; then
                touch "$state/upload-failed"
                exit 96
            fi
            ;;
        edit)
            record_write "release edit $2"
            printf 'published\n' > "$state/release"
            printf 'false\n' > "$state/release-draft"
            ;;
        *)
            printf 'unexpected gh release command: %s\n' "$1" >&2
            exit 91
            ;;
    esac
    exit 0
fi

printf 'unexpected gh command: %s\n' "$*" >&2
exit 92
SH
chmod +x "$WORK/bin/gh"

cat > "$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url="${!#}"
case "$url" in
    https://github.com/example/status-trio/releases/download/v1.0.0/StatusTrio-1.0.0.dmg)
        if [[ "${FAKE_PUBLIC_DMG_MODE:-valid}" == "invalid" ]]; then
            printf 'corrupt public DMG\n'
        else
            cat "${FAKE_PACKAGE_DIR:?}/StatusTrio-1.0.0.dmg"
        fi
        ;;
    https://raw.githubusercontent.com/example/status-trio/main/appcast.xml)
        if [[ "${FAKE_PUBLIC_APPCAST_MODE:-valid}" == "invalid" ]]; then
            printf '<rss version="2.0"><channel/></rss>\n'
        else
            cat "${FAKE_GITHUB_ROOT:?}/appcast"
        fi
        ;;
    *)
        printf 'unexpected curl URL: %s\n' "$url" >&2
        exit 94
        ;;
esac
SH
chmod +x "$WORK/bin/curl"

reset_state() {
    rm -rf "$WORK/github"
    mkdir -p "$WORK/github"
    cat > "$WORK/github/appcast" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Status Trio</title>
  </channel>
</rss>
XML
    : > "$WORK/github/writes"
    : > "$WORK/github/reads"
}

run_publish_with_env() {
    env -u GITHUB_ACTIONS \
        -u GITHUB_SHA \
        -u CANDIDATE_SHA \
        "$@" \
        MANIFEST_PATH="$PACKAGE/release-manifest.json" \
        PACKAGE_DIR="$PACKAGE" \
        FAKE_PACKAGE_DIR="$PACKAGE" \
        FAKE_GITHUB_ROOT="$WORK/github" \
        PUBLIC_VERIFY_ATTEMPTS="${PUBLIC_VERIFY_ATTEMPTS:-2}" \
        PUBLIC_VERIFY_DELAY_SECONDS=0 \
        PATH="$WORK/bin:$PATH" \
        bash "$ROOT/scripts/publish-release.sh"
}

run_publish() {
    run_publish_with_env
}

run_publish_ci() {
    local candidate_sha="$1"
    local workflow_sha="$2"
    run_publish_with_env \
        GITHUB_ACTIONS=true \
        GITHUB_SHA="$workflow_sha" \
        CANDIDATE_SHA="$candidate_sha"
}

run_publish_ci_without_candidate() {
    run_publish_with_env \
        GITHUB_ACTIONS=true \
        GITHUB_SHA="$1"
}

MANIFEST_SHA="$(printf 'a%.0s' {1..40})"
IGNORED_GITHUB_SHA="$(printf 'b%.0s' {1..40})"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
if ! run_publish_ci "$MANIFEST_SHA" "$IGNORED_GITHUB_SHA" >"$WORK/ci-normal.log" 2>&1; then
    cat "$WORK/ci-normal.log" >&2
    fail "valid CI candidate with a different GITHUB_SHA did not publish"
fi
[[ "$(cat "$WORK/github/release-draft")" == "false" ]] ||
    fail "valid CI candidate with a different GITHUB_SHA did not publish"

APPCAST_BEFORE="$(sha256 "$WORK/github/appcast")"
WRITES_BEFORE="$(<"$WORK/github/writes")"
if ! run_publish_ci "$MANIFEST_SHA" "$IGNORED_GITHUB_SHA" >"$WORK/ci-public-retry.log" 2>&1; then
    cat "$WORK/ci-public-retry.log" >&2
    fail "valid CI public retry failed"
fi
[[ "$APPCAST_BEFORE" == "$(sha256 "$WORK/github/appcast")" ]] ||
    fail "valid CI public retry rewrote the appcast"
[[ "$WRITES_BEFORE" == "$(<"$WORK/github/writes")" ]] ||
    fail "valid CI public retry mutated release metadata"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
expect_failure "CI candidate SHA mismatch" \
    run_publish_ci "$IGNORED_GITHUB_SHA" "$MANIFEST_SHA"
assert_contains "$WORK/output.log" \
    "candidate SHA $IGNORED_GITHUB_SHA differs from manifest source_sha $MANIFEST_SHA"
[[ ! -s "$WORK/github/writes" ]] || fail "CI candidate SHA mismatch wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
expect_failure "missing CI candidate SHA" run_publish_ci_without_candidate "$MANIFEST_SHA"
assert_contains "$WORK/output.log" \
    "CANDIDATE_SHA must be a lowercase 40-character commit SHA"
[[ ! -s "$WORK/github/writes" ]] || fail "missing CI candidate SHA wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
expect_failure "invalid CI candidate SHA" \
    run_publish_ci "$(printf 'A%.0s' {1..40})" "$MANIFEST_SHA"
assert_contains "$WORK/output.log" \
    "CANDIDATE_SHA must be a lowercase 40-character commit SHA"
[[ ! -s "$WORK/github/writes" ]] || fail "invalid CI candidate SHA wrote to GitHub"

reset_state
rm "$PACKAGE/release-manifest.json"
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$(printf '0%.0s' {1..64})" "$DMG_LENGTH" "fixture-signature"
expect_failure "manifest digest mismatch" run_publish
[[ ! -s "$WORK/github/writes" ]] || fail "digest mismatch wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
printf '{"object":{"sha":"%s","type":"commit"}}\n' \
    "$(printf 'c%.0s' {1..40})" > "$WORK/github/tag"
expect_failure "Tag SHA mismatch" run_publish
[[ ! -s "$WORK/github/writes" ]] || fail "Tag SHA mismatch wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
FAKE_API_FAIL_ENDPOINT="repos/example/status-trio/git/ref/tags/v1.0.0" \
    expect_failure "GitHub API 500" run_publish
[[ ! -s "$WORK/github/writes" ]] || fail "GitHub API 500 wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
cat > "$WORK/github/appcast" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item><sparkle:version>100</sparkle:version></item>
  </channel>
</rss>
XML
expect_failure "build lower than the published appcast" run_publish
[[ ! -s "$WORK/github/writes" ]] || fail "stale build wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "diagnostic-not-for-publication"
expect_failure "diagnostic package" run_publish
assert_contains "$WORK/output.log" "diagnostic packages cannot be published"
[[ ! -s "$WORK/github/writes" ]] || fail "diagnostic package wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature" developer_id not_requested
expect_failure "Developer ID package without notarization" run_publish
[[ ! -s "$WORK/github/writes" ]] || fail "unnotarized Developer ID package wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature" ad_hoc not_requested
run_publish >"$WORK/ad-hoc.log" 2>&1
assert_contains "$WORK/ad-hoc.log" "Warning: publishing an Ad-hoc package without notarization."
[[ "$(cat "$WORK/github/release-draft")" == "false" ]] || fail "Ad-hoc release was not published"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
printf '{"object":{"sha":"%s","type":"commit"}}\n' \
    "$(printf 'a%.0s' {1..40})" > "$WORK/github/tag"
printf 'draft\n' > "$WORK/github/release"
printf 'true\n' > "$WORK/github/release-draft"
touch "$WORK/github/assets"
printf '%064d\n' 0 > "$WORK/github/digest-override"
expect_failure "existing Draft with a different artifact" run_publish
assert_contains "$WORK/output.log" "not the verified package"
[[ ! -s "$WORK/github/writes" ]] || fail "mismatched Draft artifact was overwritten"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
touch "$WORK/github/draft-by-tag-404"
run_publish
[[ "$(cat "$WORK/github/release-draft")" == "false" ]] || fail "release was not published"
grep -Fq 'fixture-signature' "$WORK/github/appcast" || fail "appcast omitted signature"
grep -Fq 'StatusTrio-1.0.0.dmg' "$WORK/github/appcast" || fail "appcast omitted DMG URL"
assert_contains "$WORK/github/reads" \
    "GET repos/example/status-trio/releases?per_page=100 paginate=true slurp=true"
assert_contains "$WORK/github/reads" "GET repos/example/status-trio/releases/123 paginate=false slurp=false"
ruby -e '
  lines = File.readlines(ARGV[0], chomp: true)
  expected = [
    "api POST git/refs",
    "release create v1.0.0",
    "release upload v1.0.0",
    "api PUT appcast",
    "release edit v1.0.0"
  ]
  abort("unexpected publish order: #{lines.inspect}") unless lines == expected
' "$WORK/github/writes"

APPCAST_BEFORE="$(sha256 "$WORK/github/appcast")"
WRITES_BEFORE="$(<"$WORK/github/writes")"
run_publish >"$WORK/public-retry.log" 2>&1
APPCAST_AFTER="$(sha256 "$WORK/github/appcast")"
[[ "$APPCAST_BEFORE" == "$APPCAST_AFTER" ]] || fail "public retry rewrote the appcast"
[[ "$WRITES_BEFORE" == "$(<"$WORK/github/writes")" ]] || fail "public retry mutated release metadata"

FAKE_PUBLIC_DMG_MODE=invalid PUBLIC_VERIFY_ATTEMPTS=2 expect_failure \
    "public DMG mismatch" run_publish
assert_contains "$WORK/output.log" "Public DMG or appcast did not match"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
printf '{"object":{"sha":"%s","type":"commit"}}\n' \
    "$(printf 'a%.0s' {1..40})" > "$WORK/github/tag"
printf 'existing\n' > "$WORK/github/release"
printf 'true\n' > "$WORK/github/release-draft"
printf '421\n' > "$WORK/github/release-id"
touch "$WORK/github/assets" "$WORK/github/draft-by-tag-404"
cat > "$WORK/github/releases-pages.json" <<'JSON'
[
  [
    {"id": 17, "tag_name": "v0.9.9", "draft": false, "assets": []}
  ],
  [
    {"id": 421, "tag_name": "v1.0.0", "draft": true, "assets": []}
  ]
]
JSON
run_publish >"$WORK/paginated-draft.log" 2>&1
[[ "$(cat "$WORK/github/release-draft")" == "false" ]] ||
    fail "paginated draft discovery did not publish"
assert_contains "$WORK/github/reads" \
    "GET repos/example/status-trio/releases?per_page=100 paginate=true slurp=true"
assert_contains "$WORK/github/reads" "GET repos/example/status-trio/releases/421 paginate=false slurp=false"
[[ "$(grep -c '^release create ' "$WORK/github/writes")" -eq 0 ]] ||
    fail "paginated draft recovery created a duplicate release"
[[ "$(grep -c '^api POST git/refs' "$WORK/github/writes")" -eq 0 ]] ||
    fail "paginated draft recovery created a duplicate tag"
[[ "$(grep -c '^release upload ' "$WORK/github/writes")" -eq 1 ]] ||
    fail "paginated draft recovery did not reassert the same artifacts"

APPCAST_BEFORE="$(sha256 "$WORK/github/appcast")"
WRITES_BEFORE="$(<"$WORK/github/writes")"
run_publish >"$WORK/paginated-public-retry.log" 2>&1
[[ "$APPCAST_BEFORE" == "$(sha256 "$WORK/github/appcast")" ]] ||
    fail "paginated draft's public retry rewrote the appcast"
[[ "$WRITES_BEFORE" == "$(<"$WORK/github/writes")" ]] ||
    fail "paginated draft's public retry mutated release metadata"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
printf 'existing\n' > "$WORK/github/release"
printf 'true\n' > "$WORK/github/release-draft"
printf '421\n' > "$WORK/github/release-id"
touch "$WORK/github/draft-by-tag-404"
cat > "$WORK/github/releases-pages.json" <<'JSON'
[
  [
    {"id": 421, "tag_name": "v1.0.0", "draft": true, "assets": []}
  ]
]
JSON
expect_failure "paginated Draft with missing Tag" run_publish
assert_contains "$WORK/output.log" "Release v1.0.0 exists but its Tag is missing"
[[ ! -s "$WORK/github/writes" ]] || fail "Draft missing its Tag wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
printf '{"object":{"sha":"%s","type":"commit"}}\n' \
    "$(printf 'a%.0s' {1..40})" > "$WORK/github/tag"
printf 'draft\n' > "$WORK/github/release"
printf 'true\n' > "$WORK/github/release-draft"
touch "$WORK/github/assets" "$WORK/github/draft-by-tag-404"
cat > "$WORK/github/releases-pages.json" <<'JSON'
[
  [
    {"id": 421, "tag_name": "v1.0.0", "draft": true, "assets": []},
    {"id": 422, "tag_name": "v1.0.0", "draft": true, "assets": []}
  ]
]
JSON
expect_failure "ambiguous matching drafts" run_publish
assert_contains "$WORK/output.log" "refusing to choose one"
[[ ! -s "$WORK/github/writes" ]] || fail "ambiguous matching drafts wrote to GitHub"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
FAKE_APPCAST_PUT_FAILS=true expect_failure "appcast PUT failure" run_publish
[[ "$(cat "$WORK/github/release-draft")" == "true" ]] || fail "appcast failure published the draft"
[[ -f "$WORK/github/assets" ]] || fail "appcast failure did not upload the draft assets"
run_publish >"$WORK/recovery.log" 2>&1
[[ "$(cat "$WORK/github/release-draft")" == "false" ]] || fail "draft recovery did not publish"
[[ "$(grep -c '^release upload ' "$WORK/github/writes")" -eq 2 ]] ||
    fail "draft recovery did not reassert the same artifacts"
[[ "$(grep -c '^release create ' "$WORK/github/writes")" -eq 1 ]] ||
    fail "draft recovery created a duplicate release"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
FAKE_UPLOAD_FAIL_ONCE=true expect_failure "initial asset upload failure" run_publish
[[ "$(cat "$WORK/github/release-draft")" == "true" ]] || fail "upload failure published the draft"
run_publish >"$WORK/upload-recovery.log" 2>&1
[[ "$(cat "$WORK/github/release-draft")" == "false" ]] || fail "upload recovery did not publish"
[[ "$(grep -c '^release upload ' "$WORK/github/writes")" -eq 2 ]] ||
    fail "upload recovery did not reassert all artifacts"
[[ "$(grep -c '^release create ' "$WORK/github/writes")" -eq 1 ]] ||
    fail "upload recovery created a duplicate release"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
run_publish >/dev/null
FAKE_PUBLIC_APPCAST_MODE=invalid PUBLIC_VERIFY_ATTEMPTS=2 expect_failure \
    "public appcast mismatch" run_publish
assert_contains "$WORK/output.log" "Public DMG or appcast did not match"

reset_state
make_manifest "$PACKAGE/release-manifest.json" "$PACKAGE/StatusTrio-1.0.0.dmg" \
    "$DMG_SHA" "$DMG_LENGTH" "fixture-signature"
printf 'existing\n' > "$WORK/github/release"
printf 'false\n' > "$WORK/github/release-draft"
touch "$WORK/github/assets"
expect_failure "public release without its appcast item" run_publish
[[ ! -s "$WORK/github/writes" ]] || fail "missing public appcast triggered a write"

if VERSION=1.0.0 BUILD=99 PUBLISH=true NOTES_MODE=publish \
    RELEASE_NOTES_DIR="$PACKAGE/release-notes/1.0.0" \
    APPCAST_FILE=appcast.xml bash "$ROOT/scripts/validate-appcast-notes.sh" \
    >"$WORK/notes-publish.log" 2>&1; then
    fail "publish notes accepted only two of the twelve required languages"
fi
VERSION=1.0.0 BUILD=99 PUBLISH=false NOTES_MODE=package \
    RELEASE_NOTES_DIR="$PACKAGE/release-notes/1.0.0" \
    APPCAST_FILE=appcast.xml bash "$ROOT/scripts/validate-appcast-notes.sh" \
    >"$WORK/notes-package.log" 2>&1 ||
    fail "package notes rejected a valid partial future-version directory"
expect_failure "publish without a release-notes directory" \
    env VERSION=9.9.9 BUILD=100 PUBLISH=true NOTES_MODE=publish \
        RELEASE_NOTES_DIR="$WORK/missing-notes" APPCAST_FILE=appcast.xml \
        bash "$ROOT/scripts/validate-appcast-notes.sh"
VERSION=9.9.9 BUILD=100 PUBLISH=false NOTES_MODE=package \
    RELEASE_NOTES_DIR="$WORK/missing-notes" APPCAST_FILE=appcast.xml \
    bash "$ROOT/scripts/validate-appcast-notes.sh" >"$WORK/notes-skip.log" 2>&1 ||
    fail "package notes rejected a missing future-version directory"

echo "release pipeline regressions passed"
