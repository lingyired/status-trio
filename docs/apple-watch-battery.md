# iPhone, iPad, and Apple Watch battery rows

## Setup

1. In **Settings → Bluetooth**, enable **Show Apple devices and battery**.
   Verified devices already trusted by this Mac appear automatically in the Bluetooth list; there is no device picker.
2. Connect an iPhone or iPad to the Mac over USB and accept **Trust This Computer** if prompted. Status Trio does not initiate pairing or change trust settings.
3. For wireless reads, configure Wi-Fi syncing for the iPhone in Finder yourself. The app uses an already configured trusted route and does not enable Wi-Fi syncing.
4. Keep the iPhone and Watch paired as usual. A Watch is verified and read through its trusted paired iPhone; the Watch does not need a separate Mac pairing.

The setting is off by default. The Bluetooth battery-level setting must also be
on to read levels. Reads are on demand for currently verified devices whose
rows are visible in the list viewport, refresh periodically while visible, and
stop when the panel closes or eligibility is revoked. Previously verified
metadata can keep an offline row visible, but cached metadata alone does not
authorize a new read. Battery observations are cached for up to 30 minutes
across temporary read failures. The helper reads only devices already trusted
by macOS. It stores no pairing credentials in Status Trio and routine logs omit
device identifiers.

A Watch can appear with the localized fallback name **Apple Watch**. Watch
charging state is not currently read. When the phone is temporarily
unavailable, a previously verified row can remain visible; the prior battery
reading can remain until its observation expires. Same-named classic Bluetooth
rows are not assumed to be the same device as helper UDIDs and remain separate
when no stable mapping exists.

## Why a Watch row may be missing

Discovery has no Bluetooth route of its own. A Watch is read only through its
paired iPhone's companion service, so all of the following are prerequisites:

1. The iPhone must appear in the helper's `--list` output. That list contains
   only devices reachable over USB or an already configured Wi-Fi sync route; a
   Bluetooth-only pairing never appears, so its Watch cannot be discovered.
2. The iPhone must be trusted by this Mac. An untrusted route produces a
   `trustRequired` candidate with no model and no Watch candidates, and it is
   never shown as an Apple device row.
3. The iPhone must be unlocked and reachable long enough for the companion
   service to answer. If the companion client or its device registry fails, the
   helper still returns the iPhone candidate with **no Watch candidates**. The
   helper's discovery output only reports `trust-required`,
   `host-identity-missing`, and `session-unavailable` failures; a failed
   companion client is silent, so the app cannot tell "no paired Watch" apart
   from "companion unavailable". An empty companion result is therefore logged
   as `companion-empty-or-unavailable`, not as a specific failure.
4. Discovery probes at most eight iPhone routes and keeps whole phone groups
   against an eight-candidate budget. The first group may contain nine entries
   (one phone plus eight Watches); later groups that would exceed the budget are
   omitted. Selection follows phone-ID order, so completion timing cannot change
   which group survives. A Watch is only dropped together with its own iPhone.
   A cycle runs at most eight routes × two transports = 16 helper discovery
   processes, and only while discovery demand is active (panel visible or
   background refresh enabled). The reader logs one identifier-free summary per
   cycle — listed/probed phones, discovered/retained candidates, dropped groups,
   and dropped Watch candidates — before the cap, so a group the cap removed
   stays visible in diagnostics.
5. The Watch row must be verified: `trustRequired == false`, the candidate
   carries the iPhone route's `.usb`/`.network` transport, and the evidence is an
   Apple Watch model or the trusted companion route. The helper never sets
   `.bluetooth` on these candidates; `isVerifiedTrustedAppleDevice` rejects any
   candidate without a trusted transport, so a helper that ever emitted
   `.bluetooth` for a Watch would hide that row.
6. A read needs the parent iPhone to still appear in `--list` in the same cycle.
   If the iPhone dropped between discovery and reading, that Watch read is
   skipped silently for the cycle.
7. `--read-watch` can fail while the Watch is off the wrist, locked, or out of
   range. An initial Watch observation gets at most three retries at one-minute
   intervals, then it follows the regular refresh cadence.

`MobileBatteryHelperReader.decodeWatchCandidates` is not part of discovery: it
reads the `watchCandidates` list that only the `--read-phone` envelope emits.
Watches reach discovery inline in `--discover-device`'s `candidates` array and
are decoded by `MobileBatteryWire.decodeDiscovery`.

`AppleDeviceDiscoveryController.discoveryDiagnostics` records one identifier-free
summary per discovery cycle: candidate count, Watch count, verified count,
rejected counts, and a failure category. A missing Watch row can therefore be
traced to a helper failure instead of guessed at.

## Helper dependencies and redistribution

The app bundles a native helper and universal runtime libraries built from source. Exact upstream repositories, versions, commit pins, and declared licenses are in [`Support/mobile-battery-dependencies.json`](../Support/mobile-battery-dependencies.json). The dependency graph is OpenSSL 3.5.9, libplist 2.8.0, libimobiledevice-glue 1.3.2, libusbmuxd 2.1.1, libtatsu 1.0.5, and libimobiledevice 1.4.0. The corresponding license texts and source rebuild/replacement instructions are in [`Support/MobileBatteryHelper/ThirdPartyNotices/`](../Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md).

To rebuild the helper, install the build-only tools `autoconf`, `automake`, `libtool`, and `pkg-config`, then run:

```sh
UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
```

The build checks out the pinned commits and builds arm64 and x86_64 slices with a macOS 15 deployment target. `scripts/verify-mobile-battery-bundle.sh` checks architectures, deployment versions, macOS SDK adoption, signatures, runtime load paths, transitive dependencies, and a sterile-environment helper invocation. The linked runtime libraries are bundled in the app; Homebrew is not needed at runtime. Recipients can replace an LGPL library with a compatible build from its identified source; see the notice for replacement and re-signing steps.

## Verification record

**Local automated checks — 2026-10-03:** on macOS 27.0.1 with Xcode 27.0 (Swift 6.4, macOS SDK 27.0), `swift test` passed 1,139 XCTest cases (6 skipped, 0 failed) and 475 Swift Testing cases in 76 suites; `swift build -c release` completed. `scripts/test-mobile-battery-helper.sh` passed all 17 native adapter cases. `UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open` built and signed the app; the bundle audit passed for arm64 and x86_64. The app executable slices report macOS 15.0 minimum and SDK 26.0; the helper and each bundled runtime library report macOS 15.0 minimum and SDK 27.0. Xcode 27 also emitted its x86_64 deployment-target deprecation warning; the requested universal build and audit passed, and no build setting was changed to suppress the warning. The packaged app also passed `scripts/verify-mobile-battery-bundle.sh` after copying it to a temporary path containing spaces and invoking the helper with a sterile PATH. The audit's transitive `otool` checks accepted bundled/Apple dependencies and rejected unbundled runpaths; the dedicated rpath and dependency fixtures passed. Appcast-note validation and final diff checks are recorded with the preflight evidence below.

Local logs are retained in the task scratch directory (not shipped): `.superpowers/sdd/2026-10-03-apple-watch-battery/task-5-*.log`.

**Release workflow preflight — PASS:** [run 37108779255](https://github.com/lingyired/status-trio/actions/runs/37108779255) ran against tested commit `42c47b0e33d326421f1a1566bc3130010020147e`. The runner was macOS 26.6.2 with Xcode 26.6, Swift 6.3.3, and macOS SDK 26.5. CI passed 1,139 XCTest cases (6 skipped, 0 failed) and 475 Swift Testing cases in 76 suites; appcast-note validation passed for all 12 languages. The app executable passed audit with arm64 and x86_64 slices, macOS 15.0 minimum, and LC_BUILD_VERSION SDK 26.0. The source-built helper and each bundled runtime library passed audit with arm64 and x86_64 slices, macOS 15.0 minimum, and SDK 26.5. SDK 26.5 is the CI toolchain SDK; the app executable reports 26.0 in its own load-command metadata. The app was signed Ad-hoc because Developer ID signing and Apple notarization are not configured. DMG `StatusTrio-1.4.0.dmg` was created without publishing, and the workflow artifact upload succeeded ([artifact 11269166810](https://github.com/lingyired/status-trio/actions/runs/37108779255/artifacts/11269166810)). GitHub Release upload and appcast publication were skipped by `publish=false`. This verification covers the tested feature SHA above; this evidence update is a documentation-only follow-up.

**Hardware acceptance: PENDING.** At the local check on 2026-10-03, the packaged helper's isolated `--list` command found zero trusted phones. No already-trusted iPhone or paired Watch was available to this check, so USB battery values, Watch readings against device displays, configured Wi-Fi transport, panel reopen, Bluetooth-off behavior, phone disconnect, and cache expiry have not been observed on hardware. Mocks and packaging checks do not resolve this acceptance item. To complete it, connect an already-trusted iPhone by USB, enable the setting, compare iPhone and Watch battery percentages and the iPhone charging state with their displays, then check the existing Wi-Fi-sync route and the documented close/reopen, Bluetooth-off, disconnect, and expiry behavior. Record OS/device versions, transport, observation times, and results here without stable device IDs. Do not pair devices or change Wi-Fi-sync configuration as part of verification.

**Current helper enumeration — 2026-10-07:** the helper's `--list` operation
found zero trusted devices. Automated discovery and authorization tests pass,
but physical iPhone/iPad/Watch reads still require hardware verification. Do
not infer working hardware reads from an empty enumeration.

**Final review fix wave — 2026-10-03:** local `swift test` passed 1,142 XCTest cases (6 skipped, 0 failed) and 476 Swift Testing tests across 76 suites; `swift build -c release` passed; the native helper adapter suite passed 18/18 cases. The universal app build, helper bundle audit, signature verification, rpath/dependency fixtures, and executor-backed `--list` smoke against `dist/StatusTrio.app` passed. This packaged-reader smoke found zero trusted phones (`phones: []`): it verifies the packaged helper path and list decoding only, and is not hardware acceptance. Its test asserts an empty phone list, so it may fail when run on a machine with a trusted phone connected; use the app UI and compare against device displays for hardware acceptance. On this local macOS 27.0.1 / Xcode 27.0 / Swift 6.4 / SDK 27.0 machine, the app executable's LC_BUILD_VERSION SDK was 26.0 and the helper/runtime library SDK was 27.0. Detailed logs are in `.superpowers/sdd/2026-10-03-apple-watch-battery/final-*.log`.

**Release workflow preflight for final review fixes — PASS:** [run 37111365303](https://github.com/lingyired/status-trio/actions/runs/37111365303) tested source commit `21a2392b12babc424fc9ae5d145f49b09bf86085` on macOS 26.6.2 with Xcode 26.6 and Swift 6.3.3. All 1,142 XCTest cases passed (6 skipped, 0 failed), along with 476 Swift Testing tests across 76 suites. Version/build 1.4.0/18 appcast validation passed for all 12 languages; the app executable audit passed for arm64 and x86_64 at macOS 15.0 minimum with LC_BUILD_VERSION SDK 26.0. The helper and bundled runtime libraries passed the same architecture/minimum-version audit with SDK 26.5. The Ad-hoc signed `StatusTrio-1.4.0.dmg` was built without publishing, and artifact `StatusTrio-223` (ID 11269634230) uploaded successfully. GitHub Release upload and appcast publication were skipped because `publish=false`. The optional local packaged-reader smoke returned `phones: []`; it verifies path resolution and response decoding only. Its empty-list assertion can fail when a trusted phone is connected, and is not hardware acceptance. Hardware acceptance remains pending as described above.
