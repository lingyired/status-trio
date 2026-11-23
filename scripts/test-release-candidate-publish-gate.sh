#!/usr/bin/env bash
# Offline regression for publish-release.sh schema v2 candidate gating. Uses
# stub gh/curl/xmllint so no network is touched; asserts the manifest gate.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioPublishGate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "publish gate regression failed: $*" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || { cat "$1" >&2; fail "$1 must contain: $2"; }; }

BIN="$WORK/bin"
PKG="$WORK/package"
mkdir -p "$BIN" "$PKG/release-notes/1.0.0"
for tool in gh curl xmllint; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/$tool"
    chmod +x "$BIN/$tool"
done

printf 'dmg-bytes\n' > "$PKG/StatusTrio-1.0.0.dmg"
DMG_SHA="$(shasum -a 256 "$PKG/StatusTrio-1.0.0.dmg" | awk '{print $1}')"
DMG_LEN="$(stat -f '%z' "$PKG/StatusTrio-1.0.0.dmg")"
printf '%s  StatusTrio-1.0.0.dmg\n' "$DMG_SHA" > "$PKG/StatusTrio-1.0.0.dmg.sha256"
printf 'zip-bytes\n' > "$PKG/StatusTrio-1.0.0.zip"
ZIP_SHA="$(shasum -a 256 "$PKG/StatusTrio-1.0.0.zip" | awk '{print $1}')"
ZIP_LEN="$(stat -f '%z' "$PKG/StatusTrio-1.0.0.zip")"
printf '%s  StatusTrio-1.0.0.zip\n' "$ZIP_SHA" > "$PKG/StatusTrio-1.0.0.zip.sha256"
printf '# notes\n' > "$PKG/release-body.md"

make_manifest() {
    local out="$1" publishable="$2" level="$3" status="$4" cand_sha="$5" signing="$6" notarization="$7"
    ruby -rjson -e '
        out, publishable, level, status, cand_sha, signing, notarization, dmg_sha, dmg_len, zip_sha, zip_len = ARGV
        manifest = {
          schema_version: 2,
          source_sha: "af7f637f186cd611fbc7b0053897ac8a5a17e8ed",
          version: "1.0.0", build: "99", tag: "v1.0.0",
          app_name: "Status Trio", bundle_id: "com.lingsmbp.StatusTrio", minimum_system_version: "13.0",
          toolchain: { xcode: "Xcode 27.0 Build version 27A100", swift: "Apple Swift version 6.4", sdk: "27.0", runner: "xcode-27" },
          dmg: { filename: "StatusTrio-1.0.0.dmg", sha256: dmg_sha, length: dmg_len, ed_signature: "fixture-ed-sig" },
          zip: { filename: "StatusTrio-1.0.0.zip", sha256: zip_sha, length: zip_len, ed_signature: "fixture-zip-sig" },
          signing: { kind: signing }, notarization: { status: notarization },
          release: { repo: "example/status-trio", branch: "main", appcast_file: "appcast.xml", body_file: "release-body.md", notes_dir: "release-notes/1.0.0" },
          candidate: { id: "example/status-trio#1", source_sha: cand_sha, build_run_id: "1", build_workflow: "build-candidate.yml", release_mode: level, publishable: (publishable == "true"), created_at: "2026-11-21T00:00:00Z" },
          verification: { level: level, status: status, evidence: ["fixture"] }
        }
        File.write(out, JSON.pretty_generate(manifest))
    ' "$out" "$publishable" "$level" "$status" "$cand_sha" "$signing" "$notarization" "$DMG_SHA" "$DMG_LEN" "$ZIP_SHA" "$ZIP_LEN"
}

run_publish() {
    PATH="$BIN:$PATH" MANIFEST_PATH="$PKG/release-manifest.json" PACKAGE_DIR="$PKG" \
        GH_TOKEN=fake bash "$ROOT/scripts/publish-release.sh" >"$WORK/out" 2>&1
}

expect_gate_fail() {
    local label="$1" expected="$2"
    if run_publish; then cat "$WORK/out" >&2; fail "$label was accepted"; fi
    assert_contains "$WORK/out" "$expected"
}

SHA40="af7f637f186cd611fbc7b0053897ac8a5a17e8ed"
# Non-publishable candidate is refused.
make_manifest "$PKG/release-manifest.json" false fast declared "$SHA40" developer_id accepted_and_stapled
expect_gate_fail "non-publishable" "not publishable"

# Strict candidate that only declared its verification is refused.
make_manifest "$PKG/release-manifest.json" true strict declared "$SHA40" developer_id accepted_and_stapled
expect_gate_fail "strict declared" "must record verification.status=passed"

# Candidate source_sha inconsistent with manifest source_sha is refused.
make_manifest "$PKG/release-manifest.json" true fast declared "b1111111111111111111111111111111111111111" developer_id accepted_and_stapled
expect_gate_fail "candidate sha mismatch" "does not match source_sha"

# Ad-hoc signed candidate is refused.
make_manifest "$PKG/release-manifest.json" true fast declared "$SHA40" ad_hoc accepted_and_stapled
expect_gate_fail "ad-hoc candidate" "Developer ID"

# A valid fast candidate passes the manifest gate (later network steps are stubbed).
make_manifest "$PKG/release-manifest.json" true fast declared "$SHA40" developer_id accepted_and_stapled
run_publish || true
assert_contains "$WORK/out" "Publishing fast candidate built by run 1"

echo "test-release-candidate-publish-gate: PASS"
