#!/usr/bin/env bash
# Versioned provenance validation for a Build Candidate run before Publish
# Existing Candidate is allowed to create a Tag, Release, asset, or appcast item.
#
# This validator understands the build-candidate.yml workflow (schema v2
# manifest, fast/strict verification levels) and optional strict-evidence
# artifacts produced by verify-candidate.yml. It never rebuilds, signs, or
# notarizes anything; it only reads GitHub provenance.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CANDIDATE_WORKFLOW_ID=".github/workflows/build-candidate.yml"
# GitHub's workflows API accepts the workflow file name (or numeric id), not the repo path.
CANDIDATE_WORKFLOW_FILE="build-candidate.yml"
CANDIDATE_WORKFLOW_PATH="${CANDIDATE_WORKFLOW_PATH:-${GITHUB_WORKSPACE:-$(pwd)}/$CANDIDATE_WORKFLOW_ID}"
ARTIFACT_NAME="${ARTIFACT_NAME:-status-trio-release-package}"

REPOSITORY="${REPOSITORY:-}"
SOURCE_RUN_ID="${SOURCE_RUN_ID:-}"
CANDIDATE_SHA="${CANDIDATE_SHA:-}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_BUILD="${EXPECTED_BUILD:-}"
EXPECTED_TAG="${EXPECTED_TAG:-}"
EXPECTED_ARTIFACT_ID="${EXPECTED_ARTIFACT_ID:-}"
EXPECTED_ARTIFACT_DIGEST="${EXPECTED_ARTIFACT_DIGEST:-}"
MANIFEST_PATH="${MANIFEST_PATH:-}"
ALLOWED_LEVELS="${ALLOWED_LEVELS:-fast,strict}"
STRICT_EVIDENCE_PATH="${STRICT_EVIDENCE_PATH:-}"
OUTPUT_VARS_PATH="${OUTPUT_VARS_PATH:-${GITHUB_OUTPUT:-}}"

die() {
    echo "Candidate provenance error: $*" >&2
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
[[ -f "$MANIFEST_PATH" ]] ||
    die "MANIFEST_PATH must name the downloaded candidate manifest."
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
    die "SOURCE_RUN_ID must not be the current publish run."
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioCandidate.XXXXXX")"
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
RESULT_PATH="$TEMP_ROOT/result.json"

read_api "repos/$REPOSITORY/actions/runs/$SOURCE_RUN_ID" "$RUN_PATH"
read_api "repos/$REPOSITORY/actions/workflows/$CANDIDATE_WORKFLOW_FILE" "$WORKFLOW_JSON_PATH"
read_api "repos/$REPOSITORY/actions/runs/$SOURCE_RUN_ID/jobs?per_page=100" "$JOBS_PATH"
read_api "repos/$REPOSITORY/actions/runs/$SOURCE_RUN_ID/artifacts?per_page=100" "$ARTIFACTS_PATH"

ruby -rjson -rtime - "$RUN_PATH" "$WORKFLOW_JSON_PATH" "$JOBS_PATH" \
    "$ARTIFACTS_PATH" "$MANIFEST_PATH" "$REPOSITORY" "$CANDIDATE_WORKFLOW_ID" \
    "$SOURCE_RUN_ID" "$CANDIDATE_SHA" "$EXPECTED_VERSION" "$EXPECTED_BUILD" \
    "$EXPECTED_TAG" "$EXPECTED_ARTIFACT_ID" "$EXPECTED_ARTIFACT_DIGEST" \
    "$ARTIFACT_NAME" "$ALLOWED_LEVELS" "$STRICT_EVIDENCE_PATH" "$RESULT_PATH" \
    "${GITHUB_RUN_ID:-}" <<'RUBY'
require "json"

run_path, workflow_file, jobs_file, artifacts_file, manifest_path,
  repository, expected_workflow_path, source_run_id, candidate_sha,
  expected_version, expected_build, expected_tag, expected_artifact_id,
  expected_artifact_digest, artifact_name, allowed_levels, strict_evidence_path,
  result_path, current_run_id = ARGV

def fail!(message)
  abort("Candidate provenance error: #{message}")
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
workflow = read_json(workflow_file, "candidate workflow")
jobs_payload = read_json(jobs_file, "source jobs")
artifacts_payload = read_json(artifacts_file, "source artifacts")
manifest = read_json(manifest_path, "candidate manifest")

fail!("source run ID does not match.") unless value(run, "id", "source run").to_s == source_run_id
fail!("source run repository is not #{repository}.") unless run.dig("repository", "full_name") == repository
fail!("source run head repository is not #{repository}.") unless run.dig("head_repository", "full_name") == repository
fail!("workflow ID does not match the build-candidate workflow.") unless
  value(run, "workflow_id", "source run") == value(workflow, "id", "candidate workflow")
fail!("candidate workflow path is not #{expected_workflow_path}.") unless
  value(workflow, "path", "candidate workflow") == expected_workflow_path
fail!("source run workflow path is not #{expected_workflow_path}.") unless
  value(run, "path", "source run") == expected_workflow_path
fail!("source run must be a workflow_dispatch run.") unless
  value(run, "event", "source run") == "workflow_dispatch"
fail!("source run must have completed successfully.") unless
  value(run, "status", "source run") == "completed" &&
  value(run, "conclusion", "source run") == "success"
fail!("source run must be dispatched from main.") unless
  value(run, "head_branch", "source run") == "main"
fail!("source run must not be the current run.") unless current_run_id.to_s.empty? || run["id"].to_s != current_run_id.to_s

schema_version = value(manifest, "schema_version", "candidate manifest")
fail!("candidate manifest must be schema_version 2, not #{schema_version.inspect}.") unless schema_version == 2
candidate = value(manifest, "candidate", "candidate manifest")
verification = value(manifest, "verification", "candidate manifest")
fail!("candidate manifest is not publishable.") unless value(candidate, "publishable", "candidate") == true
fail!("candidate.source_sha is not #{candidate_sha}.") unless value(candidate, "source_sha", "candidate") == candidate_sha
fail!("manifest source_sha is not #{candidate_sha}.") unless value(manifest, "source_sha", "manifest") == candidate_sha
fail!("candidate.build_workflow must be build-candidate.yml.") unless value(candidate, "build_workflow", "candidate") == "build-candidate.yml"
fail!("candidate.build_run_id is not the source run.") unless value(candidate, "build_run_id", "candidate").to_s == source_run_id

fail!("manifest version #{value(manifest, "version", "manifest")} is not #{expected_version}.") unless
  value(manifest, "version", "manifest").to_s == expected_version
fail!("manifest build #{value(manifest, "build", "manifest")} is not #{expected_build}.") unless
  value(manifest, "build", "manifest").to_s == expected_build
fail!("manifest tag #{value(manifest, "tag", "manifest")} is not #{expected_tag}.") unless
  value(manifest, "tag", "manifest") == expected_tag

level = value(verification, "level", "verification").to_s
status = value(verification, "status", "verification").to_s
allowed = allowed_levels.split(",").map(&:strip).reject(&:empty?)
fail!("verification.level #{level.inspect} is not allowed (#{allowed.join(', ')}).") unless allowed.include?(level)
fail!("verification.level #{level.inspect} is invalid.") unless %w[fast strict].include?(level)
fail!("verification.status #{status.inspect} is invalid.") unless %w[passed declared].include?(status)
fail!("a strict candidate must record verification.status=passed.") if level == "strict" && status != "passed"

jobs = value(jobs_payload, "jobs", "source jobs")
by_name = {}
jobs.each { |job| by_name[job["name"]] = job }
fail!("source run has no jobs.") if jobs.empty?
jobs.each do |job|
  conclusion = job["conclusion"]
  next if %w[success skipped neutral].include?(conclusion)
  fail!("job #{job['name'].inspect} did not succeed (conclusion=#{conclusion.inspect}).")
end
%w[prepare package].each do |required|
  job = by_name[required]
  fail!("source run is missing the #{required} job.") unless job
  fail!("the #{required} job conclusion is #{job['conclusion'].inspect}, not success.") unless job["conclusion"] == "success"
end
if level == "strict"
  %w[verify native].each do |required|
    job = by_name[required]
    fail!("a strict candidate is missing the #{required} job.") unless job
    fail!("a strict candidate requires the #{required} job to succeed, not #{job['conclusion'].inspect}.") unless job["conclusion"] == "success"
  end
end

artifacts = value(artifacts_payload, "artifacts", "source artifacts")
matching = artifacts.select { |artifact| artifact["name"] == artifact_name }
fail!("source run has #{matching.length} #{artifact_name} artifacts, expected exactly one.") unless matching.length == 1
artifact = matching.first
fail!("candidate artifact #{artifact['id']} is expired.") if artifact["expired"]
fail!("candidate artifact has no sha256 digest.") unless artifact["digest"].to_s.start_with?("sha256:")
fail!("candidate artifact ID #{artifact['id']} is not #{expected_artifact_id}.") if
  !expected_artifact_id.empty? && artifact["id"].to_s != expected_artifact_id
fail!("candidate artifact digest #{artifact['digest']} is not #{expected_artifact_digest}.") if
  !expected_artifact_digest.empty? && artifact["digest"] != expected_artifact_digest

effective_level = level
unless strict_evidence_path.to_s.empty? || !File.exist?(strict_evidence_path)
  evidence = read_json(strict_evidence_path, "strict evidence")
  fail!("strict evidence is not for this candidate run.") unless evidence["candidate_run_id"].to_s == source_run_id
  fail!("strict evidence source_sha is not #{candidate_sha}.") unless evidence["source_sha"] == candidate_sha
  fail!("strict evidence level is not strict.") unless evidence["verification_level"] == "strict"
  fail!("strict evidence did not pass.") unless evidence["status"] == "passed"
  effective_level = "strict"
end

File.write(
  result_path,
  JSON.pretty_generate(
    artifact_id: artifact["id"],
    artifact_digest: artifact["digest"],
    verification_level: level,
    effective_level: effective_level,
    source_sha: candidate_sha,
    build_run_id: run["id"],
    run_attempt: run["run_attempt"]
  ) + "\n"
)
puts "Validated #{artifact_name} artifact #{artifact['id']} (#{artifact['digest']}) for #{effective_level} candidate run #{source_run_id}."
RUBY

if [[ -n "$OUTPUT_VARS_PATH" ]]; then
    ruby -rjson -e '
        result = JSON.parse(File.read(ARGV[0]))
        File.open(ARGV[1], "a") do |file|
          file.puts "artifact_id=#{result.fetch("artifact_id")}"
          file.puts "artifact_digest=#{result.fetch("artifact_digest")}"
          file.puts "verification_level=#{result.fetch("verification_level")}"
          file.puts "effective_level=#{result.fetch("effective_level")}"
          file.puts "run_attempt=#{result.fetch("run_attempt")}"
        end
    ' "$RESULT_PATH" "$OUTPUT_VARS_PATH"
fi

echo "Candidate provenance accepted for run $SOURCE_RUN_ID."
