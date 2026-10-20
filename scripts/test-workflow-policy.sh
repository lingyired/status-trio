#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioWorkflowPolicy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "workflow policy contract failed: $*" >&2
    exit 1
}

run_policy() {
    local root="$1"
    STATUS_TRIO_POLICY_ROOT="$root" bash "$ROOT/scripts/check-workflow-policy.sh" >"$WORK/output.log" 2>&1
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
    mkdir -p "$fixture/.agents/rules" "$fixture/.github"
    cp "$ROOT/AGENTS.md" "$fixture/AGENTS.md"
    cp "$ROOT/.github/pull_request_template.md" "$fixture/.github/pull_request_template.md"
    cp "$ROOT/.agents/rules/"*.md "$fixture/.agents/rules/"
    cat > "$fixture/scripts-test" <<'SH'
#!/usr/bin/env bash
SH
}

if [[ ! -f "$ROOT/scripts/check-workflow-policy.sh" ]]; then
    fail "missing scripts/check-workflow-policy.sh"
fi

valid="$WORK/valid"
make_fixture "$valid"
run_policy "$valid" || fail "valid workflow policy fixture failed"

for phrase in \
    "Before committing Swift changes" \
    "run a non-publishing release workflow before merging" \
    "must be added to" \
    "The release workflow is the acceptance environment"; do
    invalid="$WORK/invalid-$(printf '%s' "$phrase" | tr ' ' '-')"
    make_fixture "$invalid"
    printf '\n%s\n' "$phrase" >> "$invalid/AGENTS.md"
    expect_failure "stale AGENTS policy: $phrase" run_policy "$invalid"
done

invalid="$WORK/invalid-missing-rule"
make_fixture "$invalid"
rm "$invalid/.agents/rules/performance.md"
expect_failure "missing mapped rule file" run_policy "$invalid"

invalid="$WORK/invalid-missing-evidence"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/^## Verification\n.*?(?=^## )/m, "") or abort "missing verification section"
  File.write(path, source)
' "$invalid/.github/pull_request_template.md"
expect_failure "PR template without verification evidence" run_policy "$invalid"

invalid="$WORK/invalid-bypass"
make_fixture "$invalid"
printf '\nRelease CI is not required before publishing.\n' >> "$invalid/AGENTS.md"
expect_failure "release CI bypass" run_policy "$invalid"

invalid="$WORK/invalid-mode-contract"
make_fixture "$invalid"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  needle = "`bash scripts/verify-local.sh <quick|docs|full> [swift-test-filter]`"
  replacement = "`bash scripts/verify-local.sh <quick|full> [swift-test-filter]`"
  source.sub!(needle, replacement) or abort "missing verification mode contract"
  File.write(path, source)
' "$invalid/AGENTS.md"
expect_failure "verification mode contract without docs" run_policy "$invalid"

echo "workflow policy contract passed"
