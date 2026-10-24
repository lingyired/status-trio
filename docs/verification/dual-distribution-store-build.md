# Dual Distribution Store Build Verification

Date: 2026-10-24

Worktree: `/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio`

Branch: `codex/dual-distribution-platform`

HEAD at final build: `a4c9f34a1c9ade2c1116f02781ea549521eaa370`

The final archive was built after the B/E policy fix. Remaining uncommitted
files are the later phase/documentation payload, so the archive's pre/post
source-tree digest is the authoritative source-content evidence. `source_sha`
records the Git HEAD; it does not hash the working tree by itself.

## Toolchain

- XcodeGen: exact `2.46.0` from the verified pinned asset.
- Xcode: `27.0`, build `27A266a`.
- macOS SDK: `27.0`.
- Deployment target: macOS `13.0`.
- Swift language mode: Swift 6.0 with complete strict concurrency.

## Project Path Root Cause

The first three real builds failed while resolving copied localized resources.
The generated project attached the same `PBXFileReference` to multiple
`PBXGroup`/`PBXVariantGroup` parents: Core included the whole Resources
directory while the app separately included its `InfoPlist.strings` files.
Xcode consequently resolved some resource inputs one directory above the
actual project.

The generator now emits explicit resource file references under one
`SharedStoreResources` group and does not include the Resources directory as a
second source tree. Before `xcodebuild`, it parses the actual generated
`.pbxproj` and fails if any object has multiple or no group parents or if a
resource path does not exist inside the repository.

Project preflight resolved:

- `SRCROOT = PROJECT_DIR = .build/app-store/XcodeProject`
- 40 resource build entries
- 28 unique resource files
- 12 shared app/Core resource files
- no malformed group membership

## Offline Contract

Command:

```bash
XCODEGEN=/Users/lingsmbp/.codex/worktrees/dual-distribution-foundation/status-trio/.build/tools/xcodegen-2.46.0-pin-verification/xcodegen \
bash scripts/test-app-store-project-contract.sh
```

Final result: `74/74 PASS`, exit `0`. The fixture covers missing/escaping source
membership, Direct-file exclusion, version and build overrides, SDK floor,
strict concurrency, forbidden Sparkle/private configuration, real nested
XcodeGen path resolution, malformed duplicate-group rejection, resources, and
the Store Info.plist category `public.app-category.utilities`.

## Final Real Archive

Command:

```bash
APP_STORE_ARCHIVE_PATH=.build/dual-distribution-archives/final-20261024-r2.xcarchive \
bash scripts/build-app-store.sh release no-open
```

Result: exit `0`.

- `** ARCHIVE SUCCEEDED **`
- App and Core dSYM contract passed; both dSYMs are arm64+x86_64 and their
  architecture UUIDs match the binaries.
- 303 compiled sources recorded from two actual archive
  `SwiftFileList` inputs under `ArchiveIntermediates`.
- Source membership: 300 shared, 23 excluded, 3 Store platform.
- Source closure audit passed after the pre/post source digest comparison.
- App and Core report `minos 13.0`, SDK `27.0`, arm64+x86_64.
- Signed static bundle audit passed: 2 Mach-O files, 4 signed code items,
  3 symlinks; App Sandbox entitlement present in the local ad-hoc signature.

Log: the parent command output in this session; the earlier archive logs remain
under `.build/dual-distribution-logs/`.

## Earlier Builds

The following commands were run after platform integration. All exited `0`;
the three builds were not repeated for the later App Category plist-only fix.

- Unsigned Release:
  `APP_STORE_UNSIGNED=1 bash scripts/build-app-store.sh release no-open`
- Default local ad-hoc Release:
  `bash scripts/build-app-store.sh release no-open`
- Unsigned archive:
  `APP_STORE_UNSIGNED=1 APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive bash scripts/build-app-store.sh release no-open`

Logs:

- `.build/dual-distribution-logs/app-store-unsigned-build-20261024T005954.log`
- `.build/dual-distribution-logs/app-store-adhoc-build-20261024T010048.log`
- `.build/dual-distribution-logs/app-store-archive-20261024T010224.log`
- `.build/dual-distribution-logs/app-store-project-path-preflight-20261024T005747.log`
- `.build/dual-distribution-logs/app-store-project-contract-20261024T011111.log`

## Source Closure

- Included sources: 303
- Excluded Direct-only sources: 23
- Compiled sources: 303
- `included_sources == compiled_sources`
- Included/excluded overlap: none
- Generated derived Swift sources: none
- Archive Swift file lists: two actual `StatusTrioCore.SwiftFileList` files,
  each with 303 entries under `ArchiveIntermediates`
- Swift defines: `STATUS_TRIO_APP_STORE`
- Linked frameworks: 23 public frameworks, with no Sparkle, DDCPrivateAPI,
  PowerHelperProtocol, CoreDisplay, or privileged helper dependency

The stable audit output is `.build/app-store/source-membership.json`.
`compiled_sources` comes from the actual Swift file lists, not from the
generator's self-declared membership.

## Archive And Signing

- Archive app: `Products/Applications/StatusTrio.app`
- Embedded framework:
  `Contents/Frameworks/StatusTrioCore.framework`
- No standalone `Products/Library/Frameworks/StatusTrioCore.framework`
- Core `SKIP_INSTALL=YES`; app `SKIP_INSTALL=NO`
- App and Core: Universal `arm64 x86_64`, minimum macOS `13.0`, SDK `27.0`
- App resources: 12 `InfoPlist.strings`, `PrivacyInfo.xcprivacy`, and a valid
  generated ICNS
- Core resources: 12 `InfoPlist.strings`, 12 `Localizable.strings`,
  `GitHubMark.svg`, and `VolumeFeedback.wav`

The ad-hoc build signed the embedded framework first and the app last. Deep
strict verification passed. The app signature had only the checked-in
entitlements: app sandbox, outbound network client, Bluetooth device access,
and personal-information location. The framework signature had no
entitlements.

The archive command copies its unsigned app to `dist/AppStore/StatusTrio.app`
last. The `dist` artifact present after the three-build sequence was therefore
unsigned, despite the standalone ad-hoc build having passed.

## App Category

The generated Store Info.plist sets
`LSApplicationCategoryType=public.app-category.utilities`. The final archive
contains it, and the offline contract asserts the value.

## NOT RUN

- Sandbox runtime behavior
- Bluetooth or location hardware access
- TCC permission presentation or response
- App launch and menu interaction
- App Store export, upload, signing with Apple Distribution, and ASC validation
- Full SwiftPM/full/foundation Swift build (covered by the separate final
  `verify-local full` record, not inferred from this archive)
- Universal package, notarization, DMG, release, or Homebrew flow

Entitlement presence is a static signature contract, not runtime proof.
