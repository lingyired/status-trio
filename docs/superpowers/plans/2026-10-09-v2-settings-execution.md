# Status Trio 2.0 Icon Designer — Execution Ledger

- Worktree: `/Users/lingsmbp/.codex/worktrees/v2-icon-designer-plan/status-trio`
- Branch: `codex/v2-settings-icon-designer`
- Required base: `2ec5b81ce1f4731dca4d1f2ed61bfdbbb53e426e`
- Latest implementation commit (ledger-only commits excluded; verified with `git rev-parse cab9bd8`): `cab9bd8f5802be86f6d87d89cafe1e1387c53e8b`
- Continue only in this worktree. Do not merge `main`, publish a release/appcast, alter permissions/secrets, or modify other checkouts.
- User authorized full Phase 5 implementation (Tasks 0–12), push only this feature branch, draft PR, and a `publish=false` release preflight. No merge or formal release is authorized.

## Task status

| Task | Status | Evidence / remaining boundary |
|---|---|---|
| 0 — Classic compatibility baseline | Complete | Six concrete-output characterization tests and demand-ownership baseline. CPU/wakeups and hardware checks remain unmeasured. |
| 1 — Versioned configuration and validation | Complete | V1 composition/behavior/appearance, normalization, per-slot reset, schema-first codec. |
| 2 — Migration and atomic SettingsStore publish | Complete | One-time migration, old keys preserved, versioned snapshot is sole icon publisher, corrupt/future schema protected until explicit reset. |
| 3 — Slot resolver, fallback, constrained override | Complete | Primary/fallback/none, explicit source availability, per-slot mapping, redacted traces, constrained network override. |
| 4 — Freshness, VM wiring, redraw deduplication | Implemented; independent review pending | Four P2 fixes in `2614757e933aa2c2c2bf0a00e928f9d8bb62b6cc`; focused and full local gates passed. |
| 5 — Appearance, custom colors, cache parity | Implemented; independent review pending | Two P2 fixes in `235aec17ba9f9fc3a541bfc4b54f2ff69ec73adb`; alpha/inactive-track raster and cache tests plus full local gates passed. |
| 6 — Production-pipeline state simulation | Core complete | Deterministic value scenarios + resolver parity tests committed as `cab9bd8f5802be86f6d87d89cafe1e1387c53e8`. Scenario picker/localized explanations belong to Task 9; no monitor/store mutation or additional requests. |
| 7 — Settings navigation and feature reachability | Not started | |
| 8 — Source/Behavior/Appearance editor and Classic | Not started | |
| 9 — Diagnostics, localization, accessibility, preview lifecycle | Not started | |
| 10 — Phase 4 core delivery gate | Not started | |
| 11 — AirPods source adapter and owner-aware demand | Not started | |
| 12 — AirPods ring geometry, preview, final gate | Not started | |

## Verified decisions and review record

- Tasks 0–1 fixed-commit Luna/high review: no blocking findings (user-reported). Task commits: `f539abb8acec6e83afea80f34bef93f67e6467fa`, `2030a8ff0b60a2f1e67a0e908ed243619dcd1b94`, `3692dc69ce06683d984a01dcbadea7d606c917cf`.
- Task 3 fixture ruling: the legacy network scale is `1.0` (the earlier `1.6` expectation was inconsistent with `ConnectionIconOptions.standard`). Trace exposes source enum IDs only. Network-problem override applies only to explicit Bluetooth-audio primary and existing no-internet/off/not-associated/unavailable cases; offline does not trigger it.
- Task 2–3 review fixes: `0422eb4fbed8fe197dff450da075a62d846f0e51` changed missing source values from `.available(false)` to explicit unavailable, honored the saved pinned Bluetooth symbol, and limited legacy battery-percentage precedence to `automaticLegacy`. User-reported independent re-review confirmed all three findings resolved. Local gate at that commit: 1458 XCTest, 7 skipped, 0 failures; Swift Testing 573 tests / 90 suites; release build and `git diff --check` passed.
- Task 4 original feature commit: `2d8240b3f61c6ab4031c3213f7130b1da3189b4f`. Follow-up review fixes at `2614757e933aa2c2c2bf0a00e928f9d8bb62b6cc`: only schedule hold expiry for unknown/stale held data; retain per-slot last valid payload during the bounded hold; treat wired Ethernet as Network-available with Wi-Fi off; preserve Classic no-battery legacy ring via `automaticLegacy`. RED gate had 13 failures across expiry, payload, wired-network, and Classic behavior; focused GREEN gate passed 38 tests. Full gate then passed 1478 XCTest / 7 skipped and 573 Swift Testing tests; release build and diff check passed. Independent review of this fix is pending.
- Task 5 feature commit: `ed252b7ad45d8c6326298694e1e6367705d23017`. Follow-up review fixes at `235aec17ba9f9fc3a541bfc4b54f2ff69ec73adb`: charging animation opacity now respects custom base alpha, and semantic inactive color flows through ring/footer tracks, volume dots, Dock static scene and cache identity. RED raster/cache regressions produced 12 failures; focused GREEN passed 13 tests. Full gate passed 1481 XCTest / 7 skipped and 573 Swift Testing tests; release build and diff check passed. Independent review of this fix is pending.
- Task 6 tests were first run before implementation and failed to compile because `IconPreviewScenario` did not yet exist (expected RED). The first GREEN run exposed an incorrect test assumption that Classic enabled network override; corrected the assertion to compare against the legacy production mapper. Final focused `swift test --filter IconPreviewScenarioTests` passed 5 Swift Testing tests. Scenarios are Live, Network healthy, Network no Internet, Wi-Fi off + Ethernet, charging, critical battery, and muted. Availability for the changed system sources is recomputed from the synthetic snapshot; other narrow source availability is retained. Fallback and override resolver paths are explicitly exercised. Live returns the exact input.
- Task 6 full gate (after changes): `swift test --quiet` passed 1481 XCTest, 7 skipped, 0 failures; Swift Testing passed 578 tests in 91 suites. `swift build -c release` completed successfully; `git diff --check` passed. This is local toolchain evidence only (Swift 6.4 / SDK 27, not CI Swift 6.3.3). No UI, VoiceOver, or hardware validation is claimed.
- At resume, the HEAD was verified as `bdd97853ac11ac2b05599501a15442bd12794323`, with no active Swift test/build/CI process and only the two user-provided plan/spec files untracked. The implementation commit for Task 6 is exactly `cab9bd8f5802be86f6d87d89cafe1e1387c53e8b`.

## Next actions

1. Before each task and heavy review, call `get_usage_limits`; stop starting model-heavy work if the 5-hour remaining allowance is below 3%, update this ledger, and report the Unix reset time. Current last observed reading: used 21%, remaining 79%, `resetsAt=1791502308`.
2. Continue Task 7 next, test-first. Preserve the two untracked user files. Stage explicit paths only; never use `git add .`.
3. After Tasks 7–12, run the final full test/release, localization/plist lint, SDK/package validation, appcast-note validation, non-publishing CI, and local acceptance build/DMG. Recheck the live appcast before choosing the preflight build; user-provided prior read was published build 17 and local baseline build 18, candidate 19. Never publish or merge.
4. Prepare the authorized push and draft PR, attach it after creation, and retain the CI run ID/result. Record every failed CI run with stage/root cause/fix/verification in `docs/swift-ci-compatibility.md`.
5. Write a tomorrow acceptance checklist. Clearly label UI, VoiceOver, macOS 13, device, sleep/wake, CPU/wakeup, and real AirPods checks as unverified unless actually performed.
