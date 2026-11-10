#!/usr/bin/env bash
# Exercises fail-closed artifact recovery with a fake GitHub CLI. It never
# contacts GitHub, creates a Tag/Release, or invokes the publishing scripts.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioReleaseRecovery.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

BASE="$WORK/base"
STATE="$WORK/github"
OUTPUT="$WORK/output.log"
GITHUB_OUTPUT_FILE="$WORK/github-output"
LEGACY_CANDIDATE="$WORK/legacy-candidate"
CURRENT_CANDIDATE="$WORK/current-candidate"
LEGACY_WRONG_NEEDS_CANDIDATE="$WORK/legacy-wrong-needs-candidate"
CURRENT_WRONG_NEEDS_CANDIDATE="$WORK/current-wrong-needs-candidate"
VALIDATOR_CWD="$LEGACY_CANDIDATE"
CANDIDATE_SHA="af7f637f186cd611fbc7b0053897ac8a5a17e8ed"
SOURCE_RUN_ID="39923069756"
ARTIFACT_ID="12489237102"
ARTIFACT_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fail() {
    echo "release recovery regression failed: $*" >&2
    exit 1
}

assert_contains() {
    local path="$1"
    local text="$2"
    grep -Fq -- "$text" "$path" || {
        cat "$path" >&2
        fail "$path must contain: $text"
    }
}

mkdir -p "$BASE" "$STATE" "$WORK/bin"

mkdir -p \
    "$LEGACY_CANDIDATE/.github/workflows" \
    "$CURRENT_CANDIDATE/.github/workflows" \
    "$LEGACY_WRONG_NEEDS_CANDIDATE/.github/workflows" \
    "$CURRENT_WRONG_NEEDS_CANDIDATE/.github/workflows"
cp "$ROOT/.github/workflows/release.yml" \
    "$CURRENT_CANDIDATE/.github/workflows/release.yml"
ruby -ryaml - \
    "$LEGACY_CANDIDATE/.github/workflows/release.yml" \
    "$LEGACY_WRONG_NEEDS_CANDIDATE/.github/workflows/release.yml" \
    "$CURRENT_WRONG_NEEDS_CANDIDATE/.github/workflows/release.yml" <<'RUBY'
legacy, legacy_wrong_needs, current_wrong_needs = ARGV
File.write(
  legacy,
  YAML.dump(
    "jobs" => {
      "verify" => {},
      "package" => { "needs" => "verify" },
      "publish" => { "needs" => %w[verify package] }
    }
  )
)
File.write(
  legacy_wrong_needs,
  YAML.dump(
    "jobs" => {
      "verify" => {},
      "package" => { "needs" => %w[verify native] },
      "publish" => { "needs" => %w[verify package] }
    }
  )
)
File.write(
  current_wrong_needs,
  YAML.dump(
    "jobs" => {
      "verify" => {},
      "native" => {},
      "package" => { "needs" => "verify" },
      "publish" => { "needs" => %w[verify native package] }
    }
  )
)
RUBY

ruby -rjson - "$BASE" "$CANDIDATE_SHA" "$SOURCE_RUN_ID" "$ARTIFACT_ID" \
    "$ARTIFACT_DIGEST" <<'RUBY'
require "json"

base, candidate_sha, run_id, artifact_id, artifact_digest = ARGV
run_id = Integer(run_id)
artifact_id = Integer(artifact_id)

run = {
  id: run_id,
  workflow_id: 357050162,
  path: ".github/workflows/release.yml",
  event: "workflow_dispatch",
  head_branch: "main",
  head_sha: candidate_sha,
  status: "completed",
  conclusion: "failure",
  run_attempt: 1,
  repository: { id: 1367294837, full_name: "example/status-trio" },
  head_repository: { id: 1367294837, full_name: "example/status-trio" }
}
File.write(File.join(base, "run.json"), JSON.pretty_generate(run) + "\n")

workflow = {
  id: 357050162,
  path: ".github/workflows/release.yml",
  state: "active"
}
File.write(File.join(base, "workflow.json"), JSON.pretty_generate(workflow) + "\n")

jobs = %w[verify package publish].map.with_index do |name, index|
  {
    id: 120312725000 + index,
    run_id: run_id,
    run_attempt: 1,
    name: name,
    head_branch: "main",
    head_sha: candidate_sha,
    status: "completed",
    conclusion: name == "publish" ? "failure" : "success"
  }
end
File.write(
  File.join(base, "jobs.json"),
  JSON.pretty_generate(total_count: jobs.length, jobs: jobs) + "\n"
)

artifact = {
  id: artifact_id,
  name: "status-trio-release-package",
  size_in_bytes: 14_444_110,
  digest: artifact_digest,
  expired: false,
  created_at: "2026-10-23T08:35:07Z",
  expires_at: "2099-11-22T08:35:05Z",
  workflow_run: {
    id: run_id,
    head_branch: "main",
    head_sha: candidate_sha,
    repository_id: 1367294837
  }
}
File.write(
  File.join(base, "artifacts.json"),
  JSON.pretty_generate(total_count: 1, artifacts: [artifact]) + "\n"
)

manifest = {
  schema_version: 1,
  source_sha: candidate_sha,
  version: "1.7.2",
  build: "40",
  tag: "v1.7.2",
  minimum_system_version: "13.0",
  toolchain: { runner: "xcode-27" },
  signing: { kind: "developer_id" },
  notarization: { status: "accepted_and_stapled" },
  release: { notes_dir: "release-notes/1.7.2" }
}
File.write(
  File.join(base, "release-manifest.json"),
  JSON.pretty_generate(manifest) + "\n"
)
RUBY

cat > "$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

state="${FAKE_GH_STATE:?}"
printf '%s\n' "$*" >> "$state/calls"
[[ "${1:-}" == "api" ]] || {
    echo "unexpected gh command: $*" >&2
    exit 91
}

endpoint="${2:-}"
case "$endpoint" in
    repos/example/status-trio/actions/runs/39923069756)
        cat "$state/run.json"
        ;;
    repos/example/status-trio/actions/workflows/release.yml)
        cat "$state/workflow.json"
        ;;
    repos/example/status-trio/actions/runs/39923069756/jobs?per_page=100)
        cat "$state/jobs.json"
        ;;
    repos/example/status-trio/actions/runs/39923069756/artifacts?per_page=100)
        cat "$state/artifacts.json"
        ;;
    *)
        echo "unexpected gh api endpoint: $endpoint" >&2
        exit 90
        ;;
esac
SH
chmod +x "$WORK/bin/gh"

reset_state() {
    rm -rf "$STATE"
    cp -R "$BASE" "$STATE"
    : > "$STATE/calls"
    : > "$GITHUB_OUTPUT_FILE"
}

run_validator() {
    local output="$1"
    shift
    (
        cd "$VALIDATOR_CWD"
        env \
            PATH="$WORK/bin:$PATH" \
            FAKE_GH_STATE="$STATE" \
            GH_TOKEN="fixture-token" \
            GITHUB_RUN_ID="40000000000" \
            GITHUB_WORKSPACE="" \
            REPOSITORY="example/status-trio" \
            SOURCE_RUN_ID="$SOURCE_RUN_ID" \
            CANDIDATE_SHA="$CANDIDATE_SHA" \
            EXPECTED_VERSION="1.7.2" \
            EXPECTED_BUILD="40" \
            EXPECTED_TAG="v1.7.2" \
            EXPECTED_ARTIFACT_ID="" \
            EXPECTED_ARTIFACT_DIGEST="" \
            MANIFEST_PATH="" \
            GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
            "$@" \
            bash "$ROOT/scripts/validate-release-recovery.sh"
    ) >"$output" 2>&1
}

mutate_json() {
    local path="$1"
    local code="$2"
    ruby -rjson -e '
        path, code = ARGV
        data = JSON.parse(File.read(path))
        eval(code)
        File.write(path, JSON.generate(data) + "\n")
    ' "$path" "$code"
}

add_current_native_job() {
    mutate_json "$STATE/jobs.json" '
      package_job = data["jobs"].find { |job| job["name"] == "package" }
      native_job = package_job.merge("id" => package_job["id"] + 1, "name" => "native")
      data["jobs"].insert(1, native_job)
      data["total_count"] = data["jobs"].length
    '
}

expect_validator_failure() {
    local label="$1"
    local expected_error="$2"
    shift 2
    if run_validator "$OUTPUT" "$@"; then
        fail "$label was accepted"
    fi
    assert_contains "$OUTPUT" "Release recovery error:"
    assert_contains "$OUTPUT" "$expected_error"
}

reset_state
run_validator "$OUTPUT" || {
    cat "$OUTPUT" >&2
    fail "valid source run was rejected"
}
assert_contains "$OUTPUT" "Validated failed-publish source run $SOURCE_RUN_ID"
assert_contains "$GITHUB_OUTPUT_FILE" "source_run_id=$SOURCE_RUN_ID"
assert_contains "$GITHUB_OUTPUT_FILE" "artifact_id=$ARTIFACT_ID"
assert_contains "$GITHUB_OUTPUT_FILE" "artifact_digest=$ARTIFACT_DIGEST"
if grep -Eqv '^api ' "$STATE/calls"; then
    fail "validator invoked a non-read GitHub command"
fi

reset_state
add_current_native_job
VALIDATOR_CWD="$CURRENT_CANDIDATE" run_validator "$OUTPUT" || {
    cat "$OUTPUT" >&2
    fail "current four-job source run was rejected"
}
assert_contains "$OUTPUT" "Validated failed-publish source run $SOURCE_RUN_ID"

reset_state
add_current_native_job
mutate_json "$STATE/run.json" 'data["conclusion"] = "success"'
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "publish" }["conclusion"] = "skipped"'
VALIDATOR_CWD="$CURRENT_CANDIDATE" run_validator "$OUTPUT" || {
    cat "$OUTPUT" >&2
    fail "current four-job package-only source run was rejected"
}
assert_contains "$OUTPUT" "Validated package-only source run $SOURCE_RUN_ID"

reset_state
add_current_native_job
mutate_json "$STATE/jobs.json" '
  data["jobs"].reject! { |job| job["name"] == "native" }
  data["total_count"] = data["jobs"].length
'
VALIDATOR_CWD="$CURRENT_CANDIDATE" expect_validator_failure \
    "current source run without native job" "job shape does not match"

reset_state
add_current_native_job
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "native" }["conclusion"] = "failure"'
VALIDATOR_CWD="$CURRENT_CANDIDATE" expect_validator_failure \
    "source run with failed native job" "native job did not succeed"

reset_state
add_current_native_job
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "native" }["conclusion"] = "skipped"'
VALIDATOR_CWD="$CURRENT_CANDIDATE" expect_validator_failure \
    "source run with skipped native job" "native job did not succeed"

reset_state
add_current_native_job
mutate_json "$STATE/jobs.json" '
  package_job = data["jobs"].find { |job| job["name"] == "package" }
  data["jobs"] << package_job.merge("id" => package_job["id"] + 100, "name" => "unexpected")
  data["total_count"] = data["jobs"].length
'
VALIDATOR_CWD="$CURRENT_CANDIDATE" expect_validator_failure \
    "source run with unexpected job shape" "job shape does not match"

reset_state
add_current_native_job
VALIDATOR_CWD="$LEGACY_CANDIDATE" expect_validator_failure \
    "legacy workflow with native metadata" "job shape does not match"

reset_state
add_current_native_job
VALIDATOR_CWD="$CURRENT_WRONG_NEEDS_CANDIDATE" expect_validator_failure \
    "current workflow package without native dependency" "package job needs do not match"

reset_state
VALIDATOR_CWD="$LEGACY_WRONG_NEEDS_CANDIDATE" expect_validator_failure \
    "legacy workflow package with unexpected native dependency" "package job needs do not match"

reset_state
expect_validator_failure "malformed source run ID" "SOURCE_RUN_ID" \
    SOURCE_RUN_ID=not-a-run-id

reset_state
expect_validator_failure "self-recovery" "current recovery run" \
    SOURCE_RUN_ID=40000000000

reset_state
mutate_json "$STATE/run.json" 'data["repository"]["full_name"] = "other/status-trio"'
expect_validator_failure "source run from another repository" \
    "repository is not example/status-trio"

reset_state
mutate_json "$STATE/workflow.json" 'data["id"] = 1'
expect_validator_failure "source run from another workflow" \
    "workflow ID does not match"

reset_state
mutate_json "$STATE/run.json" 'data["path"] = ".github/workflows/other.yml"'
expect_validator_failure "source run from another workflow path" \
    "workflow path is not .github/workflows/release.yml"

reset_state
mutate_json "$STATE/run.json" 'data["event"] = "push"'
expect_validator_failure "non-dispatched source run" \
    "event is not workflow_dispatch"

reset_state
mutate_json "$STATE/run.json" 'data["head_sha"] = "b" * 40'
expect_validator_failure "source run with another candidate" \
    "head SHA is not the frozen candidate"

reset_state
mutate_json "$STATE/run.json" 'data["status"] = "in_progress"; data["conclusion"] = nil'
expect_validator_failure "incomplete source run" "source run is not completed"

reset_state
mutate_json "$STATE/run.json" 'data["conclusion"] = "success"'
expect_validator_failure "successful source run with failed publish" \
    "source run succeeded without skipping publication"

reset_state
mutate_json "$STATE/run.json" 'data["conclusion"] = "success"'
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "publish" }["conclusion"] = "skipped"'
run_validator "$OUTPUT" || {
    cat "$OUTPUT" >&2
    fail "valid package-only source run was rejected"
}
assert_contains "$OUTPUT" "Validated package-only source run $SOURCE_RUN_ID"

reset_state
mutate_json "$STATE/run.json" 'data["conclusion"] = "failure"'
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "publish" }["conclusion"] = "skipped"'
expect_validator_failure "failed source run with skipped publish" \
    "publish job did not fail"

reset_state
mutate_json "$STATE/run.json" 'data["conclusion"] = "success"'
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "publish" }["conclusion"] = "cancelled"'
expect_validator_failure "successful source run with cancelled publish" \
    "source run succeeded without skipping publication"

reset_state
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "package" }["conclusion"] = "failure"'
expect_validator_failure "source run with failed package" \
    "package job did not succeed"

reset_state
mutate_json "$STATE/jobs.json" 'data["jobs"].find { |job| job["name"] == "publish" }["conclusion"] = "success"'
expect_validator_failure "source run with successful publish" \
    "publish job did not fail"

reset_state
mutate_json "$STATE/artifacts.json" 'data["artifacts"] = []; data["total_count"] = 0'
expect_validator_failure "source run without artifact" \
    "exactly one unexpired status-trio-release-package"

reset_state
mutate_json "$STATE/artifacts.json" '
  data["artifacts"] << data["artifacts"][0].merge("id" => 12489237103)
  data["total_count"] = 2
'
expect_validator_failure "source run with duplicate artifacts" \
    "exactly one unexpired status-trio-release-package"

reset_state
mutate_json "$STATE/artifacts.json" 'data["artifacts"][0]["expired"] = true'
expect_validator_failure "expired source artifact" \
    "exactly one unexpired status-trio-release-package"

reset_state
mutate_json "$STATE/artifacts.json" 'data["artifacts"][0]["expires_at"] = "2020-01-01T00:00:00Z"'
expect_validator_failure "artifact with elapsed expiration" "artifact has expired"

reset_state
mutate_json "$STATE/artifacts.json" 'data["artifacts"][0]["workflow_run"]["head_sha"] = "b" * 40'
expect_validator_failure "artifact without head correlation" \
    "artifact head is not the frozen candidate"

reset_state
expect_validator_failure "artifact ID different from verify output" \
    "artifact ID does not match verify output" \
    EXPECTED_ARTIFACT_ID=12489237103

reset_state
expect_validator_failure "artifact digest different from verify output" \
    "artifact digest does not match verify output" \
    EXPECTED_ARTIFACT_DIGEST="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

reset_state
cp "$BASE/release-manifest.json" "$WORK/release-manifest.json"
run_validator "$OUTPUT" \
    MANIFEST_PATH="$WORK/release-manifest.json" \
    EXPECTED_ARTIFACT_ID="$ARTIFACT_ID" \
    EXPECTED_ARTIFACT_DIGEST="$ARTIFACT_DIGEST" || {
    cat "$OUTPUT" >&2
    fail "valid recovered manifest was rejected"
}

for manifest_case in \
    'source_sha|"b" * 40|manifest source_sha is not the frozen candidate' \
    'version|"1.7.3"|manifest version is not 1.7.2' \
    'build|"41"|manifest build is not 40' \
    'tag|"v1.7.3"|manifest tag is not v1.7.2'; do
    IFS='|' read -r field replacement expected_error <<< "$manifest_case"
    reset_state
    cp "$BASE/release-manifest.json" "$WORK/release-manifest.json"
    mutate_json "$WORK/release-manifest.json" "data[\"$field\"] = $replacement"
    expect_validator_failure "manifest $field mismatch" "$expected_error" \
        MANIFEST_PATH="$WORK/release-manifest.json" \
        EXPECTED_ARTIFACT_ID="$ARTIFACT_ID" \
        EXPECTED_ARTIFACT_DIGEST="$ARTIFACT_DIGEST"
done

reset_state
cp "$BASE/release-manifest.json" "$WORK/release-manifest.json"
mutate_json "$WORK/release-manifest.json" 'data["signing"]["kind"] = "ad_hoc"'
expect_validator_failure "Ad-hoc recovered package" \
    "manifest signing kind is not developer_id" \
    MANIFEST_PATH="$WORK/release-manifest.json" \
    EXPECTED_ARTIFACT_ID="$ARTIFACT_ID" \
    EXPECTED_ARTIFACT_DIGEST="$ARTIFACT_DIGEST"

reset_state
cp "$BASE/release-manifest.json" "$WORK/release-manifest.json"
mutate_json "$WORK/release-manifest.json" 'data["notarization"]["status"] = "not_requested"'
expect_validator_failure "un-notarized recovered package" \
    "manifest notarization is not accepted_and_stapled" \
    MANIFEST_PATH="$WORK/release-manifest.json" \
    EXPECTED_ARTIFACT_ID="$ARTIFACT_ID" \
    EXPECTED_ARTIFACT_DIGEST="$ARTIFACT_DIGEST"

WORKFLOW="$ROOT/.github/workflows/release.yml"
ruby -ryaml - "$WORKFLOW" <<'RUBY'
require "yaml"

path = ARGV.fetch(0)
source = File.read(path)
YAML.parse(source)

checks = {
  "package_run_id input" => "      package_run_id:\n",
  "package skip placement" =>
    "  package:\n" \
    "    needs: [verify, native]\n" \
    "    runs-on: xcode-27\n" \
    "    if: ${{ inputs.package_run_id == '' }}\n",
  "workflow SHA checkout" => "ref: ${{ github.workflow_sha }}",
  "trusted tooling path" => "path: release-tools",
  "recovery working directory" => "working-directory: release-tools",
  "literal publish command" => "run: bash scripts/publish-release.sh",
  "source run download" => "run-id: ${{ needs.verify.outputs.recovery_source_run_id || github.run_id }}",
  "actions read" => "actions: read",
  "trusted recovery test" => "bash release-tools/scripts/test-release-recovery.sh",
  "trusted policy test" => 'bash "$CI_TOOLS_ROOT/scripts/test-release-workflow-policy.sh"',
  "trusted pipeline test" => "bash release-tools/scripts/test-release-pipeline.sh"
}
checks.each do |label, needle|
  abort("release workflow is missing #{label}") unless source.include?(needle)
end
abort("release workflow must not override reserved GITHUB_SHA") if source.match?(/^\s+GITHUB_SHA:/)
abort("publish must use CANDIDATE_SHA from verify outputs") unless source.include?(
  "CANDIDATE_SHA: ${{ needs.verify.outputs.candidate_sha || inputs.candidate_sha }}"
)
abort("publish must reassert the explicit candidate checkout") unless source.include?(
  '[[ "${ACTUAL_SHA}" == "${CANDIDATE_SHA}" ]]'
)

jobs_section = source[/^jobs:\n(.*)\z/m, 1] || ""
jobs = jobs_section.scan(/^  ([A-Za-z0-9_-]+):$/).flatten
abort("release workflow must have exactly verify, native, package, and publish jobs: #{jobs.inspect}") unless
  jobs == %w[verify native package publish]

workflow = YAML.safe_load(source, aliases: true)
package = workflow.fetch("jobs").fetch("package")
abort("package must wait for verify and native") unless
  Array(package.fetch("needs")).sort == %w[native verify]
publish = workflow.fetch("jobs").fetch("publish")
abort("publish must wait for verify, native, and package") unless
  Array(publish.fetch("needs")).sort == %w[native package verify]
abort("publish must require native success") unless
  publish.fetch("if").include?("needs.native.result == 'success'")
RUBY

bash -n "$ROOT/scripts/validate-release-recovery.sh" "$ROOT/scripts/test-release-recovery.sh"
STATUS_TRIO_RELEASE_POLICY_ROOT="$ROOT" \
    bash "$ROOT/scripts/check-release-workflow-policy.sh" >/dev/null

echo "release recovery regressions passed"
