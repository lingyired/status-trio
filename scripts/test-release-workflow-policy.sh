#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioReleaseWorkflow.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "release workflow policy contract failed: $*" >&2
    exit 1
}

run_policy() {
    local root="$1"
    STATUS_TRIO_RELEASE_POLICY_ROOT="$root" \
        bash "$ROOT/scripts/check-release-workflow-policy.sh" >"$WORK/output.log" 2>&1
}

expect_failure() {
    local label="$1"
    shift
    if "$@" >"$WORK/output.log" 2>&1; then
        fail "$label was accepted"
    fi
}

make_fixture() {
    local fixture="$1"
    mkdir -p "$fixture/.github/workflows" "$fixture/scripts"
    cp "$ROOT/.github/workflows/release.yml" "$fixture/.github/workflows/release.yml"
    cp "$ROOT/scripts/publish-release.sh" "$fixture/scripts/publish-release.sh"
    cp "$ROOT/scripts/package-release.sh" "$fixture/scripts/package-release.sh"
    cp "$ROOT/scripts/release.sh" "$fixture/scripts/release.sh"
}

[[ -f "$ROOT/scripts/check-release-workflow-policy.sh" ]] ||
    fail "missing scripts/check-release-workflow-policy.sh"

valid="$WORK/valid"
make_fixture "$valid"
run_policy "$valid" || fail "valid release workflow fixture failed"

for mutation in missing-native-contract conditional-native-contract verify-environment \
    native-environment package-status-bypass package-formal-review-bypass \
    package-rerun-actor-bypass publish-environment publish-status-bypass \
    missing-recovery-regressions native-summary-status conditional-preflight \
    conditional-swift-tests native-shell workflow-shell job-shell verify-write-token \
    native-write-token early-native-summary wrong-native-runner; do
    invalid="$WORK/invalid-$mutation"
    make_fixture "$invalid"
    ruby -e '
      path, mutation = ARGV
      source = File.read(path)
      changed = case mutation
      when "missing-native-contract"
        source.sub!("          bash scripts/test-macos13-bundle-contract.sh\n", "")
      when "conditional-native-contract"
        source.sub!("      - name: Run native and release-contract tests\n",
          "      - name: Run native and release-contract tests\n        if: ${{ false }}\n")
      when "verify-environment", "native-environment"
        job = mutation.split("-").first
        source.sub!("  #{job}:\n", "  #{job}:\n    environment: distribution\n")
      when "package-status-bypass"
        source.sub!(%q{    if: ${{ inputs.package_run_id == '"'"''"'"' }}},
          %q{    if: ${{ always() && inputs.package_run_id == '"'"''"'"' }}})
      when "package-formal-review-bypass"
        source.sub!("inputs.publish || github.triggering_actor", "false || github.triggering_actor") or
          abort "package environment publication guard missing"
      when "package-rerun-actor-bypass"
        source.sub!("github.triggering_actor", "github.actor") or
          abort "package environment triggering actor missing"
      when "publish-environment"
        source.sub!(/(  publish:\n(?:.*\n)*?      name: )distribution/, %q{\1ci}) or
          abort "publish environment missing"
      when "publish-status-bypass"
        source.sub!(/(  publish:\n    if:).*/, %q{\1 ${{ always() && inputs.publish }}})
      when "missing-recovery-regressions"
        source.sub!("          bash release-tools/scripts/test-release-recovery.sh\n", "")
      when "native-summary-status"
        source.sub!(/(      - name: Summarize native diagnostics\n        if: always\(\)\n)(?:        env:\n(?:          [^\n]*\n)+)?/,
          "\\1        env:\n          JOB_STATUS: unknown\n")
      when "conditional-preflight", "conditional-swift-tests"
        name = mutation == "conditional-preflight" ? "Run static release preflight" : "Run tests"
        source.sub!("      - name: #{name}\n", "      - name: #{name}\n        if: ${{ false }}\n")
      when "native-shell"
        source.sub!("      - name: Run native and release-contract tests\n",
          "      - name: Run native and release-contract tests\n        shell: bash -n {0}\n")
      when "workflow-shell"
        source.sub!("jobs:\n", "defaults:\n  run:\n    shell: bash -n {0}\n\njobs:\n")
      when "job-shell"
        source.sub!("  native:\n", "  native:\n    defaults:\n      run:\n        shell: bash -n {0}\n")
      when "verify-write-token", "native-write-token"
        job = mutation.split("-").first
        source.sub!("  #{job}:\n", "  #{job}:\n    permissions:\n      contents: write\n")
      when "early-native-summary"
        summary = source[/^      - name: Summarize native diagnostics\n.*?(?=^      - name:|\z)/m] or
          abort "native summary missing"
        source.sub!(summary, "")
        source.sub!("      - name: Run native and release-contract tests\n",
          summary + "      - name: Run native and release-contract tests\n")
      when "wrong-native-runner"
        source.sub!("  native:\n    runs-on: xcode-27\n",
          "  native:\n    runs-on: [self-hosted, macOS]\n    # runs-on: xcode-27\n")
      end
      abort "fixture mutation did not apply: #{mutation}" unless changed
      File.write(path, source)
    ' "$invalid/.github/workflows/release.yml" "$mutation"
    expect_failure "$mutation" run_policy "$invalid"
done

invalid="$WORK/invalid-missing-package-script"
make_fixture "$invalid"
rm "$invalid/scripts/package-release.sh"
expect_failure "missing guarded package script" run_policy "$invalid"

invalid="$WORK/invalid-package-source-bypass"
make_fixture "$invalid"
printf '\nSKIP_SOURCE_SHA_CHECK=1\n' >> "$invalid/scripts/package-release.sh"
expect_failure "package source SHA bypass" run_policy "$invalid"

invalid="$WORK/invalid-job-runner-context"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/^      BUILD_TIMING_FILE:.*$/, "      BUILD_TIMING_FILE: ${{ runner.temp }}/status-trio-build-timings.tsv") or
    abort "package timing environment missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "runner context in job-level environment" run_policy "$invalid"

invalid="$WORK/invalid-push-trigger"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  workflow_dispatch:\n", "  push:\n    tags: [\"v*\"]\n  workflow_dispatch:\n") or
    abort "workflow_dispatch input missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "tag-push release trigger" run_policy "$invalid"

invalid="$WORK/invalid-candidate"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/^      candidate_sha:\n(?:.*\n){3}      version:\n/, "      version:\n") or
    abort "candidate input missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "workflow without required candidate SHA" run_policy "$invalid"

invalid="$WORK/invalid-workflow-ref"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!('"'"'"${GITHUB_REF}" != "refs/heads/main"'"'"', '"'"'"${GITHUB_REF}" != "refs/heads/release"'"'"') or
    abort "main dispatch guard missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "release dispatch outside main" run_policy "$invalid"

invalid="$WORK/invalid-verify-secret"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  needle = "  verify:\n"
  source.sub!(needle, needle + "    env:\n      LEAKED_SECRET: ${{ secrets.SPARKLE_PRIVATE_KEY }}\n") or
    abort "verify job missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "secret in verify job" run_policy "$invalid"

invalid="$WORK/invalid-verify-bypasses-test-wrapper"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(%q{run: bash "$CI_TOOLS_ROOT/scripts/ci-run-stage.sh" tests bash scripts/test.sh}, "run: swift test") or
    abort "test wrapper command missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "verify job bypassing scripts/test.sh" run_policy "$invalid"

invalid="$WORK/invalid-verify-missing-native-check"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          bash scripts/test-workflow-policy.sh\n", "") or
    abort "workflow policy regression command missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "native verification without workflow policy regression" run_policy "$invalid"

invalid="$WORK/invalid-package-skips-native"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("    needs: [verify, native]\n", "    needs: verify\n") or
    abort "parallel package dependency missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "package without native verification dependency" run_policy "$invalid"

invalid="$WORK/invalid-publish-skips-native"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("    needs: [verify, native, package]\n", "    needs: [verify, package]\n") or
    abort "parallel publish dependency missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "publish without native verification dependency" run_policy "$invalid"

invalid="$WORK/invalid-native-secret"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  needle = "  native:\n"
  source.sub!(needle, needle + "    env:\n      LEAKED_SECRET: ${{ secrets.SPARKLE_PRIVATE_KEY }}\n") or
    abort "native job missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "secret in native verification job" run_policy "$invalid"

invalid="$WORK/invalid-publish-build"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  needle = "  publish:\n    if:"
  source.sub!(needle, "  publish:\n    env:\n      UNSAFE: ${{ secrets.SPARKLE_PRIVATE_KEY }}\n    if:") or
    abort "publish job missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "release signing secret in publish job" run_policy "$invalid"

invalid="$WORK/invalid-concurrency"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("group: status-trio-release-publish", "group: release-${{ github.ref }}") or
    abort "fixed publish concurrency missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "ref-scoped publish concurrency" run_policy "$invalid"

invalid="$WORK/invalid-publish-rebuild"
make_fixture "$invalid"
printf '\nswift build\n' >> "$invalid/scripts/publish-release.sh"
expect_failure "publish script rebuild" run_policy "$invalid"

invalid="$WORK/invalid-package-command"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("bash scripts/package-release.sh", "bash scripts/release.sh") or
    abort "package command missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "package job bypassing package-release.sh" run_policy "$invalid"

invalid="$WORK/invalid-direct-publish"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("run: bash scripts/publish-release.sh", "run: gh release edit v1 --draft=false") or
    abort "publish command missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "publish job bypassing publish-release.sh" run_policy "$invalid"

invalid="$WORK/invalid-package-environment"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  package:\n    needs: [verify, native]\n    runs-on: xcode-27\n", "  package:\n    needs: [verify, native]\n    runs-on: xcode-27\n") or
    abort "package job missing"
  source.sub!(/^      name: .*distribution-owner-signing.*$/, "      name: ci") or
    abort "package environment missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "package without reviewed and owner environment split" run_policy "$invalid"

invalid="$WORK/invalid-verify-outputs"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/^    outputs:\n(?:      .*\n){4}/, "") or abort "verify outputs missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "verify job without declared outputs" run_policy "$invalid"

invalid="$WORK/invalid-test-failure-suppression"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Run tests\n", "      - name: Run tests\n        continue-on-error: true\n") or abort "tests missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "suppressed Swift test failure" run_policy "$invalid"

invalid="$WORK/invalid-summary-on-success-only"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Summarize verify diagnostics\n        if: always()", "      - name: Summarize verify diagnostics\n        if: success()") or abort "summary missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "diagnostics lost after failure" run_policy "$invalid"

invalid="$WORK/invalid-late-preflight"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  preflight = source.slice!(/      - name: Run static release preflight\n.*?(?=      - name: Run tests\n)/m) or abort "preflight missing"
  source.sub!(/(?=      - name: Run native and release-contract tests\n)/, preflight)
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "static preflight after expensive tests" run_policy "$invalid"

invalid="$WORK/invalid-broad-native-cache"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]; source = File.read(path)
  source.sub!(".build/mobile-battery/arm64/prefix", ".build/mobile-battery") or abort "cache path missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "cache including helper/package/source outputs" run_policy "$invalid"

invalid="$WORK/invalid-native-cache-fallback"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]; source = File.read(path)
  source.sub!("          key: ${{ steps.native-cache-keys.outputs.key_arm64 }}",
    "          restore-keys: status-trio-mobile-battery-\n          key: ${{ steps.native-cache-keys.outputs.key_arm64 }}") or abort "cache key missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "broad native restore-key fallback" run_policy "$invalid"

invalid="$WORK/invalid-untrusted-native-cache"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]; source = File.read(path)
  source.sub!("        if: github.ref == '"'"'refs/heads/main'"'"'\n", "") or abort "cache trust guard missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "cache restore without trusted-main guard" run_policy "$invalid"

echo "release workflow policy regressions passed"
