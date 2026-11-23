#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioFocusCoverage.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
cat "$ROOT/scripts/measure-ui-focus.swift" > "$FIXTURE/main.swift"
cat >> "$FIXTURE/main.swift" <<'SWIFT'
import Foundation

let first = FocusTargetIdentity(pid: 10, path: "/test/StatusTrio.app", launchedAt: Date(timeIntervalSince1970: 1))
let second = FocusTargetIdentity(pid: 11, path: first.path, launchedAt: first.launchedAt)
var coverage = FocusTargetCoverage(expectedPID: nil)
precondition(coverage.observe([], elapsed: 0) == .waiting)
precondition(coverage.identity == nil)
precondition(coverage.observe([first], elapsed: 1) == .bound)
precondition(coverage.boundAt == 1)
precondition(coverage.observe([first], elapsed: 2) == .tracking)
precondition(coverage.observe([], elapsed: 3) == .ended("target-disappeared"))
precondition(coverage.observe([second], elapsed: 4) == .ended("target-disappeared"))
precondition(coverage.identity == first)

var replacement = FocusTargetCoverage(expectedPID: nil)
precondition(replacement.observe([first], elapsed: 0) == .bound)
precondition(replacement.observe([second], elapsed: 1) == .ended("target-identity-changed"))

var reusedPID = FocusTargetCoverage(expectedPID: nil)
precondition(reusedPID.observe([first], elapsed: 0) == .bound)
let recycled = FocusTargetIdentity(pid: first.pid, path: first.path, launchedAt: Date(timeIntervalSince1970: 2))
precondition(reusedPID.observe([recycled], elapsed: 1) == .ended("target-identity-changed"))

var ambiguous = FocusTargetCoverage(expectedPID: nil)
precondition(ambiguous.observe([first, second], elapsed: 0) == .ended("multiple-targets"))

var expected = FocusTargetCoverage(expectedPID: first.pid)
precondition(expected.observe([], elapsed: 0) == .waiting)
precondition(expected.observe([second], elapsed: 1) == .ended("unexpected-pid"))
for incomplete in [
    FocusTargetIdentity(pid: first.pid, path: nil, launchedAt: first.launchedAt),
    FocusTargetIdentity(pid: first.pid, path: first.path, launchedAt: nil)
] {
    var unavailable = FocusTargetCoverage(expectedPID: nil)
    precondition(unavailable.observe([incomplete], elapsed: 0) == .ended("target-identity-unavailable"))
}
print("Focus coverage: pending launch, binding, disappearance, replacement, PID reuse, ambiguity, expected PID and missing identity passed.")
SWIFT
swiftc -D FOCUS_COVERAGE_TESTS "$FIXTURE/main.swift" -o "$FIXTURE/check"
"$FIXTURE/check"
