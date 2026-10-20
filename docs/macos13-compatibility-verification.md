# macOS 13 Compatibility Verification

## Scope and status

- Goal: one Universal app for macOS 13 Ventura and later, built with SDK 26+.
- Code baseline before implementation: `be80a4ce12d691cb9696127eacd94c0040694965`.
- Preflight code head: `c2ea2ccaef546ffa61377cfc718e44cbcc039865`.
- Superseded first successful preflight: `8ee4b6d042d3b6d386274d54093c42de342fe722`.
- Automated preflight: [run 37765927373](https://github.com/lingyired/status-trio/actions/runs/37765927373), success.
- Hardware runtime export: **not complete**. The authoritative macOS 13 Intel and Apple Silicon
  checklists remain **NOT RUN** until tested on those systems. Do not describe this build as
  fully supported on Ventura from the CI result alone.

## Automated evidence

- CI toolchain: macOS 26 runner, Xcode 26.6, Apple Swift 6.3.3.
- `Run tests`: passed; XCTest executed 1390 tests with 7 skipped and 0 failures, and Swift Testing
  ran 570 tests in 90 suites.
- `Run native compatibility tests`: passed; deployment contract, appcast fixture, bundle contract,
  native Helper tests, RPATH parser tests, and dependency parser tests all passed.
- `Build, sign, notarize, and publish` (`publish=false`): passed; Universal release app and
  `StatusTrio-1.5.1.dmg` were produced.
- Main app: `x86_64` and `arm64` each have `minos 13.0` / `sdk 26.0`.
- MobileBattery Helper and bundled dylibs: each reports `minos 13.0`; SDK values are `26.0` or
  `26.5` depending on the source build stage.
- `verify-mobile-battery-bundle.sh`: passed; architecture slices, RPATHs, dependency paths, and
  signatures were checked.
- Sparkle metadata: 5 Mach-O files checked, all with macOS minimums at or below 13.0.
- Artifact: `StatusTrio-1.5.1.dmg` (13,797,188 bytes),
  SHA-256 `5c43be21fd4b804ac87948c6fb75fcf0f9bc859725db915a04e3a1042bd6bcfd`.
- Packaging is Ad-hoc signed; this repository has no Developer ID certificate or notarization
  secrets. Do not claim notarization.

## Local automated evidence

- Local toolchain: Swift 6.4 / macOS SDK 27.0 / arm64 host; useful for development only.
- `swift test`: passed in the worktree before and after the changes.
- `swift build -c release`: passed after the deployment target was lowered to 13.0.
- `swift test --filter MacOS13UICompatibilityTests`: passed.
- `swift test --filter BluetoothBatteryLevelTextFallbackTests`: passed.
- `scripts/test-macos13-deployment-contract-regressions.sh`,
  `scripts/test-macos13-deployment-contract.sh`, and
  `scripts/test-appcast-minimum-system-version.sh`: passed. The regression
  fixture covers the automatic `grep` fallback and scanner failures; the
  deployment contract is also part of the release workflow's native checks.
- `scripts/test-macos13-bundle-contract.sh`: passed.
- `scripts/test-mobile-battery-helper.sh`, `scripts/test-mobile-battery-rpaths.sh`, and
  `scripts/test-otool-dependencies.sh`: passed.

## Verification status update (2026-10-21)

- Local toolchain: Xcode 27.0, Swift 6.4, macOS SDK 27.0, arm64 host.
- `swift test` passed three consecutive full runs (XCTest 1719, 7 skipped;
  Swift Testing 697 tests / 103 suites each run).
- `swift build -c release` passed. The native compatibility suite, including the
  deployment-contract regression script, passed locally.
- These are local automated checks only. The runtime matrix below still governs
  macOS 13 support; do not mark Ventura or Liquid Glass behavior as runtime-verified
  from this evidence.

## Runtime matrix

| Runtime | Architecture | Status | Evidence / remaining work |
| --- | --- | --- | --- |
| macOS 13 Ventura | Intel | NOT RUN | Need an actual Intel Ventura machine or VM; launch, settings navigation, keyboard, Wi-Fi, Bluetooth, audio, battery, and Sparkle startup are unverified. |
| macOS 13 Ventura | Apple Silicon | NOT RUN | Need an actual Apple Silicon Ventura machine or VM; same functional checklist as Intel. Do not substitute a newer host. |
| macOS 14 | Intel / Apple Silicon | NOT RUN | No runtime regression run. |
| macOS 15 | Intel / Apple Silicon | NOT RUN | No runtime regression run. |
| macOS 26 | Intel / Apple Silicon | NOT RUN | CI builds and tests only; no interactive app/runtime pass. |
| macOS 27 | arm64 local | PARTIAL | Local tests and release build passed; full app interaction not run. |

## Required manual Ventura checklist

1. Install the artifact or build from the same commit and launch it on Intel macOS 13.
2. Repeat on Apple Silicon macOS 13, using the same app bundle and build number.
3. Verify Wi-Fi name, scan, toggle, wired connection, VPN, and each Settings pane route.
4. Verify Bluetooth connect/disconnect, battery rows, AirPods case fallback, and permission denial.
5. Verify audio output, mute, volume slider, microphone input, and unavailable-device states.
6. Verify system battery, charging, low-battery updates, mobile device discovery, and trusted-device reads.
7. Verify settings card arrow keys, Space/Return, Tab, VoiceOver, and Reduce Motion.
8. Verify menu-bar-only, Dock-only, and both placement modes, including icon rendering parity.
9. Verify Sparkle update discovery/download/signature path against an isolated test feed.
10. Record PASS / FAIL / BLOCKED / NOT RUN for each item; do not infer success from CI.

## Git and release state

- Baseline: `be80a4ce12d691cb9696127eacd94c0040694965`.
- Verified preflight code head: `c2ea2ccaef546ffa61377cfc718e44cbcc039865`.
- Branch: `codex/macos13-compatibility`; preflight is `publish=false`, so the version `1.5.1`
  and build `19` remain unpublished.
- No merge, tag, GitHub Release, or online appcast update was performed by this work.
- The preflight artifact is `StatusTrio-1.5.1.dmg`; keep it as a test artifact, not as a release
  approval for Ventura. The missing Intel and Apple Silicon runtime tests are the remaining gate.
