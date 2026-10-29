#!/usr/bin/env bash
# Exercises the release workflow and package orchestration with fake external
# tools; never changes a keychain and never publishes.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
export TEST_ROOT
# Workflow verification exports its resolved tag. Keep an unrelated parent tag
# present so each fixture must supply the tag matching its own version.
export TAG=v999.999.999
ruby -ryaml -rjson -e '
  workflow = YAML.load_file(ARGV[0])
  input = (workflow["on"] || workflow.fetch(true)).fetch("workflow_dispatch").fetch("inputs").fetch("notarize")
  abort "notarize must be boolean, default false" unless input["type"] == "boolean" && input["default"] == false
  job = workflow.fetch("jobs").fetch("package")
  abort "NOTARIZE must be wired from dispatch" unless job.fetch("env").fetch("NOTARIZE").include?("inputs.notarize")
  expected_environment = "\${{ (inputs.publish || github.triggering_actor != \x27lingyired\x27) && \x27distribution\x27 || \x27distribution-owner-signing\x27 }}"
  abort "package must keep formal and non-owner builds reviewed while allowing owner diagnostics" unless
    job.fetch("environment").fetch("name") == expected_environment
  steps = job.fetch("steps")
  ["Validate publishing secrets and notarization mode", "Configure Developer ID signing", "Configure Apple notarization"].each do |name|
    step = steps.find { |candidate| candidate["name"] == name }
    script = step ? step.fetch("run") : ""
    script = script.gsub("/usr/bin/codesign", "codesign") if name == "Configure Developer ID signing"
    File.write(File.join(ENV.fetch("TEST_ROOT"), name + ".sh"), script)
  end
  signing_step = steps.find { |candidate| candidate["name"] == "Configure Developer ID signing" } || abort("missing signing setup step")
  signing_script = signing_step.fetch("run")
  ["security list-keychains -d user", "security list-keychains -d user -s", "/usr/bin/true", "codesign --force --sign"].each do |required|
    abort "Developer ID setup must register and smoke-test its identity (missing #{required})" unless signing_script.include?(required)
  end
  backup_step = steps.find { |candidate| candidate["name"] == "Clean up signing keychain" } || abort("missing signing cleanup step")
  backup_script = backup_step.fetch("run")
  ["KEYCHAIN_LIST_BACKUP", "security list-keychains -d user -s", "security delete-keychain"].each do |required|
    abort "signing cleanup must restore and delete temporary keychain (missing #{required})" unless backup_script.include?(required)
  end
  File.write(File.join(ENV.fetch("TEST_ROOT"), "Clean up signing keychain.sh"), backup_script)
  ["Configure Developer ID signing", "Configure Apple notarization"].each do |name|
    step = steps.find { |candidate| candidate["name"] == name } || abort("missing step #{name}")
    guard = step.fetch("if", "")
    ["inputs.publish", "inputs.notarize"].each do |condition|
      abort "#{name} must guard secret injection with #{condition}" unless guard.include?(condition)
    end
    abort "#{name} must run for publishing or notarization" unless guard.include?("||")
  end
  release_step = steps.find { |candidate| candidate["name"] == "Build, sign, notarize, and package once" } || abort("missing package step")
  sparkle_key = release_step.fetch("env").fetch("SPARKLE_PRIVATE_KEY", "")
  ["secrets.SPARKLE_PRIVATE_KEY"].each do |condition|
    abort "SPARKLE_PRIVATE_KEY must be wired into package (missing #{condition})" unless sparkle_key.include?(condition)
  end
' "$ROOT/.github/workflows/release.yml"

# Evaluate real workflow gate bodies, stopping before any actual credential setup.
for step in 'Configure Developer ID signing' 'Configure Apple notarization'; do
    if env PUBLISH_MODE=false NOTARIZE=true DEVELOPER_ID_CERTIFICATE_P12='' CERTIFICATE_PASSWORD='' \
        NOTARY_API_PRIVATE_KEY='' NOTARY_API_KEY_ID='' NOTARY_API_ISSUER_ID='' \
        /bin/bash "$TEST_ROOT/$step.sh" > "$TEST_ROOT/gate.log" 2>&1; then
        echo "FAIL: explicitly requested notarization accepted missing secrets: $step" >&2
        exit 1
    fi
    env PUBLISH_MODE=false NOTARIZE=false DEVELOPER_ID_CERTIFICATE_P12='' CERTIFICATE_PASSWORD='' \
        NOTARY_API_PRIVATE_KEY='' NOTARY_API_KEY_ID='' NOTARY_API_ISSUER_ID='' \
        /bin/bash "$TEST_ROOT/$step.sh" > "$TEST_ROOT/gate.log" 2>&1
    env PUBLISH_MODE=true NOTARIZE=false DEVELOPER_ID_CERTIFICATE_P12='' CERTIFICATE_PASSWORD='' \
        NOTARY_API_PRIVATE_KEY='' NOTARY_API_KEY_ID='' NOTARY_API_ISSUER_ID='' \
        /bin/bash "$TEST_ROOT/$step.sh" > "$TEST_ROOT/gate.log" 2>&1
 done

mkdir -p "$TEST_ROOT/repo/scripts" "$TEST_ROOT/bin"
# Keep the wrapper real; copy its delegated scripts so absolute tool names can
# be redirected inside the disposable fixture only.
cp "$ROOT/scripts/release.sh" "$TEST_ROOT/repo/scripts/release.sh"
cp "$ROOT/scripts/build-timing.sh" "$TEST_ROOT/repo/scripts/build-timing.sh"
for script in package-release.sh publish-release.sh prepare-release-body.sh validate-appcast-notes.sh update-appcast.rb; do
    sed -e 's@/usr/bin/codesign@codesign@g' -e 's@/usr/bin/xcrun@xcrun@g' \
        "$ROOT/scripts/$script" > "$TEST_ROOT/repo/scripts/$script"
done
cat > "$TEST_ROOT/repo/release.json" <<'JSON'
{"app_name":"Fixture","bundle_id":"test.fixture","github_repo":"test/fixture","git_branch":"main","min_system_version":"13.0","appcast_file":"appcast.xml","dmg_name":"Fixture.dmg"}
JSON
printf '<rss/>' > "$TEST_ROOT/repo/appcast.xml"
mkdir -p "$TEST_ROOT/repo/.build/artifacts/sparkle/Sparkle/bin"
ln -s "$TEST_ROOT/bin/sign_update" "$TEST_ROOT/repo/.build/artifacts/sparkle/Sparkle/bin/sign_update"
cat > "$TEST_ROOT/repo/scripts/validate-appcast-notes.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'release-notes\n' >> "$TRACE"
VERIFY
cat > "$TEST_ROOT/repo/scripts/build-app.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
printf 'build\n' >> "$TRACE"
mkdir -p dist/StatusTrio.app/Contents/MacOS dist/StatusTrio.app/Contents/Helpers
printf fixture > dist/StatusTrio.app/Contents/MacOS/StatusTrio
printf fixture > dist/StatusTrio.app/Contents/Helpers/StatusTrioPowerHelper
BUILD
cat > "$TEST_ROOT/repo/scripts/verify-platform-version.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'platform %s\n' "$*" >> "$TRACE"
VERIFY
cat > "$TEST_ROOT/repo/scripts/verify-mobile-battery-bundle.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'mobile-bundle %s\n' "$*" >> "$TRACE"
VERIFY
cat > "$TEST_ROOT/repo/scripts/verify-privileged-helper-bundle.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'helper-bundle %s\n' "$*" >> "$TRACE"
VERIFY
cat > "$TEST_ROOT/repo/scripts/test-macos13-sparkle-metadata.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
printf 'sparkle-metadata %s\n' "$*" >> "$TRACE"
VERIFY
chmod +x "$TEST_ROOT/repo/scripts/build-app.sh" \
    "$TEST_ROOT/repo/scripts/verify-platform-version.sh" \
    "$TEST_ROOT/repo/scripts/verify-mobile-battery-bundle.sh" \
    "$TEST_ROOT/repo/scripts/verify-privileged-helper-bundle.sh" \
    "$TEST_ROOT/repo/scripts/test-macos13-sparkle-metadata.sh"
cat > "$TEST_ROOT/bin/tool" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
name="$(basename "$0")"
printf '%s' "$name" >> "$TRACE"
previous=''
for argument in "$@"; do
    if [[ "$name" == security && "$previous" == -p || "$name" == security && "$previous" == -P || "$name" == security && "$previous" == -k ]]; then
        printf ' <REDACTED>' >> "$TRACE"
    else
        printf ' <%s>' "$argument" >> "$TRACE"
    fi
    previous="$argument"
done
printf '\n' >> "$TRACE"
case "$name" in
    security)
        case "$1" in
            create-keychain) touch "${!#}" ;;
            list-keychains)
                if [[ "$*" == 'list-keychains -d user' ]]; then
                    printf '"%s"\n"%s"\n' "$ORIGINAL_KEYCHAIN_ONE" "$ORIGINAL_KEYCHAIN_TWO"
                else
                    if [[ "${FAIL_SEARCH_RESTORE:-false}" == true && "$*" != *app-signing.keychain-db* ]]; then exit 43; fi
                    shift 4
                    printf '%s\n' "$@" > "$SEARCH_LIST"
                fi ;;
            find-identity)
                echo '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Fixture (TEAM123456)"'
                echo '     1 valid identities found' ;;
        esac ;;
    codesign)
        if [[ "${SMOKE_CODESIGN_FAIL:-false}" == true && "$*" == *codesign-smoke* ]]; then exit 42; fi ;;
    hdiutil) touch "${!#}" ;;
    ditto)
        if [[ "$1" != '-c' ]]; then cp -R "$1" "$2"; else touch "${!#}"; fi ;;
    xcrun)
        if [[ "$1 $2" == '--sdk macosx' ]]; then
            printf '27.0\n'
        elif [[ "$1 $2" == 'notarytool submit' ]]; then
            printf '{"status":"%s"}\n' "${NOTARY_STATUS:-Accepted}"
        fi ;;
    xcodebuild) printf 'Xcode 27.0\nBuild version 27A266a\n' ;;
    lipo) printf 'arm64 x86_64\n' ;;
    sign_update)
        size="$(stat -f '%z' "${!#}")"
        printf 'sparkle:edSignature="fixture-signature" length="%s"\n' "$size"
        ;;
    shasum) /usr/bin/shasum "$@" ;;
    gh) echo 'FAIL: publishing tool reached in no-publish run' >&2; exit 99 ;;
esac
TOOL
chmod +x "$TEST_ROOT/bin/tool"
for command in swift xcodebuild hdiutil ditto codesign xcrun spctl plutil xmllint gh sign_update shasum security openssl lipo; do
    ln -s tool "$TEST_ROOT/bin/$command"
done
ln -s /bin/bash "$TEST_ROOT/bin/bash"
cat > "$TEST_ROOT/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    "rev-parse HEAD"|"-C "*" rev-parse HEAD")
        printf '0123456789abcdef0123456789abcdef01234567\n'
        ;;
    "status --porcelain=v1 --untracked-files=all"|"-C "*" status --porcelain=v1 --untracked-files=all")
        printf '%s' "${GIT_STATUS:-}"
        ;;
    *)
        exec /usr/bin/git "$@"
        ;;
esac
GIT
chmod +x "$TEST_ROOT/bin/git"

if env PUBLISH_MODE=false NOTARIZE=true DEVELOPER_ID_CERTIFICATE_P12='fixture' CERTIFICATE_PASSWORD='' \
    /bin/bash "$TEST_ROOT/Configure Developer ID signing.sh" > "$TEST_ROOT/gate.log" 2>&1; then
    echo 'FAIL: notarization accepted a missing Developer ID certificate password' >&2
    exit 1
fi

for missing in key-id issuer-id; do
    :
    if [[ "$missing" == key-id ]]; then
        key_id=''
        issuer_id='fixture-issuer'
    else
        key_id='fixture-key'
        issuer_id=''
    fi
    if env PUBLISH_MODE=false NOTARIZE=true NOTARY_API_PRIVATE_KEY='fixture' \
        NOTARY_API_KEY_ID="$key_id" NOTARY_API_ISSUER_ID="$issuer_id" KEYCHAIN_PATH='' \
        RUNNER_TEMP="$TEST_ROOT" GITHUB_ENV="$TEST_ROOT/github-env" \
        /bin/bash "$TEST_ROOT/Configure Apple notarization.sh" > "$TEST_ROOT/gate.log" 2>&1; then
        echo "FAIL: notarization accepted missing App Store Connect $missing" >&2
        exit 1
    fi
done
export PATH="$TEST_ROOT/bin:$PATH" TRACE="$TEST_ROOT/trace"

# Signing setup must preserve the existing user search list, register the
# imported keychain before the real smoke sign, and fail before building if it cannot sign.
export ORIGINAL_KEYCHAIN_ONE="$TEST_ROOT/login.keychain-db" ORIGINAL_KEYCHAIN_TWO="$TEST_ROOT/System.keychain"
export SEARCH_LIST="$TEST_ROOT/search-list"
printf 'fixture' | base64 | tr -d '\n' > "$TEST_ROOT/certificate.p12.base64"
CERTIFICATE_FIXTURE="$(<"$TEST_ROOT/certificate.p12.base64")"
: > "$TRACE"
env PUBLISH_MODE=false NOTARIZE=true DEVELOPER_ID_CERTIFICATE_P12="$CERTIFICATE_FIXTURE" \
    CERTIFICATE_PASSWORD='fixture-password' RUNNER_TEMP="$TEST_ROOT/signing" \
    GITHUB_ENV="$TEST_ROOT/signing-github-env" SEARCH_LIST="$SEARCH_LIST" TRACE="$TRACE" \
    ORIGINAL_KEYCHAIN_ONE="$ORIGINAL_KEYCHAIN_ONE" ORIGINAL_KEYCHAIN_TWO="$ORIGINAL_KEYCHAIN_TWO" \
    mkdir -p "$TEST_ROOT/signing"
env PUBLISH_MODE=false NOTARIZE=true DEVELOPER_ID_CERTIFICATE_P12="$CERTIFICATE_FIXTURE" \
    CERTIFICATE_PASSWORD='fixture-password' RUNNER_TEMP="$TEST_ROOT/signing" \
    GITHUB_ENV="$TEST_ROOT/signing-github-env" SEARCH_LIST="$SEARCH_LIST" TRACE="$TRACE" \
    ORIGINAL_KEYCHAIN_ONE="$ORIGINAL_KEYCHAIN_ONE" ORIGINAL_KEYCHAIN_TWO="$ORIGINAL_KEYCHAIN_TWO" \
    /bin/bash "$TEST_ROOT/Configure Developer ID signing.sh" > "$TEST_ROOT/signing-setup.log" 2>&1 || {
        cat "$TEST_ROOT/signing-setup.log" >&2
        exit 1
    }
grep -Fxq "$TEST_ROOT/signing/app-signing.keychain-db" "$SEARCH_LIST" || {
    echo 'FAIL: temporary signing keychain was not added to the user search list' >&2; cat "$TRACE" >&2; exit 1;
}
grep -Fxq "$ORIGINAL_KEYCHAIN_ONE" "$SEARCH_LIST" && grep -Fxq "$ORIGINAL_KEYCHAIN_TWO" "$SEARCH_LIST" || {
    echo 'FAIL: signing setup did not preserve all original user keychains' >&2; cat "$TRACE" >&2; exit 1;
}
ruby -e '
  lines = File.readlines(ARGV[0])
  search = lines.index { |line| line.start_with?("security ") && line.include?("<-s>") } or abort "missing search-list update"
  sign = lines.index { |line| line.start_with?("codesign ") && line.include?("<--sign>") && line.include?("codesign-smoke") } or abort "missing real smoke sign"
  verify = lines.index { |line| line.start_with?("codesign ") && line.include?("<--verify>") && line.include?("codesign-smoke") } or abort "missing smoke verification"
  abort "smoke test ran before search-list registration" unless search < sign && sign < verify
' "$TRACE"
if grep -q 'fixture-password\|fixture-private-key\|CERTIFICATE_FIXTURE' "$TEST_ROOT/signing-setup.log"; then
    echo 'FAIL: signing diagnostics exposed fixture credentials' >&2; exit 1
fi

: > "$TRACE"
mkdir -p "$TEST_ROOT/signing-fail"
if env PUBLISH_MODE=false NOTARIZE=true DEVELOPER_ID_CERTIFICATE_P12="$CERTIFICATE_FIXTURE" \
    CERTIFICATE_PASSWORD='fixture-password' RUNNER_TEMP="$TEST_ROOT/signing-fail" \
    GITHUB_ENV="$TEST_ROOT/signing-fail-github-env" SEARCH_LIST="$SEARCH_LIST" TRACE="$TRACE" \
    ORIGINAL_KEYCHAIN_ONE="$ORIGINAL_KEYCHAIN_ONE" ORIGINAL_KEYCHAIN_TWO="$ORIGINAL_KEYCHAIN_TWO" \
    SMOKE_CODESIGN_FAIL=true /bin/bash "$TEST_ROOT/Configure Developer ID signing.sh" \
    > "$TEST_ROOT/signing-fail.log" 2>&1; then
    echo 'FAIL: signing setup accepted a failed codesign smoke test' >&2; exit 1
fi
grep -q 'disposable codesign smoke-test binary' "$TEST_ROOT/signing-fail.log" || {
    echo 'FAIL: failed smoke sign did not produce the targeted diagnostic' >&2; cat "$TEST_ROOT/signing-fail.log" >&2; exit 1;
}
if grep -q '^build' "$TRACE"; then echo 'FAIL: failed smoke test reached build' >&2; exit 1; fi

env KEYCHAIN_PATH="$TEST_ROOT/signing/app-signing.keychain-db" \
    KEYCHAIN_LIST_BACKUP="$TEST_ROOT/signing/app-signing-keychains.original" RUNNER_TEMP="$TEST_ROOT/signing" \
    /bin/bash "$TEST_ROOT/Clean up signing keychain.sh" > "$TEST_ROOT/signing-cleanup.log" 2>&1 || {
        cat "$TEST_ROOT/signing-cleanup.log" >&2; cat "$TRACE" >&2; exit 1;
    }
grep -q '^security <list-keychains> <-d> <user> <-s>' "$TRACE" || {
    echo 'FAIL: cleanup did not restore the original keychain search list' >&2; cat "$TRACE" >&2; exit 1;
}
grep -q '^security <delete-keychain>' "$TRACE" || {
    echo 'FAIL: cleanup did not delete the temporary keychain' >&2; cat "$TRACE" >&2; exit 1;
}

: > "$TRACE"
printf '"%s"\n"%s"\n' "$ORIGINAL_KEYCHAIN_ONE" "$ORIGINAL_KEYCHAIN_TWO" \
    > "$TEST_ROOT/signing/app-signing-keychains.original"
if env KEYCHAIN_PATH="$TEST_ROOT/signing/app-signing.keychain-db" \
    KEYCHAIN_LIST_BACKUP="$TEST_ROOT/signing/app-signing-keychains.original" RUNNER_TEMP="$TEST_ROOT/signing" \
    FAIL_SEARCH_RESTORE=true /bin/bash "$TEST_ROOT/Clean up signing keychain.sh" \
    > "$TEST_ROOT/signing-cleanup-failure.log" 2>&1; then
    echo 'FAIL: cleanup hid a keychain search-list restore failure' >&2; exit 1
fi
grep -q '^security <delete-keychain>' "$TRACE" || {
    echo 'FAIL: temporary keychain deletion was skipped after search-list restore failed' >&2; cat "$TRACE" >&2; exit 1;
}
grep -q 'Could not restore the original user keychain search list' "$TEST_ROOT/signing-cleanup-failure.log" || {
    echo 'FAIL: cleanup did not report search-list restore failure' >&2; cat "$TEST_ROOT/signing-cleanup-failure.log" >&2; exit 1;
}

: > "$TRACE"
env PUBLISH_MODE=false NOTARIZE=true NOTARY_API_PRIVATE_KEY='fixture-private-key' \
    NOTARY_API_KEY_ID='fixture-key' NOTARY_API_ISSUER_ID='fixture-issuer' \
    KEYCHAIN_PATH="$TEST_ROOT/keychain with spaces" RUNNER_TEMP="$TEST_ROOT" \
    GITHUB_ENV="$TEST_ROOT/github-env" /bin/bash "$TEST_ROOT/Configure Apple notarization.sh" \
    > "$TEST_ROOT/notary-setup.log" 2>&1
grep -Fq "xcrun <notarytool> <store-credentials> <status-trio-notary> <--key> <$TEST_ROOT/AuthKey_fixture-key.p8> <--key-id> <fixture-key> <--issuer> <fixture-issuer> <--keychain> <$TEST_ROOT/keychain with spaces>" "$TRACE" || {
    echo 'FAIL: notary credentials did not retain the keychain path as one argument' >&2
    cat "$TRACE" >&2
    exit 1
}
if [[ -e "$TEST_ROOT/AuthKey_fixture-key.p8" ]]; then
    echo 'FAIL: temporary App Store Connect private key was not removed' >&2
    exit 1
fi

: > "$TRACE"
if ! env PUBLISH_MODE=false NOTARIZE=true NOTARY_API_PRIVATE_KEY='fixture-private-key' \
    NOTARY_API_KEY_ID='fixture-key' NOTARY_API_ISSUER_ID='fixture-issuer' \
    KEYCHAIN_PATH='' RUNNER_TEMP="$TEST_ROOT" GITHUB_ENV="$TEST_ROOT/github-env" \
    /bin/bash "$TEST_ROOT/Configure Apple notarization.sh" > "$TEST_ROOT/notary-setup.log" 2>&1; then
    echo 'FAIL: Bash 3.2 workflow setup failed with an empty keychain path' >&2
    cat "$TEST_ROOT/notary-setup.log" >&2
    exit 1
fi
if grep -q '<--keychain>' "$TRACE"; then
    echo 'FAIL: empty keychain path produced a --keychain argument' >&2
    cat "$TRACE" >&2
    exit 1
fi

run_release() {
    env VERSION=1.0 BUILD=99 TAG=v1.0 PUBLISH=false UNIVERSAL_BUILD=1 OUTPUT_DIR="$TEST_ROOT/output" \
        SPARKLE_PRIVATE_KEY='' \
        /bin/bash "$TEST_ROOT/repo/scripts/release.sh"
}

SOURCE_SHA="$(git rev-parse HEAD)"
run_package() {
    env \
        SPARKLE_PRIVATE_KEY='' \
        SOURCE_SHA="$SOURCE_SHA" \
        VERSION=1.0 BUILD=99 TAG=v1.0 PUBLISH_MODE=false NOTARIZE=false \
        UNIVERSAL_BUILD=1 OUTPUT_DIR="$TEST_ROOT/output" \
        RELEASE_REPO=test/fixture RELEASE_BRANCH=main \
        CODE_SIGN_IDENTITY=- KEYCHAIN_PATH='' NOTARY_PROFILE='' \
        GIT_STATUS="${GIT_STATUS:-}" \
        /bin/bash "$TEST_ROOT/repo/scripts/package-release.sh"
}

mkdir -p "$TEST_ROOT/output"
: > "$TRACE"
if GIT_STATUS=' M scripts/package-release.sh' run_package > "$TEST_ROOT/dirty-package.log" 2>&1; then
    echo 'FAIL: package accepted a dirty worktree' >&2
    exit 1
fi
grep -q 'requires a clean committed worktree' "$TEST_ROOT/dirty-package.log" || {
    echo 'FAIL: dirty worktree did not produce the targeted package diagnostic' >&2
    cat "$TEST_ROOT/dirty-package.log" >&2
    exit 1
}
if grep -q '^build' "$TRACE"; then
    echo 'FAIL: dirty worktree reached build' >&2
    exit 1
fi

: > "$TRACE"
if ! run_package > "$TEST_ROOT/diagnostic-package.log" 2>&1; then
    cat "$TEST_ROOT/diagnostic-package.log" >&2
    exit 1
fi
DIAGNOSTIC_MANIFEST="$TEST_ROOT/output/release-manifest.json"
ruby -rjson -e '
    manifest = JSON.parse(File.read(ARGV[0]))
    abort("diagnostic signature marker missing") unless manifest.dig("dmg", "ed_signature") == "diagnostic-not-for-publication"
    abort("diagnostic package was not Ad-hoc") unless manifest.dig("signing", "kind") == "ad_hoc"
    abort("diagnostic package was notarized") unless manifest.dig("notarization", "status") == "not_requested"
' "$DIAGNOSTIC_MANIFEST"
grep -q 'Diagnostic package has no Sparkle signature' "$TEST_ROOT/diagnostic-package.log" ||
    { echo 'FAIL: diagnostic package did not explain its missing signature' >&2; exit 1; }
: > "$TRACE"
if env VERSION=1.0 BUILD=99 TAG=v1.0 PUBLISH=true NOTARIZE=true UNIVERSAL_BUILD=1 OUTPUT_DIR="$TEST_ROOT/output" \
    SPARKLE_PRIVATE_KEY='' \
    CODE_SIGN_IDENTITY='Developer ID Application: Fixture' NOTARY_PROFILE=fixture \
    GH_TOKEN=fixture RELEASE_REPO=test/fixture RELEASE_BRANCH=main \
    /bin/bash "$TEST_ROOT/repo/scripts/release.sh" > "$TEST_ROOT/release.log" 2>&1; then
    echo 'FAIL: release accepted publish without a Sparkle signing key' >&2
    exit 1
fi
grep -q 'SPARKLE_PRIVATE_KEY is required for a publishable package' "$TEST_ROOT/release.log" || {
    echo 'FAIL: release script did not reject publish without a Sparkle signing key' >&2
    cat "$TEST_ROOT/release.log" >&2
    exit 1
}
if grep -q '^build' "$TRACE"; then
    echo 'FAIL: invalid publish request reached build' >&2
    exit 1
fi
if grep -q 'fixture-signature' "$TRACE"; then
    echo 'FAIL: invalid publish request reached Sparkle signing' >&2
    exit 1
fi

for bad in missing-profile missing-identity; do
    : > "$TRACE"
    if [[ "$bad" == missing-profile ]]; then
        export NOTARIZE=true NOTARY_PROFILE='' CODE_SIGN_IDENTITY='Developer ID Application: Fixture' KEYCHAIN_PATH=test-keychain
    else
        export NOTARIZE=true NOTARY_PROFILE=fixture CODE_SIGN_IDENTITY='-' KEYCHAIN_PATH=test-keychain
    fi
    if run_release > "$TEST_ROOT/release.log" 2>&1; then
        echo "FAIL: requested notarization accepted $bad" >&2; exit 1
    fi
    if grep -q '^build' "$TRACE"; then echo 'FAIL: invalid request reached build' >&2; exit 1; fi
done
export NOTARIZE=true NOTARY_PROFILE=fixture CODE_SIGN_IDENTITY='Developer ID Application: Fixture' KEYCHAIN_PATH=test-keychain
: > "$TRACE"
if ! run_release > "$TEST_ROOT/release.log" 2>&1; then
    cat "$TEST_ROOT/release.log" >&2
    exit 1
fi
ruby -e '
  lines = File.readlines(ARGV[0])
  def locate(lines, *parts)
    lines.index { |line| parts.all? { |part| line.include?(part) } } || abort("missing operation #{parts.inspect}")
  end
  operations = [
    ["ditto", "<-c>"], ["xcrun", "<submit>", ".zip>"],
    ["xcrun", "<staple>", ".app>"], ["xcrun", "<validate>", ".app>"],
    ["hdiutil", "<create>"], ["codesign", "<--sign>", ".dmg>", "<--timestamp>", "<--keychain>", "<test-keychain>"],
    ["codesign", "<--verify>", ".dmg>"], ["xcrun", "<submit>", ".dmg>"],
    ["xcrun", "<staple>", ".dmg>"], ["xcrun", "<validate>", ".dmg>"],
    ["spctl", "<--type>", "<open>", "<context:primary-signature>"],
    ["spctl", "<--type>", "<execute>"], ["shasum", "<-a>", "<256>", ".dmg>"]
  ].map { |parts| locate(lines, *parts) }
  abort "incorrect sign/notary/staple order" unless operations == operations.sort && operations.uniq.length == operations.length
  abort "unexpected duplicate submissions" unless lines.count { |line| line.include?("<submit>") } == 2
  abort "publishing reached" if lines.any? { |line| line.start_with?("gh ") }
' "$TRACE"

: > "$TRACE"
export KEYCHAIN_PATH=''
if ! run_release > "$TEST_ROOT/release.log" 2>&1; then
    echo 'FAIL: Bash 3.2 release notarization failed with an empty keychain path' >&2
    cat "$TEST_ROOT/release.log" >&2
    exit 1
fi
ruby -e '
  lines = File.readlines(ARGV[0])
  submits = lines.select { |line| line.start_with?("xcrun ") && line.include?("<notarytool> <submit>") }
  abort "expected app and DMG notarization submissions" unless submits.length == 2
  abort "empty keychain path was passed to notarytool" if submits.any? { |line| line.include?("<--keychain>") }
  abort "empty keychain path was passed to codesign" if lines.any? { |line| line.start_with?("codesign ") && line.include?("<--keychain>") }
' "$TRACE"

# Rejected submissions must stop before an artifact is advertised as successful.
: > "$TRACE"
if NOTARY_STATUS=Invalid run_release > "$TEST_ROOT/rejected.log" 2>&1; then
    echo 'FAIL: rejected notarization succeeded' >&2; exit 1
fi
: > "$TRACE"
NOTARIZE=false NOTARY_PROFILE='' CODE_SIGN_IDENTITY='-' run_release > "$TEST_ROOT/release.log" 2>&1
if grep -Eq '^(xcrun <notarytool>|codesign |spctl |gh )' "$TRACE"; then
    echo 'FAIL: fast preflight reached notarization/signing/publishing' >&2; cat "$TRACE" >&2; exit 1
fi
# The compatibility wrapper delegates in order and has no publication powers.
ruby -e '
  wrapper = File.read(ARGV[0])
  package = wrapper.index("scripts/package-release.sh") or abort "missing package delegation"
  publish = wrapper.index("scripts/publish-release.sh") or abort "missing publish delegation"
  abort "publish delegation must follow package" unless package < publish
  ["gh release", "update-appcast.rb", "swift build", "hdiutil create"].each do |action|
    abort "wrapper retained #{action}" if wrapper.include?(action)
  end

  publisher = File.read(ARGV[1])
  ["swift build", "scripts/build-app.sh", "hdiutil create", "notarytool submit", "codesign"].each do |action|
    abort "publisher can rebuild or sign via #{action}" if publisher.include?(action)
  end
' "$ROOT/scripts/release.sh" "$ROOT/scripts/publish-release.sh"
echo 'release notarization gates, artifact ordering, rejection and no-publish regressions passed'
