#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioBackgroundConfig.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
cat > "$FIXTURE/main.swift" <<'SWIFT'
import Foundation
let flags = ["--background-ui-testing", "--test-display=secondary", "--test-open-status-panel"]
let configuration = BackgroundUITestingConfiguration(arguments: flags)
#if DEBUG
precondition(configuration.isEnabled)
precondition(configuration.display == .secondary)
precondition(configuration.opensStatusPanel)
precondition(!configuration.rejectsLaunch)
precondition(!BackgroundUITestingConfiguration(arguments: ["--test-display=secondary"]).diagnostics.isEmpty)
for flags in [
    ["--background-ui-testing", "--test-display=primary"],
    ["--background-ui-testing", "--background-ui-testing"],
    ["--test-display=secondary"],
    ["--test-open-status-panel"],
    ["--background-ui-testing", "--test-open-status-panel-typo"],
    ["--background-ui-testing", "--test-open-status-panel",
     "--test-open-status-panel"]
] {
    precondition(BackgroundUITestingConfiguration(arguments: flags).rejectsLaunch)
}
precondition(!BackgroundUITestingConfiguration(arguments: []).rejectsLaunch)
print("Debug configuration: explicit opt-in and diagnostics passed.")
#else
precondition(configuration == .disabled)
precondition(!configuration.rejectsLaunch)
precondition(BackgroundUITestingConfiguration(arguments: ["--background-ui-testing-typo"]) == .disabled)
print("Release configuration: testing arguments have no effect.")
#endif
SWIFT
for mode in debug release; do
    if [[ "$mode" == debug ]]; then
        swiftc -D DEBUG "$ROOT/Sources/StatusTrioCore/App/BackgroundUITestingConfiguration.swift" \
            "$FIXTURE/main.swift" -o "$FIXTURE/check"
    else
        swiftc -O "$ROOT/Sources/StatusTrioCore/App/BackgroundUITestingConfiguration.swift" \
            "$FIXTURE/main.swift" -o "$FIXTURE/check"
    fi
    "$FIXTURE/check"
done
