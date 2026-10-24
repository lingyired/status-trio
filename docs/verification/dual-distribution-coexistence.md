# Dual-Distribution Coexistence Verification

Date: 2026-10-23

Scope: Direct/Store single-instance lock-path coexistence and Launch at Login
identity review for the foundation worktree.

- Base/Phase A commit: `95858e076a91bf4837f8101d681b23e6d7d8b1f5`
- Branch after parent integration: `codex/dual-distribution-platform`
- Worktree: `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`
- Toolchain: Xcode 27.0 (27A266a), Swift 6.4, macOS SDK 27.0
- Changed files: `Sources/StatusTrioCore/App/SingleInstanceGuard.swift`,
  `Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift`, this report
- Index/HEAD: no index operation, commit, push, merge, or release by the
  implementation worker

## Implementation

`SingleInstanceGuard.acquire()` remains the app entry point and delegates to
`acquireDefault()`. Its path comes from a pure resolver that takes an explicit
`DistributionChannel`, the actual Bundle ID, and injectable path roots.
`defaultLockPath` remains available as an optional compatibility accessor; it
has no production caller in this change.

- Direct keeps the historical
  `<home>/Library/Application Support/StatusTrio/<actual Bundle ID>.lock`
  location.
- Store uses
  `FileManager.default.urls(for: .applicationSupportDirectory,
  in: .userDomainMask).first`, then appends `StatusTrio` and the actual Bundle
  ID lock name. This is the container-aware lookup; no receipt, environment
  variable, or production-ID override is used.
- If Store cannot resolve that container-aware root, acquisition returns
  `.lockUnavailable` and terminates the launch. It never substitutes the
  unsandboxed home-relative path.
- `acquireDefault()` accepts the full set of injection points, including
  `homeDirectory` and `applicationSupportDirectory`, so tests exercise the same
  resolver and rejection path without touching a user's real Application
  Support directory.
- The existing lock filename fallback and sanitization remain unchanged.
- The existing `flock` acquisition/rejection behavior remains unchanged.

No launch source was changed. `AppDelegate` already calls
`SingleInstanceGuard.acquire()` after taking the actual process identity from
`Bundle.main.bundleIdentifier`, and the compiled channel comes from
`STATUS_TRIO_APP_STORE`. No launch-at-login bug was found.

## Launch at Login Review

`SystemLaunchAtLoginService` uses `SMAppService.mainApp` for status,
registration, and unregistration. That API is tied to the running app's actual
code identity; the implementation does not substitute
`DistributionChannel.productionBundleIdentifier` for a development build.
The support gate also checks that `Bundle.main.bundleURL` is an `.app` bundle.

Tests use only `FakeLaunchAtLoginService`. No system login item was registered,
unregistered, or inspected.

## Test Evidence

First focused run intentionally failed before the implementation existed:

- `.build/dual-distribution-logs/d-single-instance-red.log`
- Exit: `1`
- Cause: `defaultLockPath` was still a `String` property, so the new
  channel/root-injected calls could not compile.

Fail-closed follow-up RED:

- `.build/dual-distribution-logs/d-single-instance-fail-closed-red.log`
- Exit: `1`
- Cause: the new missing-root test called `acquireDefault`, which did not exist.

Final focused run after the fail-closed implementation:

```bash
bash scripts/test.sh 'SingleInstanceGuardTests'
```

- Exit: `0`
- Result: 14 tests, 0 failures
- Log: `.build/dual-distribution-logs/d-single-instance-final.log`

Covered cases:

1. Direct retains the home-relative Application Support path.
2. Store selects the injected container-aware root and does not use the
   unsandboxed home path; a missing root fails closed.
3. Each channel uses the actual passed Bundle ID, including development IDs.
4. Direct and Store IDs in one temporary root can both hold `flock` locks.
5. The same ID refuses a second guard and can acquire again after release.
6. Two isolated `UserDefaults` suites do not share a probe value; both suites
   are removed explicitly and checked absent, with `defer` as failure cleanup.
7. Existing same-path, cross-process, unusable-directory, and unusable-file
   coverage remains green.

The final SwiftPM build emitted one pre-existing warning in
`MemoryPressureMonitor.swift` (`nonisolated(unsafe)` is unnecessary for a
`Sendable` constant). It is outside this change and did not affect the test
result.

## Runtime Status

| Item | Status |
| --- | --- |
| Pure path resolution | PASS |
| Missing Store support root fails closed | PASS |
| Same-process lock contention/release | PASS |
| Different-ID concurrent locks in one temp root | PASS |
| Different defaults suites isolation/cleanup | PASS |
| Existing Direct lock tests | PASS |
| Real sandboxed Store process | NOT RUN |
| Real Direct + Store installation/coexistence | NOT RUN |
| User TCC/privacy permissions | NOT RUN; no permission prompt was invoked |
| Real `SMAppService.mainApp` registration | NOT RUN; no system login item was changed |
| macOS 13 Ventura runtime | NOT RUN |
| Full local verification | PASS on the final integrated tree; separate final record |
| Universal/signing/notarization/DMG/release | NOT RUN |

The tests prove path selection and `flock` semantics with real temporary files.
They do not prove App Sandbox behavior, container creation, cross-application
observed coexistence, login-item approval, or hardware/runtime behavior.
