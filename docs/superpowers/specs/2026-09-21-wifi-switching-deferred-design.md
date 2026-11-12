# Wi-Fi switching from the popover — deferred design

> **Superseded (2026-11-12):** in-app joining of open and personal networks was
> reintroduced with a plain-text password file at `~/.status-trio/wifi-passwords.json`
> instead of the keychain design below. See `docs/known-limitations.md`. The measurements
> and constraints here remain as history.

Status: **deferred** on 2026-09-21, not implemented. The feature that shipped up to
1.2.0 — joining a network from the popover, optionally remembering its password — was
removed in the same change; choosing a network now opens the Wi-Fi pane of System
Settings, and the app never reads or stores Wi-Fi passwords. This document records
what was measured, what the replacement design would be, and what would have to be
true before it is worth building, so the question is not re-litigated from zero.

## Why it was removed

macOS keeps a saved network's password in the system keychain and exposes no public
API that connects with a saved profile: `CWInterface.associate(to:password:)` needs
the password itself, and `associate(password: nil)` is not credential reuse. An app
that wants to switch between saved networks therefore has to either read the keychain
or keep its own copy, and neither is acceptable here.

The old flow also contradicted itself. CoreWLAN's `associate(to:password:)` makes
macOS save its own profile for the network, so a network joined from the popover
became a system-known network; the next click on that row took the
`isKnown → openSettings` branch and sent the user to System Settings. On top of that,
a stored password that had gone stale produced a loop: a click read the system
`AirPort network password` item, macOS raised an authorization prompt, the stale
password failed to associate, CoreWLAN reported a generic failure with no way to tell
the user the password was wrong, and clicking again repeated the prompt.

## What was measured

Probe on 2026-09-21, macOS 27.0 (26A428), Swift 6.4, with two ad-hoc signed app
bundles that share a bundle identifier, differ in source (so their cdhashes differ),
and use the app's own item attributes (generic password, own service, security kind +
SSID as the account, no explicit access object):

1. An ad-hoc signature's designated requirement is its cdhash
   (`codesign -d -r-` → `cdhash H"…"`, `TeamIdentifier not set`), and it changes on
   every build.
2. That does not break the item's ACL: the second build read the first build's
   password silently (`errSecSuccess`, no prompt). The discriminator is the bundle
   identifier, not the cdhash.
3. A bundle with a *different* identifier could not read the data (`errSecUserCanceled`
   while authentication UI was disabled), but could still read the item's attributes —
   service, account, and dates. Passwords are protected; "which SSIDs this app stores"
   is not.
4. `kSecUseDataProtectionKeychain` is unavailable here: `errSecMissingEntitlement`
   (-34018) without an entitlement or provisioning profile.

Measured in the app itself by the maintainer on the same day: joining a network from
the popover also makes macOS store that network and its password, so the system can
join it later on its own.

Not measured: whether `SecItemUpdate` from a new build (the "re-enter the password"
path) needs authorization. The read path does not, so it is unlikely, but the probe
was not run because a failed guess could raise a real authorization dialog.

## The design that was deferred

Model: **the app owns a credential library, and its contents are "networks the user
has successfully connected to through Status Trio".** macOS's copy is a side effect of
the association, never the authority; the app's copy is a cache.

- **Opt-in.** One switch under Settings › Network, off by default, whose disclosure
  states the boundary before the user turns it on: one password entry per network the
  first time, macOS-saved passwords are not read, passwords live in the user's
  keychain and can be deleted again.
- **Status is decided by our own items.** "Known" means the app holds a credential
  for that network (or it is the current connection). This is the part the old design
  got wrong, because it used macOS's preferred-network list.
- **One click, one prompt.** Clicking a network with no credential asks for the
  password in the popover, associates through the public CoreWLAN API, and stores the
  password in the app's own keychain item on success.
- **No system keychain reads at all**, so no authorization prompt can appear during an
  ordinary click.
- **Healing path.** A failed association offers *Re-enter password* and *Forget this
  network* (`SecItemDelete` on our own item — which also gives the app the delete
  affordance it never had). Wording says the password "may have changed" rather than
  asserting it is wrong, because CoreWLAN exposes no stable error taxonomy for
  authentication failures.
- **Enable/disable.** Turning the switch off should offer to delete the stored
  passwords, keeping "the app does not keep Wi-Fi passwords" true when the feature is
  off.

Roughly the code that would come back: a credential store and its protocol
(`WiFiPasswordStore.swift`, deleted), the credential/association states on
`WiFiListState`, the credential worker and association methods on
`WiFiNetworkController`, the password sheet and per-row actions in
`WiFiNetworkListView`, and 16 localization keys plus one hint key per `.lproj`.

## Constraints any future implementation must respect

1. **The bundle identifier must stay `com.lingsmbp.StatusTrio`.** Renaming it makes
   every stored password unreadable (measurement 2). Worth a line in the release
   check-list if this ever ships.
2. **Enabling switching makes Location authorization a hard requirement.** Without it
   SSIDs are empty, so the network list is empty and there is nothing to click. Today
   location is optional and only used for the network name, and both the switch's
   description and the privacy paragraph in every README would have to say so.
3. **Auto-storing every successful join also stores public and guest networks.** Decide
   whether the password sheet keeps a default-checked "remember this network" box.
4. **Leftover items are intentional.** Versions up to 1.2.0 left items under
   `com.lingsmbp.StatusTrio.wifi-password`; current versions never touch them, and a
   future version could reuse them instead of asking for every password again.
5. **Re-run the probe on the CI toolchain** (macOS 26, Swift 6.3.3) before relying on
   measurements 1–4; they were taken on macOS 27.

## Why deferred

The maintainer does not need it: macOS auto-joins saved networks, and switching is
rare. The users who asked for it want to switch between networks *macOS* already
saved, which this design cannot do without reading the system keychain one network at
a time — so the design serves only networks the user re-enters once, and the old
networks still open System Settings.

Revisit when the demand is larger. Note that a Developer ID is **not** a prerequisite:
measurement 2 shows the app's own keychain items survive updates under an ad-hoc
signature. A Developer ID would change notarization and the first-install Gatekeeper
step, which is a separate question.

## What a future change must also do

- Update the 12 `*.lproj` files, the 10 READMEs and `docs/known-limitations.md`
  together: their current text states the opposite policy.
- Add release notes in every shipped language for the version that reintroduces it.
