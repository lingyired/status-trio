# Legacy charge limit: lifetime, launch re-apply, self-heal, polish

Date: 2026-11-26
Branch: `fix/207-charge-limit-compat`
Scope: macOS 13–15 legacy limiter only. The group is hidden on macOS 16+;
nothing here touches the macOS 26.4+ native charge path.

## Goal

Make the legacy limiter predictable and self-correcting while keeping the
decided lifetime model: **only in force while the app runs**. On exit/crash the
helper restores stock (existing behaviour). Users who want it after a reboot use
the app's existing **Launch at Login**; on launch the app re-applies the last
ceiling. Drift caused by the system resetting the keys self-heals on wake, AC
plug-in, and when the Settings pane opens; a value owned by someone else is
never fought.

## Decisions already made (do not re-litigate)

- No resident/boot daemon enforcement. No "keep after quit" setting.
- Uninstall: documentation only.
- Hysteresis: 2% → **4%**.
- Optimized Battery Charging: **no detection**. One fixed, clickable hint that
  opens the Battery settings pane. It is always visible in the low-version group.
- No active discharge. A sentence states "above the ceiling we only stop
  charging, we do not discharge".
- No low-frequency polling.

## Current working-tree caveat

The tree has **uncommitted** work from earlier turns that must be kept:
sleep policy (`LegacySleepPolicy`, assertion), target slider, panel button +
`showsLegacyChargeToFullButton`, and an aborted `keepAfterQuit` experiment that
must be removed. Do **not** `git checkout` whole files; remove only the
`keepAfterQuit` pieces listed in Task 1.

## File map

- `Sources/StatusTrioCore/Battery/LegacyChargeLimit.swift` — domain types.
- `Sources/StatusTrioCore/Battery/LegacyChargeLimitPolicy.swift` — validator/hysteresis.
- `Sources/StatusTrioCore/Battery/LegacyChargeLimitEngine.swift` — pure gate.
- `Sources/StatusTrioCore/Battery/LegacyChargeLimitClient.swift` — XPC client protocol/impl.
- `Sources/StatusTrioCore/Battery/LegacyChargeLimitController.swift` — app state machine.
- `Sources/PowerHelperProtocol/LegacyChargeLimitXPC.swift` — XPC protocol.
- `Sources/StatusTrioPowerHelper/LegacyChargeLimitService.swift` — root enforcement.
- `Sources/StatusTrioPowerHelper/PowerHelperService.swift` — XPC forwarders.
- `Sources/StatusTrioCore/Settings/SettingsStore.swift` + `SettingsPreferenceCatalog.swift`.
- `Sources/StatusTrioCore/UI/Settings/LegacyChargeLimitSettingsView.swift` + `BatterySectionView.swift`.
- `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings` (12) + `Localization/LocalizationKey.swift`.
- Tests: `Tests/StatusTrioCoreTests/LegacyChargeLimit{Controller,PanelRow,Engine}Tests.swift`,
  `Tests/StatusTrioPowerHelperTests/LegacyChargeLimitServiceTests.swift`,
  `SettingsPreferenceCatalogTests.swift`, `LocalizationParityTests`.
- Docs: `docs/legacy-charge-limit.md`.

---

## Task 1 — Remove the aborted keepAfterQuit experiment

Pure removal; the app must compile and existing tests pass afterwards.

Steps:
1. `LegacyChargeLimitJournal.swift`: delete `var keepAfterQuit: Bool? = nil` and
   its doc comment.
2. `LegacyChargeLimitService.swift`:
   - `setLegacyChargeLimit` back to `(_ limit: Int, expectedLimit: NSNumber?, ownerID: UUID, withReply:)`; delete `session.keepAfterQuit = keepAfterQuit`.
   - `restoreJournalIfSafe`: delete the `if mutable.keepAfterQuit == true { … }` branch.
   - `restoreForClientLoss`: delete the `if let kept = try? journalStore.load(), kept.keepAfterQuit == true { … }` branch.
3. `LegacyChargeLimitXPC.swift`: remove `keepAfterQuit: Bool` from `setLegacyChargeLimit`.
4. `PowerHelperService.swift`: remove the parameter from both forwarders.
5. `LegacyChargeLimitClient.swift`: `setLimit` back to `(_ limit: Int, expectedLimit: Int?)` in the protocol and impl; drop the proxy argument.
6. `LegacyChargeLimitController.swift`: delete `keepAfterQuitProvider`, `updateRetention()`, and the `keepAfterQuit:` argument from the three `client.setLimit` calls.
7. `SettingsStore.swift`: delete `keepsLegacyChargeLimitAfterQuitDefaultsKey`, the `@Published var keepsLegacyChargeLimitAfterQuit`, and its `init` assignment. `SettingsPreferenceCatalog.swift`: delete its `boolean(...)` entry.
8. `AppEnvironment.swift`: delete `legacyChargeLimit.keepAfterQuitProvider = …`.
9. `LegacyChargeLimitSettingsView.swift`: delete `@Binding var keepAfterQuit`, the "退出后保持" `SettingsToggleRow`, and `keepAfterQuitBinding`. `BatterySectionView.swift`: delete the `keepAfterQuit:` argument.
10. Locales: delete `…legacyChargeLimit.keepAfterQuit` and `…keepAfterQuitDescription` from all 12 files; delete the two `LocalizationKey` cases.
11. Tests: revert the fake `setLimit` signatures to the two-argument form; remove `keepAfterQuit: .constant(true)` from the snapshot view call; remove `"keepsLegacyChargeLimitAfterQuit"` from the catalog expectation.

Verify: `bash scripts/test.sh 'LegacyChargeLimit|SettingsPreferenceCatalogTests|LocalizationParityTests'` passes.

---

## Task 2 — Helper: one `reconcile` operation

New single operation used by launch, wake, AC plug-in and Settings-open. It reads
the current keys, classifies them, and either re-applies the ceiling or reports a
foreign owner. Level awareness already exists in `desiredRaw`.

Files: `LegacyChargeLimitJournal` unchanged; `LegacyChargeLimitService.swift`;
`PowerHelperProtocol/LegacyChargeLimitXPC.swift`; `PowerHelperService.swift`;
`LegacyChargeLimitClient.swift`.

Signatures:
- Protocol `LegacyChargeLimitXPCProtocol`:
  `func reconcileLegacyChargeLimit(_ limit: Int, withReply reply: @escaping (SMLegacyChargeLimitWriteReply?) -> Void)`
- Service: `func reconcileLegacyChargeLimit(ownerID: UUID, limit: Int, withReply reply: @escaping (Reply?) -> Void)`
- Client protocol: `func reconcile(_ limit: Int) async throws -> LegacyChargeLimitWriteOutcome`
  (impl calls the XPC method; body mirrors `setLimit`'s `write { … }` helper).

Service behaviour (pseudo):
1. `requireEligible()`, `claimHardware(ownerID)`, validate `80...100`.
2. `let previous = try loadOwnedJournal()`.
3. If `previous == nil`: `raw = try discoverOriginal()`; build a new session with
   `originalRaw = lastWrittenRaw = raw`.
4. Else: read each key in `previous.lastWrittenRaw` with `validRead` into
   `current` (no equality assert). Classify:
   - `current == previous.lastWrittenRaw` → ours (may need gate re-evaluation);
   - `current == previous.originalRaw` → reset by the system → drift;
   - otherwise → `throw Failure(.ownershipConflict, "Another controller changed a charge setting.")`.
5. `let desired = try desiredRaw(session: session, limit: limit, full: false, current: current)`
   (`desiredRaw` already consults battery level/AC and picks allow vs inhibit).
6. `apply(&session, desired: desired, current: current)`; set `requestedLimit = limit`;
   `persist(session)`; `success(observedLimit: hardware.isIntel ? limit : nil)`.

Tests (`LegacyChargeLimitServiceTests`, reuse `intelExecutor`/`MemoryJournal`):
- reconcile with a reset journal (`BCLM` back to stock 100) rewrites the ceiling and returns success.
- reconcile when the hardware holds a foreign value (neither stock nor ours) returns
  `.ownershipConflict` and does **not** write.
- reconcile with no journal discovers stock, applies the ceiling, and journals it.

---

## Task 3 — P0-2: launch re-apply

`LegacyChargeLimitController` uses `client.reconcile` instead of `verify` for the
launch/refresh path, and maps results to status.

Steps:
1. In `refresh()`, replace the `client.verify(loaded.requestedLimit)` block with
   `client.reconcile(loaded.requestedLimit)`. Map: success → `.holding(at:)`;
   `.ownershipConflict` → `.externalChange`; other failure → `.failed`.
   Keep the `commandGeneration` guard before/after the await.
2. `start()` stays as-is (it already calls `taskRefresh()` when a session exists),
   so a launch with a saved ceiling now re-applies automatically.
3. If there is no local session, nothing happens (helper idle-exits) — unchanged.

Tests (`LegacyChargeLimitControllerTests`):
- `testLaunchReappliesTheSavedCeiling`: store a session with limit 85, fake client
  `reconcileResult = .success`; `start()`/`refresh()` ends `.holding(at: 85)` and
  `reconcileCalls == [85]`.
- `testLaunchReportsExternalChangeWithoutWriting`: `reconcileResult =
  .failure(ownershipConflict)`; status `.externalChange`, no `setLimit` call.

---

## Task 4 — P0-3: self-heal on wake, AC plug-in, Settings open

1. `handleWake()`: replace the `client.setLimit(...)` call with
   `client.reconcile(session.requestedLimit)`; keep resetting
   `lastAppliedAllowsCharging = nil`; map result as in Task 3.
2. `handleBattery`: add `private var lastWasOnAC: Bool?`. After the temporary-full
   branch, if `isOnAC` and `lastWasOnAC != true`, run the same reconcile (then
   continue to the normal engine path). Always set `lastWasOnAC = isOnAC` before
   returning. (Reconcile fixes a reset gate; the engine then applies
   level-based allow/inhibit as usual.)
3. Settings-open path already calls `refresh()` via the view's `.task`, so it
   inherits Task 3 behaviour.
4. Update `stop()` to reset `lastWasOnAC = nil`.

Tests:
- `testWakeRepairsAResetGate`: after `handleWake`, `reconcileCalls == [85]` and status `.holding(at: 85)`.
- `testACPlugInReconcilesOnce`: `handleBattery(level: 60, isOnAC: true)` after a
  `false` event triggers one reconcile; a second `true` event does not add one.
- `testForeignValueSurfacesAsExternalChange`: reconcile returns
  `.failure(ownershipConflict)` → status `.externalChange`, no `setLimit`.

---

## Task 5 — Hysteresis 2% → 4%

`LegacyChargeLimitPolicy.hysteresis` = 4. Update `LegacyChargeLimitEngineTests`
threshold expectations (e.g. at limit 85, 82/83/84 hold, 81 and below allow; 85+
inhibit). Keep `LegacyChargeLimitValidator` range 80–100 unchanged.

Run `bash scripts/test.sh 'LegacyChargeLimitEngineTests|LegacyChargeLimitTests'`.

---

## Task 6 — Fixed Optimized Battery Charging hint + Battery pane link

Wording (12 languages, always visible in the low-version group, no detection):

> 建议在「系统设置 → 电池 → 电池健康」中关闭「优化电池充电」，以免和限充冲突。

Implementation:
1. New key `settings.battery.legacyChargeLimit.optimizedChargingNote` in
   `LocalizationKey.swift` and all 12 `Localizable.strings` (parity test enforces).
2. `LegacyChargeLimitSettingsView`: add `var openBatterySettings: () -> Void = {}`.
   Render a tappable row/hint (e.g. `SettingsRow` with a trailing small button, or
   `SettingsHintRow` plus a link) that calls `openBatterySettings`.
3. `BatterySectionView`: pass `openBatterySettings` that opens the first working
   URL from `StatusBarController.batterySettingsURLs`
   (`x-apple.systempreferences:com.apple.Battery-Settings.extension`, fallback
   `com.apple.preference.battery`) via `NSWorkspace.shared.open`. No version
   branching; a deep link into the ⓘ sheet is not supported.
4. Update the settings-group snapshot test to include `openBatterySettings: {}`.

Tests: `LocalizationParityTests`, `SettingsViewTests`, existing snapshot test.

---

## Task 7 — Copy and docs (P2-8, P2-9 removal)

1. `docs/legacy-charge-limit.md`:
   - §10.1 already records the OBC hint; adjust the wording to the fixed sentence above.
   - Add one line: "Above the ceiling we only stop charging; the app never actively discharges."
   - Keep §9 manual reset; remove any implication that a separate uninstall step is needed.
2. Append a ledger entry summarising tasks 1–7.
3. No settings-transfer change beyond Task 1 removals.

---

## Task 8 — Verification

1. `bash scripts/test.sh 'LegacyChargeLimit|LegacySleepPolicy|SettingsPreferenceCatalogTests|LocalizationParityTests|SettingsViewTests'`
2. `bash scripts/verify-local.sh full` on the final tree; record the SHA and result.
3. Hardware behaviours remain **NOT RUN**: real SMC writes/cutoff, wake repair,
   AC-plug repair, launch re-apply, OBC interaction.

## Done criteria

- `keepAfterQuit` gone; tree compiles.
- Launch re-applies the saved ceiling; wake/AC/Settings-open repair a reset gate
  but never fight a foreign owner.
- Hysteresis 4%.
- Fixed OBC hint present in 12 languages and opens the Battery pane.
- Focused suites and `verify-local full` pass; doc + ledger updated.
