# Status Trio Telemetry v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The user explicitly requested writing this plan and then running it with Luna; execution is authorized. One `gpt-6-luna` worker implements the entire plan in the existing worktree, with a fresh whole-branch review after implementation.

**Goal:** Add optional installation and active-installation heartbeat statistics without changing existing users' privacy choices or contaminating production data with development builds.

**Architecture:** `AppEnvironment` remains the composition root. A MainActor reporter snapshots settings/localization and owns cancellable lifecycle triggers; an actor client owns identity, persistence, request serialization and timestamp throttling. URLSession transport and time/scheduling dependencies are injectable.

**Tech Stack:** Swift 6, Foundation, Combine, AppKit/SwiftUI, existing XCTest; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-01-app-telemetry-integration-v2.md` (verbatim reference supplied by the user).

## Global Constraints

- Base is `codex/2.0-presentation-refactor` at `4bc091783382368e2e786b78d1289192d893ca9c`, not the spec's older main baseline. Branch: `codex/telemetry-integration-v2`; worktree: `/Users/lingsmbp/.codex/worktrees/telemetry-v2/status-trio`.
- The supplied document is requirements/reference material, not permission to publish a release, delete D1 data, or modify the separate Worker/dashboard repository. Deliver client implementation and verification; keep those operations outside this run.
- CI acceptance: macos-26, Xcode 26.6, Swift 6.3.3; macOS SDK >=26. Keep both platform-version guards. Run `swift test` and `swift build -c release` before committing Swift changes. Run non-publishing release preflight before any merge/publication; no merge/publication in this task.
- Schema 1; appID `status-trio`; endpoint `https://telemetry.lingai.net/v1/ping`; production bundle ID `com.lingsmbp.StatusTrio`; source marker false; explicit release-pipeline marker true. DEBUG never eligible for production.
- Consent version 1. Existing installs default OFF with completed consent migration. Fresh installs: disclosure toggle visually ON, effective consent OFF until an explicit completion action. Disabled/undecided/ineligible paths never create an installation ID.
- Random UUID in `telemetry.installationId`; timestamp keys `telemetry.lastAttemptAt`, `telemetry.lastSuccessfulAt`. Success interval 20h, failed-attempt cooldown 6h, reporter interval 6h, request timeout 2.5s. Keep UUID through failures and OFF/ON.
- Required fields: schema_version, app_id, install_id, app_version. Optional: build, os_name, os_version, arch, distribution, os_language, app_language, attributes. Never first_app_version or hardware/network/account/location fields. Only app_icon_placement in flat typed attributes.
- No Task.detached, client singleton, unsafe Sendable bypass, new analytics SDK, entitlements, sandbox or Keychain. Silent best-effort failure; no launch blocking or sensitive logging.
- Twelve locales: ar, de, en, es, fr, it, ja, ko, pt-BR, ru, zh-Hans, zh-Hant. No unrelated presentation refactor or icon-rendering changes.

## Review Focus

1. Relaunch after dismissing fresh onboarding: existing Sparkle/onboarding flags must not turn pending consent into accepted consent; pin in Task 1.
2. Combine @Published emits before didSet: consent completion and OFF cancellation must use emitted values/coherent snapshots, not stale property reads; pin in Tasks 1 and 5.
3. OFF/stop races against a queued or suspended send: no new request after disabling, cancel URLSession work, no success recorded after cancellation; pin in Tasks 4 and 5.
4. Malformed known-language prefixes and oversized input must be rejected before permissive AppLanguage.match; pin in Task 3.
5. Clock rollback/future stored timestamps and rapid stop/start must not cause duplicate requests or busy loops; pin in Tasks 4 and 5.

## Repository findings and decisions

- `SettingsStore.init(defaults:)` migrates existing onboarding using SUHasLaunchedBefore/hasSeenIconGuide. Snapshot those flags and stored hasCompletedIconGuideOnboarding BEFORE initialization writes defaults. Use a separately persisted consent version (including pending 0) so future relaunches do not repeat legacy detection.
- `IconGuideOnboardingPolicy.consumeIfNeeded` sets hasCompletedIconGuideOnboarding on presentation. Preserve that policy's existing tests; telemetry acceptance is separate. Add disclosure to the existing two-page guide without unrelated redesign. Pending consent gets a disclosure even if the guide was dismissed previously; closing the window is not acceptance. Reopening the guide for an upgrade must not enable statistics.
- `AppLanguage.match("pt")` maps to pt-BR for UI fallback. Telemetry normalizer must special-case generic/European Portuguese as `pt` and reserve pt-BR for Brazilian input, without changing UI language resolution.
- Worker contract verified locally in `/Users/lingsmbp/Documents/aiwork/app-telemetry/src/validation.js` and `config/apps.json`: required/optional keys above; language regex anchored, maximum 16; placement values menuBar/dock/both. `src/cron.js` prunes daily_activity only; do not claim all data expires after 365 days.
- Info.plist currently says 1.4.0 (17). Do not silently bump product metadata or overwrite existing release notes. Stage notes for 2.0.0 to match this branch's presentation milestone; derive explicit preflight build greater than published maximum from appcast/releases, and record chosen numbers. This does not authorize a 2.0.0 release.

### Task 1: Consent state and migration

**Files:** Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`, `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`; create `Sources/StatusTrioCore/Telemetry/TelemetryConsent.swift`, `Tests/StatusTrioCoreTests/TelemetryConsentTests.swift`.

**Interfaces:** Produce `TelemetryConsent.currentVersion = 1`; published `sharesAnonymousAnalytics: Bool`, `telemetryConsentVersion: Int`; computed `canShareAnonymousAnalytics: Bool`; `completeTelemetryConsent(sharesAnalytics: Bool)` and `setSharesAnonymousAnalytics(_ enabled: Bool)` on SettingsStore. Settings toggling explicitly completes consent; onboarding draft never mutates effective preference until acknowledgement.

- [ ] Add failing XCTest cases in isolated UserDefaults suites for each legacy flag, fresh/pending 0, persisted true/false, reconstruct after pending guide/Sparkle flags become true, future consent version fail-closed, no UUID on disabled initialization, coherent completion notifications. Representative assertions:
```swift
let settings = SettingsStore(defaults: defaults)
XCTAssertFalse(settings.canShareAnonymousAnalytics)
XCTAssertEqual(settings.telemetryConsentVersion, 0)
settings.completeTelemetryConsent(sharesAnalytics: true)
XCTAssertTrue(settings.canShareAnonymousAnalytics)
XCTAssertEqual(settings.telemetryConsentVersion, 1)
```
- [ ] Run `bash scripts/test.sh 'TelemetryConsentTests|SettingsStoreTests'`; Expected: new symbols fail to compile initially.
- [ ] Implement snapshot-based legacy migration and persisted pending sentinel; use Bool false until acceptance. Set enabled before publishing completed version, or expose a coherent consent publisher that reporter can observe. Initialization must not accidentally trigger acceptance via didSet.
- [ ] Run same filter; Expected: PASS. Run `swift test` and `swift build -c release` before commit. Commit consent/migration changes only.

### Task 2: Production eligibility and artifact marker

**Files:** Create `Sources/StatusTrioCore/Telemetry/TelemetryEligibility.swift`, `Tests/StatusTrioCoreTests/TelemetryEligibilityTests.swift`; modify `Support/Info.plist`, `scripts/build-app.sh`, release packaging path used by `.github/workflows/release.yml` (inspect whether `scripts/release.sh` calls build-app).

**Interfaces:** Produce Sendable `TelemetryEligibilityContext(bundleIdentifier: String?, productionMarker: Bool, isDebugBuild: Bool)` and `TelemetryEligibility.isEligible(_:) -> Bool`.

- [ ] Write five matrix tests, including nil ID. Example:
```swift
XCTAssertTrue(TelemetryEligibility.isEligible(.init(
    bundleIdentifier: "com.lingsmbp.StatusTrio", productionMarker: true, isDebugBuild: false
)))
```
- [ ] Run `bash scripts/test.sh TelemetryEligibilityTests`; Expected: compile failure for missing types.
- [ ] Implement pure conjunction. Add false plist marker and script environment default 0; validate 0/1; set boolean on copied plist before signing. Official workflow packaging explicitly passes TELEMETRY_PRODUCTION=1, including non-publishing artifacts; tests/building do not launch app or send heartbeat. Ordinary release build remains false.
- [ ] Run eligibility filter and `bash -n` for modified shell scripts. Expected: PASS; source plist marker false. Full test/release build then commit.

### Task 3: Typed payload, languages and transport

**Files:** Create `TelemetryConfiguration.swift`, `TelemetryModels.swift`, `TelemetryLanguageTag.swift`, `TelemetryTransport.swift` under `Sources/StatusTrioCore/Telemetry/`; create `TelemetryLanguageTagTests.swift`, `TelemetryPayloadTests.swift`, shared transport doubles under tests; modify comment in `Models/AppIconPlacement.swift`.

**Interfaces:** Configuration values as Global Constraints, injectable URL. Sendable context with appVersion, build, osName, osVersion, architecture, distribution, osLanguage, appLanguage, appIconPlacement. Typed Codable heartbeat/attributes with explicit snake_case CodingKeys. `TelemetryTransport: Sendable` exposes `send(request: URLRequest) async throws -> HTTPURLResponse`. `TelemetryLanguageTag.osLanguageTag(preferred: [String]) -> String?`.

- [ ] Add failing normalization table tests: th/th-TH->th, vi-VN->vi, sr-Latn/sr-Latn-RS->sr-Latn, zh-TW/HK->zh-Hant, zh-CN->zh-Hans, pt-BR->pt-BR, pt-PT/pt->pt, en-GB->en, de-DE->de. Reject empty, invalid primary, trailing separators, known prefix plus garbage, non-ASCII and oversized raw input; never truncate.
- [ ] Write payload assertions:
```swift
let required: Set<String> = ["schema_version", "app_id", "install_id", "app_version"]
let allowed = required.union(["build", "os_name", "os_version", "arch", "distribution", "os_language", "app_language", "attributes"])
XCTAssertTrue(required.isSubset(of: Set(json.keys)))
XCTAssertTrue(Set(json.keys).isSubset(of: allowed))
XCTAssertNil(json["first_app_version"])
XCTAssertEqual(Set(AppIconPlacement.allCases.map(\.rawValue)), ["menuBar", "dock", "both"])
```
Also assert attributes only placement, major.minor OS version, version/build independent, invalid language omitted.
- [ ] Run `bash scripts/test.sh 'TelemetryLanguageTagTests|TelemetryPayloadTests'`; Expected: missing symbols fail.
- [ ] Implement validator before known matching, normalization, typed encoding and ephemeral URLSession transport: no cookies/cache/credentials, waitsForConnectivity false, request/resource deadlines. Return HTTP response only; non-HTTP throws. Add allowlist config comment to placement enum. Keep endpoint injection explicit and test-only configuration away from live defaults.
- [ ] Targeted tests PASS; full test/release build then commit.

### Task 4: Actor client and deterministic throttle

**Files:** Create `TelemetryClient.swift`, `Tests/StatusTrioCoreTests/TelemetryClientTests.swift`.

**Interfaces:** `TelemetrySending: Sendable` with `sendIfNeeded(context: TelemetryContext) async`; actor `TelemetryClient` conforms. Inject transport, configuration, `now: @Sendable () -> Date`, persistence domain/suite name; construct actor-owned UserDefaults inside actor instead of transferring shared mutable defaults. UUID/state never owned by reporter. Caller owns cancellable send Task; client checks Task cancellation before identity/request and after transport.

- [ ] Write failing tests using recording/stub actor transport and a controllable clock (no real 6h sleep). Cover first UUID/reuse after failure/disable-enable, timestamps before request, success boundary 20h, failure boundary 6h, 200/299 success, 400/404/429/500/errors/timeout/cancel failure, overlap produces one transport call, clock rollback conservatively skips, cancelled queued attempt creates no ID.
- [ ] Run `bash scripts/test.sh TelemetryClientTests`; Expected: missing client failure.
- [ ] Implement guard order: cancelled/in-flight, recent success, recent attempt, UUID, persist attempt, encode/send, record success only for 2xx and uncancelled task. `isSending=true` before suspension and defer reset. Catch failures silently; do not log identity/body. Document reporter as sole effective-consent caller, so disabled behavior is tested end-to-end with reporter.
- [ ] Targeted tests PASS; full test/release build then commit.

### Task 5: Reporter lifecycle, cancellation and state snapshots

**Files:** Create `TelemetryReporter.swift`, `Tests/StatusTrioCoreTests/TelemetryReporterTests.swift`.

**Interfaces:** MainActor reporter init accepts settings, localization, client any TelemetrySending, eligibility context, configuration, injected wake NotificationCenter (NSWorkspace.shared.notificationCenter live), `sleep: @Sendable (Duration) async throws -> Void`, snapshot metadata dependency. Produce idempotent `start()`, `stop()`, `sendIfNeeded()`; tracked periodic/attempt Tasks.

- [ ] Write failing tests: immediate startup only if eligible+accepted, disabled/undecided/dev never calls client or creates UUID, OFF->ON once, ON->OFF cancels pending/in-flight work, wake/tick triggers, language/placement changes wait for next heartbeat, stop removes observers/subscriptions and cancels sleeper, restart/idempotent start yields one scheduler. Use injected wake center, controllable suspension and recording fake client; no wall-clock hours. Add combined real client test for simultaneous wake/start/ON producing one request.
- [ ] Run `bash scripts/test.sh TelemetryReporterTests`; Expected: missing reporter failure.
- [ ] Implement weak-capture periodic loop without retaining reporter across sleep; scheduler suspension and cancellation exit cleanly. Evaluate consent from coherent emitted state, with fresh pre-attempt recheck; stop/OFF cancel owned Tasks. Snapshot MainActor metadata into Sendable context; no detached tasks. Deinit cleanup must use existing CI-safe patterns; prefer explicit owner stop, no isolated deinit/unsafe annotations.
- [ ] Targeted tests PASS; full test/release build then commit.

### Task 6: App composition and lifecycle wiring

**Files:** Modify `Sources/StatusTrioCore/App/AppEnvironment.swift`; add/extend lifecycle tests using project's injection seams.

**Interfaces:** AppEnvironment owns reporter; live() creates configuration/transport/client/reporter exactly once; start after store.start; stop reporter first. Existing tests constructing environment must use injected inert/fake reporter so they cannot network.

- [ ] Add failing lifecycle integration assertions for start/stop and production metadata wiring; inspect existing constructors before changing signature.
- [ ] Run relevant AppEnvironment/lifecycle filter; Expected: new lifecycle expectations fail.
- [ ] Wire Bundle eligibility (DEBUG compile flag), metadata major.minor and architecture compile checks; production transport only used behind reporter checks. Missing required bundle version must skip safely instead of fake version reaching production. Preserve existing icon presentation ownership and ordering.
- [ ] Integration tests PASS; full test/release build then commit.

### Task 7: Settings/onboarding and 12 translations

**Files:** Modify `UI/Settings/GeneralSectionView.swift`, `UI/IconGuideOnboardingView.swift`, `UI/OnboardingWindowController.swift`, `UI/IconGuideOnboardingPolicy.swift` only where pending disclosure presentation needs it; `Localization/LocalizationKey.swift`, twelve `Resources/*.lproj/Localizable.strings`; extend `IconGuideTests.swift`, `IconGuideRedesignTests.swift`, consent and localization parity tests.

**Interfaces:** Local @State onboarding choice defaults true; completion/customize must pass through disclosure acknowledgement before calling existing closure. Window close does not commit draft. Upgrade guide has no telemetry acceptance step. Settings Binding setter calls explicit setSharesAnonymousAnalytics. Privacy URL points at GitHub docs/privacy-telemetry.md on main (note pending merge if smoke testing branch).

- [ ] Tests first: pending relaunch still gets disclosure; premature close persists pending/OFF; explicit done/customize acknowledges selected ON/OFF; legacy user no forced modal; existing guide pages/layout still work; settings setter persists accepted state. Add localization keys tests for analytics title/description/privacyDetails and onboarding title/description/toggle; render smoke for expanded guide in English/Chinese/Arabic.
- [ ] Run `bash scripts/test.sh 'IconGuide|TelemetryConsent|LocalizationParity'`; Expected: new assertions fail before UI/policy edits.
- [ ] Add compact disclosure area or final step to current guide, preserving contentWidth 640 and page controls. A distinct completion path makes acceptance testable outside rendering. Never mark consent in onAppear/window close. Include short purpose/data/exclusion copy and privacy link, Settings Usage Statistics group using existing components. Translate all six keys for all 12 locales with consistent terminology.
- [ ] Targeted tests PASS; full test/release build then commit.

### Task 8: Privacy docs and localized release notes

**Files:** Create `docs/privacy-telemetry.md`; modify all README locale documents with contradictory telemetry claims, `docs/analytics-snapshot.md`, `docs/known-limitations.md`; add telemetry notes in `release-notes/2.0.0/<locale>.md` preserving already-written presentation notes if directory exists. Optionally add `docs/telemetry-verification.md` to record smoke/preflight evidence.

**Interfaces:** Public copy matches actual client/server behavior; notes first line includes %VERSION% and %BUILD%.

- [ ] Scan `rg -n -i 'telemetry|analytics|遥测|统计|first.install|original.install' README* docs` and server README/cron for facts. Expected: identify all absolute no-telemetry claims. Do not modify historical design/plan files solely because their quoted old claims match.
- [ ] Document stable random identifier/pseudonymity, server HMAC app-scoped hash, precise payload, ON/OFF and prior data retained, infrastructure can see connection IP but no IP payload field, daily_activity 365-day pruning vs install_state/aggregates, forged ping, inactivity vs uninstall/disabled, artifact origin, first observed version. Include fixed 12-language audience query and independent mismatch query; STATS_PUBLIC=false is not client blocker.
- [ ] Update localized README privacy claims and release notes all 12 locales; upgrades OFF, new-install choice and no pre-ack request, no third-party SDK. No unsupported notarization claim.
- [ ] Inspect `scripts/validate-appcast-notes.sh` usage and run with explicit 2.0.0 inputs. Expected: coverage and generated appcast XML PASS. Commit docs only after factual review.

### Task 9: Acceptance, local smoke and non-publishing CI

**Files:** Record evidence in `docs/telemetry-verification.md`; append every failed GitHub run to `docs/swift-ci-compatibility.md` with ID/stage/cause/fix/verification.

- [ ] Run `bash scripts/test.sh`, explicit `swift test`, `swift build -c release` with logs captured; Expected: PASS with counts. Run forbidden patterns and relevant shell guards. Do not install/run into /Applications or replace user's running app.
- [ ] Build ordinary artifact with isolated APP_PATH (inspect script options) and no-open; inspect STTelemetryProduction false. Build production-like artifact with TELEMETRY_PRODUCTION=1 and no-open; inspect marker true and SDK >=26. Never launch it against production.
- [ ] Local Worker smoke only: use separate local D1/state directory where supported, existing migrations, configuration-injected loopback endpoint, real URLSession release smoke harness behind explicit test flags. Exercise ON/OFF, stable ID, language/attributes and server-generated first_app_version; SELECT local rows. Do not edit Worker source or constants. If tooling/auth unavailable, record precise blocker, preserve client tests, do not fabricate success.
- [ ] Determine next preflight build greater than published maximum from appcast and GitHub releases. Push only this feature branch (no tags/main). Dispatch release.yml with explicit version=2.0.0, chosen build, publish=false; watch result with `gh run watch <run-id> --repo lingyired/status-trio --exit-status`. Confirm test/build/DMG and artifact marker true, no app launch/heartbeat; publish stages should be skipped. Log and fix any failure, then rerun. Credentials/toolchain blockers remain explicit acceptance gaps.
- [ ] Fresh whole-branch code review against base 4bc0917 and spec (requesting-code-review skill). Fix important findings with regression tests, rerun affected/full verification. Leave branch/worktree intact and report committed changes, consent/eligibility/scheduling/payload/privacy, tests, CI run link, remaining manual checks. Production URLSession smoke, remote D1 inspection, deletion and release publication are deferred pending separate authorization; no production test writes in this run.

## Completion distinction

Client implementation is complete only when consent, eligibility, scheduling, encoding, cancellation and all locales are verified. CI compatibility is complete only with a passing macos-26/Xcode26.6/Swift6.3.3 preflight. Production acceptance is not claimed until a separately authorized production smoke/post-release inspection occurs. Keep these statuses separate in final output.
