#!/usr/bin/env bash
# Exercises verify-privileged-helper-bundle.sh against mocked bundle shapes.
#
# The verifier is the gate that keeps the privileged helper and its LaunchDaemon
# property list present exactly when the build declared them, so these negative
# cases pin both directions of the STIncludesPrivilegedHelper contract.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioHelperContract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "privileged helper bundle contract failed: $*" >&2
    exit 1
}

# Mock the tools the verifier shells out to, so the test needs no real Mach-O.
cat > "$WORK/lipo" <<'SH'
#!/usr/bin/env bash
echo "${MOCK_ARCHS:-arm64}"
SH
chmod +x "$WORK/lipo"

cat > "$WORK/vtool" <<'SH'
#!/usr/bin/env bash
cat <<INFO
${MOCK_ARCH:-arm64}:
    cmd LC_BUILD_VERSION
  cmdsize 32
  platform macos
     minos ${MOCK_MINOS:-13.0}
       sdk ${MOCK_SDK:-26.0}
INFO
SH
chmod +x "$WORK/vtool"

cat > "$WORK/codesign" <<'SH'
#!/usr/bin/env bash
exit "${MOCK_CODESIGN_STATUS:-0}"
SH
chmod +x "$WORK/codesign"

# `strings` is used to prove the embedded client requirement; return it for a
# well-formed helper and nothing otherwise.
cat > "$WORK/strings" <<'SH'
#!/usr/bin/env bash
if [[ "${MOCK_REQUIREMENT:-1}" == "1" ]]; then
    printf 'anchor apple generic and identifier "com.lingsmbp.StatusTrio"\n'
fi
SH
chmod +x "$WORK/strings"

make_app() {
    local name="$1" include="$2" helper="$3" plist="$4"
    local root="$WORK/$name"
    mkdir -p "$root/Contents/Helpers" "$root/Contents/Library/LaunchDaemons"
    cat > "$root/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.lingsmbp.StatusTrio</string>
    <key>STIncludesPrivilegedHelper</key>
    <$([[ "$include" == "true" ]] && echo true || echo false)/>
</dict>
</plist>
PLIST
    if [[ "$helper" == "1" ]]; then
        printf '#!/bin/sh\nexit 0\n' > "$root/Contents/Helpers/StatusTrioPowerHelper"
        chmod +x "$root/Contents/Helpers/StatusTrioPowerHelper"
    fi
    if [[ "$plist" == "1" ]]; then
        cat > "$root/Contents/Library/LaunchDaemons/com.lingsmbp.StatusTrio.PowerHelper.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lingsmbp.StatusTrio.PowerHelper</string>
    <key>BundleProgram</key>
    <string>Contents/Helpers/StatusTrioPowerHelper</string>
    <key>MachServices</key>
    <dict>
        <key>com.lingsmbp.StatusTrio.PowerHelper</key>
        <true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.lingsmbp.StatusTrio</string>
    </array>
    <key>ThrottleInterval</key>
    <integer>1</integer>
</dict>
</plist>
PLIST
    fi
}

run() {
    PATH="$WORK:$PATH" bash "$ROOT/scripts/verify-privileged-helper-bundle.sh" "$@"
}

expect_rejected() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$label was accepted"
    fi
}

# Flagged true but the helper is missing.
make_app missing-helper true 0 1
expect_rejected "a flagged build with no helper" run "$WORK/missing-helper"

# Flagged true but the LaunchDaemon property list is missing.
make_app missing-plist true 1 0
expect_rejected "a flagged build with no property list" run "$WORK/missing-plist"

# Flagged false but the helper is still bundled.
make_app stale-helper false 1 1
expect_rejected "an unflagged build that still bundles the helper" run "$WORK/stale-helper"

# Wrong deployment target must be rejected.
make_app old-minos true 1 1
expect_rejected "a helper with the wrong minos" \
    env PATH="$WORK:$PATH" MOCK_MINOS=15.0 bash "$ROOT/scripts/verify-privileged-helper-bundle.sh" "$WORK/old-minos"

# A helper that does not embed the client requirement must be rejected.
make_app no-requirement true 1 1
expect_rejected "a helper without the embedded requirement" \
    env PATH="$WORK:$PATH" MOCK_REQUIREMENT=0 bash "$ROOT/scripts/verify-privileged-helper-bundle.sh" "$WORK/no-requirement"

# A plist that leaves launchd's default throttle in place must be rejected: the
# helper exits itself when idle, and the default would make the next request
# wait out the throttle instead of starting it again.
make_app slow-restart true 1 1
/usr/libexec/PlistBuddy -c 'Delete :ThrottleInterval' \
    "$WORK/slow-restart/Contents/Library/LaunchDaemons/com.lingsmbp.StatusTrio.PowerHelper.plist"
expect_rejected "a plist without the restart throttle" run "$WORK/slow-restart"

# Positive control: a well-formed flagged bundle passes.
make_app valid true 1 1
run "$WORK/valid" >/dev/null

# Positive control: an unflagged bundle with neither artifact passes.
make_app excluded false 0 0
run "$WORK/excluded" >/dev/null

echo "privileged helper bundle-contract regressions passed"
