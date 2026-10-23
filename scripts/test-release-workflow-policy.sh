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
}

[[ -f "$ROOT/scripts/check-release-workflow-policy.sh" ]] ||
    fail "missing scripts/check-release-workflow-policy.sh"

valid="$WORK/valid"
make_fixture "$valid"
run_policy "$valid" || fail "valid release workflow fixture failed"

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
  source.sub!("          bash scripts/test.sh\n", "          swift test\n") or
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
expect_failure "verify job without workflow policy regression" run_policy "$invalid"

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
  source.sub!("  package:\n    needs: verify\n    runs-on: xcode-27\n", "  package:\n    needs: verify\n    runs-on: xcode-27\n") or
    abort "package job missing"
  source.sub!("      name: distribution\n", "      name: ci\n") or
    abort "package environment missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "package without distribution environment" run_policy "$invalid"

invalid="$WORK/invalid-verify-outputs"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/^    outputs:\n(?:      .*\n){4}/, "") or abort "verify outputs missing"
  File.write(path, source)
' "$invalid/.github/workflows/release.yml"
expect_failure "verify job without declared outputs" run_policy "$invalid"

echo "release workflow policy regressions passed"
