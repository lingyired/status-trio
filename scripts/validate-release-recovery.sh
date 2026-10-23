#!/usr/bin/env bash
# Validates the immutable source run and its downloaded manifest before a
# recovery run is allowed to write a Tag, Release, asset, or appcast item.
set -euo pipefail

WORKFLOW_PATH=".github/workflows/release.yml"
ARTIFACT_NAME="status-trio-release-package"

REPOSITORY="${REPOSITORY:-}"
SOURCE_RUN_ID="${SOURCE_RUN_ID:-}"
CANDIDATE_SHA="${CANDIDATE_SHA:-}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_BUILD="${EXPECTED_BUILD:-}"
EXPECTED_TAG="${EXPECTED_TAG:-}"
EXPECTED_ARTIFACT_ID="${EXPECTED_ARTIFACT_ID:-}"
EXPECTED_ARTIFACT_DIGEST="${EXPECTED_ARTIFACT_DIGEST:-}"
MANIFEST_PATH="${MANIFEST_PATH:-}"

die() {
    echo "Release recovery error: $*" >&2
    exit 1
}

for command in gh ruby; do
    command -v "$command" >/dev/null 2>&1 ||
        die "required command '$command' is not available."
done

[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    die "REPOSITORY must be owner/repository."
[[ "$SOURCE_RUN_ID" =~ ^[1-9][0-9]{0,18}$ ]] ||
    die "SOURCE_RUN_ID must be a positive decimal run ID."
[[ "$CANDIDATE_SHA" =~ ^[0-9a-f]{40}$ ]] ||
    die "CANDIDATE_SHA must be a lowercase 40-character commit SHA."
[[ "$EXPECTED_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] ||
    die "EXPECTED_VERSION is invalid."
[[ "$EXPECTED_BUILD" =~ ^[0-9]+$ ]] ||
    die "EXPECTED_BUILD is invalid."
[[ "$EXPECTED_TAG" == "v${EXPECTED_VERSION}" ]] ||
    die "EXPECTED_TAG must equal vEXPECTED_VERSION."

if [[ -n "$EXPECTED_ARTIFACT_ID" ]]; then
    [[ "$EXPECTED_ARTIFACT_ID" =~ ^[1-9][0-9]{0,18}$ ]] ||
        die "EXPECTED_ARTIFACT_ID must be a positive decimal artifact ID."
fi
if [[ -n "$EXPECTED_ARTIFACT_DIGEST" ]]; then
    [[ "$EXPECTED_ARTIFACT_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] ||
        die "EXPECTED_ARTIFACT_DIGEST must be a sha256 digest."
fi

if [[ "${GITHUB_ACTIONS:-}" == "true" && -z "${GITHUB_RUN_ID:-}" ]]; then
    die "GITHUB_RUN_ID is required to reject self-recovery."
fi
if [[ -n "${GITHUB_RUN_ID:-}" && "$SOURCE_RUN_ID" == "$GITHUB_RUN_ID" ]]; then
    die "SOURCE_RUN_ID must not be the current recovery run."
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioRecovery.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

read_api() {
    local endpoint="$1"
    local output="$2"
    gh api "$endpoint" > "$output" ||
        die "GitHub API read failed for $endpoint."
}

RUN_PATH="$TEMP_ROOT/run.json"
WORKFLOW_JSON_PATH="$TEMP_ROOT/workflow.json"
JOBS_PATH="$TEMP_ROOT/jobs.json"
ARTIFACTS_PATH="$TEMP_ROOT/artifacts.json"
METADATA_PATH="$TEMP_ROOT/metadata"

read_api "repos/$REPOSITORY/actions/runs/$SOURCE_RUN_ID" "$RUN_PATH"
read_api "repos/$REPOSITORY/actions/workflows/release.yml" "$WORKFLOW_JSON_PATH"
read_api "repos/$REPOSITORY/actions/runs/$SOURCE_RUN_ID/jobs?per_page=100" "$JOBS_PATH"
read_api "repos/$REPOSITORY/actions/runs/$SOURCE_RUN_ID/artifacts?per_page=100" \
    "$ARTIFACTS_PATH"

ruby -rjson -rtime - "$RUN_PATH" "$WORKFLOW_JSON_PATH" "$JOBS_PATH" \
    "$ARTIFACTS_PATH" "$MANIFEST_PATH" "$REPOSITORY" "$WORKFLOW_PATH" \
    "$SOURCE_RUN_ID" "$CANDIDATE_SHA" "$EXPECTED_VERSION" "$EXPECTED_BUILD" \
    "$EXPECTED_TAG" "$EXPECTED_ARTIFACT_ID" "$EXPECTED_ARTIFACT_DIGEST" \
    "$ARTIFACT_NAME" "$METADATA_PATH" <<'RUBY'
require "json"
require "time"

run_path, workflow_file, jobs_file, artifacts_file, manifest_path,
  repository, expected_workflow_path, source_run_id, candidate_sha,
  expected_version, expected_build, expected_tag, expected_artifact_id,
  expected_artifact_digest, artifact_name, metadata_path = ARGV

def fail!(message)
  abort("Release recovery error: #{message}")
end

def read_json(path, label)
  JSON.parse(File.read(path))
rescue StandardError => error
  fail!("#{label} is not valid JSON: #{error.message}")
end

def value(hash, key, label)
  hash.fetch(key) { fail!("#{label} is missing #{key}.") }
end

run = read_json(run_path, "source run")
workflow = read_json(workflow_file, "workflow")
jobs_payload = read_json(jobs_file, "source jobs")
artifacts_payload = read_json(artifacts_file, "source artifacts")

fail!("source run ID does not match.") unless value(run, "id", "source run").to_s == source_run_id
fail!("source run repository is not #{repository}.") unless
  run.dig("repository", "full_name") == repository
fail!("source run head repository is not #{repository}.") unless
  run.dig("head_repository", "full_name") == repository
fail!("workflow ID does not match the current release workflow.") unless
  value(run, "workflow_id", "source run") == value(workflow, "id", "workflow")
fail!("current workflow path is not #{expected_workflow_path}.") unless
  value(workflow, "path", "workflow") == expected_workflow_path
fail!("source run workflow path is not #{expected_workflow_path}.") unless
  value(run, "path", "source run") == expected_workflow_path
fail!("current release workflow is not active.") unless value(workflow, "state", "workflow") == "active"
fail!("source run event is not workflow_dispatch.") unless
  value(run, "event", "source run") == "workflow_dispatch"
fail!("source run branch is not main.") unless value(run, "head_branch", "source run") == "main"
fail!("source run head SHA is not the frozen candidate.") unless
  value(run, "head_sha", "source run") == candidate_sha
fail!("source run is not completed.") unless value(run, "status", "source run") == "completed"
fail!("source run did not conclude with the expected publish failure.") unless
  value(run, "conclusion", "source run") == "failure"

run_attempt = value(run, "run_attempt", "source run")
fail!("source run attempt is invalid.") unless run_attempt.is_a?(Integer) && run_attempt.positive?

jobs = value(jobs_payload, "jobs", "source jobs")
fail!("source jobs response is not a complete page.") unless
  value(jobs_payload, "total_count", "source jobs") == jobs.length
fail!("source run must contain exactly verify, package, and publish jobs.") unless
  jobs.length == 3

jobs_by_name = {}
jobs.each do |job|
  jobs_by_name[job["name"]] ||= []
  jobs_by_name[job["name"]] << job
end
%w[verify package publish].each do |name|
  matches = jobs_by_name.fetch(name, [])
  fail!("source run must contain exactly one #{name} job.") unless matches.length == 1
  job = matches.first
  fail!("#{name} job is not completed.") unless value(job, "status", "#{name} job") == "completed"
  fail!("#{name} job belongs to another run.") unless
    value(job, "run_id", "#{name} job").to_s == source_run_id
  fail!("#{name} job belongs to another attempt.") unless
    value(job, "run_attempt", "#{name} job") == run_attempt
  fail!("#{name} job head is not the frozen candidate.") unless
    value(job, "head_sha", "#{name} job") == candidate_sha
  fail!("#{name} job branch is not main.") unless
    value(job, "head_branch", "#{name} job") == "main"
end
fail!("verify job did not succeed.") unless
  value(jobs_by_name.fetch("verify").first, "conclusion", "verify job") == "success"
fail!("package job did not succeed.") unless
  value(jobs_by_name.fetch("package").first, "conclusion", "package job") == "success"
fail!("publish job did not fail.") unless
  value(jobs_by_name.fetch("publish").first, "conclusion", "publish job") == "failure"

artifacts = value(artifacts_payload, "artifacts", "source artifacts")
fail!("source artifacts response is not a complete page.") unless
  value(artifacts_payload, "total_count", "source artifacts") == artifacts.length
active_artifacts = artifacts.select do |artifact|
  artifact["name"] == artifact_name && artifact["expired"] == false
end
fail!("source run must contain exactly one unexpired #{artifact_name} artifact.") unless
  active_artifacts.length == 1

artifact = active_artifacts.first
artifact_id = value(artifact, "id", "artifact")
fail!("artifact ID is invalid.") unless artifact_id.is_a?(Integer) && artifact_id.positive?
fail!("artifact ID does not match verify output.") if
  !expected_artifact_id.empty? && artifact_id.to_s != expected_artifact_id
digest = value(artifact, "digest", "artifact")
fail!("artifact digest is invalid.") unless digest.match?(/\Asha256:[0-9a-f]{64}\z/)
fail!("artifact digest does not match verify output.") if
  !expected_artifact_digest.empty? && digest != expected_artifact_digest
fail!("artifact size is invalid.") unless
  value(artifact, "size_in_bytes", "artifact").is_a?(Integer) &&
    value(artifact, "size_in_bytes", "artifact").positive?

expires_at = begin
  Time.iso8601(value(artifact, "expires_at", "artifact"))
rescue ArgumentError
  fail!("artifact expiration timestamp is invalid.")
end
fail!("artifact has expired.") unless expires_at > Time.now

artifact_run = value(artifact, "workflow_run", "artifact")
fail!("artifact is not correlated with the source run.") unless
  value(artifact_run, "id", "artifact run").to_s == source_run_id
fail!("artifact head is not the frozen candidate.") unless
  value(artifact_run, "head_sha", "artifact run") == candidate_sha
fail!("artifact head branch is not main.") unless
  value(artifact_run, "head_branch", "artifact run") == "main"
fail!("artifact repository does not match the source run repository.") unless
  value(artifact_run, "repository_id", "artifact run") == run.dig("repository", "id")

unless manifest_path.empty?
  fail!("downloaded package manifest is missing: #{manifest_path}") unless File.file?(manifest_path)
  manifest = read_json(manifest_path, "package manifest")
  fail!("manifest schema_version is not 1.") unless
    value(manifest, "schema_version", "package manifest") == 1
  fail!("manifest source_sha is not the frozen candidate.") unless
    value(manifest, "source_sha", "package manifest") == candidate_sha
  fail!("manifest version is not #{expected_version}.") unless
    value(manifest, "version", "package manifest") == expected_version
  fail!("manifest build is not #{expected_build}.") unless
    value(manifest, "build", "package manifest") == expected_build
  fail!("manifest tag is not #{expected_tag}.") unless
    value(manifest, "tag", "package manifest") == expected_tag
  fail!("manifest signing kind is not developer_id.") unless
    manifest.dig("signing", "kind") == "developer_id"
  fail!("manifest notarization is not accepted_and_stapled.") unless
    manifest.dig("notarization", "status") == "accepted_and_stapled"
  fail!("manifest minimum system version is not 13.0.") unless
    manifest.fetch("minimum_system_version", "13.0") == "13.0"
  fail!("manifest release notes path does not match the version.") unless
    manifest.dig("release", "notes_dir") == "release-notes/#{expected_version}"
  fail!("manifest release runner is not xcode-27.") unless
    manifest.dig("toolchain", "runner") == "xcode-27"
end

File.write(
  metadata_path,
  [
    "source_run_id=#{source_run_id}",
    "artifact_id=#{artifact_id}",
    "artifact_digest=#{digest}",
    "artifact_size=#{value(artifact, "size_in_bytes", "artifact")}",
    "artifact_expires_at=#{expires_at.utc.iso8601}"
  ].join("\n") + "\n"
)
RUBY

printf 'Validated source run %s and artifact from %s.\n' \
    "$SOURCE_RUN_ID" "$CANDIDATE_SHA"
while IFS='=' read -r key value; do
    printf '  %s: %s\n' "$key" "$value"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        case "$key" in
            source_run_id|artifact_id|artifact_digest)
                printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
                ;;
        esac
    fi
done < "$METADATA_PATH"
