# Task 11 Demand Review Fixes Implementation Plan

> **For agentic workers:** This bounded task is being implemented on `codex/v2-demand-review-fixes`; do not expand into Task 12.

**Goal:** Fix the four accepted findings from review of Task 11 commit `974942e5e98d38555447f250a4023ca8a74386c5` with deterministic regression tests.

**Architecture:** Deliver `@Published` demand invalidations on the main queue so callbacks run after the publishing assignment and outside any bridge reconciliation that caused the publication. Keep token ownership per surface and timestamp accessory observations at successful fallback merge. No new polling, discovery, permissions, or broad refactor.

**Tech Stack:** Swift 6 / Combine / XCTest; macOS 13 minimum and CI Swift 6.3.3.

**Spec:** Bounded review-fix request for Task 11 in the parent task prompt.

## Global Constraints

- Edit only `AppEnvironment.swift`, `IconSourceDemandBridge.swift` when necessary, `BluetoothDeviceController.swift`, `SystemStatusStore.swift`, related tests, and this plan.
- Do not edit scene, renderer, configuration, UI, source snapshot, shared ledger, main checkout, or Task 12 worktree.
- Before commit run `swift test`, `swift build -c release`, and `git diff --check`; do not push, open a PR, run CI, or merge.
- Preserve Swift 6.3.3 compatibility, macOS 13 support, weak callback captures, explicit closures for actor-isolated calls, and scoped commits.

## Review Focus

- Synchronous `@Published` reentrancy during activation/battery release — real controller publisher plus 20 configuration transitions; verify serialized reconciliation and final claims.
- A single connection event while the popover is closed — actual controller publisher must restore demand and connected-source availability without waiting for another availability transition.
- Primary battery failure plus useful accessory fallback — assert observation timestamp exists and data becomes stale after the freshness interval.
- Popover and Settings/icon token ordering — exercise `setPopoverVisible` and prove only the final owner release stops monitoring.

### Task 1: Serialize demand invalidations and consume committed state

**Files:** `Sources/StatusTrioCore/App/AppEnvironment.swift`, `Tests/StatusTrioCoreTests/IconDependencyDemandTests.swift`

- [x] Add controller-publisher regression for 20 demand configuration changes.
- [x] Add closed-popover single connection-event regression checking battery demand and connected source availability.
- [x] Deliver settings, device/battery, and availability publisher events asynchronously on the main queue; keep weak environment captures and explicit actor-isolated closures.
- [x] Run focused demand tests.

### Task 2: Preserve freshness for successful accessory fallback

**Files:** `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`, `Tests/StatusTrioCoreTests/BluetoothAccessoryBatteryEventTests.swift`

- [x] Add a primary-nil/accessory-valid regression checking current observation time and expiration.
- [x] Stamp the successful non-empty merged fallback at observation time.
- [x] Run the focused test; initial RED confirmed nil timestamp before the fix.

### Task 3: Keep popover activation independently owned

**Files:** `Sources/StatusTrioCore/Store/SystemStatusStore.swift`, `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`

- [x] Add `setPopoverVisible` coverage for Settings closing while the popover remains visible and icon ownership surviving popover close.
- [x] Always acquire the popover token when authorized, preserve its ownership bit across Settings toggles, and release it on close.
- [x] Run the focused lifetime test.

### Task 4: Verify and commit bounded changes

- [x] Run all four focused test areas.
- [x] Run the full `swift test` (1,532 XCTest cases, 7 skipped, 0 failures; 582 Swift Testing checks), `swift build -c release`, and `git diff --check`; logs are in `/tmp/v2-demand-review-fixes-swift-test.log` and `/tmp/v2-demand-review-fixes-swift-build-release.log`.
- [x] Review exact file scope and create an explicit-path commit on `codex/v2-demand-review-fixes`.
- [x] Report full `git rev-parse HEAD` SHA, test/build result, remaining manual validation, and risks. No UI/hardware validation is claimed.

## Follow-up: Reject revoked demand in deferred settings notifications

Scoped review of `adf0d5f64019d59f1f7d6fbfc81c9870c9c5b135` accepted the original four fixes but identified a new P2: the deferred settings sink still carried historical configuration/opt-in tuples. With an independent Settings owner already active and connected AirPods cached, enabling and then withdrawing demand in one main-actor turn could start battery I/O before the queued final cancellation. Releasing that claim did not undo the read.

The settings sink now treats delivered tuples as invalidations and reads the current committed `SettingsStore` values when it runs, matching the already-deferred device/availability paths. Main-queue delivery and weak environment captures remain unchanged.

Regression coverage uses real `SettingsStore` publishers, the actual `AppEnvironment.start()` subscription, and a real `BluetoothDeviceController` held active by the Settings token. The two cases enable AirPods + opt-in and immediately revoke either the opt-in or the configuration before draining the queue. They assert no increase in accessory-event registration or battery-read entry counts, no final battery claim, and continued Settings activation. A positive control verifies retained demand still claims and reads. The existing telemetry lifecycle test shares environment assembly only; the old direct-bridge tests are not used as a substitute for the settings-queue regression.

- [x] RED: both integration cases failed with one event claim and one battery read on the previous production code (`/tmp/v2-demand-queued-settings-red.log`).
- [x] Minimal production fix in `AppEnvironment.swift` only.
- [x] Focused GREEN: 11 AppEnvironment/demand tests passed (`/tmp/v2-demand-queued-settings-green.log`).
- [x] Full `swift test`: 1,534 XCTest cases, 7 skipped, 0 failures; 582 Swift Testing checks passed (`/tmp/v2-demand-queued-settings-full-test.log`).
- [x] `swift build -c release` passed (`/tmp/v2-demand-queued-settings-release.log`); `git diff --check` passed before follow-up commit. Local toolchain is Swift 6.4; CI Swift 6.3.3 was not run.

Follow-up scope is only `AppEnvironment.swift`, `AppEnvironmentTelemetryLifecycleTests.swift`, and this document. No controller, bridge, store, scene, configuration, UI, renderer, source-snapshot, shared-ledger, or Task 12 changes. No push, PR, CI, merge, UI, or hardware validation.
