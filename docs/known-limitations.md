# Known limitations

Status Trio is a status app, not a system control panel. A few boundaries are worth
stating plainly, so the popover does what users expect and the same questions do not
have to be answered one issue at a time.

## Switching networks happens in System Settings

The Wi-Fi page shows the network you are on, the nearby networks macOS knows about,
and the link details of the current connection. It does not join or switch networks:
choosing any network other than the current one opens the Wi-Fi pane of System
Settings, and Status Trio never reads or stores Wi-Fi passwords.

That is a deliberate boundary rather than a missing feature. macOS keeps a saved
network's password in the system keychain and exposes no public API that connects
with a saved profile: `CWInterface.associate(to:password:)` needs the password
itself, and `associate(password: nil)` is not credential reuse. An app that wants to
switch between saved networks therefore has two options, and this project takes
neither:

- **read the keychain**, by enumerating every saved Wi-Fi password or by asking for
  one network at a time. Enumerating puts every password in the app. Asking one at a
  time shows a system authorization prompt during an ordinary popover click, and a
  stored password that has gone stale turns into a loop of prompts, because CoreWLAN
  reports authentication failures without a stable error taxonomy — the app cannot
  even tell the user that the password is wrong.
- **store its own copy** of the passwords the user types. Such a copy goes stale as
  soon as the password is changed anywhere else, and macOS saves the network itself
  anyway, so the app ends up holding a second, older copy of a secret the system
  already has.

Switching Wi-Fi is also something macOS already does well: it auto-joins the networks
you saved, and its own menu and pane switch between them. The popover therefore stays
a status surface and hands this one job back to the system.

### Leftover items from older versions

Earlier versions could join a network from the popover and, if you ticked
**Remember password**, stored that password in the keychain under Status Trio's own
item (`com.lingsmbp.StatusTrio.wifi-password`, keyed by security kind and SSID).

Current versions neither read nor write those items. They are left in place on
purpose, so a future version that reintroduces switching could reuse them instead of
asking for every password again. To remove one yourself, open Keychain Access, search
for `com.lingsmbp.StatusTrio.wifi-password`, and delete the item.

## Internet Sharing is toggled in System Settings

When a wired link is active, the wired details page offers **Share Internet…**, which
opens the Sharing pane. It does not turn Internet Sharing on or off itself.

That is a deliberate boundary. Enabling Internet Sharing means writing the system's
network configuration — `com.apple.nat.plist` under
`/Library/Preferences/SystemConfiguration` — and starting the `InternetSharing`
daemon. Neither is a public API: the plist's own man page calls it "a contract
between the Sharing preferences pane and InternetSharing" and warns its details
"are subject to change and are not completely documented". Driving it from the app
would be a version-sensitive write to a root-owned file that the system can change
underneath it, so the popover hands this one job back to the pane that owns it.

## Charge-limit controls depend on the app version and macOS

The current public GitHub and Homebrew release, **1.7.5**, leaves charge-limit
overrides to macOS. When charging is paused, it reports the actual state and the
battery row's gear button opens System Settings.

The source on `main` adds a **Charge to Full Now** button for supported Apple
silicon Macs running macOS 26.4 or later. It is enabled by default only when the
capability is available and can be turned off in Battery settings. It uses the
same private PowerUI request observed behind the native action. There is no
public API or cross-version guarantee for this operation. Unsupported systems
do not offer the action.

**The charge limit may remain at 100% after charging completes or the adapter is
unplugged and reconnected. Status Trio does not restore it automatically.**
The implementation saves an operation session and offers **Cancel Charge to
Full** to request restoration. An ambiguous or restored session can require
another explicit confirmation. A failed request is not proof of restoration:
check the charge limit in System Settings and restore it there if needed.
See [implementation, observed native behavior, and verification
limits](charge-to-full-now-poc.md).

Battery telemetry continues to use read-only SMC commands; the PowerUI action
does not add SMC writes or a background charge watcher. Low Power Mode uses a
separate opt-in privileged helper, which does not control the charge limit;
see [privileged helper](privileged-helper.md).

## One Bluetooth battery source is undocumented

Bluetooth battery levels come from `system_profiler -json SPBluetoothDataType`, a
documented report. A connected device that report carries no level for is also
looked up in the accessory power sources — the data macOS draws its own accessory
battery display from — and their only command-line form is `pmset -g accps`. That
subcommand is undocumented: it appears nowhere in `man pmset`, and only
`-g accps -xml` produces the structured form the app needs, because the text form
prints an accessory it cannot resolve without a name.

The dependency is written so that losing it costs coverage and nothing else. A read
that fails reports no accessory rather than an error, the report stays the only
source, and nothing on screen changes. The public API cannot reach these numbers at
all: `IOPSCopyPowerSourcesInfo()` returns the internal battery alone, and the
private `IOPSCopyPowerSourcesByType(kIOPSSourceForAccessories)` that does return
them is deliberately not linked, so no private symbol and no entitlement is
involved. AirPods part levels do reach the app — including their left and right
buds — because macOS obtains them over its own private accessory protocol and
writes the result into that documented report; the app reads the outcome, not the
protocol.

The accessory battery notifications the levels refresh on are `notify(3)` keys
(`com.apple.system.accpowersources.*`). Registering for a notification key is the
public half of the mechanism; the key names belong to `powerd`, and a key that goes
away only means those notifications stop arriving, which leaves the safety-net poll
as the only trigger, exactly as before.

## Telemetry cannot identify uninstalls

When anonymous usage statistics are enabled, the app sends a small heartbeat
through the first-party service. Turning statistics off stops future heartbeats,
but does not delete data already received. The service also cannot distinguish
an uninstalled app from one that is still installed with telemetry disabled or
that has not been used recently. See [telemetry and privacy](privacy-telemetry.md)
for the fields, consent choices, and retention details.

## Status colours cannot track a Space mid-drag

While a Space switch is being dragged, the menu bar's own appearance — which
`NSStatusBarButton.effectiveAppearance` reports — does not change until the
switch commits, and macOS exposes no other signal for the Space being dragged
toward. Only template images follow the switch live, because the system re-tints
them itself; a self-drawn bitmap keeps the outgoing Space's colours for the whole
drag and only catches up on release.

The menu bar icon is therefore drawn in two layers. The monochrome chrome — the
battery ring's unfilled track, the connection glyph, the bolt, plug, or
percentage in the ring's top gap, and the volume dots or arc base — goes to the
system as a template image, so it re-tints live for the target Space, exactly
like the built-in menu bar icons. The primitives that carry a status colour (the
battery ring's progress arc, the active volume dots or arc fill, and the whole
ring while the charging effect animates) are drawn in a custom raster above it
and cannot follow.

So an icon that is monochrome throughout — the usual unplugged case, or any
configuration with status colours turned off — tracks a dragged Space perfectly,
while an icon showing `critical`, `lowPower`, `powered`, or `bluetooth` re-tints
everything except those coloured primitives and settles on the correct colour
when the switch completes. This is a menu-bar-only behaviour: the Dock icon is a
single full-colour render and is unaffected. See
[issue #112](https://github.com/lingyired/status-trio/issues/112).

## Status colours on an unfocused display

On multiple displays, macOS dims the menu bar of the display that does not have
the focused app. Attaching a coloured CALayer directly to a status button whose
image is a template can make that coloured content noticeably brighter.

For coloured scenes, the button now holds a transparent non-template footprint.
The monochrome primitives remain a template in an independent, non-interactive
image view, and the existing coloured CALayer stays above them. Entirely
monochrome scenes retain the direct template button image. Scene colours, the
animation timeline, and the Dock renderer are unchanged.

The maintainer tested this separate-template arrangement in a standalone probe
on two real displays and reported both inactive-display appearance and #112
Space-drag tinting working. This does not establish acceptance for every macOS
version or for the complete application's animation and lifecycle. See the
[integration and verification scope](verification/issue-165-template-image-view.md).
The [earlier experiments](verification/inactive-display-icon-dimming.md) describe
the rejected full-raster and template-button arrangements.
