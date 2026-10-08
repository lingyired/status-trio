# Telemetry integration verification

Implementation acceptance is recorded separately from production acceptance.
No requests were sent to the production endpoint, and no remote D1 writes were
performed.

## Delivered behavior

- Existing installations remain opted out until they explicitly enable telemetry; a new install's selected choice remains pending until the disclosure is acknowledged. Closing onboarding leaves consent off.
- Telemetry sends require an acknowledged opt-in and the production bundle marker; development and ordinary local builds cannot send.
- The heartbeat contains a random installation ID and bounded app/macOS versions, architecture, binary distribution (`github`), normalized system language, app language, and icon placement. The client does not send names, device/network details, or timestamps.
- The reporter checks on launch, wake, and every six hours. A successful send is throttled for 20 hours; a failed attempt is cooled down for six hours. Turning consent off or stopping the app cancels owned scheduled and in-flight attempts.

The field inventory, retention and privacy boundaries are documented in
[Telemetry and privacy](privacy-telemetry.md).

## Changed areas

The implementation covers consent migration and settings persistence, pure
eligibility and the build marker, typed payload/language normalization and
URLSession transport, the actor client and MainActor reporter, AppEnvironment
lifecycle wiring, localized onboarding/settings controls, privacy and release
notes, appcast link rendering, and local verification coverage.

## Local verification

- `bash scripts/test.sh`: 1,295 XCTest cases, 7 skipped, 0 failures; Swift Testing: 444 tests across 74 suites passed. Log: `/tmp/status-trio-telemetry-v2-full-test-script.log`.
- `swift test`: same XCTest and Swift Testing counts, 0 failures. Log: `/tmp/status-trio-telemetry-v2-swift-test.log`.
- `swift build -c release`: passed. Log: `/tmp/status-trio-telemetry-v2-release-build.log`.
- `VERSION=1.4.0 BUILD=17 PUBLISH=false bash scripts/validate-appcast-notes.sh`: passed with all 12 localized variants; confirms historical release notes without a telemetry link remain valid.
- `VERSION=2.0.0 BUILD=18 PUBLISH=false bash scripts/validate-appcast-notes.sh`: passed with 12 titles, 12 descriptions, English first, and a clickable privacy link in every Sparkle description. All 12 notes include the no-third-party-analytics-SDK statement.
- Ordinary and production-like no-open app bundles passed code-signature verification and `scripts/verify-platform-version.sh`: both target macOS 15.0 and record SDK 26.0; `STTelemetryProduction` is `false` and `true`, respectively. Bundles are preserved under `/tmp/status-trio-telemetry-v2/{ordinary,production}/StatusTrio.app`.
- An opt-in local Worker smoke test used `URLSessionTelemetryTransport` against `http://127.0.0.1:18787/v1/ping`, with local D1 state under `/tmp/status-trio-telemetry-v2/worker-state`. Consent OFF created no local installation ID or attempt; enabling consent produced HTTP 200. A local D1 `SELECT` found `first_app_version=2.0.0`, `app_version=2.0.0`, `build=18`, `os_language=en`, `app_language=en`, and `attributes={"app_icon_placement":"both"}`. Worker source was read only.
- A real `AppEnvironment.start()`/`stop()` lifecycle test uses fake battery, Wi-Fi and volume monitors and verifies both monitor and telemetry reporter lifecycle calls.

## Non-publishing CI

The published latest release was rechecked as v1.4.0 (2026-09-30), and the highest appcast build was 17. The feature branch was pushed and release workflow preflight was dispatched with version 2.0.0, build 18, and `publish=false`:

- Run: [36844103043](https://github.com/lingyired/status-trio/actions/runs/36844103043)
- Result: passed on 2026-10-01 with macOS 26.6.2, Xcode 26.6 (17F113), and Swift 6.3.3. The workflow's `Run tests` step passed with the counts above.
- The workflow built `StatusTrio-2.0.0.dmg` without publishing, then uploaded it as the `StatusTrio-221` Actions artifact ([download](https://github.com/lingyired/status-trio/actions/runs/36844103043/artifacts/11153255565)). The downloaded DMG was inspected without launching the app: its marker is `STTelemetryProduction=true`, both architectures report minos 15.0 and SDK 26.0, and signature verification passed.
- GitHub Release creation and appcast publication were skipped as expected for `publish=false`. The workflow used Ad-hoc signing; Developer ID credentials and notarization credentials are not configured, so this run did not notarize the app.
- The workflow ran on product/test commit `b7382e8`. The later `9dda76a` commit only acknowledges OFF consent in the lifecycle test fixture and adds this verification document. The latest tree was independently rechecked with `swift test` and `swift build -c release` after that fixture change; logs: `/tmp/status-trio-telemetry-v2-swift-test-final.log` and `/tmp/status-trio-telemetry-v2-release-build-final.log`.

## Deferred acceptance

Production endpoint requests and remote D1 inspection or writes were not
authorized and were not performed. Production smoke and post-release
verification remain outstanding. Worker/dashboard deployment source edits and
unrelated SwiftUI/XCTest architecture migration were outside this implementation
scope.
