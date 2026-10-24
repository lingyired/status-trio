# Dual-distribution development and acceptance

This runbook covers local development and internal diagnostics. Publication,
certificate provisioning, App Store Connect upload, review submission and
merging are separate maintainer actions. Use the final verification report for
observed results; the commands below are procedures, not evidence of a pass.

## Reproduce a candidate

Run from a clean checkout of the candidate commit with Xcode, macOS SDK 26 or
newer, and the pinned XcodeGen 2.46.0. Keep the original `Support/Info.plist`
version unless an explicit distribution version has been chosen.

```bash
git rev-parse HEAD
bash scripts/verify-local.sh full
bash scripts/verify-local.sh docs
APP_STORE_UNSIGNED=1 bash scripts/build-app-store.sh release no-open
bash scripts/build-app-store.sh release no-open
APP_STORE_UNSIGNED=1 APP_STORE_ARCHIVE_PATH=.build/app-store/StatusTrio.xcarchive \
  bash scripts/build-app-store.sh release no-open
```

The unsigned build proves compilation and static contracts. The default Store
build signs locally with an ad-hoc identity and sandbox entitlements; inspect
its audit results separately. Neither command proves App Sandbox runtime,
Apple Distribution signing, upload eligibility or review acceptance.

The build writes `.build/app-store/source-membership.json` and compares the
expected safe sources with the actual Xcode Swift file lists. It recursively
audits the built bundle. Do not replace those checks with a manually generated
project, a runtime channel flag or a top-level `strings` scan.

For Direct interactive development, use the existing independent development
identity:

```bash
bash scripts/build-worktree.sh release no-open
```

The Store output is `dist/AppStore/StatusTrio.app`; Direct uses its existing
output path. Copy the Store app with a distinct installation name, such as
`Status Trio (App Store).app`, when placing both channels in the same
Applications directory. Distinct bundle identities do not prevent Finder
from replacing two files with the same name. Keep development builds outside
the installed production app.

## PR and internal archive checks

The PR workflow checks the same frozen merge SHA in these two jobs:

| Job | Required evidence |
| --- | --- |
| `Direct channel / frozen merge SHA` | Full local verification and existing Direct native/release contracts |
| `App Store channel / frozen merge SHA` | Offline negative fixtures, unsigned Store build, actual source closure and recursive bundle audit |

Both jobs are read-only, have no release credentials or protected distribution
Environment, and run for every PR path. The repository does not automatically
change branch protection. A maintainer can select these job names as required
checks after the workflow has run on GitHub.

`app-store.yml` is a separate manual workflow requiring a lowercase
40-character candidate SHA and explicit numeric version/build. Its candidate
must be an ancestor of `origin/main`. It produces an unsigned internal archive
and diagnostic artifacts. It does not export, upload, acquire credentials or
submit for review. Before a future Store upload, independently check App Store
Connect's current build number; a GitHub run number is not a cross-channel
version sequence.

The existing Direct manual release workflow remains the only release entry
point. PR validation and Store archive diagnostics do not replace its frozen
artifact, signing, notarization and publication contracts.

## Runtime acceptance record

For each observation record:

```text
source SHA | clean/dirty tree | channel | version/build | signing
OS | hardware | entitlements | permission before/after
steps | observed result | PASS/FAIL/BLOCKED/NOT RUN | evidence path
```

Run Ventura and the current macOS as separate rows. For each permission-bearing
feature test allowed, denied and revoked states; also test device absence,
disconnect, sleep/wake, cancellation and relaunch. A public SDK declaration or
an entitlement is not a runtime pass.

| Surface | Acceptance procedure |
| --- | --- |
| Basic independent use | Launch Store alone; inspect battery, network, input/output audio, settings, Menu Bar and Dock; verify unavailable controls have an explanation and cannot invoke Direct code |
| Wi-Fi and network | Check status, signal, SSID/location, scanning, known-network enrichment, power change, Ethernet, VPN and local IP independently; record each restriction rather than deleting the public capability |
| Bluetooth and audio | Check paired enumeration, public connect/disconnect, BLE battery, accessory battery and Huawei RFCOMM independently; Apple private HAL/radio controls and private DDC remain excluded |
| Coexistence | Launch distinct installed channels concurrently; verify defaults, locks, onboarding and TCC domains; test each Login Item separately without changing the other channel |
| Product and lifecycle | Inspect About/system-managed updates, compact windows, denied/unknown states, idle demand stopping, device removal and Menu Bar/Dock parity |

Do not request permissions merely to mark a test complete. Record a missing
device, certificate or OS as `BLOCKED` or `NOT RUN` with its specific cause.
The existing global volume-feedback and icon-appearance preference reads also
require the policy review recorded in `distribution-privacy.md`.

## Recovery and review order

Review foundation, platform boundaries, Store engineering/CI, public providers,
then product changes in dependency order. Keep each phase's verification and
review report with its commit; retest the integrated tree after any correction.
If `main` advances, fetch it, inspect overlapping files, preserve both meanings
and rerun the affected checks.

A rollback removes the affected development commit or PR in dependency order.
It must not alter installed production settings, Secrets, published appcasts,
release artifacts or another agent's worktree. No development phase authorizes
an automatic merge or publication.
