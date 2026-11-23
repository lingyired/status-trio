#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioLocalDevBuildContract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "local dev build contract failed: $*" >&2
    exit 1
}

DEV_SCRIPT="$ROOT/scripts/build-dev-app.sh"
PLIST_HELPER="$ROOT/scripts/configure-local-dev-plist.sh"
SIGNING_HELPER="$ROOT/scripts/resolve-local-dev-signing-identity.sh"
[[ -x "$DEV_SCRIPT" ]] || fail "missing executable build-dev-app.sh"
[[ -x "$PLIST_HELPER" ]] || fail "missing executable configure-local-dev-plist.sh"
[[ -x "$SIGNING_HELPER" ]] || fail "missing executable resolve-local-dev-signing-identity.sh"

# The opt-in entry point must select an independent identity, name, and output
# path, and delegate only to the local app builder (never release machinery).
ruby -e '
  script = File.read(ARGV.fetch(0))
  required = {
    "distinct bundle identifier" => "com.lingsmbp.StatusTrio.Dev",
    "distinct display name" => "Status Trio Dev",
    "distinct output path" => "dist-dev/Status Trio Dev.app",
    "2.0.0 developer version" => "2.0.0",
    "developer build number" => "19",
    "plan-specific developer codename" => "Icon Designer",
    "local app build delegation" => "scripts/build-app.sh",
    "dev marker for updater runtime guard" => "DEVELOPMENT_CODENAME",
  }
  required.each { |label, value| abort "missing #{label}" unless script.include?(value) }
  abort "dev entry point must not invoke release/publish tooling" if script.match?(/release\.sh|gh workflow|create-dmg|publish=true/i)
' "$DEV_SCRIPT"
ruby -e '
  script = File.read(ARGV.fetch(0))
  abort "build-app must invoke the opt-in updater plist helper" unless script.include?("configure-local-dev-plist.sh") && script.include?("DISABLE_PRODUCTION_UPDATES")
' "$ROOT/scripts/build-app.sh"

# Prove the generated dev plist retains unrelated metadata while removing every
# production Sparkle update setting; the source plist must remain untouched.
cp "$ROOT/Support/Info.plist" "$WORK/Info.plist"
cp "$ROOT/Support/Info.plist" "$WORK/Info.before.plist"
bash "$PLIST_HELPER" "$WORK/Info.plist"
for key in SUFeedURL SUPublicEDKey SUEnableInstallerLauncherService; do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$WORK/Info.plist" >/dev/null 2>&1; then
        fail "development plist retains $key"
    fi
done
for key in CFBundleIdentifier CFBundleName CFBundleDisplayName LSMinimumSystemVersion STTelemetryProduction; do
    before="$(/usr/libexec/PlistBuddy -c "Print :$key" "$WORK/Info.before.plist")"
    after="$(/usr/libexec/PlistBuddy -c "Print :$key" "$WORK/Info.plist")"
    [[ "$before" == "$after" ]] || fail "helper unexpectedly changed $key"
done
cmp -s "$ROOT/Support/Info.plist" "$WORK/Info.before.plist" || fail "source plist fixture changed"

# Use a synthetic checkout plus PATH stubs to exercise identity selection and
# forwarding without building an app or touching a real keychain/certificate.
SIGNING_FIXTURE="$WORK/signing-fixture"
mkdir -p "$SIGNING_FIXTURE/scripts" "$SIGNING_FIXTURE/bin"
cp "$DEV_SCRIPT" "$SIGNING_FIXTURE/scripts/build-dev-app.sh"
cp "$SIGNING_HELPER" "$SIGNING_FIXTURE/scripts/resolve-local-dev-signing-identity.sh"
cat > "$SIGNING_FIXTURE/scripts/build-app.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${CODE_SIGN_IDENTITY-}" "${BUNDLE_ID-}" "${APP_OUTPUT_PATH-}" "$@" > "$BUILD_STUB_LOG"
STUB
cat > "$SIGNING_FIXTURE/bin/security" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$SECURITY_STUB_LOG"
printf '%s\n' "$SECURITY_STUB_OUTPUT"
STUB
chmod +x "$SIGNING_FIXTURE/bin/security" "$SIGNING_FIXTURE/scripts/build-app.sh"

export PATH="$SIGNING_FIXTURE/bin:$PATH"
export SECURITY_STUB_LOG="$WORK/security.log"
export BUILD_STUB_LOG="$WORK/build.log"

run_dev_build() {
    : > "$SECURITY_STUB_LOG"
    : > "$BUILD_STUB_LOG"
    env -u CODE_SIGN_IDENTITY SECURITY_STUB_OUTPUT="$1" \
        bash "$SIGNING_FIXTURE/scripts/build-dev-app.sh" release no-open
}

SECURITY_STUB_OUTPUT=$'2 valid identities found\n1) C28E65B91D6E931F93778552EFEEFC5EB8726CDE "Developer ID Application: Zhanghong Liu (HCB7JKMQ2F)"\n2) 2222222222222222222222222222222222222222 "Apple Development: Zhanghong Liu (HCB7JKMQ2F)"'
run_dev_build "$SECURITY_STUB_OUTPUT"
[[ "$(sed -n '1p' "$BUILD_STUB_LOG")" == "C28E65B91D6E931F93778552EFEEFC5EB8726CDE" ]] || fail "automatic signing did not forward the valid identity SHA"
[[ "$(cat "$SECURITY_STUB_LOG")" == "find-identity -v -p codesigning" ]] || fail "automatic selection used unexpected security arguments"
[[ "$(sed -n '2p' "$BUILD_STUB_LOG")" == "com.lingsmbp.StatusTrio.Dev" ]] || fail "developer build bundle ID changed"
expected_dev_app_path="$(cd "$SIGNING_FIXTURE" && pwd)/dist-dev/Status Trio Dev.app"
[[ "$(sed -n '3p' "$BUILD_STUB_LOG")" == "$expected_dev_app_path" ]] || fail "developer build output path changed"
[[ "$(sed -n '4,5p' "$BUILD_STUB_LOG" | tr '\n' ' ')" == "release no-open " ]] || fail "developer build arguments were not preserved"

for failure_case in none multiple; do
    case "$failure_case" in
        none) fixture_output='0 valid identities found' ;;
        multiple)
            fixture_output=$'2 valid identities found\n1) C28E65B91D6E931F93778552EFEEFC5EB8726CDE "Developer ID Application: Zhanghong Liu (HCB7JKMQ2F)"\n2) 1111111111111111111111111111111111111111 "Developer ID Application: Other (TEAM123456)"'
            ;;
    esac
    : > "$BUILD_STUB_LOG"
    if env -u CODE_SIGN_IDENTITY SECURITY_STUB_OUTPUT="$fixture_output" \
        bash "$SIGNING_FIXTURE/scripts/build-dev-app.sh" release no-open >"$WORK/$failure_case.out" 2>"$WORK/$failure_case.err"; then
        fail "$failure_case automatic identity candidates unexpectedly succeeded"
    fi
    [[ ! -s "$BUILD_STUB_LOG" ]] || fail "$failure_case identity candidates reached the app builder"
    case "$failure_case" in
        none) grep -qi 'no valid Developer ID Application identity' "$WORK/$failure_case.err" || fail "missing-identity error was unclear" ;;
        multiple) grep -qi 'multiple valid Developer ID Application identities' "$WORK/$failure_case.err" || fail "multiple-identity error was unclear" ;;
    esac
done

for explicit_identity in 'Developer ID Application: Explicit Name (TEAM123456)' '-'; do
    : > "$SECURITY_STUB_LOG"
    : > "$BUILD_STUB_LOG"
    CODE_SIGN_IDENTITY="$explicit_identity" SECURITY_STUB_OUTPUT='0 valid identities found' \
        bash "$SIGNING_FIXTURE/scripts/build-dev-app.sh" release no-open
    [[ "$(sed -n '1p' "$BUILD_STUB_LOG")" == "$explicit_identity" ]] || fail "explicit identity '$explicit_identity' was not honored"
    [[ ! -s "$SECURITY_STUB_LOG" ]] || fail "explicit identity '$explicit_identity' triggered automatic identity discovery"
done

# Normal app builds keep the production identity/output defaults and do not
# opt into the development plist transformation.
ruby -e '
  script = File.read(ARGV.fetch(0))
  abort "production bundle ID default changed" unless script.include?("BUNDLE_ID=\"${BUNDLE_ID:-com.lingsmbp.StatusTrio}\"")
  abort "production display name default changed" unless script.include?("APP_NAME=\"${APP_NAME:-Status Trio}\"")
  abort "production output path default changed" unless script.include?("APP_OUTPUT_PATH:-$ROOT/dist/StatusTrio.app")
' "$ROOT/scripts/build-app.sh"

bash -n "$DEV_SCRIPT" "$PLIST_HELPER" "$SIGNING_HELPER" "$ROOT/scripts/build-app.sh" "$0"
echo "local dev build contract passed"
