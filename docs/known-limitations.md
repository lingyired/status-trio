# Known limitations

Status Trio is a status app, not a system control panel. Two boundaries are worth
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

## "Charge to Full Now" stays in macOS

When optimized battery charging or a charge limit pauses charging, Status Trio
reports the state as it is: the icon shows the connected-to-power state, the Battery
Details page omits the charging row because no power is flowing into the battery, and
the battery row's gear button opens the Battery pane. The popover deliberately has
no "charge to full" button.

There is no public API to charge past the limit macOS is holding. An app can only do
it through the SMC with the firmware's charge-control keys — the approach third-party
charge limiters take — or through an undocumented PowerUI charging interface. Status
Trio reads the SMC for the system power estimate only, sends read-key-info and
read-bytes commands only, and ships no privileged helper (see [battery
details](battery-details.md)), so charge control stays where Apple put it: System
Settings › Battery, and the battery section of Control Center where macOS offers its
own charge-to-full action.

macOS 26.4 and later add a native charge limit from 80% through 100% on Apple
silicon Macs, with its own charge-to-full action, so on those versions the limit and
the override live in the same system place, and this app duplicates neither.

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
