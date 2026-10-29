# Status Trio App Store project

This directory is the reproducible, Store-only build boundary. The Direct
SwiftPM architecture remains unchanged.

## Generate and verify

```bash
python3 scripts/generate-app-store-project.py --require-xcodegen
/opt/homebrew/bin/xcodegen generate --spec AppStore/project.json --project .build/app-store/XcodeProject --project-root . --quiet
xcodebuild -project .build/app-store/XcodeProject/StatusTrioAppStore.xcodeproj -list
bash scripts/test-app-store-project-contract.sh
```

The exact project generator pin is XcodeGen `2.46.0`. The version is an exact
match, not a minimum. The CI workflow installs the official `2.46.0` archive
and verifies its published SHA-256 before exposing that binary as `XCODEGEN`.

`scripts/generate-app-store-project.py` reads `AppStore/direct-only-sources.txt`
and enumerates every Swift file under `Sources/StatusTrioCore`. It writes the
effective source membership to the stable path
`.build/app-store/source-membership.json` with this interface:

```json
{
  "schema_version": 2,
  "channel": "appStore",
  "repository_root": "/absolute/path/to/status-trio",
  "included_sources": ["..."],
  "excluded_sources": ["..."],
  "source_sha": "40 lowercase hex characters",
  "linked_frameworks": ["..."],
  "swift_defines": ["STATUS_TRIO_APP_STORE"],
  "compiled_sources": null,
  "derived_sources": [],
  "swift_file_lists": []
}
```

`included_sources` is the full StoreCore target membership: shared Store-safe
sources plus `AppStore/Platform` sources. After xcodebuild, the build script
sets `compiled_sources` from the actual `StatusTrioCore*.SwiftFileList` files
under the build's DerivedData, sets `swift_file_lists` to their repo-relative
paths, and records generated `DerivedSources` separately in
`derived_sources`. CI must require `included_sources == compiled_sources`;
the generator alone leaves `compiled_sources` null. An empty
`derived_sources` array is valid and means the target emitted no generated
Swift sources; the collector never invents a `DerivedSources` entry.

Missing manifests, nonexistent or escaping entries, empty Store platform
membership, stale generated configuration, unknown `.SwiftFileList` entries,
and source-closure mismatches fail closed.

The generated project has two targets:

- `StatusTrioCore`: shared Store-safe sources plus `AppStore/Platform/**/*.swift`
  as one embedded framework target with `PRODUCT_MODULE_NAME=StatusTrioCore`,
  `SKIP_INSTALL=YES`, and `INSTALL_PATH=$(LOCAL_LIBRARY_DIR)/Frameworks`.
- `StatusTrio`: the existing `Sources/StatusTrio/main.swift` entrypoint.
  The app embeds and signs the framework dependency and sets
  `SKIP_INSTALL=NO`.

The Store build does not link the SwiftPM target, Sparkle, DDCPrivateAPI,
PowerHelperProtocol, CoreDisplay, or the privileged helper. There is no
import of a Direct module. `STATUS_TRIO_APP_STORE` records the distribution
identity and is not a source-membership mechanism.

## Resources and provider contract

The generator enumerates every existing file under
`Sources/StatusTrioCore/Resources` and gives those explicit file references
one shared `SharedStoreResources` group. The Core framework carries the
complete shared directory: 12 `InfoPlist.strings`, 12
`Localizable.strings`, `GitHubMark.svg`, and `VolumeFeedback.wav`. The app
target separately compiles the same 12 `InfoPlist.strings` file references
into the main app, so TCC reads purpose strings from the app rather than only
from the framework. The generator fails unless all 12 known locales are
present and rejects unexpected `InfoPlist.strings` files. There is no copy or
case-only rename of either `InfoPlist.strings` or `Localizable.strings`.

The app resource phase has 14 entries: 12 existing `InfoPlist.strings`,
the E-owned `AppStore/PrivacyInfo.xcprivacy`, and the generated
`StatusTrioAppStore.icns`. In the production tree the Core phase has 26
entries, producing 24 concrete `InfoPlist.strings` build files (12 app plus
12 Core) and 40 resource build entries overall. The offline fixture asserts
both real `PBXResourcesBuildPhase` sections and their declared membership.

`AppStore/PrivacyInfo.xcprivacy` is owned by E and must remain in the app
resource phase. C validates that it is readable, sets
`NSPrivacyTracking=false`, collects no declared data, and declares no tracking
domains. The build repeats that check on the copied app bundle before signing.
The correctness and completeness of the E-owned
`NSPrivacyAccessedAPITypes` reason codes are not validated by C.

The platform task must provide this generated-source accessor at
`AppStore/Platform/StoreResourceBundle.swift`:

XcodeGen resources are declared in each target's `sources` array with
`buildPhase: resources`; a target-level `resources` key is not used because
XcodeGen ignores it. The first real build exposed a malformed project:
including the whole Resources directory in Core while separately including
its `InfoPlist.strings` files in App attached the same `PBXFileReference`
objects to multiple `PBXGroup`/`PBXVariantGroup` parents. `xcodebuild` warns
that the project is malformed and can resolve those inputs one directory
above `SRCROOT`. The generator now uses explicit resource file references, a
shared group, and no intermediate-group expansion. Before `xcodebuild`, the
build parses the generated `.pbxproj`, rejects any object with more than one
group parent, resolves every resource `PBXFileReference` from the real
project directory, and requires that each resolved path exists inside the
repository. The offline contract runs the same validator against a nested
real XcodeGen project and a deliberately malformed duplicate-group fixture.

```swift
import Foundation

extension Bundle {
    static var module: Bundle {
        // Return the Store resource bundle using an actual bundle URL/path.
    }
}
```

The accessor must expose the same call surface used by existing code:
`Bundle.module.url(forResource:withExtension:)`,
`Bundle.module.path(forResource:ofType:)`, and localized `.lproj` lookup.
Keep the actual accessor implementation in the Store platform source; this
project only guarantees that the file is a mandatory member.

The concrete public Bluetooth readers already available from D are:

- `PublicBluetoothPairedDeviceReader: BluetoothPairedDeviceReading` uses the
  public `IOBluetoothDevice.pairedDevices()` and host-controller power-state
  APIs. It publishes device identity, class, and connection state only; public
  IOBluetooth does not supply the Direct path's per-device battery values.
- `PublicAccessoryBatteryReader: BluetoothAccessoryBatteryReading` uses the
  public IOPS power-source APIs, excludes internal and UPS sources, and leaves
  `part == nil` because public IOPS has no accessory-part identifier.

The sandbox entitlements cover these public IOBluetooth/CoreBluetooth and
CoreLocation calls. Entitlement presence is a static capability contract, not
proof that hardware access or sandbox behavior works at runtime. Store
providers must also expose the shared protocol boundaries for update service,
privileged-helper-free low-power capability, audio/DDC-safe volume, Bluetooth
radio/listening status, battery details, Wi-Fi/network, input source, login
item, and mobile-battery capability. A provider that is not implemented must
report the existing `CapabilityAvailability` state rather than substitute a
Direct implementation or a hidden UI flag.

## Build contract

```bash
bash scripts/build-app-store.sh debug no-open
bash scripts/build-app-store.sh release no-open
APP_STORE_UNSIGNED=1 bash scripts/build-app-store.sh release no-open
APP_STORE_SIGNING_IDENTITY=- bash scripts/build-app-store.sh release no-open
APP_STORE_UNSIGNED=1 APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \
    bash scripts/build-app-store.sh release no-open
```

The output is always `dist/AppStore/StatusTrio.app`, never
`dist/StatusTrio.app`. Archives use only the explicit
`APP_STORE_ARCHIVE_PATH`; the default archive path is unset, and neither path
collides with the Direct build. The archive path is canonicalized with
`Path.resolve(strict=False)`, must remain under the canonical repository root,
must not equal that root, must not contain `..`, and cannot overlap the Store
DerivedData, generated project, or `dist/` outputs. Symlink and parent escapes
are rejected before any archive write.
The default signing path is local ad-hoc (`-`)
and verifies the sandbox entitlement. Embedded `.framework` bundles are signed
first, then the app is signed with entitlements; entitlements are never copied
to the framework. The checked-in template grants only sandbox, outbound network
client, Bluetooth device access, and personal-information location; it adds no
USB, network-server, or temporary-exception entitlement. These are the
minimum public capabilities used by the Store Bluetooth/IOBluetooth and
CoreLocation provider paths. `APP_STORE_UNSIGNED=1` is an explicit
compile/static mode and does not claim a signature, Developer ID, Apple
Distribution, notarization, or a sandbox runtime pass.

The build requires and always executes
`scripts/verify-app-store-bundle.sh`; execute permission is not required
because it runs through `bash`. A missing or unreadable verifier is a hard
failure. The icon is generated from the existing `Support/AppIcon.png` using
the same ten iconset sizes as the Direct build into
`.build/app-store/generated/StatusTrioAppStore.icns`. That generated file is
the app resource; the build validates the bundle copy before framework/app
signing. The build also requires all 12
localized app `InfoPlist.strings` files and validates their three public
purpose keys before signing. No new artwork or translations are introduced.

When `APP_STORE_ARCHIVE_PATH` is non-empty, the same scheme is archived at that
path and the app under `Products/Applications` is copied to
`dist/AppStore/StatusTrio.app`; no export, upload, installation, login, TCC
request, or automatic launch occurs. The default open mode is `no-open`.

The script checks macOS 13 deployment and macOS SDK 26 or newer before
compiling; it does not add flags that weaken Swift 6 strict concurrency.

## Version source

`AppStore/Info.plist` and `AppStore/Version.xcconfig` are generated from
`Support/Info.plist`. Generated versions match the Direct source by default.
`APP_VERSION` and `BUILD_NUMBER` are explicit numeric overrides and must
increase when used for an actual distribution. This project does not bump
either value.

## Build evidence

The integrated tree was built on 2026-10-24 with exact XcodeGen `2.46.0`,
Xcode 27.0 (SDK 27.0). The offline project contract passed `66/66`; unsigned
Release, default ad-hoc Release, and unsigned archive all exited `0`. Logs are
under `.build/dual-distribution-logs/`:

- `app-store-unsigned-build-20261024T005954.log`
- `app-store-adhoc-build-20261024T010048.log`
- `app-store-archive-20261024T010224.log`
- `app-store-project-contract-20261024T011111.log`

The archive has `Products/Applications/StatusTrio.app` and embeds
`Contents/Frameworks/StatusTrioCore.framework`. It has no standalone
`Products/Library/Frameworks/StatusTrioCore.framework`. Core has
`SKIP_INSTALL=YES`; the app has `SKIP_INSTALL=NO`.

The archive run recorded 303 compiled sources from two actual
`StatusTrioCore.SwiftFileList` files, each containing 303 entries. Both lists
equal `included_sources`; `excluded_sources` contains 23 entries, the sets do
not overlap, and `derived_sources` is `[]`. The app and Core binaries are
Universal `arm64 x86_64` with minimum macOS `13.0` and SDK `27.0`.

The ad-hoc build passed deep strict codesign verification. The app carried only
the four checked-in sandbox entitlements, while the framework signature had no
entitlements. The archive run copies its unsigned app to
`dist/AppStore/StatusTrio.app` last, so the current `dist` artifact is unsigned;
rerun the default signing command when a signed Store artifact is required.

`AppStore/Platform/**/*.swift` and `AppStore/direct-only-sources.txt` remain
owned by the platform isolation task. Offline tests use synthetic fixtures;
production generation fails closed if an integrated input is missing.

Sandbox runtime, Bluetooth/location hardware access, TCC, and app launch remain
`NOT RUN`. Entitlement presence is not runtime proof. The generated Store plist
sets `LSApplicationCategoryType=public.app-category.utilities`, and an offline
fixture asserts it. The parent final build must confirm that the previous
non-fatal App Category archive warning is absent; no App Store Connect metadata
claim is made here.

No generated project spec, `AppStore/Info.plist`, `AppStore/Version.xcconfig`,
icon, DerivedData, or membership file is checked in. `AppStore/.gitignore`
covers the three generated files directly under that directory; all other
generated outputs live under `.build/app-store`. They are recreated from the
reviewed generator inputs.

Scope note: Gibbs owns the source-closure implementation and fix rounds, with
Helmholtz performing the independent review chain. C's 85-case run was an
intermediate offline observation, not final evidence; only Gibbs' frozen
report and the scoped review establish the source-closure result.
