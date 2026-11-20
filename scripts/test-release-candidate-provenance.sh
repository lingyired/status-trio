#!/usr/bin/env bash
# Offline regression for the Build Candidate -> Publish Existing Candidate
# contract. Uses a fake GitHub CLI and fixture manifests; it never contacts
# GitHub, never builds, never signs, and never notarizes.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioCandidatePipeline.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

REPO="example/status-trio"
RUN_ID="39923069756"
SHA="af7f637f186cd611fbc7b0053897ac8a5a17e8ed"
VERSION="1.0.0"
BUILD="99"
TAG="v1.0.0"
ART_ID="12489237102"
DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fail() { echo "candidate pipeline regression failed: $*" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || { cat "$1" >&2; fail "$1 must contain: $2"; }; }

API="$WORK/api"
BIN="$WORK/bin"
mkdir -p "$API" "$BIN"

write_fixtures() {
    local level="$1" status="$2" verify_conclusion="$3" native_conclusion="$4" publishable="${5:-true}" expired="${6:-false}" artifact_digest="${7:-$DIGEST}" manifest_sha="${8:-$SHA}"
    ruby -rjson -e '
        repo, run_id, sha, version, build, tag, art_id, digest, level, status,
          verify, native, publishable, expired, manifest_sha, out = ARGV
        run = {
          id: run_id.to_i, workflow_id: 777, path: ".github/workflows/build-candidate.yml",
          event: "workflow_dispatch", status: "completed", conclusion: "success",
          head_branch: "main", run_attempt: 1,
          repository: { full_name: repo }, head_repository: { full_name: repo }
        }
        workflow = { id: 777, path: ".github/workflows/build-candidate.yml" }
        jobs = {
          jobs: [
            { name: "prepare", conclusion: "success" },
            { name: "verify", conclusion: verify },
            { name: "native", conclusion: native },
            { name: "package", conclusion: "success" }
          ]
        }
        artifacts = {
          artifacts: [
            { id: art_id.to_i, name: "status-trio-release-package", digest: digest, expired: (expired == "true"), size_in_bytes: 1234 }
          ]
        }
        manifest = {
          schema_version: 2,
          source_sha: manifest_sha, version: version, build: build, tag: tag,
          candidate: {
            id: "#{repo}##{run_id}", source_sha: manifest_sha, build_run_id: run_id,
            build_workflow: "build-candidate.yml", release_mode: level,
            publishable: (publishable == "true"), created_at: "2026-11-21T00:00:00Z"
          },
          verification: { level: level, status: status, evidence: ["fixture"] }
        }
        File.write(File.join(out, "run.json"), JSON.generate(run))
        File.write(File.join(out, "workflow.json"), JSON.generate(workflow))
        File.write(File.join(out, "jobs.json"), JSON.generate(jobs))
        File.write(File.join(out, "artifacts.json"), JSON.generate(artifacts))
        File.write(File.join(out, "manifest.json"), JSON.pretty_generate(manifest))
    ' "$REPO" "$RUN_ID" "$SHA" "$VERSION" "$BUILD" "$TAG" "$ART_ID" "$artifact_digest" "$level" "$status" "$verify_conclusion" "$native_conclusion" "$publishable" "$expired" "$manifest_sha" "$API"
}

cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != "api" ]]; then
    echo "fake gh only supports api" >&2
    exit 1
fi
endpoint="$2"
case "$endpoint" in
    */actions/runs/*/jobs*) body="$FAKE_API_DIR/jobs.json" ;;
    */actions/runs/*/artifacts*) body="$FAKE_API_DIR/artifacts.json" ;;
    */actions/workflows/*) body="$FAKE_API_DIR/workflow.json" ;;
    */actions/runs/*) body="$FAKE_API_DIR/run.json" ;;
    *) echo "unexpected endpoint $endpoint" >&2; exit 1 ;;
esac
cat "$body"
SH
chmod +x "$BIN/gh"

run_validator() {
    local out="$1"; shift
    rm -f "$WORK/vars"
    PATH="$BIN:$PATH" FAKE_API_DIR="$API" \
    REPOSITORY="$REPO" SOURCE_RUN_ID="$RUN_ID" CANDIDATE_SHA="$SHA" \
    EXPECTED_VERSION="$VERSION" EXPECTED_BUILD="$BUILD" EXPECTED_TAG="$TAG" \
    MANIFEST_PATH="$API/manifest.json" OUTPUT_VARS_PATH="$WORK/vars" \
    GITHUB_ACTIONS=false \
    "$@" bash "$ROOT/scripts/validate-candidate-provenance.sh" >"$out" 2>&1
}

expect_fail() {
    local label="$1"; local expected="$2"; shift 2
    if run_validator "$WORK/out" "$@"; then
        cat "$WORK/out" >&2
        fail "$label was accepted"
    fi
    assert_contains "$WORK/out" "$expected"
}

# 1. Fast candidate succeeds and records fast effective level.
write_fixtures fast declared skipped skipped
run_validator "$WORK/out"
assert_contains "$WORK/out" "Candidate provenance accepted"
assert_contains "$WORK/vars" "effective_level=fast"
assert_contains "$WORK/vars" "artifact_id=$ART_ID"

# 2. Strict candidate with successful verify/native succeeds.
write_fixtures strict passed success success
run_validator "$WORK/out"
assert_contains "$WORK/out" "for strict candidate run $RUN_ID"

# 3. Expired artifact is rejected.
write_fixtures fast declared skipped skipped true true
expect_fail "expired artifact" "expired"

# 4. Non-publishable candidate is rejected.
write_fixtures diagnostic declared skipped skipped false false
expect_fail "non-publishable" "not publishable"

# 5. A strict candidate with skipped verify is rejected.
write_fixtures strict passed skipped skipped true false
expect_fail "strict skipped verify" "requires the verify job to succeed"

# 6. Manifest source_sha mismatch is rejected.
write_fixtures fast declared skipped skipped true false "$DIGEST" "b1111111111111111111111111111111111111111"
expect_fail "source sha mismatch" "candidate.source_sha"

# 7. Artifact digest mismatch is rejected.
write_fixtures fast declared skipped skipped true false
expect_fail "digest mismatch" "digest" env EXPECTED_ARTIFACT_DIGEST="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

# 8. Self-recovery is rejected.
expect_fail "self-recovery" "must not be the current publish run" env GITHUB_RUN_ID="$RUN_ID" GITHUB_ACTIONS=true

# 9. A strict evidence file upgrades a fast candidate to strict.
write_fixtures fast declared skipped skipped
ruby -rjson -e 'File.write(ARGV[0], JSON.generate(candidate_run_id: ARGV[1].to_i, source_sha: ARGV[2], verification_level: "strict", status: "passed"))' \
    "$WORK/evidence.json" "$RUN_ID" "$SHA"
run_validator "$WORK/out" env STRICT_EVIDENCE_PATH="$WORK/evidence.json"
assert_contains "$WORK/vars" "effective_level=strict"

# 10. Strict evidence for a different candidate is rejected.
ruby -rjson -e 'File.write(ARGV[0], JSON.generate(candidate_run_id: 1, source_sha: ARGV[1], verification_level: "strict", status: "passed"))' \
    "$WORK/evidence-bad.json" "$SHA"
expect_fail "wrong strict evidence" "not for this candidate run" env STRICT_EVIDENCE_PATH="$WORK/evidence-bad.json"

echo "test-release-candidate-provenance: PASS"
