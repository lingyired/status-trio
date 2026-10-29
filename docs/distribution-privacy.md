# Distribution privacy review

Date: 2026-10-24
Scope: App Store candidate manifest and source-level policy boundaries
Status: policy review **NOT VERIFIED**

This document records the current Store privacy declaration and the questions
that still require review. It is not a compliance certification, an Apple
approval, or a claim that every data access in the shared source has been
classified. Do not remove a public capability or replace an API solely to
avoid a required-reason declaration without a separate product decision.

## Store telemetry

Store telemetry is ineligible in `TelemetryEligibility`: only the production
Direct bundle with its production marker and a non-Debug build can send a
heartbeat. The Store candidate has no third-party analytics SDK and the
manifest declares:

- `NSPrivacyTracking = false`
- `NSPrivacyTrackingDomains = []`
- `NSPrivacyCollectedDataTypes = []`

That declaration describes the current candidate. If Store telemetry is ever
enabled, it requires a separate privacy design, consent flow, disclosure, and
manifest update. It must not inherit the Direct telemetry allowlist.

## Required-reason API mapping

Apple's official DocC JSON for
[`NSPrivacyAccessedAPIType`](https://developer.apple.com/tutorials/data/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype.json)
lists the reason definitions used below. The human-readable documentation page
is
[`NSPrivacyAccessedAPIType`](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

### UserDefaults: `CA92.1`

Apple's exact reason text says: "Declare this reason to access user defaults to
read and write information that is only accessible to the app itself. This
reason does not permit reading information that was written by other apps or
the system, or writing information that can be accessed by other apps."

The shared settings, localization choice, preview suites, and Store-local
persistence are app-owned defaults. They use the Store candidate's own
container/domain and do not share a suite with the Direct app. This is the
basis for declaring `CA92.1` for that access.

### System boot time: `35F9.1`

Apple's exact reason text says: "Declare this reason to access the system boot
time in order to measure the amount of time that has elapsed between events
that occurred within the app or to perform calculations to enable timers.
Information accessed for this reason, or any derived information, may not be
sent off-device. There is an exception for information about the amount of time
that has elapsed between events that occurred within the app, which may be sent
off-device."

`VolumeFeedback.swift` reads `ProcessInfo.processInfo.systemUptime` at line 93
for an in-process throttle: it compares the current uptime with the last
in-app playback timestamp to decide whether 100 ms have elapsed. The value is
not stored, sent off-device, or used to calculate a wall-clock timestamp. This
is the basis for declaring `35F9.1` for that access.

## Policy boundaries requiring review

### System-written volume feedback preference

`VolumeFeedback.swift` reads the dotted key
`com.apple.sound.beep.feedback` through `UserDefaults.standard`. That key lives
in the global preferences domain and is normally written by the system when a
person changes the system sound setting. `CA92.1` does **not** cover reading
data written by the system, even if the lookup uses the standard search list.
The manifest's `CA92.1` declaration therefore covers app-owned defaults; it
must not be described as covering this system preference read.

Whether retaining this public behavior is appropriate for the Store candidate,
and whether a different declared reason or product behavior is required, is
**policy review NOT VERIFIED**. Do not claim this read is compliant, silently
remove it, or swap to another API just to avoid the reason.

### Global icon appearance preference

`SystemIconAppearanceReader` uses the public `CFPreferencesCopyAppValue` API
with `kCFPreferencesAnyApplication` to read the global
`AppleIconAppearanceTheme` preference. This is not the private C-function class
of API, but it is also not the UserDefaults required-reason category in the
DocC list above. Its Store policy treatment is therefore **separate review NOT
VERIFIED**.

The reader currently supplies the system icon appearance to shared rendering
paths. Do not delete that capability, change the renderer, or claim the
`CA92.1` entry covers this read without explicit review and runtime evidence.

### Shared purpose strings

The existing shared `InfoPlist.strings` resources still describe Direct
Bluetooth behavior such as noise-control mode on supported headphones. The
Store source closure may exclude the Apple private HAL implementation, so the
final Store purpose strings may need Store-specific resources. That resource
split is owned by the Store project integration, not by this privacy-manifest
phase. Until it is implemented and reviewed, the Store usage-description
coverage is **NOT VERIFIED**.

## Manifest integration dependency

`AppStore/PrivacyInfo.xcprivacy` must be included as an app resource in the
generated Store application target. The platform/Store project owner must add
it through the XcodeGen resource phase and verify that the built app contains
`Contents/Resources/PrivacyInfo.xcprivacy`. This phase does not modify the
project generator, Store build scripts, or bundle auditor.

## Offline manifest fixtures

`Tests/StatusTrioCoreTests/DistributionLocalizationTests.swift` contains nine
focused checks. Five cover distribution copy/key coverage and four cover the
privacy manifest. The manifest negative fixtures reject:

1. tracking enabled;
2. a non-empty tracking-domain list;
3. non-empty collected data;
4. a missing required API category;
5. an empty reasons array;
6. an extra reason;
7. the wrong boot-time reason;
8. an extra API category;
9. an invented API category; and
10. an unexpected top-level key.

The committed manifest itself passed `plutil -lint`. The test source defines
exact round-two snapshots for all 12 distribution descriptions, localized
forbidden-claim coverage, and the exact two-category reason mapping. Executing
that Swift test revision remains part of the parent's final verification.

## Evidence still required

- Apple policy review of the system-written volume-feedback read.
- Separate policy review of `CFPreferencesCopyAppValue` for global icon
  appearance.
- Final Store-specific purpose-string audit against the compiled source
  closure.
- A real unsigned Store build containing the manifest.
- Signed entitlement and sandbox-runtime checks.
- App Store Connect privacy answers and review submission, if separately
  authorized.
- A focused Swift test run for the round-two copy revision. The prior round's
  9/9 run predates the evergreen copy change; the current Foundation SwiftPM
  slot is owned by another worker, and the parent's final verification owns
  rerunning the focused tests.

All of the above are **NOT RUN** in this offline phase.
