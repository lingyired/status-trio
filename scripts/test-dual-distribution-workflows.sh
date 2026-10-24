#!/usr/bin/env bash
# Offline negative-first contract tests for the two dual-distribution workflows.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioDualDistributionWorkflows.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

CHECKER="$ROOT/scripts/check-dual-distribution-workflows.py"
PR_SOURCE="$ROOT/.github/workflows/pr-checks.yml"
STORE_SOURCE="$ROOT/.github/workflows/app-store.yml"
SCENARIOS=0
PASSED=0
SEMANTIC_SCENARIOS=0
SEMANTIC_PASSED=0
SHELL_SCENARIOS=0
SHELL_PASSED=0

fail() {
    echo "dual-distribution workflow contract failed: $*" >&2
    exit 1
}

run_policy() {
    local pr="$1"
    local store="$2"
    python3 "$CHECKER" --pr "$pr" --store "$store"
}

make_fixture() {
    local name="$1"
    local fixture="$WORK/$name"
    mkdir -p "$fixture"
    cp "$PR_SOURCE" "$fixture/pr-checks.yml"
    cp "$STORE_SOURCE" "$fixture/app-store.yml"
    printf '%s\n' "$fixture"
}

expect_success() {
    local label="$1"
    local pr="$2"
    local store="$3"
    SCENARIOS=$((SCENARIOS + 1))
    if ! run_policy "$pr" "$store" >"$WORK/output.log" 2>&1; then
        cat "$WORK/output.log" >&2
        fail "$label was rejected"
    fi
    PASSED=$((PASSED + 1))
    SEMANTIC_SCENARIOS=$((SEMANTIC_SCENARIOS + 1))
    SEMANTIC_PASSED=$((SEMANTIC_PASSED + 1))
}

expect_failure() {
    local label="$1"
    local pr="$2"
    local store="$3"
    local expected="${4:-}"
    SCENARIOS=$((SCENARIOS + 1))
    if run_policy "$pr" "$store" >"$WORK/output.log" 2>&1; then
        fail "$label was accepted"
    fi
    if [[ -n "$expected" ]] && ! grep -Fq -- "$expected" "$WORK/output.log"; then
        cat "$WORK/output.log" >&2
        fail "$label failed for the wrong reason; expected: $expected"
    fi
    PASSED=$((PASSED + 1))
    SEMANTIC_SCENARIOS=$((SEMANTIC_SCENARIOS + 1))
    SEMANTIC_PASSED=$((SEMANTIC_PASSED + 1))
}

[[ -f "$CHECKER" ]] || fail "missing $CHECKER"
[[ -f "$PR_SOURCE" ]] || fail "missing $PR_SOURCE"
[[ -f "$STORE_SOURCE" ]] || fail "missing $STORE_SOURCE"

# Red baselines must fail before the candidate workflows are accepted.
printf 'name: placeholder\n' > "$WORK/empty-pr.yml"
printf 'name: placeholder\n' > "$WORK/empty-store.yml"
expect_failure "empty workflows" "$WORK/empty-pr.yml" "$WORK/empty-store.yml" "workflow must declare an on: trigger"
printf 'name: placeholder\n' > "$WORK/placeholder-pr.yml"
printf 'name: placeholder\n' > "$WORK/placeholder-store.yml"
if python3 "$CHECKER" --pr "$WORK/placeholder-pr.yml" --store "$WORK/placeholder-store.yml" >"$WORK/output.log" 2>&1; then
    fail "red baseline placeholder workflows were accepted"
fi

fixture="$(make_fixture valid)"
expect_success "valid dual-distribution workflows" "$fixture/pr-checks.yml" "$fixture/app-store.yml"

fixture="$(make_fixture push-trigger)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("on:\n  pull_request:\n", "on:\n  pull_request:\n  push:\n    branches: [main]\n") or
    abort "pull_request trigger missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR workflow with push trigger" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "trigger must be pull_request only"

fixture="$(make_fixture pull-request-target)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  pull_request:\n", "  pull_request_target:\n") or abort "pull_request trigger missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "pull_request_target trigger" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "trigger must be pull_request only"

fixture="$(make_fixture job-permissions)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("    steps:\n", "    permissions:\n      contents: write\n    steps:\n") or
    abort "direct steps missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "job-level write permission" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "job-level permissions override"

fixture="$(make_fixture production-secret)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Run Direct full local verification\n", "      - name: Leak a production secret\n        env:\n          PRODUCTION_SECRET: ${{ secrets.SPARKLE_PRIVATE_KEY }}\n        run: echo unsafe\n\n      - name: Run Direct full local verification\n") or
    abort "direct verification step missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "production secret in PR workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not reference secrets or repository variables"

fixture="$(make_fixture no-space-secret)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Run Direct full local verification\n", "      - name: Leak a production secret\n        env:\n          PRODUCTION_SECRET: ${{secrets.SPARKLE_PRIVATE_KEY}}\n        run: echo unsafe\n\n      - name: Run Direct full local verification\n") or
    abort "direct verification step missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "no-space secret expression" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not reference secrets or repository variables"

fixture="$(make_fixture bracket-variable)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          persist-credentials: false\n", "          persist-credentials: false\n          repository: ${{vars[\"REPOSITORY\"]}}\n") or
    abort "direct checkout options missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "bracket repository variable expression" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not reference secrets or repository variables"

fixture="$(make_fixture pr-title-expression)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Validate dual-distribution workflow policy\n", "      - name: Unsafe PR metadata\n        env:\n          PR_TITLE: ${{github.event.pull_request.title}}\n        run: echo unsafe\n\n      - name: Validate dual-distribution workflow policy\n") or
    abort "PR policy step missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR title expression" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not use untrusted PR title or body metadata"

fixture="$(make_fixture distribution-environment)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  store:\n    name:", "  store:\n    environment:\n      name: distribution\n    name:") or
    abort "store job missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "distribution environment in PR workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not use an environment"

fixture="$(make_fixture wrong-checkout-sha)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          ref: ${{ github.sha }}", "          ref: ${{ github.event.pull_request.head.sha }}") or
    abort "merge SHA checkout missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR checkout from head SHA" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "checkout ref must be"

fixture="$(make_fixture event-merge-sha)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  PR_MERGE_SHA: ${{ github.sha }}\n", "  PR_MERGE_SHA: ${{ github.event.pull_request.merge_commit_sha }}\n") or
    abort "PR merge SHA env missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR merge SHA from empty event context" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "PR_MERGE_SHA must come from github.sha"

fixture="$(make_fixture sha-not-reasserted)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          if [[ \"${ACTUAL_SHA}\" != \"${PR_MERGE_SHA}\" ]]; then", "          if false; then") or
    abort "SHA assertion missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR SHA assertion removed" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "checkout does not enforce"

fixture="$(make_fixture direct-skipped)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  direct:\n    name:", "  direct:\n    if: ${{ false }}\n    name:") or abort "direct job missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "direct job conditionally skipped" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not have a job-level if condition"

fixture="$(make_fixture store-skipped)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  store:\n    name:", "  store:\n    if: ${{ false }}\n    name:") or abort "store job missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "store job conditionally skipped" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not have a job-level if condition"

fixture="$(make_fixture path-filter)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("on:\n  pull_request:\n", "on:\n  pull_request:\n    paths:\n      - \"Sources/**\"\n") or
    abort "pull_request trigger missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "path-filtered PR workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must run for every path"

fixture="$(make_fixture inline-path-filter)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("on:\n  pull_request:\n", "on:\n  pull_request:\n    paths: [\"Sources/**\"]\n") or
    abort "pull_request trigger missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "inline path-filtered PR workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must run for every path"

fixture="$(make_fixture branch-filter)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("on:\n  pull_request:\n", "on:\n  pull_request:\n    branches: [main]\n") or
    abort "pull_request trigger missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "branch-filtered PR workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must run for every path"

fixture="$(make_fixture action-type-filter)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("on:\n  pull_request:\n", "on:\n  pull_request:\n    types: [opened]\n") or
    abort "pull_request trigger missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "action-filtered PR workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must run for every path"

fixture="$(make_fixture toolchain-unpinned)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("\"${SDK_MAJOR}\" -ge 26", "\"${SDK_MAJOR}\" -ge 25") or abort "SDK threshold missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "unsafe SDK fallback" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "toolchain selection is missing"

fixture="$(make_fixture toolchain-direct-swift-path)"
ruby -e '
  ARGV.each do |path|
    source = File.read(path)
    source.sub!(
      "DEVELOPER_DIR=\"${DEVELOPER_CANDIDATE}\" xcrun --sdk macosx swift --version",
      "DEVELOPER_DIR=\"${DEVELOPER_CANDIDATE}\" \"${DEVELOPER_CANDIDATE}/usr/bin/swift\" --version"
    ) or abort "xcrun Swift probe missing in #{path}"
    File.write(path, source)
  end
' "$fixture/pr-checks.yml" "$fixture/app-store.yml"
expect_failure "toolchain direct Swift path" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must resolve Swift through xcrun"

fixture="$(make_fixture store-bypassed)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          APP_STORE_UNSIGNED=1 \\\n            APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \\\n            bash scripts/build-app-store.sh release no-open", "          echo skipped") or
    abort "Store build command missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Store build bypassed" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "store job is missing"

fixture="$(make_fixture direct-missing-xcodegen)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Install pinned XcodeGen 2.46.0\n", "      - name: Omit pinned XcodeGen\n") or
    abort "Store XcodeGen install missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Direct full verification without pinned XcodeGen" \
    "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must install pinned XcodeGen"

fixture="$(make_fixture pr-store-unsigned-removed)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          APP_STORE_UNSIGNED=1 \\\n            APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \\\n            bash scripts/build-app-store.sh release no-open", "          APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \\\n            bash scripts/build-app-store.sh release no-open") or
    abort "Store unsigned build command missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR Store unsigned flag removed" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "APP_STORE_UNSIGNED=1"

fixture="$(make_fixture pr-store-archive-removed)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          APP_STORE_UNSIGNED=1 \\\n            APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \\\n            bash scripts/build-app-store.sh release no-open", "          APP_STORE_UNSIGNED=1 \\\n            bash scripts/build-app-store.sh release no-open") or
    abort "Store archive path missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR Store dSYM audit without archive build" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "store job is missing"

fixture="$(make_fixture pr-store-signing-identity)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  store:\n    name:", "  store:\n    env:\n      APP_STORE_SIGNING_IDENTITY: \"Developer ID Application\"\n    name:") or
    abort "store job missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR Store signing identity" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not provide signing identities"

fixture="$(make_fixture pr-store-dsym-removed)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/      - name: Verify archived Store dSYMs\n(?:        .*\n|\n)*?(?=      - name: Verify Store source closure\n)/, "") or
    abort "Store dSYM step missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "PR Store dSYM audit removed" \
    "$fixture/pr-checks.yml" "$fixture/app-store.yml" "store job is missing"

fixture="$(make_fixture archive-dsym-removed)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/      - name: Verify archived Store dSYMs\n(?:        .*\n|\n)*?(?=      - name: Verify Store source closure\n)/, "") or
    abort "archive dSYM step missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive dSYM audit removed" \
    "$fixture/pr-checks.yml" "$fixture/app-store.yml" "archive job is missing exactly one executable command"

while IFS='|' read -r slug step_name; do
  fixture="$(make_fixture "continue-on-error-$slug")"
  ruby -e '
    path, step_name = ARGV
    source = File.read(path)
    needle = "      - name: #{step_name}\n        shell: bash\n"
    replacement = "      - name: #{step_name}\n        continue-on-error: true\n        shell: bash\n"
    source.sub!(needle, replacement) or abort "step missing: #{step_name}"
    File.write(path, source)
  ' "$fixture/pr-checks.yml" "$step_name"
  expect_failure "continue-on-error $step_name" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not use continue-on-error"
done <<'EOF'
direct-full|Run Direct full local verification
store-project|Test Store project contract
store-bundle-fixtures|Test Store bundle audit fixtures
store-source-fixtures|Test Store source closure negative fixtures
store-build|Build unsigned Store archive
store-bundle-audit|Verify unsigned Store bundle statically
store-source-audit|Verify Store source closure
EOF

fixture="$(make_fixture direct-job-continue-on-error)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  direct:\n    name:", "  direct:\n    continue-on-error: true\n    name:") or
    abort "direct job missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Direct job continue-on-error" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not use continue-on-error"

fixture="$(make_fixture direct-command-only-in-comment)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          bash scripts/verify-local.sh full 2>&1 | tee -a .build/ci-logs/direct-full.log\n", "          # bash scripts/verify-local.sh full 2>&1 | tee -a .build/ci-logs/direct-full.log\n") or
    abort "Direct verification command missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Direct command only in shell comment" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "direct job is missing exactly one executable command"

fixture="$(make_fixture direct-command-behind-false-condition)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          bash scripts/verify-local.sh full 2>&1 | tee -a .build/ci-logs/direct-full.log\n", "          if false; then\n            bash scripts/verify-local.sh full 2>&1 | tee -a .build/ci-logs/direct-full.log\n          fi\n") or
    abort "Direct verification command missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Direct command behind false condition" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "unsupported control flow or executable content"

fixture="$(make_fixture store-command-only-in-comment)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          bash scripts/test-app-store-project-contract.sh 2>&1 | tee .build/ci-logs/app-store-project-contract.log\n", "          # bash scripts/test-app-store-project-contract.sh 2>&1 | tee .build/ci-logs/app-store-project-contract.log\n") or
    abort "Store project command missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Store command only in shell comment" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "store job is missing exactly one executable command"

fixture="$(make_fixture missing-source-closure)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          python3 scripts/verify-app-store-source-closure.py .build/app-store/source-membership.json 2>&1 | tee .build/ci-logs/app-store-source-closure.log\n", "") or
    abort "source closure command missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Store source closure omitted" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "store job is missing"

fixture="$(make_fixture missing-source-closure-fixtures)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          bash scripts/test-app-store-source-closure.sh 2>&1 | tee .build/ci-logs/app-store-source-closure-contract.log\n", "") or
    abort "source closure fixture command missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Store source closure fixtures omitted" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "store job is missing"

fixture="$(make_fixture missing-app-store-source-closure-fixtures)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          bash scripts/test-app-store-source-closure.sh 2>&1 | tee .build/ci-logs/app-store-source-closure-contract.log\n", "") or
    abort "source closure fixture command missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "App Store source closure fixtures omitted" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "archive job is missing exactly one executable command"

fixture="$(make_fixture xcodegen-brew-latest)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("PREFIX=\"${TOOL_ROOT}\" bash \"${EXTRACT}/xcodegen/install.sh\"", "brew install xcodegen") or
    abort "pinned XcodeGen install missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "unpinned Homebrew XcodeGen" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "pinned XcodeGen install is missing"

fixture="$(make_fixture xcodegen-tool-root-uncreated)"
ruby -e '
  ARGV.each do |path|
    source = File.read(path)
    source.sub!("          mkdir -p \"${TOOL_ROOT}\"\n          PREFIX=\"${TOOL_ROOT}\"", "          PREFIX=\"${TOOL_ROOT}\"") or
      abort "XcodeGen tool root creation missing in #{path}"
    File.write(path, source)
  end
' "$fixture/pr-checks.yml" "$fixture/app-store.yml"
expect_failure "XcodeGen tool root not created" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "pinned XcodeGen install is missing"

fixture="$(make_fixture xcodegen-checksum)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  XCODEGEN_ARCHIVE_SHA256: \"4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806\"\n", "  XCODEGEN_ARCHIVE_SHA256: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n") or
    abort "XcodeGen checksum missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "guessed XcodeGen checksum" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "XCODEGEN_ARCHIVE_SHA256 must be exactly"

fixture="$(make_fixture xcodegen-version)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  XCODEGEN_VERSION: \"2.46.0\"\n", "  XCODEGEN_VERSION: \"2.47.0\"\n") or
    abort "XcodeGen version missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "moving XcodeGen minor" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "XCODEGEN_VERSION must be exactly 2.46.0"

fixture="$(make_fixture xcodegen-version-substring)"
ruby -e '
  ARGV.each do |path|
    source = File.read(path)
    source.sub!("if [[ \"${ACTUAL_XCODEGEN_VERSION}\" != \"${XCODEGEN_VERSION}\" ]]; then", "if [[ \"${ACTUAL_XCODEGEN_VERSION}\" != \"${XCODEGEN_VERSION}\"* ]]; then") or
      abort "exact XcodeGen comparison missing in #{path}"
    File.write(path, source)
  end
' "$fixture/pr-checks.yml" "$fixture/app-store.yml"
expect_failure "XcodeGen substring comparison" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "pinned XcodeGen install is missing"

fixture="$(make_fixture xcodegen-normalization-removed)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          ACTUAL_XCODEGEN_VERSION=\"${ACTUAL_XCODEGEN_VERSION#Version: }\"\n", "") or
    abort "XcodeGen version normalization missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "XcodeGen normalization removed" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "ACTUAL_XCODEGEN_VERSION"

fixture="$(make_fixture xcodegen-version-hardcoded)"
ruby -e '
  ARGV.each do |path|
    source = File.read(path)
    source.sub!("ACTUAL_XCODEGEN_VERSION=\"$(\"${TOOL_ROOT}/bin/xcodegen\" --version 2>&1 | head -n 1)\"", "ACTUAL_XCODEGEN_VERSION=\"2.46.0\"") or
      abort "runtime XcodeGen capture missing in #{path}"
    File.write(path, source)
  end
' "$fixture/pr-checks.yml" "$fixture/app-store.yml"
expect_failure "XcodeGen version hard-coded without runtime capture" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "pinned XcodeGen install is missing ACTUAL_XCODEGEN_VERSION"

fixture="$(make_fixture xcodegen-version-overridden)"
ruby -e '
  ARGV.each do |path|
    source = File.read(path)
    needle = "ACTUAL_XCODEGEN_VERSION=\"${ACTUAL_XCODEGEN_VERSION#Version: }\"\n"
    source.sub!(needle, needle + "          ACTUAL_XCODEGEN_VERSION=\"${XCODEGEN_VERSION}\"\n") or
      abort "XcodeGen normalization missing in #{path}"
    File.write(path, source)
  end
' "$fixture/pr-checks.yml" "$fixture/app-store.yml"
expect_failure "XcodeGen runtime capture overridden" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "unexpected assignment outside the runtime capture"

fixture="$(make_fixture xcodegen-latest-url)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("/releases/download/2.46.0/xcodegen.zip", "/releases/latest/download/xcodegen.zip") or
    abort "XcodeGen release URL missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "XcodeGen latest release URL" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "XCODEGEN_ARCHIVE_URL must be exactly"

fixture="$(make_fixture unexpected-pr-network)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Validate dual-distribution workflow policy\n", "      - name: Fetch untrusted content\n        run: curl -fsSL https://example.invalid/payload\n\n      - name: Validate dual-distribution workflow policy\n") or
    abort "PR policy step missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "unexpected network access in PR workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "network access is limited to the pinned XcodeGen install"

fixture="$(make_fixture unexpected-store-network)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("      - name: Test Store project contract\n", "      - name: Fetch untrusted content\n        run: wget https://example.invalid/payload\n\n      - name: Test Store project contract\n") or
    abort "Store contract step missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "unexpected network access in archive workflow" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "archive network access is limited to the pinned XcodeGen install"

fixture="$(make_fixture direct-hidden-logs-omitted)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          include-hidden-files: true\n          if-no-files-found: warn\n          retention-days: 7\n", "          if-no-files-found: warn\n          retention-days: 7\n") or
    abort "Direct diagnostic upload options missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Direct hidden diagnostic logs omitted" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "include-hidden-files: true"

fixture="$(make_fixture store-hidden-logs-omitted)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(
    "          name: app-store-pr-diagnostic-logs\n          path: |\n            .build/ci-logs/\n            .build/app-store/*.log\n          include-hidden-files: true\n",
    "          name: app-store-pr-diagnostic-logs\n          path: |\n            .build/ci-logs/\n            .build/app-store/*.log\n"
  ) or
    abort "Store diagnostic upload options missing"
  File.write(path, source)
' "$fixture/pr-checks.yml"
expect_failure "Store hidden diagnostic logs omitted" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "include-hidden-files: true"

fixture="$(make_fixture archive-hidden-output-omitted)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          include-hidden-files: true\n          if-no-files-found: error\n", "          if-no-files-found: error\n") or
    abort "unsigned archive upload options missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "unsigned archive hidden output omitted" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "include-hidden-files: true"

fixture="$(make_fixture archive-hidden-logs-omitted)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          include-hidden-files: true\n          if-no-files-found: warn\n", "          if-no-files-found: warn\n") or
    abort "archive log upload options missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive hidden diagnostic logs omitted" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "include-hidden-files: true"

fixture="$(make_fixture archive-upload-hidden-but-overbroad)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("            .build/app-store/StatusTrio.xcarchive\n", "            .\n") or
    abort "unsigned archive upload path missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "unsigned archive uploads whole repository" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "exact diagnostic path allowlist"

fixture="$(make_fixture archive-upload-unrelated-build-path)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("            .build/app-store/StatusTrio.xcarchive\n", "            .build/private-diagnostic-output\n") or
    abort "unsigned archive upload path missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "unsigned archive uploads an unrelated build path" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "exact diagnostic path allowlist"

fixture="$(make_fixture input-shell-interpolation)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          echo \"Frozen candidate: ${CANDIDATE_SHA}\"\n", "          echo ${{ inputs.candidate_sha }}\n") or
    abort "candidate validation output missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "dispatch input interpolated into shell" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "interpolates untrusted inputs or event data"

fixture="$(make_fixture bracket-input-shell-interpolation)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          echo \"Frozen candidate: ${CANDIDATE_SHA}\"\n", "          echo ${{inputs['candidate_sha']}}\n") or
    abort "candidate validation output missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "bracket input interpolated into shell" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "interpolates untrusted inputs or event data"

fixture="$(make_fixture event-input-shell-interpolation)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          echo \"Frozen candidate: ${CANDIDATE_SHA}\"\n", "          echo ${{ github.event.inputs.candidate_sha }}\n") or
    abort "candidate validation output missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "github event input interpolated into shell" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "interpolates untrusted inputs or event data"

fixture="$(make_fixture dispatch-store-publish)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  workflow_dispatch:\n", "  workflow_dispatch:\n  push:\n    tags: [\"v*\"]\n") or
    abort "workflow_dispatch trigger missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "Store workflow tag trigger" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "trigger must be workflow_dispatch only"

fixture="$(make_fixture archive-write)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  contents: read\n", "  contents: write\n") or abort "contents permission missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "Store workflow write permission" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "permissions must be exactly"

fixture="$(make_fixture unsigned-disabled)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          APP_STORE_UNSIGNED=1 \\\n            APP_STORE_ARCHIVE_PATH", "          APP_STORE_UNSIGNED=0 \\\n            APP_STORE_ARCHIVE_PATH") or
    abort "unsigned archive command missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "signed archive claimed as unsigned" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "archive job is missing exactly one executable command"

fixture="$(make_fixture archive-default-signing)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          APP_STORE_UNSIGNED=1 \\\n            APP_STORE_ARCHIVE_PATH", "          APP_STORE_ARCHIVE_PATH") or
    abort "unsigned archive command missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive without unsigned flag" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "archive job is missing exactly one executable command"

while IFS='|' read -r slug step_name; do
  fixture="$(make_fixture "archive-continue-on-error-$slug")"
  ruby -e '
    path, step_name = ARGV
    source = File.read(path)
    needle = "      - name: #{step_name}\n        shell: bash\n"
    replacement = "      - name: #{step_name}\n        continue-on-error: true\n        shell: bash\n"
    source.sub!(needle, replacement) or abort "step missing: #{step_name}"
    File.write(path, source)
  ' "$fixture/app-store.yml" "$step_name"
  expect_failure "archive continue-on-error $step_name" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not use continue-on-error"
done <<'EOF'
build|Build unsigned Store archive
bundle-audit|Verify unsigned Store app statically
source-audit|Verify Store source closure
EOF

fixture="$(make_fixture archive-job-continue-on-error)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  archive:\n    name:", "  archive:\n    continue-on-error: true\n    name:") or
    abort "archive job missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive job continue-on-error" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not use continue-on-error"

fixture="$(make_fixture archive-command-only-in-comment)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          python3 scripts/verify-app-store-source-closure.py .build/app-store/source-membership.json 2>&1 | tee .build/ci-logs/app-store-source-closure.log\n", "          # python3 scripts/verify-app-store-source-closure.py .build/app-store/source-membership.json 2>&1 | tee .build/ci-logs/app-store-source-closure.log\n") or
    abort "archive source closure command missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive command only in shell comment" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "archive job is missing exactly one executable command"

fixture="$(make_fixture archive-release-env)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("    timeout-minutes: 75\n    env:\n", "    timeout-minutes: 75\n    environment:\n      name: distribution\n    env:\n") or
    abort "archive env missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive using production environment" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not use the distribution environment"

fixture="$(make_fixture archive-job-skipped)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("  archive:\n    name:", "  archive:\n    if: ${{ false }}\n    name:") or
    abort "archive job missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive job conditionally skipped" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not have a job-level if condition"

fixture="$(make_fixture archive-unbounded-timeout)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("    timeout-minutes: 75\n", "    timeout-minutes: 180\n") or
    abort "archive timeout missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive unbounded timeout" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "finite timeout of at most 90 minutes"

fixture="$(make_fixture archive-upload-step)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source << "\n      - name: Unsafe upload\n        run: xcrun altool --upload-app --file dist/AppStore/StatusTrio.app\n"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive workflow with ASC upload" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not contain 'xcrun altool'"

fixture="$(make_fixture archive-tag-push)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source << "\n      - name: Unsafe publish\n        run: git tag v9.9.9 && git push --tags\n"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive workflow with tag push" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "must not contain 'git push'"

fixture="$(make_fixture archive-run-number)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          echo \"Store candidate: ${VERSION_INPUT} (${BUILD_INPUT})\"\n", "          echo \"Store candidate: ${VERSION_INPUT} (${GITHUB_RUN_NUMBER})\"\n") or
    abort "Store candidate output missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive deriving build from run number" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "workflow run number"

fixture="$(make_fixture archive-missing-input)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!(/      build:\n(?:.*\n){3}/, "") or abort "build input missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive without explicit build input" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "workflow_dispatch input build:"

fixture="$(make_fixture archive-candidate-mismatch)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          ref: ${{ inputs.candidate_sha }}", "          ref: main") or abort "candidate checkout missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive checkout not frozen" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "checkout ref must be"

fixture="$(make_fixture archive-not-main)"
ruby -e '
  path = ARGV[0]
  source = File.read(path)
  source.sub!("          if [[ \"${GITHUB_REF}\" != \"refs/heads/main\" ]]; then", "          if [[ \"${GITHUB_REF}\" != \"refs/heads/release\" ]]; then") or
    abort "main ref guard missing"
  File.write(path, source)
' "$fixture/app-store.yml"
expect_failure "archive dispatch outside main" "$fixture/pr-checks.yml" "$fixture/app-store.yml" "frozen candidate validation is missing"

for workflow in "$PR_SOURCE" "$STORE_SOURCE"; do
    scripts_dir="$WORK/embedded-$(basename -- "$workflow" .yml)"
    rm -rf "$scripts_dir"
    mkdir -p "$scripts_dir"
    ruby -ryaml -e '
      workflow_path, output_dir = ARGV
      workflow = YAML.load_file(workflow_path)
      index = 0
      workflow.fetch("jobs").each do |job_name, job|
        job.fetch("steps", []).each do |step|
          script = step["run"]
          next unless script
          index += 1
          safe_job = job_name.gsub(/[^[:alnum:]]/, "_")
          path = File.join(output_dir, format("%03d-%s.sh", index, safe_job))
          File.write(path, script)
          puts(path)
        end
      end
    ' "$workflow" "$scripts_dir" > "$WORK/embedded-scripts.list"

    while IFS= read -r script_path; do
        [[ -n "$script_path" ]] || continue
        SCENARIOS=$((SCENARIOS + 1))
        if ! bash -n "$script_path" >"$WORK/output.log" 2>&1; then
            cat "$WORK/output.log" >&2
            fail "embedded shell syntax failed: $(basename -- "$workflow"): $(basename -- "$script_path")"
        fi
        PASSED=$((PASSED + 1))
        SHELL_SCENARIOS=$((SHELL_SCENARIOS + 1))
        SHELL_PASSED=$((SHELL_PASSED + 1))
    done < "$WORK/embedded-scripts.list"
done

if ! python3 "$CHECKER" --pr "$PR_SOURCE" --store "$STORE_SOURCE" >"$WORK/output.log" 2>&1; then
    cat "$WORK/output.log" >&2
    fail "repository workflows were rejected"
fi
SCENARIOS=$((SCENARIOS + 1))
PASSED=$((PASSED + 1))
SEMANTIC_SCENARIOS=$((SEMANTIC_SCENARIOS + 1))
SEMANTIC_PASSED=$((SEMANTIC_PASSED + 1))

echo "dual-distribution workflow contract passed: ${PASSED}/${SCENARIOS} checks"
echo "semantic policy fixtures: ${SEMANTIC_PASSED}/${SEMANTIC_SCENARIOS} PASS"
echo "embedded shell syntax checks: ${SHELL_PASSED}/${SHELL_SCENARIOS} PASS"
