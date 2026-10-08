# Status Trio 2.0 Icon Designer — Execution Ledger

- Worktree: `/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio`
- Branch: `codex/v2-settings-icon-designer`
- Required base: `2ec5b81ce1f4731dca4d1f2ed61bfdbbb53e426e`
- Latest code commit (ledger-only commits excluded; verified with `git rev-parse HEAD`): `f736739b6336d206dffcb0785edb708bb1c0a8a3`
- Continue only in this worktree. Do not merge `main`, publish a release/appcast, alter permissions/secrets, or modify other checkouts.
- User authorized full Phase 5 implementation (Tasks 0–12), push only this feature branch, draft PR, and a `publish=false` release preflight. No merge or formal release is authorized.

## Task status

| Task | Status | Evidence / remaining boundary |
|---|---|---|
| 0 — Classic compatibility baseline | Complete | Six concrete-output characterization tests and demand-ownership baseline. CPU/wakeups and hardware checks remain unmeasured. |
| 1 — Versioned configuration and validation | Complete | V1 composition/behavior/appearance, normalization, per-slot reset, schema-first codec. |
| 2 — Migration and atomic SettingsStore publish | Complete | One-time migration, old keys preserved, versioned snapshot is sole icon publisher, corrupt/future schema protected until explicit reset. |
| 3 — Slot resolver, fallback, constrained override | Complete | Primary/fallback/none, explicit source availability, per-slot mapping, redacted traces, constrained network override. |
| 4 — Freshness, VM wiring, redraw deduplication | Complete | Four P2 fixes in `2614757e933aa2c2c2bf0a00e928f9d8bb62b6cc`; focused and full local gates passed. |
| 5 — Appearance, custom colors, cache parity | Complete | Two P2 fixes in `235aec17ba9f9fc3a541bfc4b54f2ff69ec73adb`; alpha/inactive-track raster and cache tests plus full local gates passed. |
| 6 — Production-pipeline state simulation | Core complete | Deterministic value scenarios + resolver parity tests in `cab9bd8f5802be86f6d87d89cafe1e1387c53e8`, with muted Bluetooth metadata regression fixed in `1076542513e56a07904dda1999d470e71f5557e6`. Scenario picker/localized explanations belong to Task 9; no monitor/store mutation or additional requests. |
| 7 — Settings navigation and feature reachability | Complete | Navigation defaults to Icon Designer; all four device pages and other legacy pages remain reachable. Existing pinned-preview/scroll page reused as the Designer shell; slot editors follow in Task 8. Window close visibility cleanup remains covered by existing controller tests. Commit `ac903aa4547274adcd90af99fa4a73a90bf40887`. |
| 8 — Source/Behavior/Appearance editor and Classic | Complete | Source-aware editing, slot swap/reset, source-specific behavior and appearance, Classic confirmation, global placement/Dock settings retained; validation documented below. |
| 9 — Diagnostics, localization, accessibility, preview lifecycle | Not started | |
| 10 — Phase 4 core delivery gate | Not started | |
| 11 — AirPods source adapter and owner-aware demand | Not started | |
| 12 — AirPods ring geometry, preview, final gate | Not started | |

## Verified decisions and review record

- Tasks 0–1 fixed-commit Luna/high review: no blocking findings (user-reported). Task commits: `f539abb8acec6e83afea80f34bef93f67e6467fa`, `2030a8ff0b60a2f1e67a0e908ed243619dcd1b94`, `3692dc69ce06683d984a01dcbadea7d606c917cf`.
- Task 3 fixture ruling: the legacy network scale is `1.0` (the earlier `1.6` expectation was inconsistent with `ConnectionIconOptions.standard`). Trace exposes source enum IDs only. Network-problem override applies only to explicit Bluetooth-audio primary and existing no-internet/off/not-associated/unavailable cases; offline does not trigger it.
- Task 2–3 review fixes: `0422eb4fbed8fe197dff450da075a62d846f0e51` changed missing source values from `.available(false)` to explicit unavailable, honored the saved pinned Bluetooth symbol, and limited legacy battery-percentage precedence to `automaticLegacy`. User-reported independent re-review confirmed all three findings resolved. Local gate at that commit: 1458 XCTest, 7 skipped, 0 failures; Swift Testing 573 tests / 90 suites; release build and `git diff --check` passed.
- Task 4 original feature commit: `2d8240b3f61c6ab4031c3213f7130b1da3189b4f`. Follow-up review fixes at `2614757e933aa2c2c2bf0a00e928f9d8bb62b6cc`: only schedule hold expiry for unknown/stale held data; retain per-slot last valid payload during the bounded hold; treat wired Ethernet as Network-available with Wi-Fi off; preserve Classic no-battery legacy ring via `automaticLegacy`. RED gate had 13 failures across expiry, payload, wired-network, and Classic behavior; focused GREEN gate passed 38 tests. Full gate then passed 1478 XCTest / 7 skipped and 573 Swift Testing tests; release build and diff check passed. User-scoped review confirmed all six findings resolved.
- Task 5 feature commit: `ed252b7ad45d8c6326298694e1e6367705d23017`. Follow-up review fixes at `235aec17ba9f9fc3a541bfc4b54f2ff69ec73adb`: charging animation opacity now respects custom base alpha, and semantic inactive color flows through ring/footer tracks, volume dots, Dock static scene and cache identity. RED raster/cache regressions produced 12 failures; focused GREEN passed 13 tests. Full gate passed 1481 XCTest / 7 skipped and 573 Swift Testing tests; release build and diff check passed. User-scoped review confirmed all six findings resolved.
- Task 6 tests were first run before implementation and failed to compile because `IconPreviewScenario` did not yet exist (expected RED). The first GREEN run exposed an incorrect test assumption that Classic enabled network override; corrected the assertion to compare against the legacy production mapper. Final focused `swift test --filter IconPreviewScenarioTests` passed 5 Swift Testing tests. Scenarios are Live, Network healthy, Network no Internet, Wi-Fi off + Ethernet, charging, critical battery, and muted. Availability for the changed system sources is recomputed from the synthetic snapshot; other narrow source availability is retained. Fallback and override resolver paths are explicitly exercised. Live returns the exact input.
- Task 6 full gate (after changes): `swift test --quiet` passed 1481 XCTest, 7 skipped, 0 failures; Swift Testing passed 578 tests in 91 suites. `swift build -c release` completed successfully; `git diff --check` passed. This is local toolchain evidence only (Swift 6.4 / SDK 27, not CI Swift 6.3.3). No UI, VoiceOver, or hardware validation is claimed.
- At resume, the HEAD was verified as `bdd97853ac11ac2b05599501a15442bd12794323`, with no active Swift test/build/CI process and only the two user-provided plan/spec files untracked. The implementation commit for Task 6 is exactly `cab9bd8f5802be86f6d87d89cafe1e1387c53e8b`.

## Next actions

1. Before each task and heavy review, call `get_usage_limits`; stop starting model-heavy work if the 5-hour remaining allowance is below 3%, update this ledger, and report the Unix reset time. Latest observed reading: used 33%, remaining 67%, `resetsAt=1791502308`.
2. Continue Task 9 next, test-first. Preserve the two untracked user files. Stage explicit paths only; never use `git add .`.
3. After Tasks 7–12, run the final full test/release, localization/plist lint, SDK/package validation, appcast-note validation, non-publishing CI, and local acceptance build/DMG. Recheck the live appcast before choosing the preflight build; user-provided prior read was published build 17 and local baseline build 18, candidate 19. Never publish or merge.
4. Prepare the authorized push and draft PR, attach it after creation, and retain the CI run ID/result. Record every failed CI run with stage/root cause/fix/verification in `docs/swift-ci-compatibility.md`.
5. Write a tomorrow acceptance checklist. Clearly label UI, VoiceOver, macOS 13, device, sleep/wake, CPU/wakeup, and real AirPods checks as unverified unless actually performed.


## Latest review and Task 7 continuation

- User-scoped review of `2614757` and `235aec1` confirmed the prior six P2 findings resolved and reported two new issues. (1) `.fixed` color made active and inactive roles identical; introduce shared `IconColorRole.inactiveTrackOpacity = 0.22` attenuation for fixed inactive colors and use it in rendering; `.semanticOverrides([.inactive: color])` still uses the exact user-selected color. Added raster coverage for volume 0/100% and ring progress 0/100% on Menu Bar and Dock. RED failed both paired raster-difference assertions; focused GREEN `swift test --filter IconPaletteResolverTests` passed 14 XCTest tests. (2) `.volumeMuted` discarded `VolumeStatus` identity/metadata and could fall from Bluetooth primary to Network. It now changes only scalar/muted while preserving device name, output devices, current Bluetooth device, capabilities, and the live audio symbol. Bluetooth Live→Muted→latest Live regression initially failed current-device preservation and center equality; GREEN `swift test --filter 'IconPreviewScenarioTests|IconPaletteResolverTests'` passed 14 XCTest and 6 Swift Testing tests.
- Both review fixes are in `1076542513e56a07904dda1999d470e71f5557e6` (`fix: preserve fixed palette contrast and Bluetooth preview`). After both fixes, `swift test --quiet` passed 1482 XCTest (7 skipped, 0 failures) and 581 Swift Testing tests / 92 suites; `swift build -c release` passed; `git diff --check` passed. This is local Swift 6.4 / SDK 27 validation, not CI Swift 6.3.3.
- Task 7 RED: new `SettingsNavigationModelTests` first failed to compile because the model did not exist. After adding the model, the existing `SettingsViewTests` correctly caught its stale `.appIcon` expectation; updated it to `.iconDesigner`. Final focused gate `swift test --filter 'SettingsNavigationModelTests|SettingsViewTests'` passed 7 XCTest and 2 Swift Testing tests. Task 7 full run before review follow-ups passed 1481 XCTest (7 skipped) and 580 Swift Testing tests / 92 suites; release build passed. Existing `SettingsWindowControllerTests.testSettingsWindowTogglesVolumeDetailsVisibility` continues to exercise closing-window visibility cleanup.
- Task 7 code commit SHA: `ac903aa4547274adcd90af99fa4a73a90bf40887`. User-provided plan/spec files remain untracked and untouched.


## Independent review and Task 8 completion

- User reports the independent review of commits `2614757` and `235aec1` confirmed all six earlier Task 4/5 P2 findings resolved. The separate review of Task 7 commit `ac903aa` reported no P1/P2 findings and confirmed legacy device pages remain reachable, Designer defaults, and the placement/Dock path and Settings lifecycle/route are preserved. These were static reviews; no UI interaction is claimed.
- The two follow-up P2 findings on Task 6 (fixed-palette inactive contrast and preserving live Bluetooth metadata in muted preview) were fixed test-first in `1076542513e56a07904dda1999d470e71f5557e6`; user reports review confirmed both resolved.
- Task 8 editing tests started RED because `IconDesignerEditingModel` was absent. Added behavior tests for editing fallback without changing primary, explicit primary/fallback swap preserving both source configurations, rejecting duplicate primary as fallback, excluding Phase 5 AirPods until enabled, keeping configured unavailable values visible, slot reset isolation, Bluetooth override constraints, and Classic reset preserving Dock background and background permission. The test suite also exposed and led to removal of duplicate controls in Battery/Network/Bluetooth/Audio pages; those pages route to the Designer while retaining device-specific settings. Global placement, menu bar size, and Dock background settings are shared through `IconSurfaceSettings` in the Designer. Task 8 code commit: `f736739b6336d206dffcb0785edb708bb1c0a8a3`.
- Task 8 verification: `swift test --quiet` passed 1491 XCTest (7 skipped, 0 failures) and 581 Swift Testing tests in 92 suites; `swift build -c release` passed; `git diff --check` passed. Local evidence is Swift 6.4 / SDK 27, not CI Swift 6.3.3. UI/keyboard/VoiceOver behavior was not manually tested.
- Last code commit SHA before this ledger-only commit is `f736739b6336d206dffcb0785edb708bb1c0a8a3`, verified by `git rev-parse HEAD`. The user-provided plan/spec files remain untracked and untouched.
