# Status Trio for Mac App Store

Status: pre-release product draft, 2026-10-24. This is not a published App
Store listing, not an Apple review result, and not evidence that any listed
capability works in a sandboxed build.

## Product positioning

Status Trio keeps essential Mac status controls in the menu bar. The Store
candidate shares the menu-bar and Dock scene, status model, settings structure,
and twelve shipped languages with the GitHub distribution. Its intended core
value is:

- one compact menu-bar view for battery, network, Bluetooth, audio, and input
  status;
- optional Dock presence rendered from the same scene source as the menu bar;
- public-API battery, Wi-Fi/network, Bluetooth, CoreAudio, and input-source
  candidates where sandbox and permission tests prove them;
- independently stored settings and permissions for each distribution; and
- updates delivered by the Mac App Store rather than Sparkle; and
- no Store telemetry while the candidate remains outside the Direct telemetry
  allowlist.

The Store build must remain useful when a capability is unavailable. It must
not substitute a private Direct implementation, request broader access to make
a row appear complete, or describe an unverified control as supported.

## Distribution copy

The in-app channel explanation uses these seven localized keys:

| Key | Product meaning |
| --- | --- |
| `settings.distribution.title` | Distribution |
| `settings.distribution.description` | Status Trio is an open-source macOS utility; system control availability may vary by distribution channel and macOS permissions |
| `settings.distribution.project` | Open-source project and release notes |
| `settings.distribution.independentSettings` | Each distribution keeps its own settings and permissions |
| `settings.updates.systemManaged` | Updates are managed by the Mac App Store |
| `capability.unavailableDistribution` | The control is unavailable in this distribution |
| `capability.notVerified` | Availability on this Mac has not been verified |

The copy deliberately avoids a download, upgrade, full-version, subscription,
or external-purchase call to action. It does not claim that the Store candidate
has been published or approved.

## Product page draft

> **Status Trio**
>
> Your Mac's essential status, together in one calm menu-bar view.
>
> See battery, network, Bluetooth, audio, and input status without opening
> several system panes. Choose a compact menu-bar presentation, optionally keep
> Status Trio in the Dock, and arrange the controls you use most.
>
> The Mac App Store edition is built with App Sandbox constraints in mind.
> Features that depend on macOS permissions or external hardware may differ
> from the GitHub edition, and each edition keeps its own settings.
>
> Updates are delivered by the Mac App Store.

This draft is not approved marketing copy. It must be reconciled with the final
capability matrix and screenshots before submission.

## Screenshot capture checklist

Capture only after the Store build and sandbox evidence exist. Each screenshot
must come from a known Store candidate SHA and show a capability marked
`available`, with no fabricated rows or placeholder hardware.

- Menu bar with a representative battery and network state.
- Expanded status panel with the public battery/network/audio layout that
  passed Store verification.
- Dock presentation demonstrating the shared scene source.
- Settings showing the distribution explanation and independent-settings copy.
- Permission or unavailable state rendered honestly, without implying that an
  unverified feature is supported.

Screenshots are blocked until those states are verified. They must not expose
personal device names, SSIDs, account data, or a signed/uploadable claim.

## Website copy status

The repository has no deployed Store product-page source for this phase. The
copy above is a draft for review only; it is not published and does not imply
Apple approval or availability.

## Verification status

Store build, App Sandbox runtime behavior, TCC allow/deny/revoke flows, real
Wi-Fi/Bluetooth/audio hardware, coinstallation, update delivery, and App Store
Connect submission are **NOT RUN**. Offline localization and manifest tests do
not prove any of those behaviors.
