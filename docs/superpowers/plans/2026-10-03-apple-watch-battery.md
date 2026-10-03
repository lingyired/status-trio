# Apple Watch Battery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The implementation worker must use `gpt-6-luna`, as required by the user's standing preference.

**Goal:** Show iPhone and paired Apple Watch battery readings obtained through an already trusted iPhone over USB or Wi-Fi, fixing issue #89's absent Watch row.

**Architecture:** A separately compiled Objective-C helper calls libimobiledevice and emits versioned JSON. A cancellable Swift reader supervises bounded helper invocations; a separate mobile-device controller owns claims and cache lifetime. A pure merge layer folds validated snapshots into the existing device list without changing Bluetooth connection state or device actions.

**Tech Stack:** Swift 6, SwiftUI, Foundation Process, Objective-C/Foundation, libimobiledevice and its source-built dynamic dependencies, existing Swift Testing/XCTest, Bash build scripts.

**Spec:** `docs/superpowers/specs/2026-10-03-apple-watch-battery-design.md` (approved by the user on 2026-10-03).

## Global Constraints

- Work only in `/Users/lingsmbp/.codex/worktrees/issue-89-apple-watch/status-trio`, branch `codex/issue-89-apple-watch`, based on main at `c065b80`.
- CI uses macos-26, Xcode 26.6, Swift 6.3.3; build with macOS SDK 26 or newer and retain platform-version checks. Deployment floor remains macOS 15.
- Build dependencies from pinned upstream source and record their licenses and redistribution requirements. Do not copy AirBattery Swift code, scripts, packet classifiers, or bundled binaries.
- No permanent background polling. Do not silently enable Finder Wi-Fi sync or initiate pairing. Store no pairing credentials in Status Trio and omit device identifiers from routine logs.
- Retain the last successful snapshot with its observation time through temporary failures using the existing 30-minute nearby-result lifetime. Localize new user-facing strings in all 12 shipped languages.
- No release is part of this change until hardware evidence and release preflight are available. Do not claim notarization: the repository currently ships Ad-hoc signing.
- Before every Swift commit run `swift test` and `swift build -c release`. Run a non-publishing release preflight before merging; record every failed GitHub Actions run in `docs/swift-ci-compatibility.md`.

## Review Focus

1. An untrusted phone is discovered: return a trust-required failure without requesting pairing or modifying system configuration (Task 1 native mock test).
2. Two devices share a name: keep their readings separate and never assign a Watch level to an unrelated Bluetooth row (Task 4 pure merge tests).
3. A phone hangs while another responds: terminate the first invocation and publish the second phone's results within the cycle budget (Task 2 fake-process integration test).
4. The popover's view survives closing: cancel helper work from the store's actual popover-close event and reject late results (Task 3 lifecycle tests).
5. A release runs on a Mac with no Homebrew: resolve only bundled or Apple system libraries and verify both architecture slices (Tasks 1 and 5 packaging checks).

## Files and interfaces

New files:

- `Support/MobileBatteryHelper/main.m`: command dispatcher, validated native reads, JSON serialization.
- `Support/MobileBatteryHelper/NativeBatteryClient.h` and `.m`: libimobiledevice adapter, with an injectable native function table for tests.
- `Support/MobileBatteryHelper/tests/NativeBatteryClientTests.m`: mocked native API tests; no attached phone required.
- `Support/mobile-battery-dependencies.json`: dependency versions, source commit pins, build order and license metadata.
- `scripts/build-mobile-battery-helper.sh`: per-architecture builds and universal assembly.
- `scripts/verify-mobile-battery-bundle.sh`: executable, dependency, architecture, minimum OS, SDK, signing and JSON checks.
- `scripts/test-mobile-battery-helper.sh`: build/run the native mock tests.
- `Sources/StatusTrioCore/Models/MobileBatterySnapshot.swift`: wire validation and snapshot types.
- `Sources/StatusTrioCore/Monitoring/MobileBatteryHelperReader.swift`: subprocess supervision and discovery/read orchestration.
- `Sources/StatusTrioCore/Monitoring/MobileBatteryController.swift`: claims, generation gate, refresh and cache expiry.
- `Sources/StatusTrioCore/Models/MobileBatteryDeviceMerge.swift`: identity-safe merge and presentation metadata.
- `Sources/StatusTrioCore/UI/MobileBatteryDeviceRows.swift`: provider-specific observation/charging/source text using existing device row styling.
- `Tests/StatusTrioCoreTests/MobileBatterySnapshotTests.swift`, `MobileBatteryHelperReaderTests.swift`, `MobileBatteryControllerTests.swift`, `MobileBatteryDeviceMergeTests.swift`, `MobileBatteryPresentationTests.swift`: tests owned by the corresponding tasks.
- `docs/apple-watch-battery.md`: setup, limitations, dependency provenance and hardware acceptance evidence.
- `Support/MobileBatteryHelper/ThirdPartyNotices/`: exact upstream license texts plus source and relinking/replacement instructions.

Existing integration files:

- `scripts/build-app.sh`, `.github/workflows/release.yml`: build tools, helper packaging and verification.
- `Sources/StatusTrioCore/Store/SystemStatusStore.swift`: controller ownership and actual popover lifecycle.
- `Sources/StatusTrioCore/UI/BluetoothStatusView.swift`, `StatusPopoverView.swift`: merge rendering, feature claims and refresh.
- `Sources/StatusTrioCore/Settings/SettingsStore.swift`, `Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift`: persisted opt-in setting and setup copy.
- `Sources/StatusTrioCore/Localization/LocalizationKey.swift`, `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`: new copy in all languages.
- `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`, `LocalizationParityTests.swift`: persistence and key coverage.

Do not add runtime native dependencies to Package.swift: ordinary `swift test` and `swift build` must run without the helper. Resolve the helper only from the packaged application bundle; inject its URL and executor in tests. Never search PATH or substitute an AirBattery/Homebrew executable.

---

### Task 1: Build a trusted-device helper and reproducible dependency bundle

**Files:** Native helper, dependency manifest, notices, three helper scripts, `scripts/build-app.sh`, `.github/workflows/release.yml`.

**Interfaces:** Helper accepts `--list` or `--read-phone <identifier> --transport usb|network`. `--list` emits `{"schemaVersion":1,"phones":[{"id":"phone-id","transport":"usb"}]}`. Read mode emits the response in Task 2. stdout is JSON only; stderr contains error categories without identifiers. Failure to execute or enumerate uses a nonzero exit; failures on individual devices remain structured in a successful envelope.

- [ ] **Step 1: Add failing native tests using an injectable adapter.** Mock `idevice_get_device_list_extended`, pair-record access, lockdown values, companion registry and companion values. Tests must cover no devices, USB/network duplicates, missing trust record, missing host identity, invalid percentage node type, missing percentage, unsupported keys, two Watches, and failures releasing all allocated handles. Pin the trust test with counters:

```objective-c
assert(result.error == STMobileBatteryErrorTrustRequired);
assert(fake.pairRequestCount == 0);
assert(fake.startSessionCount == 0);
assert(fake.configurationWriteCount == 0);
```

Run `bash scripts/test-mobile-battery-helper.sh` and confirm the tests fail because the adapter is absent. Define the injectable test boundary in `NativeBatteryClient.h`; production and tests use the same validation paths.

- [ ] **Step 2: Add the source manifest and per-architecture build.** The following upstream tag commits were resolved through GitHub when this plan was written. Build in this order, with libtatsu after libplist and before libimobiledevice; use Apple's SDK libcurl for libtatsu, verified in the linkage audit.

| Dependency | Version | Commit |
| --- | --- | --- |
| openssl/openssl | openssl-3.5.4 | c1eeb9406b6142148f267594197d853403d10208 |
| libimobiledevice/libplist | 2.8.0 | fe3dc34dc3484006e12b403f7ceb06f0ad40b6f4 |
| libimobiledevice/libimobiledevice-glue | 1.3.2 | aef2bf0f5bfe961ad83d224166462d87b1df2b00 |
| libimobiledevice/libusbmuxd | 2.1.1 | adf9c22b9010490e4b55eaeb14731991db1c172c |
| libimobiledevice/libtatsu | 1.0.5 | 42329cb756682535c7c0f087987b78d1dd5b16c8 |
| libimobiledevice/libimobiledevice | 1.4.0 | 149f7623c672c1fa73122c7119a12bfc0012f2ac |

Use checkout-by-commit with a HEAD equality check. Build all runtime libraries dynamically in `.build/mobile-battery/<arch>/`; no user installation. Set `MACOSX_DEPLOYMENT_TARGET=15.0`, SDK from `xcrun`, clang `-arch` and `-isysroot`, and a task-local pkg-config search path restricted to the source-built prefixes. For OpenSSL use `darwin64-arm64-cc` or `darwin64-x86_64-cc`, `shared` and `no-tests`. For the autotools libraries use shared builds with static disabled; libimobiledevice also uses `--without-cython --without-readline --with-openssl`. Disable optional tools where the pinned package supports that flag. Install only runtime dylibs/helper/notices into the app, not upstream CLI tools. CI may install build-only autoconf, automake, libtool and pkg-config; those must not appear as shipped dependencies.

Audit each upstream license at the pinned commit and retain its text, attribution, source retrieval/build instructions and any needed replacement/relinking materials. Use dynamic linkage and document how bundled library copies can be replaced; do not claim the entire dependency graph is Apache-2.0.

- [ ] **Step 3: Implement native reads without pairing.** Enumerate with `idevice_get_device_list_extended`, preserving transport. Before opening a session, read the existing system pair record via libusbmuxd, validate HostID/SystemBUID, and use `lockdownd_client_new` plus `lockdownd_start_session` with that existing record. Do not use a convenience handshake that may initiate pairing; do not call pair/unpair/set-value APIs. The stored record remains owned by the system and must never be copied to app files or emitted.

Read phone name/model/class and `com.apple.mobile.battery` values. Query companion registry and the keys `DeviceName`, `ProductType`, `BatteryCurrentCapacity`, `BatteryIsCharging` separately; unsupported name/charging values are optional, but a missing/invalid level prevents a device snapshot. Start services only after the trusted session. Serialize with Foundation `NSJSONSerialization`, never manual interpolation of names. Free pair plists, strings, arrays, sessions and clients on every exit.

- [ ] **Step 4: Package and verify.** Build the host architecture for ordinary app builds and both arm64/x86_64 when `UNIVERSAL_BUILD=1`. Use lipo on matching helper/dylib slices; validate both architectures and deployment floors. Package the executable at `Contents/Helpers/StatusTrioMobileBatteryHelper` and libraries under `Contents/Frameworks/MobileBattery/`. Rewrite each dylib ID and internal references to `@rpath`; helper rpath is `@executable_path/../Frameworks/MobileBattery`. Reject paths into `/opt/homebrew`, `/usr/local`, build directories and other non-system absolute dependencies. Keep the existing app SDK guard; verify helper and libraries with the platform-version script as applicable.

Sign dylibs first, helper next, enclosing app last, using the existing signing identity. Include notices under `Contents/Resources/MobileBatteryLicenses/`. Add the build-only tool installation step to the release workflow before its build step. Helper packaging must fail explicitly if native build or dependency verification fails, rather than silently shipping without Watch support.

```bash
bash scripts/test-mobile-battery-helper.sh
UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open
bash scripts/verify-mobile-battery-bundle.sh dist/StatusTrio.app
codesign --verify --deep --strict --verbose=2 dist/StatusTrio.app
```

Verification runs `--list` with a minimal environment and validates the JSON schema; no phone attached is a valid empty response. The script checks otool references recursively and each binary's architecture, signature and deployment target. Re-run native mock tests and commit these helper/build changes only after they pass.

### Task 2: Validate snapshots and supervise independent helper invocations

**Files:** `MobileBatterySnapshot.swift`, `MobileBatteryHelperReader.swift`, snapshot/reader tests.

**Interfaces:** Define `MobileBatteryTransport: String, Codable, Sendable` (`usb`, `network`); `MobileBatterySnapshot: Equatable, Sendable` with `id: String`, `parentID: String?`, `name: String?`, `model: String`, `batteryLevel: Int`, `isCharging: Bool?`, `transport: MobileBatteryTransport`, `observedAt: Date`. Identity is `phone:<id>` for phones and `watch:<parentID>:<id>` for Watches. Define `MobileBatteryReadResult: Sendable` containing `snapshots: [MobileBatterySnapshot]` and categorized `failures`, and `MobileBatteryReading: Sendable` with `func read() async throws -> MobileBatteryReadResult`. Define injectable `MobileBatteryHelperExecuting: Sendable` with `func run(arguments: [String], timeout: Duration) async throws -> Data`.

Wire example (id values are test-only placeholders, not real identifiers):

```json
{"schemaVersion":1,"devices":[{"id":"phone-a","parentID":null,"name":"Phone","model":"iPhone17,1","batteryLevel":72,"isCharging":false,"transport":"usb"},{"id":"watch-a","parentID":"phone-a","name":null,"model":"Watch7,1","batteryLevel":61,"isCharging":null,"transport":"usb"}],"failures":[]}
```

Use an internal Codable wire envelope and independent per-device validation; one invalid entry must not throw away its valid siblings. Set observation time in Swift only after a successful response. Reject unknown schema versions; do not accept booleans, strings or floats as integer percentages. Reject blank identifiers, a Watch without parentID, and incompatible families; enforce that every Watch parent matches the read command's phone identifier.

- [ ] **Step 1: Write failing validation tests.** Define `MobileBatteryWire.decode(_:expectedParentID:observedAt:) throws -> MobileBatteryReadResult` and use this contract:

```swift
@Test func realZeroSurvivesValidation() throws {
    let json = Data(#"{"schemaVersion":1,"devices":[{"id":"w","parentID":"p","name":null,"model":"Watch7,1","batteryLevel":0,"isCharging":null,"transport":"usb"}],"failures":[]}"#.utf8)
    let result = try MobileBatteryWire.decode(json, expectedParentID: "p", observedAt: .distantPast)
    #expect(result.snapshots.first?.batteryLevel == 0)
    #expect(result.snapshots.first?.observedAt == .distantPast)
}
```

Add full-battery, -1/101, string/Bool/fraction, missing battery, whitespace ID, escaped Unicode name, unknown schema, wrong parent and mixed-validity tests. Run `swift test --filter MobileBatterySnapshotTests` and confirm the missing types fail first.

- [ ] **Step 2: Implement bounded process supervision.** Resolve the packaged helper using `Bundle.main.bundleURL`, verify it is executable and do not fall back to PATH. Execute using Process executableURL and a literal argument array, never a shell. Drain stdout/stderr asynchronously to avoid pipe deadlocks, cap each stream at 1 MiB, and redact stderr from user-facing errors. Coordinate launch, termination, timeout and cancellation so the continuation completes exactly once. On timeout/cancel send termination, then SIGKILL after 250 ms if still running, and reap the child. Do not read/wait synchronously on MainActor. Keep process state on one serial executor with explicit teardown; no `isolated deinit` or experimental flags.

The reader runs listing with a 3-second timeout, deduplicates phone identifiers preferring USB, and reads at most eight phones with two concurrent read processes. Each phone invocation gets 5 seconds and the whole cycle gets 25 seconds; cancellations stop all child processes. A failed USB read may try a discovered network route for the same phone within the remaining phone budget, never an invented route. Read results are accumulated independently so one timeout does not discard another phone's snapshots.

- [ ] **Step 3: Add fake-executor and real-process tests.** Inject listing/read responses and verify the two-process limit, eight-phone bound, one read for USB/network duplicates, network retry, late completion after cancellation and unrelated phone success during a timeout. Use temporary executable test scripts with small stdout, large stdout, large stderr, nonzero exit and ignored SIGTERM to verify process cleanup and size limits. Test scripts contain no device secrets and are deleted afterward. Run reader/snapshot tests, then `swift test` and `swift build -c release` before committing.

### Task 3: Add a mobile controller tied to actual popover lifetime

**Files:** `MobileBatteryController.swift`, `SystemStatusStore.swift`, controller tests.

**Interfaces:** `@MainActor final class MobileBatteryController: ObservableObject` exposes `@Published private(set) var snapshots: [MobileBatterySnapshot]`, `request(_ token: String)`, `release(_ token: String, keepingResults: Bool = false)`, `setSurfaceVisible(_ visible: Bool)`, `refresh()` and `stop()`. Inject `reader: any MobileBatteryReading`, a clock returning Date and a cancellable sleep closure. This controller is separate from Bluetooth availability; USB reads must work with Bluetooth off or permission denied.

- [ ] **Step 1: Write failing lifecycle tests with a controllable async reader.** Opening the surface without claims does nothing; claims on a closed surface do nothing; visible surface plus claim reads immediately. Closing the real popover cancels the active read; reopening starts a fresh generation. Releasing one of two claims does not cancel the other; disabling the final claim clears snapshots immediately. Add a test where the old reader intentionally returns after cancellation and verify it cannot replace the new generation's reading.

```swift
@Test @MainActor func claimsAloneDoNotRead() async {
    let reader = MobileBatteryReaderSpy()
    let controller = MobileBatteryController(reader: reader)
    controller.request("summary")
    await Task.yield()
    #expect(reader.readCount == 0)
    controller.stop()
}
```

`MobileBatteryReaderSpy` is defined in this test file, conforms to `MobileBatteryReading`, and records starts/cancellations behind synchronized storage; deterministic continuations control completion. Do not assert on arbitrary real sleeps.

- [ ] **Step 2: Implement generations, refresh and timestamp-preserving cache.** Read immediately when the predicate becomes true; refresh every 60 seconds while visible and claimed, with no overlapping cycles. Manual refresh cancels/supersedes the current generation and starts fresh. Merge successful snapshots by stable identity; a failure or empty response retains existing readings without updating their timestamps. Prune at `now >= observedAt + 1800`, schedule the earliest expiry even while the surface is closed, and avoid rescheduling an already expired entry in a tight loop. Stop cancels refresh/expiry tasks and reader work; add deinit cancellation with CI-compatible teardown storage.

- [ ] **Step 3: Wire actual store lifecycle.** Add a mobile controller property/injectable initializer parameter to `SystemStatusStore`, forward popover-open and popover-close events via `setSurfaceVisible`, and call `stop()` during app/store shutdown. The retained view's onDisappear is insufficient: tests must invoke the store's close path and assert reader cancellation. Surface visibility and mobile claims remain independent of Bluetooth activation and permission. Add tests for expiry while closed, cache retention after partial failure, last reading replacement, deallocation and Bluetooth-off USB reads. Run focused tests, full tests and release build before committing.

### Task 4: Merge readings and add localized opt-in UI

**Files:** Merge/row files, `BluetoothStatusView.swift`, `StatusPopoverView.swift`, SettingsStore, BluetoothSectionView, LocalizationKey, all Localizable.strings, merge/presentation/settings/localization tests.

**Interfaces:** `MobileBatteryDeviceMerge.merged(devices:batteryLevels:nearbyDevices:mobileSnapshots:fallbackWatchName:) -> Result`. `Result` contains `devices: [BluetoothDevice]`, `batteryLevels: [String: BluetoothBatteryLevel]`, `remainingNearby: [NearbyBluetoothBatteryDevice]`, and `mobileMetadataByDeviceID: [String: MobileBatterySnapshot]`. Combine raw sources in one pass so Task 4 does not inherit the existing nearby merge's first-name-match ambiguity. New provider-only rows reuse `BluetoothDevice` with `isConnected: false`, `isReadOverTheAir: true`, and a prefixed stable ID; that flag already disables Bluetooth connect/disconnect actions. Broaden its documentation to describe externally read devices without changing action behavior or icon options.

- [ ] **Step 1: Add failing merge tests.** Test a named/unnamed Watch, two Watches on one phone, same Watch name on different parents, duplicate USB/network phone results, unique name match against a BLE phone, two Bluetooth rows with the same name, phone/watch family mismatch, and an existing paired battery value. Require real paired readings to win; otherwise trusted mobile readings win over BLE readings. Identity always wins over names; use a normalized exact name only if both sides have one compatible-family candidate. Ambiguous candidates stay separate with their own source metadata; never silently move a battery between them.

```swift
@Test func watchRowsAreNotBluetoothConnections() {
    let watch = MobileBatterySnapshot(id: "w", parentID: "p", name: nil,
        model: "Watch7,1", batteryLevel: 61, isCharging: false,
        transport: .usb, observedAt: .distantPast)
    let result = MobileBatteryDeviceMerge.merged(devices: [], batteryLevels: [:],
        nearbyDevices: [], mobileSnapshots: [watch], fallbackWatchName: "Apple Watch")
    #expect(result.devices.count == 1)
    #expect(result.devices[0].kind == .mobile(.watch))
    #expect(!result.devices[0].isConnected)
    #expect(result.devices[0].isReadOverTheAir)
    #expect(result.devices[0].name == "Apple Watch")
}
```

- [ ] **Step 2: Implement merge and settings persistence.** Add `SettingsStore.showsMobileDeviceBatteryLevels` and defaults key `showsMobileDeviceBatteryLevels`, default false. Follow the existing nearby setting's didSet persistence/initializer pattern. Add tests proving default, save/reload and independence from nearby BLE opt-in. Pass a separately observed `MobileBatteryController` into BluetoothStatusView from StatusPopoverView so snapshot updates repaint even though the parent store does not forward nested publishers.

Claim only when the master battery setting and mobile setting are on and the existing device-list setting allows the panel to show results. The store remains the actual visibility gate. Release/clear on disabling; preserve cache on closing. Refresh button triggers both Bluetooth refresh and mobile refresh. Render mobile rows when Bluetooth availability is off/denied, outside the current paired-device visibility gate. Preserve paired filtering, hidden rows, ordering and maximum-visible behavior for the final list. Do not request Bluetooth authorization to retrieve USB data.

- [ ] **Step 3: Add truthful source/age copy and all language variants.** Present observation time/age for mobile readings using a localized date formatter, plus source text for Watch through iPhone and optional charging state. Do not label the Watch connected or paired to the Mac. Add localized fallback Watch name and setup/failure text. English and Simplified Chinese copy:

```text
settings.bluetooth.mobileBatteryDevices = iPhone and Apple Watch battery
settings.bluetooth.mobileBatteryDevicesDescription = Read through a trusted iPhone over USB or Wi-Fi. Connect the iPhone by cable once and tap Trust. Wireless use requires existing Wi-Fi syncing.
mobileBattery.watchFallbackName = Apple Watch
mobileBattery.watchSource = Via iPhone
mobileBattery.updatedAt = Updated %@
mobileBattery.charging = Charging
mobileBattery.trustRequired = Connect your iPhone by cable and tap Trust to read its Apple Watch battery.
mobileBattery.unavailable = iPhone and Apple Watch battery could not be refreshed.
```

```text
settings.bluetooth.mobileBatteryDevices = iPhone 与 Apple Watch 电量
settings.bluetooth.mobileBatteryDevicesDescription = 通过已信任的 iPhone，经 USB 或 Wi-Fi 读取。首次请用线连接 iPhone 并轻点“信任”；无线读取需要已配置 Wi-Fi 同步。
mobileBattery.watchFallbackName = Apple Watch
mobileBattery.watchSource = 通过 iPhone 读取
mobileBattery.updatedAt = 更新于 %@
mobileBattery.charging = 正在充电
mobileBattery.trustRequired = 请用线连接 iPhone 并轻点“信任”，以读取配对 Apple Watch 的电量。
mobileBattery.unavailable = 无法刷新 iPhone 与 Apple Watch 电量。
```

Translate the same keys into ar, de, es, fr, it, ja, ko, pt-BR, ru and zh-Hant, matching existing terminology. Use existing localization formatting conventions and ensure `%@` placeholder parity. Show a single actionable failure line when there are no usable results; stale successful readings retain their original update time. The feature remains opt-in; no new startup modal.

- [ ] **Step 4: Verify presentation and regressions.** Test mobile results visible with Bluetooth off, disabled mobile setting clears rows, hidden/read-only row actions, unique fallback names, cached timestamps unchanged on failed refresh, and master-setting/claim transitions. Run merge/presentation/settings/localization suites plus the existing Bluetooth nearby, device-list and battery suites; finish with full tests and release build before committing.

### Task 5: Validate packaged app, document hardware evidence and run release preflight

**Files:** `docs/apple-watch-battery.md`, build verification scripts if corrections are needed, `docs/swift-ci-compatibility.md` only for failed CI runs.

**Interfaces:** This task produces an evidence record with local test/build results, helper dependency pins, packaging audits, workflow run URL/SHA and actual hardware results or explicitly pending hardware acceptance. It does not publish a release.

- [ ] **Step 1: Run final automated checks against the complete branch.**

```bash
swift test
swift build -c release
bash scripts/test-mobile-battery-helper.sh
UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open
bash scripts/verify-mobile-battery-bundle.sh dist/StatusTrio.app
bash scripts/validate-appcast-notes.sh
git diff --check
```

Run the packaged helper after copying the app to a path containing spaces. Verification must audit transitive otool references so success on a developer Mac cannot conceal Homebrew runtime dependencies. Confirm all dylibs and the helper have arm64 and x86_64 slices and macOS 15 deployment floors; retain macOS 26 SDK adoption checks. Preserve evidence without committing generated binaries/build directories.

- [ ] **Step 2: Perform hardware checks if a trusted phone/Watch is available.** Enable the mobile battery option, connect an already trusted iPhone over USB, compare phone and Watch levels/charging against device displays, disconnect USB with existing Wi-Fi sync configured, and confirm wireless discovery. Close/reopen the panel, turn Bluetooth off, disconnect the phone and exercise cache expiry. Never change system pairing or Wi-Fi sync configuration automatically. Record OS/device versions, transport, observation times and results without publishing stable device IDs. If no hardware is available, mark that acceptance pending and do not claim #89 fully resolved from mocks alone.

- [ ] **Step 3: Commit verified implementation, push the feature branch and run preflight.** Read the latest published build/version and choose explicit preflight inputs immediately before dispatch. The checked-in version is 1.4.0/build 17; use 1.4.0/build 18 only if the latest published build is still 17. Otherwise choose the next greater build, using the current version's existing notes for this non-publishing check. Do not change release version files or create a tag solely for preflight.

```bash
gh release view --repo lingyired/status-trio
git push -u origin codex/issue-89-apple-watch
gh workflow run release.yml --repo lingyired/status-trio \
  --ref codex/issue-89-apple-watch -f version=1.4.0 -f build=18 -f publish=false
gh run list --repo lingyired/status-trio --workflow release.yml \
  --branch codex/issue-89-apple-watch --limit 5
```

The dispatch command above is concrete for the observed build-17 baseline; update its version/build if the preceding published-state check requires it. Match the returned run to the pushed HEAD SHA, then watch that numeric run ID with `gh run watch` and `--exit-status`. Use nonblocking/polled execution so progress can still be reported within 60 seconds. Inspect test, helper build, universal app build/signing, DMG creation and artifact upload stages; publish/upload-to-release/appcast stages must remain skipped for `publish=false`. Record any failure's run ID, stage, cause, fix and verification in the compatibility document, then re-run corrected HEAD. Stop after three failed fixes and name the assumption requiring reconsideration.

- [ ] **Step 4: Review the complete branch and report evidence.** Use requesting-code-review and verification-before-completion skills. A fresh reviewer checks trust handling, dynamic packaging, timeout teardown, identity matching and real popover-close cancellation. Correct findings and repeat only affected checks plus required pre-commit checks. Do not merge or publish as part of this task. If hardware remains pending, report implementation/CI status separately and provide the one-minute USB verification action.

## Plan self-review

- Spec coverage: helper/native provenance and packaging in Task 1; valid per-device wire data and bounded reads in Task 2; claims/cancel/cache in Task 3; deduplication/settings/source text/localization in Task 4; real hardware and release preflight in Task 5.
- Failure coverage: all five Review Focus inputs have owning-task tests or packaging assertions. Additional tests cover malformed values, unsupported keys, multiple Watches, source precedence, generation rejection and expiry.
- Interface consistency: the helper emits `schemaVersion`, devices and failures; validated snapshots carry parent identity, transport and observation time; reader and controller use the declared async protocol; merge receives raw sources once.
- Scope: no AirBattery code/binaries, no pairing changes, no Pencil/Nearcast, no icon-option changes, no publishing.

## Execution handoff

The approved design is implemented by a `gpt-6-luna` worker in the existing worktree, sequentially across the five tasks. Native helper and runtime packaging come first because that is the primary feasibility risk. Preserve all tests and source in this branch. Review this written plan before implementation, as required by the project's writing-plans workflow.
