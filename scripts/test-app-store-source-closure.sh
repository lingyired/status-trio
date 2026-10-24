#!/usr/bin/env bash
# Offline contract tests for verify-app-store-source-closure.py.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AUDITOR="$ROOT/scripts/verify-app-store-source-closure.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioSourceClosure.XXXXXX")"
SCENARIOS=0
PASSED=0
trap '/bin/rm -rf "$WORK"' EXIT

fail() {
    echo "App Store source closure contract failed: $*" >&2
    exit 1
}

[[ -f "$AUDITOR" ]] || fail "missing auditor at $AUDITOR"

manifest_path() {
    printf '%s/.build/app-store/source-membership.json' "$1"
}

arm_file_list() {
    printf '%s/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrio.build/Debug/StatusTrioCore.build/Objects-normal/arm64/StatusTrioCore.SwiftFileList' "$1"
}

x86_file_list() {
    printf '%s/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrio.build/Debug/StatusTrioCore.build/Objects-normal/x86_64/StatusTrioCore.SwiftFileList' "$1"
}

derived_relative() {
    printf '%s' '.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrio.build/Debug/StatusTrioCore.build/DerivedSources/StoreResourceAccessor.swift'
}

run_audit() {
    local fixture="$1"
    (
        cd "$fixture"
        python3 "$AUDITOR" --repository-root "$fixture" \
            .build/app-store/source-membership.json
    )
}

run_audit_after_source_change() {
    local fixture="$1"
    refresh_source_tree_sha "$fixture"
    run_audit "$fixture"
}

expect_pass() {
    local label="$1"
    shift
    SCENARIOS=$((SCENARIOS + 1))
    if ! "$@" >"$WORK/last.stdout" 2>"$WORK/last.stderr"; then
        cat "$WORK/last.stdout" >&2
        cat "$WORK/last.stderr" >&2
        fail "$label was rejected"
    fi
    PASSED=$((PASSED + 1))
    printf 'PASS %02d: %s\n' "$SCENARIOS" "$label"
}

expect_fail_contains() {
    local label="$1"
    local expected="$2"
    shift 2
    SCENARIOS=$((SCENARIOS + 1))
    if "$@" >"$WORK/last.stdout" 2>"$WORK/last.stderr"; then
        cat "$WORK/last.stdout" >&2
        fail "$label was accepted"
    fi
    if ! grep -Fq -- "$expected" "$WORK/last.stderr"; then
        cat "$WORK/last.stderr" >&2
        fail "$label failed without expected text '$expected'"
    fi
    PASSED=$((PASSED + 1))
    printf 'PASS %02d: %s\n' "$SCENARIOS" "$label"
}

set_manifest_field() {
    local fixture="$1"
    local field="$2"
    local value="$3"
    python3 - "$(manifest_path "$fixture")" "$field" "$value" <<'PY'
import json
import sys

path, field, encoded = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload[field] = json.loads(encoded)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

remove_derived_evidence() {
    local fixture="$1"
    python3 - "$fixture" "$(arm_file_list "$fixture")" \
        "$(x86_file_list "$fixture")" "$(derived_relative)" <<'PY'
import json
import os
import sys

fixture, arm_list, x86_list, derived_relative = sys.argv[1:]
fixture = os.path.realpath(fixture)
derived_path = os.path.realpath(os.path.join(fixture, derived_relative))
for file_list in (arm_list, x86_list):
    with open(file_list, encoding="utf-8") as handle:
        lines = handle.readlines()
    kept = [
        line for line in lines
        if os.path.realpath(line.rstrip("\n")) != derived_path
    ]
    if len(kept) != len(lines) - 1:
        raise SystemExit(f"fixture file list did not contain {derived_path}")
    with open(file_list, "w", encoding="utf-8") as handle:
        handle.writelines(kept)

manifest_path = os.path.join(
    fixture, ".build", "app-store", "source-membership.json"
)
with open(manifest_path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload["derived_sources"] = []
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

delete_manifest_field() {
    local fixture="$1"
    local field="$2"
    python3 - "$(manifest_path "$fixture")" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload.pop(field, None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

refresh_source_tree_sha() {
    local fixture="$1"
    local digest
    digest="$(
        python3 - "$fixture" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
audit = json.loads((root / ".build/app-store/source-membership.json").read_text())
paths = sorted(audit["included_sources"] + audit["excluded_sources"])
digest = hashlib.sha256()
for relative in paths:
    data = (root / relative).read_bytes()
    digest.update(relative.encode("utf-8") + b"\0")
    digest.update(str(len(data)).encode("ascii") + b"\0")
    digest.update(data)
    digest.update(b"\0")
print(digest.hexdigest())
PY
    )"
    set_manifest_field "$fixture" source_tree_sha256 "\"$digest\""
}

json_list() {
    python3 -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "$@"
}

swift_integer_literal() {
    python3 - "$1" "$2" <<'PY'
import sys

value = int(sys.argv[1], 16)
base = int(sys.argv[2])
prefixes = {2: "0b", 8: "0o", 10: "", 16: "0x"}
digits = {
    2: format(value, "b"),
    8: format(value, "o"),
    10: str(value),
    16: format(value, "x"),
}[base]
groups = []
while digits:
    groups.append(digits[-4:])
    digits = digits[:-4]
print(prefixes[base] + "_".join(reversed(groups)))
PY
}

append_to_file_list() {
    local fixture="$1"
    local file_list="$2"
    local relative="$3"
    printf '%s/%s\n' "$fixture" "$relative" >>"$file_list"
}

fixture_git() {
    local fixture="$1"
    shift
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        git -C "$fixture" \
        -c user.name="Status Trio Fixture" \
        -c user.email="fixture@example.invalid" \
        -c commit.gpgsign=false \
        "$@"
}

initialize_fixture_git() {
    local fixture="$1"
    local head
    fixture_git "$fixture" init --quiet
    fixture_git "$fixture" add --all
    fixture_git "$fixture" commit --quiet --no-gpg-sign -m "source closure fixture"
    head="$(fixture_git "$fixture" rev-parse --verify 'HEAD^{commit}')"
    set_manifest_field "$fixture" source_sha "\"$head\""
    refresh_source_tree_sha "$fixture"
}

make_fixture() {
    local fixture="$1"
    local arm_list
    local x86_list
    local derived

    mkdir -p \
        "$fixture/AppStore" \
        "$fixture/.build/app-store" \
        "$fixture/Sources/StatusTrioCore/App" \
        "$fixture/Sources/StatusTrioCore/Platform" \
        "$fixture/AppStore/Platform"

    cat >"$fixture/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'
import Foundation

// IOAVServiceCreate Sparkle SPUUpdater PowerHelperProtocol AppleSMC
// 0x69616170 com.apple.nat /Library/Preferences/com.apple.powerd.charging.plist
/* Outer block comment.
   /* Nested IOBluetoothPreferenceSetControllerPowerState */
   Sparkle and DDCPrivateAPI are not compiled implementation here.
*/
struct SharedProbe {
    let publicCoreAudioValue: UInt32 = 0x12345678
}

protocol SharedTransportProtocol {
    func use(_ connection: NSXPCConnection)
}

func loadPublicSystemLibrary() {
    _ = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY)
}
SWIFT

    cat >"$fixture/Sources/StatusTrioCore/Platform/PublicFrameworks.swift" <<'SWIFT'
@preconcurrency import CoreBluetooth
import CoreWLAN
import IOBluetooth
import CoreAudio
import IOKit

struct PublicFrameworksProbe {}
SWIFT

    cat >"$fixture/Sources/StatusTrioCore/App/DirectOnly.swift" <<'SWIFT'
import Sparkle

struct DirectOnlyProbe {}
SWIFT

    cat >"$fixture/AppStore/Platform/StorePlatform.swift" <<'SWIFT'
import IOKit

struct StorePlatformProbe {}
SWIFT

    printf 'Sources/StatusTrioCore/App/DirectOnly.swift\n' \
        >"$fixture/AppStore/direct-only-sources.txt"

    derived="$(derived_relative)"
    mkdir -p "$(dirname -- "$fixture/$derived")"
    cat >"$fixture/$derived" <<'SWIFT'
import Foundation

struct StoreResourceAccessor {}
SWIFT

    arm_list="$(arm_file_list "$fixture")"
    x86_list="$(x86_file_list "$fixture")"
    mkdir -p "$(dirname -- "$arm_list")" "$(dirname -- "$x86_list")"

    printf '%s/%s\n' "$fixture" "$derived" >"$arm_list"
    append_to_file_list "$fixture" "$arm_list" "Sources/StatusTrioCore/App/Shared.swift"
    append_to_file_list "$fixture" "$arm_list" "Sources/StatusTrioCore/Platform/PublicFrameworks.swift"
    append_to_file_list "$fixture" "$arm_list" "AppStore/Platform/StorePlatform.swift"

    cp "$arm_list" "$x86_list"

    python3 - "$fixture" "$arm_list" "$x86_list" "$derived" <<'PY'
import json
import os
import sys

fixture, arm_list, x86_list, derived = sys.argv[1:]
fixture = os.path.realpath(fixture)
included = [
    "Sources/StatusTrioCore/App/Shared.swift",
    "Sources/StatusTrioCore/Platform/PublicFrameworks.swift",
    "AppStore/Platform/StorePlatform.swift",
]
payload = {
    "schema_version": 2,
    "channel": "appStore",
    "repository_root": fixture,
    "included_sources": included,
    "excluded_sources": ["Sources/StatusTrioCore/App/DirectOnly.swift"],
    "source_sha": "a" * 40,
    "linked_frameworks": [
        "CoreWLAN",
        "IOBluetooth",
        "CoreBluetooth",
        "CoreAudio",
        "IOKit",
    ],
    "swift_defines": ["STATUS_TRIO_APP_STORE"],
    "compiled_sources": list(reversed(included)),
    "derived_sources": [derived],
    "swift_file_lists": [
        os.path.relpath(os.path.realpath(arm_list), fixture),
        os.path.relpath(os.path.realpath(x86_list), fixture),
    ],
    "source_tree_sha256": "",
}
path = os.path.join(fixture, ".build", "app-store", "source-membership.json")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

    initialize_fixture_git "$fixture"
}

# Clean fixture: public frameworks, public dlopen, unrelated CoreAudio values,
# safe XPC protocol types, and private tokens only in nested comments.
make_fixture "$WORK/clean"
expect_pass "clean closure with comments, dlopen, and public frameworks" run_audit "$WORK/clean"

make_fixture "$WORK/no-derived"
remove_derived_evidence "$WORK/no-derived"
expect_pass "valid target with no generated Swift sources" run_audit "$WORK/no-derived"

make_fixture "$WORK/missing-field"
delete_manifest_field "$WORK/missing-field" source_sha
expect_fail_contains "missing required field" "missing required field" run_audit "$WORK/missing-field"

make_fixture "$WORK/missing-source-tree-sha"
delete_manifest_field "$WORK/missing-source-tree-sha" source_tree_sha256
expect_fail_contains "missing source tree digest" "source_tree_sha256" \
    run_audit "$WORK/missing-source-tree-sha"

make_fixture "$WORK/schema"
set_manifest_field "$WORK/schema" schema_version '1'
expect_fail_contains "unknown schema version" "schema_version" run_audit "$WORK/schema"

make_fixture "$WORK/channel"
set_manifest_field "$WORK/channel" channel '"direct"'
expect_fail_contains "non-App-Store channel" "channel" run_audit "$WORK/channel"

make_fixture "$WORK/sha"
set_manifest_field "$WORK/sha" source_sha '"A"'
expect_fail_contains "invalid source SHA" "source_sha" run_audit "$WORK/sha"

make_fixture "$WORK/stale-sha"
set_manifest_field "$WORK/stale-sha" source_sha "\"$(printf 'a%.0s' {1..40})\""
expect_fail_contains "stale source SHA" "source_sha is stale" run_audit "$WORK/stale-sha"

make_fixture "$WORK/source-tree-content"
printf '\n// same-HEAD content change\n' \
    >>"$WORK/source-tree-content/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "same-HEAD source content changed" "source_tree_sha256" \
    run_audit "$WORK/source-tree-content"

make_fixture "$WORK/source-tree-direct-exclusion"
printf '\n// same-HEAD excluded content change\n' \
    >>"$WORK/source-tree-direct-exclusion/Sources/StatusTrioCore/App/DirectOnly.swift"
expect_fail_contains "same-HEAD excluded source content changed" "source_tree_sha256" \
    run_audit "$WORK/source-tree-direct-exclusion"

make_fixture "$WORK/define"
set_manifest_field "$WORK/define" swift_defines '["DEBUG"]'
expect_fail_contains "missing Store compilation condition" "STATUS_TRIO_APP_STORE" run_audit "$WORK/define"

make_fixture "$WORK/type"
set_manifest_field "$WORK/type" included_sources '"Sources/StatusTrioCore/App/Shared.swift"'
expect_fail_contains "wrong included_sources type" "included_sources" run_audit "$WORK/type"

make_fixture "$WORK/repository-root"
set_manifest_field "$WORK/repository-root" repository_root '"."'
expect_fail_contains "relative repository_root" "repository_root" run_audit "$WORK/repository-root"

make_fixture "$WORK/repository-root-symlink"
ln -s "$WORK/repository-root-symlink" "$WORK/repository-root-alias"
set_manifest_field "$WORK/repository-root-symlink" repository_root \
    "\"$WORK/repository-root-alias\""
expect_fail_contains "repository_root alias escapes canonical root" \
    "repository_root" run_audit "$WORK/repository-root-symlink"

make_fixture "$WORK/omitted-exclusion"
cat >"$WORK/omitted-exclusion/Sources/StatusTrioCore/App/DirectOnlyTwo.swift" <<'SWIFT'
import Sparkle

struct DirectOnlyTwoProbe {}
SWIFT
printf 'Sources/StatusTrioCore/App/DirectOnlyTwo.swift\n' \
    >>"$WORK/omitted-exclusion/AppStore/direct-only-sources.txt"
expect_fail_contains "omitted direct-only exclusion" "direct-only-sources.txt" run_audit "$WORK/omitted-exclusion"

make_fixture "$WORK/extra-exclusion"
cat >"$WORK/extra-exclusion/Sources/StatusTrioCore/App/NotActuallyDirect.swift" <<'SWIFT'
struct NotActuallyDirectProbe {}
SWIFT
set_manifest_field "$WORK/extra-exclusion" excluded_sources \
    "$(json_list Sources/StatusTrioCore/App/DirectOnly.swift Sources/StatusTrioCore/App/NotActuallyDirect.swift)"
refresh_source_tree_sha "$WORK/extra-exclusion"
expect_fail_contains "extra exclusion absent from source manifest" "direct-only-sources.txt" run_audit "$WORK/extra-exclusion"

make_fixture "$WORK/duplicate-exclusion"
printf 'Sources/StatusTrioCore/App/DirectOnly.swift\n' \
    >>"$WORK/duplicate-exclusion/AppStore/direct-only-sources.txt"
expect_fail_contains "duplicate direct-only manifest entry" "duplicate" run_audit "$WORK/duplicate-exclusion"

make_fixture "$WORK/duplicate-included"
set_manifest_field "$WORK/duplicate-included" included_sources \
    "$(json_list Sources/StatusTrioCore/App/Shared.swift Sources/StatusTrioCore/App/Shared.swift)"
expect_fail_contains "duplicate included source" "duplicate" run_audit "$WORK/duplicate-included"

make_fixture "$WORK/overlap"
set_manifest_field "$WORK/overlap" included_sources \
    "$(json_list Sources/StatusTrioCore/App/Shared.swift Sources/StatusTrioCore/App/DirectOnly.swift)"
expect_fail_contains "included/excluded overlap" "overlap" run_audit "$WORK/overlap"

make_fixture "$WORK/traversal"
set_manifest_field "$WORK/traversal" included_sources '["../Outside.swift"]'
expect_fail_contains "source path traversal" ".." run_audit "$WORK/traversal"

make_fixture "$WORK/missing-source"
set_manifest_field "$WORK/missing-source" included_sources \
    "$(json_list Sources/StatusTrioCore/App/Shared.swift Sources/StatusTrioCore/App/Missing.swift)"
set_manifest_field "$WORK/missing-source" compiled_sources \
    "$(json_list Sources/StatusTrioCore/App/Shared.swift Sources/StatusTrioCore/App/Missing.swift)"
append_to_file_list "$WORK/missing-source" "$(arm_file_list "$WORK/missing-source")" \
    "Sources/StatusTrioCore/App/Missing.swift"
expect_fail_contains "missing source file" "Missing.swift" run_audit "$WORK/missing-source"

make_fixture "$WORK/unreadable-source"
chmod 000 "$WORK/unreadable-source/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "unreadable source file" "readable" run_audit "$WORK/unreadable-source"
chmod 600 "$WORK/unreadable-source/Sources/StatusTrioCore/App/Shared.swift"

make_fixture "$WORK/source-symlink"
printf 'struct OutsideProbe {}\n' >"$WORK/outside-source.swift"
ln -s "$WORK/outside-source.swift" "$WORK/source-symlink/Sources/StatusTrioCore/App/Escape.swift"
set_manifest_field "$WORK/source-symlink" included_sources \
    "$(json_list Sources/StatusTrioCore/App/Shared.swift Sources/StatusTrioCore/App/Escape.swift)"
set_manifest_field "$WORK/source-symlink" compiled_sources \
    "$(json_list Sources/StatusTrioCore/App/Shared.swift Sources/StatusTrioCore/App/Escape.swift)"
append_to_file_list "$WORK/source-symlink" "$(arm_file_list "$WORK/source-symlink")" \
    "Sources/StatusTrioCore/App/Escape.swift"
expect_fail_contains "source symlink escape" "symlink" run_audit "$WORK/source-symlink"

make_fixture "$WORK/compiled-claim"
set_manifest_field "$WORK/compiled-claim" compiled_sources \
    "$(json_list Sources/StatusTrioCore/App/Shared.swift)"
expect_fail_contains "manifest compiled_sources disagree with real file list" "compiled_sources" run_audit "$WORK/compiled-claim"

make_fixture "$WORK/compiled-source-token"
cat >>"$WORK/compiled-source-token/Sources/StatusTrioCore/Platform/PublicFrameworks.swift" <<'SWIFT'

let storeDynamicSymbol = "IOAVServiceCreate"
SWIFT
expect_fail_contains "private token in compiled Store source" "PublicFrameworks.swift" run_audit_after_source_change "$WORK/compiled-source-token"

make_fixture "$WORK/direct-in-file-list"
for file_list in \
    "$(arm_file_list "$WORK/direct-in-file-list")" \
    "$(x86_file_list "$WORK/direct-in-file-list")"; do
    append_to_file_list "$WORK/direct-in-file-list" "$file_list" \
        "Sources/StatusTrioCore/App/DirectOnly.swift"
done
expect_fail_contains "Direct source injected into real compile list" "compiled_sources" run_audit "$WORK/direct-in-file-list"

make_fixture "$WORK/duplicate-file-list"
set_manifest_field "$WORK/duplicate-file-list" swift_file_lists \
    "$(json_list .build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrio.build/Debug/StatusTrioCore.build/Objects-normal/arm64/StatusTrioCore.SwiftFileList .build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrio.build/Debug/StatusTrioCore.build/Objects-normal/arm64/StatusTrioCore.SwiftFileList)"
expect_fail_contains "duplicate SwiftFileList evidence" "duplicates" run_audit "$WORK/duplicate-file-list"

make_fixture "$WORK/duplicate-file-list-entry"
for file_list in \
    "$(arm_file_list "$WORK/duplicate-file-list-entry")" \
    "$(x86_file_list "$WORK/duplicate-file-list-entry")"; do
    append_to_file_list "$WORK/duplicate-file-list-entry" "$file_list" \
        "Sources/StatusTrioCore/App/Shared.swift"
done
expect_fail_contains "duplicate entry inside file list" "duplicate file-list entry" run_audit "$WORK/duplicate-file-list-entry"

make_fixture "$WORK/architecture-mismatch"
sed '$d' "$(x86_file_list "$WORK/architecture-mismatch")" \
    >"$WORK/architecture-mismatch/short.SwiftFileList"
mv "$WORK/architecture-mismatch/short.SwiftFileList" \
    "$(x86_file_list "$WORK/architecture-mismatch")"
expect_fail_contains "architecture file-list mismatch" "architecture slices" run_audit "$WORK/architecture-mismatch"

make_fixture "$WORK/no-file-lists"
set_manifest_field "$WORK/no-file-lists" swift_file_lists '[]'
expect_fail_contains "missing SwiftFileList evidence" "swift_file_lists" run_audit "$WORK/no-file-lists"

make_fixture "$WORK/missing-file-list"
set_manifest_field "$WORK/missing-file-list" swift_file_lists \
    "$(json_list .build/app-store/missing/StatusTrioCore.SwiftFileList)"
expect_fail_contains "missing SwiftFileList path" "SwiftFileList" run_audit "$WORK/missing-file-list"

make_fixture "$WORK/outside-file-list-build"
cp "$(arm_file_list "$WORK/outside-file-list-build")" \
    "$WORK/outside-file-list-build/StatusTrioCore.SwiftFileList"
set_manifest_field "$WORK/outside-file-list-build" swift_file_lists \
    "$(json_list StatusTrioCore.SwiftFileList)"
expect_fail_contains "SwiftFileList outside .build" ".build" run_audit "$WORK/outside-file-list-build"

make_fixture "$WORK/file-list-symlink"
cp "$(arm_file_list "$WORK/file-list-symlink")" "$WORK/outside.SwiftFileList"
ln -s "$WORK/outside.SwiftFileList" \
    "$WORK/file-list-symlink/.build/app-store/StatusTrioCore.SwiftFileList"
set_manifest_field "$WORK/file-list-symlink" swift_file_lists \
    "$(json_list .build/app-store/StatusTrioCore.SwiftFileList)"
expect_fail_contains "SwiftFileList symlink escape" ".build" run_audit "$WORK/file-list-symlink"

make_fixture "$WORK/wrong-file-list-name"
cp "$(arm_file_list "$WORK/wrong-file-list-name")" \
    "$WORK/wrong-file-list-name/.build/app-store/Other.SwiftFileList"
set_manifest_field "$WORK/wrong-file-list-name" swift_file_lists \
    "$(json_list .build/app-store/Other.SwiftFileList)"
expect_fail_contains "non-Store-Core file list" "StatusTrioCore.SwiftFileList" run_audit "$WORK/wrong-file-list-name"

make_fixture "$WORK/derived-mismatch"
set_manifest_field "$WORK/derived-mismatch" derived_sources '[]'
expect_fail_contains "omitted DerivedSources entry" "derived_sources" run_audit "$WORK/derived-mismatch"

make_fixture "$WORK/derived-outside-build"
printf 'struct OutsideDerived {}\n' \
    >"$WORK/derived-outside-build/Sources/StatusTrioCore/App/OutsideDerived.swift"
set_manifest_field "$WORK/derived-outside-build" derived_sources \
    '["Sources/StatusTrioCore/App/OutsideDerived.swift"]'
expect_fail_contains "DerivedSources outside .build" "derived_sources" run_audit "$WORK/derived-outside-build"

make_fixture "$WORK/derived-private-token"
cat >>"$WORK/derived-private-token/$(derived_relative)" <<'SWIFT'

let generatedPrivateSymbol = "IOAVServiceCreate"
SWIFT
expect_fail_contains "private token in generated Swift source" "IOAVService" \
    run_audit "$WORK/derived-private-token"

for framework in Sparkle DDCPrivateAPI PowerHelperProtocol CoreDisplay DirectPlatform; do
    fixture="$WORK/framework-$framework"
    make_fixture "$fixture"
    set_manifest_field "$fixture" linked_frameworks "$(json_list "$framework")"
    expect_fail_contains "forbidden Store framework $framework" "$framework" run_audit "$fixture"
done

make_fixture "$WORK/import-sparkle"
printf '\nimport Sparkle\n' >>"$WORK/import-sparkle/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "Sparkle import" "Sparkle" run_audit_after_source_change "$WORK/import-sparkle"

make_fixture "$WORK/preconcurrency-import-sparkle"
printf '\n@preconcurrency import Sparkle\n' \
    >>"$WORK/preconcurrency-import-sparkle/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "@preconcurrency Sparkle import" "Sparkle" \
    run_audit_after_source_change "$WORK/preconcurrency-import-sparkle"

make_fixture "$WORK/exported-import-sparkle"
printf '\n@_exported import Sparkle\n' \
    >>"$WORK/exported-import-sparkle/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "@_exported Sparkle import" "Sparkle" \
    run_audit_after_source_change "$WORK/exported-import-sparkle"

make_fixture "$WORK/import-power-helper"
printf '\nimport PowerHelperProtocol\n' \
    >>"$WORK/import-power-helper/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "PowerHelperProtocol import" "PowerHelperProtocol" run_audit_after_source_change "$WORK/import-power-helper"

make_fixture "$WORK/import-in-comment"
cat >>"$WORK/import-in-comment/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

// import Sparkle
SWIFT
expect_pass "forbidden import text only in a comment" run_audit_after_source_change "$WORK/import-in-comment"

make_fixture "$WORK/dynamic-symbol"
cat >>"$WORK/dynamic-symbol/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let dynamicSymbol = "IOBluetoothPreferenceSetControllerPowerState"
SWIFT
expect_fail_contains "private dynamic symbol string" "IOBluetoothPreference" run_audit_after_source_change "$WORK/dynamic-symbol"

for symbol in \
    IOBluetoothLocalDeviceSetPowerState \
    IOBluetoothLocalDeviceSupportsPowerOff; do
    for literal_kind in ordinary raw triple; do
        fixture="$WORK/local-device-${symbol}-${literal_kind}"
        make_fixture "$fixture"
        case "$literal_kind" in
            ordinary)
                printf '\nlet privateSymbol = "%s"\n' "$symbol" \
                    >>"$fixture/Sources/StatusTrioCore/App/Shared.swift"
                ;;
            raw)
                printf '\nlet privateSymbol = #"%s"#\n' "$symbol" \
                    >>"$fixture/Sources/StatusTrioCore/App/Shared.swift"
                ;;
            triple)
                cat >>"$fixture/Sources/StatusTrioCore/App/Shared.swift" <<SWIFT

let privateSymbol = """
$symbol
"""
SWIFT
                ;;
        esac
        expect_fail_contains \
            "LocalDevice symbol $symbol in $literal_kind string" \
            "IOBluetoothLocalDevice" run_audit_after_source_change "$fixture"
    done
done

for private_name in \
    com.lingsmbp.StatusTrio.PowerHelper \
    com.lingsmbp.StatusTrio.MobileBatteryHelper \
    StatusTrioPowerHelper \
    StatusTrioMobileBatteryHelper; do
    for indirection in direct variable; do
        fixture="$WORK/helper-name-${private_name}-${indirection}"
        make_fixture "$fixture"
        if [[ "$indirection" == "direct" ]]; then
            printf '\nlet privateName = "%s"\n' "$private_name" \
                >>"$fixture/Sources/StatusTrioCore/App/Shared.swift"
        else
            cat >>"$fixture/Sources/StatusTrioCore/App/Shared.swift" <<SWIFT

let indirectName = "$private_name"
let indirectUse = indirectName
SWIFT
        fi
        expect_fail_contains \
            "known helper name $private_name via $indirection" \
            "$private_name" run_audit_after_source_change "$fixture"
    done
done

make_fixture "$WORK/public-nsxpc"
cat >>"$WORK/public-nsxpc/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let publicConnection = NSXPCConnection(
    machServiceName: "com.example.public-service"
)
let nearMatchService = "com.example.com.lingsmbp.StatusTrio.PowerHelper.Debug"
let nearMatchComponent = "MyStatusTrioMobileBatteryHelper"
SWIFT
expect_pass "ordinary public NSXPC connection" run_audit_after_source_change "$WORK/public-nsxpc"

make_fixture "$WORK/private-names-in-comments"
cat >>"$WORK/private-names-in-comments/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

// IOBluetoothLocalDeviceSetPowerState IOBluetoothLocalDeviceSupportsPowerOff
// com.lingsmbp.StatusTrio.PowerHelper
// com.lingsmbp.StatusTrio.MobileBatteryHelper
// StatusTrioPowerHelper StatusTrioMobileBatteryHelper 0x69616170
/* Nested comment:
   /* com.lingsmbp.StatusTrio.MobileBatteryHelper */
*/
let publicService = NSXPCConnection(machServiceName: "com.example.public-service")
SWIFT
expect_pass "known private names only in comments" run_audit_after_source_change "$WORK/private-names-in-comments"

make_fixture "$WORK/raw-string"
cat >>"$WORK/raw-string/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let rawPrivateSymbol = #"IOAVServiceCreate"#
SWIFT
expect_fail_contains "private symbol in raw string" "IOAVService" run_audit_after_source_change "$WORK/raw-string"

make_fixture "$WORK/triple-string"
cat >>"$WORK/triple-string/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let triplePrivateSymbol = """
SPUUpdater
"""
SWIFT
expect_fail_contains "private symbol in triple string" "SPUUpdater" run_audit_after_source_change "$WORK/triple-string"

make_fixture "$WORK/ordinary-escaped-quote-comment-like"
cat >>"$WORK/ordinary-escaped-quote-comment-like/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let escapedQuoteProbe = "quoted: \" still string /* IOAVServiceCreate */"
SWIFT
expect_fail_contains "escaped quote followed by comment-like private text" \
    "IOAVService" run_audit_after_source_change "$WORK/ordinary-escaped-quote-comment-like"

make_fixture "$WORK/raw-escaped-quote-comment-like"
cat >>"$WORK/raw-escaped-quote-comment-like/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let rawEscapedQuoteProbe = #"quoted: \#" still string /* IOAVServiceCreate */"#
SWIFT
expect_fail_contains "raw escaped quote followed by comment-like private text" \
    "IOAVService" run_audit_after_source_change "$WORK/raw-escaped-quote-comment-like"

make_fixture "$WORK/triple-quote-comment-like"
cat >>"$WORK/triple-quote-comment-like/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let tripleQuoteProbe = """
quoted: " still string
/* IOAVServiceCreate */
"""
SWIFT
expect_fail_contains "triple string with bare quote and comment-like private text" \
    "IOAVService" run_audit_after_source_change "$WORK/triple-quote-comment-like"

make_fixture "$WORK/raw-triple-escaped-quote-comment-like"
cat >>"$WORK/raw-triple-escaped-quote-comment-like/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let rawTripleQuoteProbe = #"""
quoted: \#" still string
/* IOAVServiceCreate */
"""#
SWIFT
expect_fail_contains "raw triple string with escaped quote and comment-like private text" \
    "IOAVService" run_audit_after_source_change "$WORK/raw-triple-escaped-quote-comment-like"

make_fixture "$WORK/safe-comment-like-strings"
cat >>"$WORK/safe-comment-like-strings/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let safeRaw = #"quoted: \#" public /* not compiled */"#
let safeTriple = """
public " quoted text
/* not compiled */
"""
let safeRawTriple = #"""
public \#" quoted text
/* not compiled */
"""#
SWIFT
expect_pass "public comment-like text retained inside all string forms" \
    run_audit_after_source_change "$WORK/safe-comment-like-strings"

for hex_value in 69616170 6c73746d 6c736d73; do
    for base in 2 8 10 16; do
        literal="$(swift_integer_literal "$hex_value" "$base")"
        fixture="$WORK/hal-${hex_value}-${base}"
        make_fixture "$fixture"
        printf '\nlet privateSelector: UInt32 = %s\n' "$literal" \
            >>"$fixture/Sources/StatusTrioCore/App/Shared.swift"
        expect_fail_contains "private HAL selector 0x$hex_value base $base" \
            "HAL selector" run_audit_after_source_change "$fixture"
    done
done

make_fixture "$WORK/apple-smc"
printf '\nlet privateService = "AppleSMC"\n' \
    >>"$WORK/apple-smc/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "AppleSMC reference" "AppleSMC" run_audit_after_source_change "$WORK/apple-smc"

make_fixture "$WORK/powerd-path"
printf '\nlet privatePath = "/Library/Preferences/com.apple.powerd.charging.plist"\n' \
    >>"$WORK/powerd-path/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "private powerd plist path" "powerd.charging.plist" run_audit_after_source_change "$WORK/powerd-path"

make_fixture "$WORK/nat-key"
printf '\nlet privateKey = "com.apple.nat"\n' \
    >>"$WORK/nat-key/Sources/StatusTrioCore/App/Shared.swift"
expect_fail_contains "undocumented NAT key" "com.apple.nat" run_audit_after_source_change "$WORK/nat-key"

make_fixture "$WORK/privileged-xpc"
cat >>"$WORK/privileged-xpc/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let privilegedConnection = NSXPCConnection(
    machServiceName: "com.example.privileged-service",
    options: .privileged
)
SWIFT
expect_fail_contains "privileged NSXPC connection" "privileged NSXPC" run_audit_after_source_change "$WORK/privileged-xpc"

make_fixture "$WORK/root-helper"
cat >>"$WORK/root-helper/Sources/StatusTrioCore/App/Shared.swift" <<'SWIFT'

let rootHelper = SMAppService.daemon(
    plistName: "com.example.PowerHelper.plist"
)
SWIFT
expect_fail_contains "root helper registration" "root-helper" run_audit_after_source_change "$WORK/root-helper"

if [[ "$PASSED" -ne "$SCENARIOS" ]]; then
    fail "expected every offline scenario to pass"
fi

printf '\nOffline App Store source closure: %d/%d PASS\n' "$PASSED" "$SCENARIOS"
