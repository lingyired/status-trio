# Status Trio 2.0 presentation architecture handoff

Branch: `codex/2.0-presentation-refactor`

2.0 refactor starting baseline: `4176b78`

Integrated latest main: `fb76626326117a86a982a959a10016de1788d67f` (v1.4.0)
Integration merge commit: `f6a28ff34971106aa73e859b6c145d8ef360daa5`
Main integration product commit: `6c09c12de0f829e76f67c4e6f407cee3c1d0ca44`

The approved architecture-only, gradual migration is implemented: shared icon presentation mapping for Menu Bar, Dock and previews; scene-only rendering; panel value states and action coordination; obsolete adapters removed. Existing UI and behavior remain the acceptance contract.

## Final icon architecture cleanup

The final cleanup is complete in `e731036`, with the independent review's interpolation guard fix in `8d46656`. `AppIconController` no longer retains `SystemStatusStore`. `IconPresentationViewModel` accepts a MainActor `IconSceneMapper` closure, defaults to the existing mapper through an explicit closure, and uses the same path for initial/canonical/charging-test output. Scheduling, cache semantics, renderer implementations, UI and panel behavior are unchanged. Semantic identity and source-boundary regression tests were added.

[CI run 36825078720](https://github.com/lingyired/status-trio/actions/runs/36825078720) passed on exact SHA `8d46656f7d4acfa3e408701cdeec04e2c3febdbb`, Xcode 26.6 / Swift 6.3.3, version 2.0.0 / build 33 / publish=false. It ran 1,251 XCTest (6 skipped, no failures) and 444 Swift Testing tests / 74 suites, verified SDK26.0 on both architectures, created the DMG and uploaded artifacts without publishing.

The plan, independent review, fix evidence, all execution rulings and conservative scanner limits are preserved in `docs/superpowers/plans/2026-10-01-icon-architecture-cleanup.md` and `docs/superpowers/reviews/2026-10-01-icon-architecture-cleanup.md`. No actionable minor was deferred. This closes the current architecture cleanup; a future plugin host requires a separate design/branch.

## Pre-integration verification

- Local final `swift test`: 1,225 XCTest, 6 skipped, 0 failures; Swift Testing 410 tests / 71 suites passed.
- Local `swift build -c release`, app packaging, and platform guard passed; packaged `LC_BUILD_VERSION` SDK is 26.0.
- Whole-branch review identified two stale panel state regressions. One fix wave corrected listening-mode/device invalidation of volume state and delivered Wi-Fi snapshot mapping. Scoped rereview confirms both addressed, with no new findings.
- Cached Menu Bar frames again have eager backing bitmaps at the requested scale. General image rendering remains appearance adaptive.
- Remote acceptance: [run 36762652467](https://github.com/lingyired/status-trio/actions/runs/36762652467) succeeded on exact pre-integration code SHA `ef4e4c74dee4b67f64cf07ea6f22191d4586ba69` with version 2.0.0 / build 31 / publish=false. This historical run does not validate the integrated branch.

## Integrated verification

- Final local and remote `swift test`: 1,248 XCTest, 6 skipped, 0 failures; Swift Testing 438 tests / 74 suites passed.
- Local `swift build -c release`: passed with the macOS 27 SDK.
- Remote acceptance: [run 36817244648](https://github.com/lingyired/status-trio/actions/runs/36817244648) passed on product SHA `6c09c12de0f829e76f67c4e6f407cee3c1d0ca44`, Xcode 26.6 / Swift 6.3.3, version 2.0.0 / build 32 / publish=false. Both arm64 and x86_64 passed the SDK 26.0 platform guard; DMG creation and artifact upload succeeded without publishing.
- `swift test --filter Bluetooth`: 306 XCTest, 0 failures; Swift Testing 188 tests / 27 suites passed.
- `git diff --check` and merge-marker scan: passed. Local `main` remained `fb76626326117a86a982a959a10016de1788d67f`.

## Main integration

The branch now includes v1.4.0 from `fb76626326117a86a982a959a10016de1788d67f`, including external AirPods listening-mode property listeners and the BLE battery scanner, model identification, mobile glyphs, and 30-minute reading retention. Bluetooth UI remains value-only: `BluetoothPanelMapper` merges paired and nearby values, `BluetoothPanelState` carries read-only/actionable row state, and `StatusPanelActions` owns live action checks and scan claims. Closing the summary releases the BLE scan claim while keeping cached readings; an explicit opt-out clears that cache even while the panel is closed. The popover visibility token still gates radio work.

The merge also keeps the v1.4.0 release metadata, appcast history, and localized release notes. A non-publishing GitHub workflow verified the integrated product commit. No tag, GitHub Release, or appcast publication was created. The application-lifetime opt-out observer clears retained BLE battery readings even after the panel is gone, without starting scanning on enable or discarding independent claims. An independent Astra integration review found this lifecycle gap; scoped rereview confirmed the fix with no new findings.

Mounted Bluetooth row hit-test coverage is a disclosed nonblocking limitation: source Button callback wiring and action/confirmation policy tests were reviewed, but NSHostingView did not expose NSButton for the attempted interaction test. A platform-stable mounted test remains future work.

During the original pre-integration refactor, fresh reviewer seats became unavailable due to the agent thread limit; a CLI fallback timed out before performing work, so reviews reused independent Luna agents with root inspection. The later main integration received an independent Astra review and scoped fix rereview. Implementation remained on Luna.

The build is ad-hoc signed; Developer ID and Apple notarization are not configured, so this is not a notarized release.

Latest main was merged into the 2.0 branch only. Local and remote main remain at `fb76626326117a86a982a959a10016de1788d67f`. No merge into main, PR, tag, GitHub Release or appcast publication is part of this handoff. The independent worktree is preserved for integration choice. Release notes prepared here cover the two languages needed by publish=false; publishing requires the complete language set and explicit release authorization.

## Rulings I made

These are every ledger ruling, in recorded order, including each cost if wrong.

1. Ruling: Task 1 is characterization-only, so new baseline assertions first passing is intentional — it records existing behavior without production edits — cost if wrong: weak baseline requires test rework before Mapper migration.

2. Ruling: The approved spec governs interfaces; implementation may clarify constructor signatures and split a large task into incremental commits without adding product features — prose plan signatures are contracts, not complete source — cost if wrong: downstream interface rework.

3. Ruling: Task 2 generic symbol/text scale constructors preserve finite positive values and replace nonfinite/nonpositive values with 1.0; mapper supplies current option-specific defaults/ranges. Symbol variable values normalize nonfinite to nil and finite to 0...1 at composed state boundary — avoid domain-specific default rules in generic state and unstable NaN equality — cost if wrong: constructor tests and future producer behavior need adjustment, current validated settings unchanged.

4. Ruling: Ring segment arrays may represent unsupported input, but production Mapper must emit one nonempty segment and renderer must explicitly reject empty/unsupported counts; no precondition crash or silent invented segment in value constructors — spec requires current continuous ring and explicit unsupported handling, not a crash-based array API — cost if wrong: strengthen constructor API before a future producer is added.

5. Ruling: Task 4 may correct Task 3 top-ring and center percentage text to digits only, with mapper assertion and independent pixel parity regression — both legacy drawing helpers draw digits; renderer must consume visual text without battery-specific parsing — cost if wrong: revert mapper text and corresponding baseline tests; distinct top-ring and center typography/geometry remain preserved.

6. Ruling: Preserve existing Menu Bar-only charging test mode with canonical real scene plus optional menuBarTestScene in the same owner/output, both using the same Mapper/config; Dock always canonical — unchanged behavior and existing explicit test override ambiguous plan shared projected scene; spec/plan corrected — cost if wrong: additive output contract/test correction rework; no real snapshot or Dock behavior changes.

7. Ruling: Replace shared-owner immediate CombineLatest mapping with latest-delivered snapshot/settings plus injectable500ms domain debounce and immediate preference mapping of latest snapshot — existing domain cadence and fast settings are binding spec; controllers stay scene-only — cost if wrong: owner scheduling/API tests need rework, no independent state authority or product features added. Stop must cancel pending; restart refresh current inputs.

8. Ruling: Task7 durable SF Symbol/font-sensitive regression uses fixed existing geometry/color/scaling/pixel-region conventions instead of invented macOS26 hashes; Task4 independent exact comparisons preserved in git8fe0d37/a8d2758, primitive hashes only existing verifiedcross26/27 — plan permits conventions and localhost27 cannot establish26expectedbytes — cost if wrong: convention coverage less sensitive than fullhash, strengthen specific regression or collect CI26 baselines before merge. No tautological expectedMapper or mere nonnil assertions.

9. Ruling: Carry non-load-bearing staticDock effect-key normalization P3 into Task12 cleanup instead of a new interim fix loop — SDD minor findings defer; reviewer confirms priorbehavior, noPaneldependency or visualregression, bindingcachegoal mustclosebeforecompletion — cost if wrong: intermediate extraDockbitmap forrarecharging setting toggles; Task12mustadd key/hash/controller no-raster regression and finalreviewverify.

10. Ruling: Task9 volumeMapper accepts additive defaulted narrow value preferences for output order/visible limit; displaystate exposes resolved full/collapsed row sets and expansion copy, local UI expansion stays view-owned under spec§7 — planned signature omitted realsettings needed by existinglist; preserve rules without mutableSettingsStore/domainlogic inview — cost if wrong: additiveAPI/listprojection tests needrework; no second expansion authority/newfeature.

11. Ruling: Task10 PanelDetailRow adds defaulted isCopyable Bool carrying existing LinkDetailPresentation eligibility; Task11 renders resolvedflag with explicitcopy callback — approved architecture-only scope requires existing pasteboard affordance omitted by planned row signature — cost if wrong: additive row API andconsumer tests rework, no new copyability policy. Workerupdates plan/spec relevantcontract andtests beforecommit.

12. Ruling: Task10 WiFi state must expose full resolved details plus narrow collapsed projection and original expansion/collapse copy; Task11 keeps only local expansion toggle — planned mapper omitted existing More radio/detail rows, architecture-only behavior preservation requires them now — cost if wrong: additive state API andconsumer tests rework. No domain remapping inview or missingfeature deferred toTask11.

13. Ruling: Amend narrow Task10 sample Bluetooth intent/row contracts with resolved permission action, connected/component battery/failure/confirmation values and policy-routed rowTapped action — approved architecture-only behavior/pixel preservation governs incomplete sample signatures; existinghelpers are authority — cost if wrong: additive value/API/consumer tests rework, no new product policy. Panel drag indices belong filtered displayedpairedRows, translate atpanelcoordinator without changing rawSettingsmove callers.

14. Ruling: Task11 audio row/state adds resolved listening-mode address/value presentation and preview taskidentity — existing output controls require these affordances omitted by planned values; views stayvalue+callbacks with no domaincontroller — cost if wrong: additive state/Mapper/consumer tests rework. Preserve real-vs-synthetic localization andselected/enabled capsule semantics; workerupdates plan/relevant spec contract.

15. Ruling: Task11 must not add Bluetooth panel drag/drop when baselineBluetoothDeviceList hasnone; bind onlyexisting reorder controls andpreserveSettingsreorder — plan assumed nonexistent panel affordance, approved no-behavior-change scope overrides it — cost if wrong: restore wiring onlywhen actualexistingcontrol isfound. Task12 audits/removes unused panelBluetoothreorderAPI/tests if no realconsumer, doesnot inventUItojustifyAPI. Workerupdatesplan/brief andreportsbaselineevidence.

16. Ruling: Reuse available independent task3_mapper for Task11 review after freshAstra spawn and existingAstra reactivation bothfailed agentthreadlimit — toolingcap blocks freshseat, reviewer didnotimplementTask11 andsame read-only scopedcontract applies — cost if wrong: priorcontext andlowerLuna reviewcapability require escalation/finalreview foruncertainties; do not skipreview or claimfreshAstraapproval. Futureagentdispatch mayneedexistingavailableLuna seats; no repeatedcompletedtasks.

17. Ruling: At the pre-integration handoff, keep approved product baseline `4176b78` rather than silently absorb concurrent main v1.4.0 changes — the approved plan pinned that baseline and integration was a separate decision. The user later authorized merging current main; `fb76626326117a86a982a959a10016de1788d67f` is now integrated and the full local suite passes. The integrated product subsequently passed remote preflight run 36817244648. Historical cost if the original ruling had remained in force: v1.4 behavior would have been absent from the 2.0 candidate.

18. Ruling: Final whole-branch review uses available independent task4_renderer plus root integration inspection rather than unavailable fresh most-capable seat — native agentthreadlimit and failed CLI transport prevent requested fresh reviewer, root writes no product code — cost if wrong: reused Luna prior renderer context and lower review capability can miss issues; disclose this limit and require any uncertain finding resolved before integration. Final diff4176b78..8178059 handed to reviewer with all deferred minors/rulings.

19. Ruling: Retain mounted Bluetooth button hit-test gap as a disclosed nonblocking test limitation — action callbacks and value-only row state are covered, attempted NSHostingView exposes noNSButton, no current behavioral defect found — cost if wrong: a future wiring regression could bypass callback-only tests; add platform-stable mounted interaction coverage before changing row controls.
