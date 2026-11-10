# Battery runtime subtitle implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement issue #298 with the default subtitle display selected by the user.
**Architecture:** Carry positive IOKit runtime minutes through the existing battery snapshot and format them in the panel mapper. Keep notification cadence, existing charging handling, and icon rendering unchanged.
**Tech Stack:** Swift, Foundation, IOKit, XCTest.
**Spec:** `docs/superpowers/specs/2026-11-08-battery-time-design.md`

## Global constraints

macOS 13+; no new polling, stored settings, dependencies, or rendering changes. All 12 shipped languages must translate new copy; duration units must use the selected app language and handle plurals.

## Review focus

Stale estimates after connecting power; missing/zero/negative readings; Low Power Mode priority; language override versus system locale; updates where percentage does not change. Tests below cover each.

### Task 1: Carry and display the runtime estimate

**Files:** BatteryMonitor.swift; Models/StatusSnapshot.swift; Presentation/Panel/PanelPresentationMapper.swift; Localization/LocalizationKey.swift; all Resources/*/Localizable.strings; BatteryMonitorTests.swift; PanelPresentationTextTests.swift; UI/BatteryStatusView.swift; BatteryDetailsLayoutTests.swift; StatusPanelViewModelTests.swift.
**Interfaces:** Add optional `Int` `timeToEmptyMinutes`, default nil, alongside `timeToFullChargeMinutes` in BatteryReading and BatteryStatus. Existing initializer calls remain valid. `batterySubtitle` keeps its signature.

- [x] Add parser tests for positive NSNumber minutes and missing/zero/negative values. Add monitor tests for power transitions, absent batteries, and estimate-only updates.
- [x] Add subtitle tests for 1/2/59/60/61/85/120 minutes, unknown values, state priority, English plurals, Chinese output, every shipped language, and accessibility parity.
- [x] Run `bash scripts/test.sh 'BatteryMonitorTests|PresentationTextMapperTests'`; expect failure because the field/behavior does not exist.
- [x] Implement the fields, positive estimate parsing, and discharge-only snapshot propagation. Add localized duration output and translated wrapper copy, retaining other state priority.
- [x] Run `bash scripts/test.sh 'BatteryMonitorTests|PresentationTextMapperTests|PanelPresentationMapperTests|StatusSnapshotTests|LocalizationTests|LocalizationParityTests'`; expect PASS.
- [x] Fetch origin/main and inspect the final diff and shared-file overlap; run `bash scripts/verify-local.sh full` once on the final integrated tree. Expect PASS; report any unrelated blocker without changing unrelated code.
- [x] Request a fresh read-only whole-change review. Address substantive findings, verify affected scope, and commit on the feature branch. Do not merge or publish.

## Validation record (2026-11-08)

- Base: fresh `origin/main` at `cd8699916d3aed7c988a82dbbddae1197ea60fc1`; isolated branch `feat/issue-298-battery-time`. The original checkout's concurrent Keep Awake edits were preserved. Shared-file overlap is limited to LocalizationKey.swift and translations; no merge was performed.
- Baseline focused tests: 39 XCTest passed. New API tests first failed because the estimate field/key were absent. After implementation: 112 focused XCTest and one Swift Testing test passed.
- New offscreen wrapping test first failed 24 assertions, then all eight BatteryDetailsLayoutTests passed. Inspected English, Chinese, German, and Arabic snapshots. No native window was presented.
- Estimate-only panel-update integration test passed with a constant 72% battery level.
- Independent read-only review: no critical, important, or minor findings.
- `bash scripts/verify-local.sh full`: **FAIL** at Swift tests. XCTest executed 2820 tests (82 skipped), with two assertions failing in `AppIconPreviewTests.testCommittedIconComposerArtworkMatchesTheRenderer`. Swift Testing ran 952 tests (41 explicitly skipped), with one issue in `ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint`.
- A pristine `git archive origin/main` source tree reproduced both failures with identical artwork/static-render fingerprints. No rendering code, artwork, fingerprint expectations, or test tolerances were changed. The full profile remains failed; its later stages are checked separately below rather than represented as a green full profile.
- `swift build -c release`: **PASS**, Xcode 27.2 / Swift 6.4.2 / SDK 27.2.
- Hardware battery accuracy, live UI/VoiceOver, idle power measurement, Ventura/current-macOS app runtime, Developer ID signing, notarization, Universal packaging, and publication: **NOT RUN**.
- `UNIVERSAL_BUILD=0 bash scripts/build-worktree.sh release no-open`: **BLOCKED** during MobileBattery dependency preparation because `command -v autoconf` fails. The dependency bounds and build scripts were not changed. A complete app bundle was not produced; bundle-specific platform/MobileBattery/Helper contract checks remain **NOT RUN**.
- All 27 native/offline check scripts enumerated by `verify-local.sh full` were run individually after its Swift-test stop: **27/27 PASS**. These use fixture/fake-tool contracts and do not replace the blocked actual app-bundle checks.
- Final `origin/main` fetch still resolved to the same base SHA. `git diff --check`: **PASS**. Verification ran on the final implementation tree before commit; only this documentation record changed afterward.
