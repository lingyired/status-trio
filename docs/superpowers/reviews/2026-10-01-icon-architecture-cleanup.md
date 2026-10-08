# Icon architecture cleanup — independent final review

**Verdict: WITH FIXES (one P2 finding).** Production cleanup passes review; the new source guard needs to detect two demonstrated executable interpolation forms before the cleanup satisfies its acceptance criteria.

## Scope and evidence

- Read-only review of `/Users/lingsmbp/.codex/worktrees/status-trio-2-0/status-trio`, HEAD `e731036aefdf6033e736ef09c3f1a3f6817f31f9`; substantive diff `234e3a2..e731036`, product baseline `1c1049399ccdddb17ea73cd590445e8292abb856`.
- Read the reviewer instructions, implementation plan, spec including binding amendments, all changed production code and tests, changed documentation, and relevant unchanged lifecycle/mapper/resolver context. This was the single requested whole-cleanup review, not another review of the existing 2.0 refactor.
- Verified production changes are confined to three specified files. Both renderers have zero diff. Both AppIconController construction sites were updated, and AppEnvironment still retains the system store.
- Inspected full test/build logs: 1,251 XCTest tests, 6 skipped, 0 failures; 444 Swift Testing tests in 74 suites passed; release build completed in 20.69 seconds. Independently ran `git diff --check 234e3a2..e731036` successfully. Did not rerun the full suite.
- Ran an isolated scanner reproduction with `swift /tmp/status-trio-scanner-review.swift`; this copies the scanner into a temporary file and leaves checkout/index/HEAD untouched. The reproduction also evaluates the same Swift interpolation syntax with a stub SettingsStore, proving that these identifiers execute. Working tree remained clean at reviewed HEAD.

## Strengths

1. The mapper injection is narrow and correct: explicit default closure, MainActor closure type, initialized before initial output, and one shared output helper for initial, subsequent canonical, and charging-test scenes.
2. Store removal is complete without broadening Dock responsibilities. No renderer, cache equality, panel, accessibility, settings behavior, or scheduling implementation was changed.
3. Tests use distinctive custom outputs and a manual scheduler, and semantic characterization preserves legitimate visual differences rather than treating all raw domain changes as equivalent.

## Review focus results

1. **Initial/start injection and duplicate start — PASS.** Init and synchronized start call the injected mapper through the static helper. `start()` retains its two-subscription guard; existing subscription-count test calls it twice and asserts exactly one subscription per publisher. Startup mapping was inspected directly; new tests clear spy history after start and therefore do not independently pin its exact call count, which is appropriate for the plan's avoidance of startup timing assumptions.
2. **Charging test projection vs canonical snapshot — PASS.** Canonical mapping receives the actual snapshot first; only the test mapping receives `ChargingEffectTestMode.snapshot`. Custom-mapper tests assert real and projected battery differences and on/off/on behavior. The unchanged helper structure preserves the two outputs and the existing default-mapper parity coverage.
3. **Burst debounce and immediate preferences — PASS.** Snapshot scheduling remains 500 ms trailing debounce. The new spy verifies only latest snapshot maps after manual delivery; existing tests verify immediate settings against the latest delivered snapshot and pending cancellation, and the charging spy verifies a preferences update maps the pending latest snapshot. No store readback was added.
4. **Constant scene dedup, stop, restart — PASS.** Equality remains on the complete `IconPresentationOutput`. Constant-scene updates do not publish; size updates still publish. Stop cancels scheduled work and subscriptions; restart synchronizes current publisher values. Injected mapper lifecycle coverage supplements existing subscription-count coverage.
5. **Semantic identity without suppressing visual changes — PASS.** RSSI same-bucket identity is pinned alongside the -60/-61 boundary. Muted dots/arc are equal for different raw volume, whereas unmuted arc remains unequal. Device rename runs through the real resolver with stable classification metadata, verifies a nonnil equal symbol, and exercises Bluetooth center replacement. SSID/exact volume affect accessibility while equal dots scenes remain equal.

## Issues

### Critical

None.

### Important — P2: Scanner silently drops executable identifiers in valid string interpolation

**File:** `Tests/StatusTrioCoreTests/TestSupport/SwiftSourceIdentifierScanner.swift:83` (nested-string closing logic, lines 83–91) and `:134` (raw-string backslash parity, lines 131–140).

The guard is allowed to conservatively reject literal/comment tokens, but the plan expressly requires that executable identifiers inside interpolation cannot disappear. Two valid Swift cases currently do disappear:

```swift
// Paste these exact fixture declarations into the scanner test.
let nested = #"let text = "\(String(describing: "inner") + SettingsStore.description)""#
let raw = ##"let text = #"\\#(SettingsStore.shared)"#"##
#expect(SwiftSourceIdentifierScanner.identifiers(in: nested).contains("SettingsStore"))
#expect(SwiftSourceIdentifierScanner.identifiers(in: raw).contains("SettingsStore"))
```

Both expectations are RED with the reviewed scanner. The standalone reproduction produced:

```text
nested let text = "\(String(describing: "inner") + SettingsStore.description)"
["String", "describing", "inner", "let", "text"]
raw let text = #"\\#(SettingsStore.shared)"#
["let", "text"]
Swift evaluated nested: innerforbidden
Swift evaluated raw: \forbidden
```

**Cause:** `consumeString` treats an inner quoted expression within interpolation as the end of the outer string. After consuming `inner` as code, the next quote starts another supposedly plain string, causing the real `SettingsStore.description` expression to be skipped. Separately, `hasInterpolation` applies ordinary-string backslash parity to raw strings. In `#"\\#(...)"#`, the first backslash is literal and the second starts a valid `\#(...)` interpolation; treating two slashes as an escape pair hides it.

**Impact:** This is a regression-guard gap, not a current shipped UI defect. A future direct domain/store dependency can enter a renderer without failing the new architecture test, despite the claimed executable-interpolation protection. It violates a specifically required acceptance boundary, so it should be fixed before accepting this cleanup.

**Fix:** Add both fixtures and correct interpolation/string-boundary handling, or simplify to a deliberately conservative strategy that cannot discard executable interpolation content. No AST dependency or general-purpose Swift parser is required. Preserve the existing plain-comment/plain-literal acceptance tests; document any broader conservative false positives.

### Minor

No separate actionable minor finding.

## Scanner complexity and accepted limitations

The 198-line helper is larger than the production change, but remains isolated test support and introduces no dependency; size alone does not justify another finding. Its two separate string passes and handwritten escape handling are where the demonstrated errors occur. Prefer a bounded correction or simpler conservative guard instead of expanding this into a complete parser.

A confirmed conservative false positive is:

```swift
let comment = #"let text = "\(value /* SettingsStore */)""#
```

The scanner reports `SettingsStore` from the interpolation's comment. It likewise reports forbidden words from prose in a string that contains interpolation. This is documented by the helper and permitted by the accepted conservative strategy, so it is recorded as a limitation, not a requested fix. Ordinary standalone nested comments, plain literals, and longer ASCII identifier names are covered by existing fixtures.

## Recommendations

1. Have the Luna implementer fix the P2 with the two exact RED fixtures, then run focused scanner/architecture coverage plus the required verification for the final changed tree.
2. The root-owned non-publishing CI preflight must still pass on the final product SHA before merge/release; the local macOS 27 SDK build is not evidence of Xcode 26.6 / Swift 6.3.3 compatibility.

## Declined to judge

- **Remote CI toolchain/build/DMG acceptance:** not yet executed for this cleanup; root owns the required exact-SHA `publish=false` preflight. Local success is not substituted for it.
- **Live interactive visual comparison and accessibility/panel interaction:** no live app interaction was performed. These implementations have zero diff; relevant parity/integration tests and logs were inspected instead. No new behavior concern was found requiring an interactive reproduction.
- **Full pre-existing 2.0 architecture, plugin-host design, or external producer APIs:** explicitly outside this small cleanup review; no related implementation was introduced. This does not exempt any new seam from reasonable input/lifecycle expectations, which were reviewed above.
- **Complete Swift lexical grammar coverage beyond the advertised bounded source guard:** the helper is not a security parser. Conservative false positives are accepted and explicitly documented above; executable interpolation false negatives were not set aside and are the P2 finding.

## Assessment

**Ready to merge? With fixes.** The production injection/removal and semantic tests meet the intended cleanup with unchanged behavior. Correct the demonstrated source-guard false negatives and obtain the required CI preflight; no broader architecture changes or repeated whole-branch review are recommended.

## Root disposition and fix verification

The single P2 was accepted and fixed by the Luna implementer in `8d46656f7d4acfa3e408701cdeec04e2c3febdbb`, a separate child of `e731036aefdf6033e736ef09c3f1a3f6817f31f9`. The exact two reviewer fixtures first failed, then passed after the bounded scanner correction. Final local `swift test`: 1,251 XCTest, 6 skipped, zero failures; 444 Swift Testing cases in 74 suites passed. Product code did not change during the test-support fix, so the successful 20.69-second release build remains applicable. No second whole-change review was dispatched; the single fix pass was verified through RED/GREEN and the complete suite.

The guard intentionally remains a test helper, not a security parser. It conservatively checks complete interpolation-bearing literals, so forbidden words in their prose/comments can cause false positives. Plain literal contents and standalone comments are ignored. No actionable review minor was deferred.

## Rulings I made

1. Ruling: Task-start BASE is actual planning HEAD `234e3a2`, while product review baseline remains `1c10493` — this includes the plan history and isolates the intended cleanup; cost if wrong: an incomplete or overly broad review range.
2. Ruling: Interpolation-bearing strings are checked conservatively in full — executable references must not escape detection, without a parser dependency; cost if wrong: false positives require fixture/guard adjustment, not runtime changes.
3. Ruling: Track balanced interpolation parentheses, nested strings/comments and raw interpolation markers — closes both demonstrated false negatives; cost if wrong: a later valid Swift spelling may need another regression test and correction.
4. Ruling: Remote toolchain acceptance is resolved by an exact-SHA publish=false workflow, never by the local SDK27 result — cost if wrong: compiler incompatibility would remain unproven.
5. Ruling: Live interaction is not a new acceptance gate for this cleanup because UI/rendering/AX/panel implementations have zero diff and existing parity tests pass — cost if wrong: a runtime wiring issue not covered by those tests could need manual reproduction.
6. Ruling: Existing 2.0 architecture and future plugin-host design stay outside this cleanup review — no new related implementation is introduced; cost if wrong: unrelated architectural debt remains for its separate design effort.
7. Ruling: Complete Swift lexical grammar is outside this bounded guard, but the two demonstrated executable misses are fixed — cost if wrong: an untested legal spelling may still need a future guard regression; the guard is not a security boundary.

## Remote acceptance and completion

[Run 36825078720](https://github.com/lingyired/status-trio/actions/runs/36825078720) succeeded on exact SHA `8d46656f7d4acfa3e408701cdeec04e2c3febdbb`, version 2.0.0 / build 33 / publish=false. Xcode 26.6 and Swift 6.3.3 ran 1,251 XCTest (6 skipped, zero failures) and 444 Swift Testing tests / 74 suites. Both x86_64 and arm64 passed SDK26.0 guards. DMG creation and artifact upload (11144722531) succeeded without publishing. Signing remains ad-hoc; Developer ID/notarization are not configured.

Root accepts the cleanup after the single review fix pass and exact-SHA CI. API documentation and plan are current, the development build 33 is running, and local/remote main remain at `fb76626326117a86a982a959a10016de1788d67f`. There is no merge into main, tag, release, appcast publication, or plugin-host implementation.
