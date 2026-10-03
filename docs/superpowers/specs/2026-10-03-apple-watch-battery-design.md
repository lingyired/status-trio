# Apple Watch battery through a trusted iPhone

## Goal and evidence

Issue #89 reports that the Apple Watch device row is entirely absent. Show a named Watch row with the battery level obtained through its trusted parent iPhone. The Watch does not need to pair with the Mac.

Status Trio already recognizes `Watch` model strings and renders watch icons. Its current nearby scanner reads the standard BLE Battery Service; the repository has no iPhone USB/network provider or companion-proxy client. Model recognition alone does not supply a reading.

AirBattery's `IDeviceBattery.swift` discovers USB and network iPhones, reads their battery through lockdown, and runs `comptest` to retrieve Watch information. Its README explicitly excludes Watch readings through the Bluetooth iPhone path. The upstream companion-proxy sample enumerates paired Watch identifiers and queries `ProductType`, `BatteryCurrentCapacity`, and `BatteryIsCharging`. These are reference mechanisms, not proof of compatibility with every current iOS/watchOS version.

References:

- https://github.com/lingyired/status-trio/issues/89
- https://github.com/lihaoyun6/AirBattery/blob/main/AirBattery/BatteryInfo/IDeviceBattery.swift
- https://github.com/lihaoyun6/AirBattery#qa
- https://gist.github.com/nikias/ebc6e975dc908f3741af0f789c5b1088
- https://github.com/libimobiledevice/libimobiledevice

## Selected approach

Add an independent USB/network mobile-device battery provider using a small, separately built helper and libimobiledevice. Ship its runtime dependencies with the app so users do not need Homebrew. Build those dependencies from pinned upstream source and record their licenses and redistribution requirements. Do not copy AirBattery Swift code, scripts, packet classifiers, or bundled binaries.

Compared with a Homebrew-only integration, bundling supplies the feature to ordinary release users. Compared with direct use of Apple's private MobileDevice framework, the helper provides a documented upstream client API and isolates native library calls from the Swift UI process. Packaging and current-device compatibility must be verified before calling the feature supported.

## Data flow

The helper enumerates USB and network devices already trusted by this Mac. It connects to iPhone lockdown, queries phone identity and battery, starts `com.apple.companion_proxy`, enumerates paired Watch identifiers, and queries each Watch's battery and model. It emits a versioned JSON response with transport, parent identifier, stable device identifier, display name when available, model, percentage, charging state, and per-device failures.

Swift validates this response and publishes mobile-device snapshots. Percentages outside 0...100, absent battery values, malformed responses, and unsuccessful Watch queries must not become zero-percent rows. A supported Watch model may use a localized Apple Watch name if no device name is available.

USB and Wi-Fi results for the same identifier describe one device. A Watch is keyed by its stable identifier and parent relationship, not its name. Integrate the provider's snapshots with existing BLE and paired-device presentation without duplicating phone or Watch rows. Prefer stable shared identifiers where available; if BLE supplies only a name, merge only a unique exact normalized name match with a compatible device family. Ambiguous names must not transfer readings between devices.

## Lifecycle and user experience

Follow the existing battery claims and visible-surface lifecycle: run discovery when the relevant panel is open and the feature is enabled, use bounded refreshes, and cancel active helper work when the surface closes, settings disable it, or the app terminates. No permanent background polling. Bound each invocation and the total cycle; one unreachable phone or Watch must not block results from other devices. Late results from a previous session must not overwrite the current session.

Expose a USB/Wi-Fi mobile-device battery option distinct from nearby BLE scanning. Explain that the user must connect the iPhone by cable once and select Trust; wireless discovery also requires the phone to be reachable through its existing Wi-Fi pairing configuration. Do not silently enable Finder Wi-Fi sync or initiate pairing. Watch data is supplied by the iPhone, so the row must not claim that the Watch is connected directly to the Mac.

Retain the last successful snapshot with its observation time through temporary failures using the existing 30-minute nearby-result lifetime. Expire it afterward; never present an old reading as newly fetched. Store no pairing credentials in Status Trio and omit device identifiers from routine logs. Localize new user-facing strings in all 12 shipped languages.

## Scope

Include trusted iPhone USB/network discovery, iPhone battery and paired Watch battery, display integration, settings/help, dependency packaging, and verification. Exclude Apple Pencil, Nearcast, a phone/watch companion app, Find My data extraction, menu-bar icon options, and changes to system pairing configuration.

## Verification and acceptance

Cover helper response validation, multiple Watches, absent/unsupported keys, zero and full battery, malformed values, transport deduplication, same-name devices, source precedence, timeouts, cancellation, session generations, and snapshot expiry. Check that BLE phone readings continue to work without the helper and that an unavailable phone produces no invented Watch reading.

Build and package the helper reproducibly for supported Mac architectures, validate app signing and library paths, and confirm a packaged app runs without developer Homebrew libraries. Run `swift test` and `swift build -c release`. Run the non-publishing release workflow with explicit version/build inputs for the actor-isolation and UI integration changes. CI uses macos-26, Xcode 26.6, Swift 6.3.3; build with macOS SDK 26 or newer and retain platform-version checks. Record any failed workflow in `docs/swift-ci-compatibility.md`.

Hardware acceptance requires a trusted iPhone and paired Apple Watch: verify USB first, then Wi-Fi after disconnecting the cable, compare against the Watch's displayed battery, and test an unreachable Watch/phone and reopening the panel. Unit tests and a successful build cannot establish real-device compatibility. No release is part of this change until that evidence and release preflight are available.

## Next stage

Review this specification before producing the implementation plan. Implement the approved written plan using `gpt-6-luna`, following the user's standing model preference.
