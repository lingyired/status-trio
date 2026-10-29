#!/usr/bin/env bash
# Fails closed when release-only CI regresses or publication gains build powers.
set -euo pipefail

ROOT="${STATUS_TRIO_RELEASE_POLICY_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKFLOW="$ROOT/.github/workflows/release.yml"
PUBLISH_SCRIPT="$ROOT/scripts/publish-release.sh"
PACKAGE_ENVIRONMENT="\${{ (inputs.publish || github.triggering_actor != 'lingyired') && 'distribution' || 'distribution-owner-signing' }}"

fail() {
    echo "release workflow policy check failed: $*" >&2
    exit 1
}

require_text() {
    local path="$1"
    local text="$2"
    grep -Fq -- "$text" "$path" || fail "$path must contain: $text"
}

forbid_text() {
    local path="$1"
    local text="$2"
    local rc
    [[ -f "$path" && -r "$path" ]] || fail "$path is missing or unreadable"
    if grep -Fq -- "$text" "$path"; then
        fail "$path must not contain: $text"
    else
        rc=$?
        [[ "$rc" == 1 ]] || fail "could not inspect $path"
    fi
}

[[ -f "$WORKFLOW" ]] || fail "release workflow is missing"
[[ -f "$PUBLISH_SCRIPT" ]] || fail "publish script is missing"

require_text "$WORKFLOW" "workflow_dispatch:"
require_text "$WORKFLOW" "candidate_sha:"
require_text "$WORKFLOW" "^[0-9a-f]{40}$"
require_text "$WORKFLOW" 'refs/heads/main'
require_text "$WORKFLOW" "ref: \${{ inputs.candidate_sha }}"
require_text "$WORKFLOW" "group: status-trio-release-publish"
require_text "$WORKFLOW" "  verify:"
require_text "$WORKFLOW" "  native:"
require_text "$WORKFLOW" "  package:"
require_text "$WORKFLOW" "  publish:"
require_text "$WORKFLOW" "needs: [verify, native]"
require_text "$WORKFLOW" "needs: [verify, native, package]"
require_text "$WORKFLOW" "$PACKAGE_ENVIRONMENT"
require_text "$WORKFLOW" "name: status-trio-release-package"
require_text "$WORKFLOW" "bash scripts/package-release.sh"
require_text "$WORKFLOW" "bash scripts/publish-release.sh"
require_text "$WORKFLOW" "RESOLVED_RELEASE_REPO: \${{ vars.RELEASE_REPO || 'lingyired/status-trio' }}"
require_text "$WORKFLOW" "RESOLVED_RELEASE_BRANCH: \${{ vars.RELEASE_BRANCH || 'main' }}"
require_text "$WORKFLOW" "NOTES_MODE=publish"
require_text "$WORKFLOW" "NOTES_MODE=package"
require_text "$WORKFLOW" "RELEASE_REPO: \${{ env.RESOLVED_RELEASE_REPO }}"
require_text "$WORKFLOW" "RELEASE_BRANCH: \${{ env.RESOLVED_RELEASE_BRANCH }}"
require_text "$WORKFLOW" "bash scripts/test.sh"
require_text "$WORKFLOW" "needs.verify.outputs.candidate_sha"
require_text "$WORKFLOW" "needs.verify.outputs.version"
require_text "$WORKFLOW" "needs.verify.outputs.build"
require_text "$WORKFLOW" "needs.verify.outputs.tag"
require_text "$WORKFLOW" "xcode-27"
require_text "$WORKFLOW" "/Applications/Xcode_27.app/Contents/Developer"
require_text "$WORKFLOW" "xcrun --sdk macosx --show-sdk-version"
if [[ "$(grep -c 'runs-on: xcode-27' "$WORKFLOW")" -ne 4 ]]; then
    fail "verify, native, package, and publish must all run on xcode-27"
fi
if grep -Eq '^    runs-on: (macos-|ubuntu-|windows-)' "$WORKFLOW"; then
    fail "release jobs must not fall back to a generic runner"
fi

for forbidden in \
    "push:" \
    "github.ref_name" \
    "github.event_name == 'push'" \
    "scripts/prepare-release-body.sh" \
    "gh release create --target" \
    "bash scripts/build-app.sh" \
    "hdiutil create" \
    "notarytool submit"; do
    forbid_text "$WORKFLOW" "$forbidden"
done

if ! grep -Eq '^      candidate_sha:$' "$WORKFLOW"; then
    fail "workflow must declare a candidate_sha input"
fi

for forbidden in \
    "swift build" \
    "bash scripts/build-app.sh" \
    "hdiutil create" \
    "notarytool submit" \
    "codesign --force" \
    "SKIP_SOURCE_SHA_CHECK" \
    "TEST_SPARKLE_METADATA"; do
    forbid_text "$PUBLISH_SCRIPT" "$forbidden"
done

for production_script in "$ROOT/scripts/package-release.sh" "$ROOT/scripts/release.sh"; do
    for forbidden in \
        "SKIP_SOURCE_SHA_CHECK" \
        "TEST_SPARKLE_METADATA" \
        "BUILD_APP=" \
        "VERIFY_PLATFORM="; do
        forbid_text "$production_script" "$forbidden"
    done
done

job_block() {
    local name="$1"
    awk -v name="$name" '
        BEGIN { in_job = 0; in_fence = 0 }
        /^  [A-Za-z0-9_-]+:$/ {
            in_job = ($0 == "  " name ":")
        }
        in_job { print }
    ' "$WORKFLOW"
}

VERIFY_BLOCK="$(job_block verify)"
NATIVE_BLOCK="$(job_block native)"
PACKAGE_BLOCK="$(job_block package)"
PUBLISH_BLOCK="$(job_block publish)"

[[ -n "$VERIFY_BLOCK" ]] || fail "verify job is missing"
[[ -n "$NATIVE_BLOCK" ]] || fail "native job is missing"
[[ -n "$PACKAGE_BLOCK" ]] || fail "package job is missing"
[[ -n "$PUBLISH_BLOCK" ]] || fail "publish job is missing"
if printf '%s\n' "$VERIFY_BLOCK" | grep -Eq '^[[:space:]]+swift test([[:space:]]|$)'; then
    fail "verify job must run scripts/test.sh so forbidden-pattern checks cannot be bypassed"
fi
for required_check in \
    "scripts/test-mobile-battery-source-cache.sh" \
    "scripts/test-mobile-battery-clang-version.sh" \
    "scripts/test-verify-local.sh" \
    "scripts/test-verify-local-bundle.sh" \
    "scripts/test-workflow-policy.sh"; do
    printf '%s\n' "$NATIVE_BLOCK" | grep -Fq "bash $required_check" ||
        fail "native job must run $required_check"
done
printf '%s\n' "$PACKAGE_BLOCK" | grep -Fq "      name: $PACKAGE_ENVIRONMENT" ||
    fail "package job must use the reviewed distribution environment for publication and the owner-only signing environment for diagnostics"
printf '%s\n' "$PUBLISH_BLOCK" | grep -Fq '      name: distribution' ||
    fail "publish job must use the protected distribution environment"
printf '%s\n' "$NATIVE_BLOCK" | grep -Fq 'bash scripts/test-release-notarization.sh' ||
    fail "native job must run the offline release notarization regressions"

printf '%s\n' "$VERIFY_BLOCK" | grep -Fxq '    outputs:' ||
    fail "verify job must declare workflow outputs"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 -Fx '    outputs:' |
    grep -Fq 'candidate_sha: ${{ steps.release.outputs.candidate_sha }}' ||
    fail "verify job must expose candidate_sha output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'version: ${{ steps.release.outputs.version }}' ||
    fail "verify job must expose version output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'build: ${{ steps.release.outputs.build }}' ||
    fail "verify job must expose build output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'tag: ${{ steps.release.outputs.tag }}' ||
    fail "verify job must expose tag output"

if printf '%s\n' "$VERIFY_BLOCK" | grep -Fq 'secrets.'; then
    fail "verify job must not receive secrets"
fi
if printf '%s\n' "$NATIVE_BLOCK" | grep -Fq 'secrets.'; then
    fail "native job must not receive secrets"
fi
if sed -n '/^permissions:$/,/^[^ ]/p' "$WORKFLOW" | grep -Fq 'contents: write'; then
    fail "workflow-level permissions must be read-only"
fi
if printf '%s\n' "$PACKAGE_BLOCK" | grep -Fq 'secrets.GITHUB_TOKEN'; then
    fail "package job must not publish with a GitHub write token"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'SPARKLE_PRIVATE_KEY|DEVELOPER_ID_CERTIFICATE|APPSTORE_CONNECT'; then
    fail "publish job must not receive build/signing/notarization secrets"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'swift build|build-app\.sh|hdiutil create|notarytool submit|codesign'; then
    fail "publish job must not rebuild, repackage, sign, or notarize"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'gh release (create|upload|edit)|update-appcast\.rb'; then
    fail "publish job must delegate publication to scripts/publish-release.sh"
fi

# Inspect actual steps as well as text so reordering or a conditional cannot
# leave a required command present but ineffective.
ruby -ryaml - "$WORKFLOW" <<'RUBY'
workflow = YAML.load_file(ARGV.fetch(0))
abort "release policy: workflow may not replace the executing Bash shell" unless
  workflow.fetch("defaults", {}).fetch("run", {}).fetch("shell", "bash") == "bash"
workflow.fetch("jobs").each do |name, job|
  abort "release policy: #{name} must use the release runner" unless job["runs-on"] == "xcode-27"
  abort "release policy: #{name} may not replace the executing Bash shell" unless
    job.fetch("defaults", {}).fetch("run", {}).fetch("shell", "bash") == "bash" &&
    job.fetch("steps").all? { |step| step.fetch("shell", "bash") == "bash" }
  job.fetch("env", {}).each do |variable, value|
    value.to_s.scan(/\$\{\{(.*?)\}\}/m).each do |expression|
      # Runner context is available in steps, but GitHub rejects it in job env.
      code = expression.first.gsub(/'(?:[^']|'')*'/, "")
      abort "release policy: runner context is unavailable in jobs.#{name}.env.#{variable}" if
        code.match?(/\brunner\s*(?:\.|\[)/)
    end
  end
end
verify = workflow.fetch("jobs").fetch("verify").fetch("steps")
candidate_step = verify.find { |s| s["name"] == "Validate frozen candidate and resolve release" }
abort "release policy: frozen candidate validation must enforce main dispatch" unless
  candidate_step && candidate_step.fetch("run").include?(%q{if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then})
names = verify.map { |step| step["name"] }
preflight = names.index("Run static release preflight")
tests = names.index("Run tests")
abort "release policy: static preflight must precede tests" unless preflight && tests && preflight < tests
abort "release policy: preflight and the full Swift suite must run unconditionally" if
  verify[preflight].key?("if") || verify[tests].key?("if")
abort "release policy: native contracts must run in the parallel native job" if
  names.include?("Run native and release-contract tests")
abort "release policy: test execution must preserve diagnostics and original exit code" unless
  verify[tests].fetch("run").strip == %q{bash "$CI_TOOLS_ROOT/scripts/ci-run-stage.sh" tests bash scripts/test.sh}
["Summarize verify diagnostics", "Upload verify diagnostics"].each do |name|
  step = verify.find { |item| item["name"] == name }
  abort "release policy: #{name} must run after failure" unless step && step["if"] == "always()"
  abort "release policy: #{name} must follow Swift tests" unless verify.index(step) > tests
end
["verify", "native", "package"].each do |job|
  config = workflow.fetch("jobs").fetch(job)
  abort "release policy: #{job} may not suppress failures" if
    config["continue-on-error"] || config.fetch("steps").any? { |step| step["continue-on-error"] }
end
%w[verify native].each do |job|
  config = workflow.fetch("jobs").fetch(job)
  abort "release policy: #{job} must not access an environment or skip verification" if
    config.key?("environment") || config.key?("if")
  permissions = config["permissions"]
  abort "release policy: #{job} token permissions must remain read-only" unless
    permissions.nil? || (permissions.is_a?(Hash) &&
      permissions.keys.all? { |scope| %w[actions contents].include?(scope) } &&
      permissions.values.all? { |access| %w[read none].include?(access) })
end
native_job = workflow.fetch("jobs").fetch("native")
native_steps = native_job.fetch("steps")
native = native_steps.find { |step| step["name"] == "Run native and release-contract tests" }
abort "release policy: native contracts must use the diagnostic stage wrapper" unless
  native && !native.key?("if")
native_lines = native.fetch("run").lines.map(&:strip)
expected_native = <<~COMMANDS.lines.map(&:strip)
  bash scripts/test-macos13-deployment-contract-regressions.sh
  bash scripts/test-macos13-deployment-contract.sh
  bash scripts/test-appcast-minimum-system-version.sh
  bash scripts/test-macos13-bundle-contract.sh
  bash scripts/test-privileged-helper-bundle-contract.sh
  bash scripts/test-mobile-battery-helper.sh
  bash scripts/test-mobile-battery-rpaths.sh
  bash scripts/test-otool-dependencies.sh
  bash scripts/test-macos13-sparkle-contract.sh
  bash scripts/test-mobile-battery-source-cache.sh
  bash "$CI_TOOLS_ROOT/scripts/test-mobile-battery-build-cache.sh"
  bash "$CI_TOOLS_ROOT/scripts/test-ci-diagnostics.sh"
  bash "$CI_TOOLS_ROOT/scripts/test-build-timing.sh"
  bash scripts/test-release-pipeline.sh
  bash scripts/test-release-notarization.sh
  bash scripts/test-mobile-battery-clang-version.sh
  bash scripts/test-verify-local.sh
  bash scripts/test-verify-local-bundle.sh
  bash scripts/test-workflow-policy.sh
COMMANDS
abort "release policy: native must run all 19 contracts unconditionally with strict diagnostics" unless
  native_lines.first == %q{bash "$CI_TOOLS_ROOT/scripts/ci-run-stage.sh" native bash -euo pipefail <<'NATIVE'} &&
  native_lines.last == "NATIVE" && native_lines[1...-1] == expected_native
recovery = verify.find { |step| step["name"] == "Run trusted release recovery regressions" }
abort "release policy: recovery must run both trusted regressions" unless
  recovery && recovery["if"] == "${{ inputs.package_run_id != '' }}" &&
  recovery.fetch("run").lines.map(&:strip) == [
    "set -euo pipefail",
    "bash release-tools/scripts/test-release-recovery.sh",
    "bash release-tools/scripts/test-release-pipeline.sh"
  ]
["Summarize native diagnostics", "Upload native diagnostics"].each do |name|
  step = native_steps.find { |item| item["name"] == name }
  abort "release policy: #{name} must run after failure" unless step && step["if"] == "always()"
  abort "release policy: #{name} must follow native contracts" unless
    native_steps.index(step) > native_steps.index(native)
end
native_summary = native_steps.find { |step| step["name"] == "Summarize native diagnostics" }
abort "release policy: native summary must identify the job and its status" unless
  native_summary.fetch("env", {})["JOB_STATUS"] == "${{ job.status }}" &&
  native_summary.fetch("env", {})["CI_DIAGNOSTIC_JOB"] == "native"
package_job = workflow.fetch("jobs").fetch("package")
abort "release policy: package must wait for verify and native" unless
  Array(package_job.fetch("needs")).sort == %w[native verify]
abort "release policy: package must preserve the default success dependency gate" unless
  package_job["if"] == "${{ inputs.package_run_id == '' }}"
publish_job = workflow.fetch("jobs").fetch("publish")
abort "release policy: publish must wait for verify, native, and package" unless
  Array(publish_job.fetch("needs")).sort == %w[native package verify]
abort "release policy: publish must require successful verification and a successful or recovered package" unless
  publish_job["if"] == "${{ !cancelled() && inputs.publish && needs.verify.result == 'success' && needs.native.result == 'success' && (inputs.package_run_id != '' || needs.package.result == 'success') }}"
package = workflow.fetch("jobs").fetch("package").fetch("steps")
build_index = package.index { |s| s["name"] == "Build, sign, notarize, and package once" }
validation = package.index { |s| s["name"] == "Validate native dependency caches before saving" }
abort "release policy: native cache save must follow successful package validation" unless
  build_index && validation && build_index < validation && !package[validation].key?("if")
%w[arm64 x86_64].each do |arch|
  %w[restore save].each do |operation|
    step = package.find { |s| s["uses"] == "actions/cache/#{operation}@v4" &&
      s.fetch("with", {})["key"] == "${{ steps.native-cache-keys.outputs.key_#{arch} }}" }
    abort "release policy: missing exact #{arch} cache #{operation}" unless step
    settings = step.fetch("with")
    expected = [".build/mobile-battery/#{arch}/prefix", ".build/mobile-battery/#{arch}/.dependencies-cache.json"]
    abort "release policy: cache may contain only one native prefix and its inventory" unless
      settings.fetch("path").lines.map(&:strip).reject(&:empty?) == expected
    abort "release policy: native release caches may not use fallback keys" if settings.key?("restore-keys")
    condition = "github.ref == 'refs/heads/main'"
    condition += " && steps.native-cache-#{arch}.outputs.cache-hit != 'true'" if operation == "save"
    abort "release policy: native cache writes/restores must be trusted main only" unless step["if"] == condition
    abort "release policy: native cache save precedes validation" if
      operation == "save" && package.index(step) <= validation
    abort "release policy: native cache restore must precede package build" if
      operation == "restore" && package.index(step) >= build_index
  end
end
abort "release policy: unexpected cache action in release jobs" unless
  package.count { |s| s.fetch("uses", "").start_with?("actions/cache") } == 4 &&
  workflow.fetch("jobs").reject { |name, _| name == "package" }.values.all? { |j|
    j.fetch("steps").none? { |s| s.fetch("uses", "").start_with?("actions/cache") }
  }
RUBY

echo "release workflow policy check passed"
