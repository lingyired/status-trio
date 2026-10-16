#!/usr/bin/env bash
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" ]]; then
    echo "Usage: $0 <StatusTrio.app>" >&2
    exit 2
fi
CONTENTS="$APP/Contents"
HELPER="$CONTENTS/Helpers/StatusTrioPowerHelper"
PLIST="$CONTENTS/Library/LaunchDaemons/com.lingsmbp.StatusTrio.PowerHelper.plist"
INFO="$CONTENTS/Info.plist"
EXPECTED_MINOS="13.0"
EXPECTED_LABEL="com.lingsmbp.StatusTrio.PowerHelper"

INCLUDED="$(/usr/libexec/PlistBuddy -c 'Print :STIncludesPrivilegedHelper' "$INFO" 2>/dev/null || echo "false")"

if [[ "$INCLUDED" != "true" ]]; then
    # An App-Store-style build must ship neither the daemon nor its daemon plist,
    # or the bundle would contain a root LaunchDaemon it cannot run.
    if [[ -e "$HELPER" || -e "$PLIST" ]]; then
        echo "Error: STIncludesPrivilegedHelper is false but the bundle still contains the privileged helper." >&2
        exit 1
    fi
    echo "Privileged helper intentionally excluded (STIncludesPrivilegedHelper=false)"
    exit 0
fi

if [[ ! -x "$HELPER" ]]; then
    echo "Error: STIncludesPrivilegedHelper is true but $HELPER is missing or not executable." >&2
    exit 1
fi
if [[ ! -f "$PLIST" ]]; then
    echo "Error: the LaunchDaemon property list is missing at $PLIST." >&2
    exit 1
fi

# The daemon is a Mach-O that must meet the same deployment and SDK contract as
# the app, and be signed so launchd and notarization accept it.
bash "$(dirname -- "${BASH_SOURCE[0]}")/verify-platform-version.sh" "$HELPER" "$EXPECTED_MINOS" 26
codesign --verify --strict --verbose=2 "$HELPER"

HELPER_ARCHS="$(lipo -archs "$HELPER")"
if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
    for arch in arm64 x86_64; do
        if [[ " $HELPER_ARCHS " != *" $arch "* ]]; then
            echo "Error: helper is missing required $arch architecture slice." >&2
            exit 1
        fi
    done
fi

# The property list must name the same service the daemon listens on and point
# BundleProgram at the packaged binary, relative to the bundle root.
LABEL="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST")"
if [[ "$LABEL" != "$EXPECTED_LABEL" ]]; then
    echo "Error: LaunchDaemon Label is '$LABEL', expected '$EXPECTED_LABEL'." >&2
    exit 1
fi

PROGRAM="$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$PLIST")"
if [[ "$PROGRAM" != "Contents/Helpers/StatusTrioPowerHelper" ]]; then
    echo "Error: LaunchDaemon BundleProgram is '$PROGRAM', expected 'Contents/Helpers/StatusTrioPowerHelper'." >&2
    exit 1
fi
if [[ ! -x "$APP/$PROGRAM" ]]; then
    echo "Error: LaunchDaemon BundleProgram does not resolve to an executable inside the bundle." >&2
    exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c "Print :MachServices:$EXPECTED_LABEL" "$PLIST" 2>/dev/null)" != "true" ]]; then
    echo "Error: LaunchDaemon MachServices does not advertise $EXPECTED_LABEL." >&2
    exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")"
ASSOCIATED="$(/usr/libexec/PlistBuddy -c 'Print :AssociatedBundleIdentifiers:0' "$PLIST")"
if [[ "$ASSOCIATED" != "$BUNDLE_ID" ]]; then
    echo "Error: LaunchDaemon AssociatedBundleIdentifiers:0 is '$ASSOCIATED', expected the app bundle id '$BUNDLE_ID'." >&2
    exit 1
fi

# The daemon exits itself once the app is done with it, so launchd must be able
# to start it again right away; the 10-second default would make the next
# toggle wait out the throttle instead of reaching a freshly started helper.
THROTTLE="$(/usr/libexec/PlistBuddy -c 'Print :ThrottleInterval' "$PLIST" 2>/dev/null || echo "")"
if [[ "$THROTTLE" != "1" ]]; then
    echo "Error: LaunchDaemon ThrottleInterval is '$THROTTLE', expected '1' so the idle-exited helper restarts on demand." >&2
    exit 1
fi

# The daemon must carry the client code-signing requirement that pins the app's
# bundle identifier and signing team. The string is embedded in the binary, so a
# regression that loosened it would show up here rather than at runtime.
if ! strings -a "$HELPER" | grep -Fq 'com.lingsmbp.StatusTrio'; then
    echo "Error: helper does not embed the app bundle identifier in its client requirement." >&2
    exit 1
fi
if ! strings -a "$HELPER" | grep -Fq 'anchor apple generic'; then
    echo "Error: helper does not embed an Apple-anchored client requirement." >&2
    exit 1
fi

echo "Privileged helper bundle verified: $HELPER_ARCHS"
