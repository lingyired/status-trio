# Status Trio: AirPods 5 Identification and Apple Bluetooth Audio Resolution

## Summary

Implement the authorized AirPods 5 recognition and Apple Bluetooth audio resolver plan. Keep model detection centralized, preserve hardware-over-name precedence, refresh persisted Bluetooth icon overrides from the selected device, and emit deduplicated debug diagnostics for unknown Apple audio identities. Do not publish a release.

## Implementation Changes

1. Audit each proposed Product ID against Apple system metadata and at least one independent implementation. Add only IDs with corroborated family attribution; record unconfirmed mappings and block the renamed-AirPods-5 hardware acceptance claim if neither AirPods 5 ID is confirmed.
2. Add `.airPodsGen5` and a single `AppleBluetoothAudioResolver` entry point for Product ID/vendor ID, CoreAudio model UID, and name parsing. Route Bluetooth and CoreAudio identity through it. Preserve non-Apple vendor rejection, existing nil-vendor behavior, transport rules, and non-AirPods families.
3. Add the gen5 symbol candidate chain `airpods.gen5 → airpods.gen4 → airpods → headphones`, with an injectable availability check for tests and AppKit as the production default.
4. Add an `AppEnvironment`-owned synchronizer that observes existing device-list and selected-address updates, refreshes the saved Bluetooth symbol only when a valid matching device exists, retains the prior value during failures or temporary absence, and clears the override in audio-device mode. Keep menu bar and Dock paths in parity.
5. Add structured unknown Apple Bluetooth audio records for eligible Bluetooth parser and existing CoreAudio data, debug-log with private identifying strings, and deduplicate per monitor instance with a 128-entry FIFO cap.

## Tests and Acceptance

- Cover corroborated Product IDs, model UID parsing, name fallback, renamed-device hardware precedence, non-Apple vendor rejection, transport behavior, runtime symbol fallback, profiler metadata, icon synchronization under startup/list/error/missing-device conditions, menu bar/Dock propagation, diagnostics filtering, privacy-relevant fields, deduplication, and FIFO eviction.
- Replace unknown `0x201F` fixtures if and only if that ID becomes a confirmed mapping; use `0x2042` for unknown-ID coverage.
- Run `swift test`, `swift build -c release`, `bash scripts/check-forbidden-patterns.sh`, and the release workflow with `publish=false` on the specified CI toolchain. Record every failed workflow run in `docs/swift-ci-compatibility.md`.

## Assumptions and Defaults

- No system metadata catalog protocol or runtime system-file lookup is introduced in this change.
- Unknown or unsupported IDs retain conservative existing name/type fallback.
- The latest published release is v1.3.3 (build 16), and `Support/Info.plist` is also at 1.3.3 (build 16). The non-publishing preflight inputs are version `1.3.4`, build `17`. No release is created.

## Product ID Audit

The top-level `CoreTypes.bundle/Contents/Info.plist` is an incomplete source on macOS 27.0.1. Its nested `Contents/Library/CoreTypes-NNNN.bundle/Contents/Info.plist` files contain the accessory mappings. The system metadata uses `public.bluetooth-vendor-product-id` tags in `vendorDecimal:productDecimal` form; vendor 76 is `0x004C`.

| Product ID | Apple CoreTypes family and metadata | Product tag (`vendor:product`, decimal) | Status Trio family |
| --- | --- | --- | --- |
| `0x201C` | `com.apple.airpods-gen4`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0019.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8220` | `.airPodsGen4` |
| `0x201E` | `com.apple.airpods-gen4`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0019.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8222` | `.airPodsGen4` |
| `0x2020` | `com.apple.airpods-gen4`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0019.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8224` | `.airPodsGen4` |
| `0x201F` | `com.apple.airpods-max-2024`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0019.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8223` | `.airPodsMax` |
| `0x2024` | `com.apple.airpods-pro-gen2-2023`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0012.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8228` | `.airPodsPro` |
| `0x202D` | `com.apple.airpods-max-2`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0038.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8237` | `.airPodsMax` |
| `0x2030` | `com.apple.airpods-gen5`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0041.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8240` | `.airPodsGen5` |
| `0x2036` | `com.apple.airpods-gen5`; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-0041.bundle/Contents/Info.plist`; UTI `public.bluetooth-vendor-product-id` | `76:8246` | `.airPodsGen5` |

The CoreTypes data has no corresponding new AirPods records in the top-level `/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist`; the nested bundle plists above supplied the mappings.

Independent implementation cross-check: [AppleAudioProducts.swift at commit `c5ede4933199b2ccd93f8e0beb481659a8ecf9f9`](https://github.com/raulgg/airpods-control/blob/c5ede4933199b2ccd93f8e0beb481659a8ecf9f9/Sources/AirPodsControl/AppleAudioProducts.swift#L21-L50) contains the same product families, including AirPods 5 at decimal IDs 8240 and 8246. Its [PR #136 test matrix](https://github.com/raulgg/airpods-control/pull/136) retains both IDs as AirPods 5 after removing redundant name pins.

`system_profiler SPBluetoothDataType -json` returned six device records on this Mac; the numeric vendor/product pairs contained no `0x2030` or `0x2036`, so there is no local connected-device capture for AirPods 5. No device name or address was recorded during this check. The local OS accessory mapping and independent implementation agree, so both AirPods 5 IDs meet the static-table evidence gate.
