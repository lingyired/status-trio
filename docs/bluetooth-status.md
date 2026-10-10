# Bluetooth popover summary

The popover's Bluetooth row reports live device state instead of a generic
prompt. What it shows is derived by `BluetoothSummary.presentation(availability:
devices:batteryLevels:)`, so the text is testable without rendering SwiftUI:

| Availability | Row |
| --- | --- |
| `authorizationNotDetermined` | A tappable **Allow Bluetooth to show device status** action |
| `idle`, `initializing` | Initializing Bluetooth… |
| `available` | The connected device names, joined with `、` |
| `available`, nothing connected | No connected devices |
| `poweredOff`, `unavailable`, `failed` | Their own existing messages |
| `authorizationDenied` | A tappable **Allow Bluetooth in Settings** action, which opens Privacy & Security › Bluetooth |
| `authorizationRestricted` | Its own existing message |

Device names are joined with the ideographic comma `、`. A connected battery
reading is joined to its device with the existing ` · ` separator, so the level
reads as a property of that device rather than another entry in the list:
`AirPods Pro · L 80% · R 75% · Case 60%、MX Master 3 · 45%`. The `Case` in that
example is the text-only rendering of the level — on screen the case is a glyph
(see *The charging case is a glyph* below).

## Device names come from the system profiler

The paired-device list, including each device's name, is read from
`system_profiler SPBluetoothDataType` — the same report the battery levels come
from. `IOBluetoothDevice.nameOrAddress` is deliberately not used: it returns a
cached name that kept reporting the old value after the device was renamed in
System Settings, so a renamed AirPods stayed on its previous name indefinitely.
The profiler reports what the system currently uses. Reading it takes well under
a second and reuses the existing refresh cadence, so it adds no timer.

The parser separates "the report could not be read" (a read failure) from "the
machine has no paired devices" (an empty list), so a malformed report is never
displayed as an empty device list. It accepts the profiler's wrapped
`SPBluetoothDataType` list and a bare section. How a device's class is resolved
from the report's wording is described under *Device classes and their glyphs*
below.

One address names one device, so the parser keeps one entry per address. Every
consumer treats the address as the identity — the list's `Identifiable.id`, the
battery-level lookup, the action state and the pending disconnect confirmation —
so a report that carries one address twice used to draw that device twice, with
both rows sharing a single set of state, and hand `ForEach` a duplicate id,
which SwiftUI leaves undefined. Three report shapes can do it: a connect or a
disconnect caught between the two collections, a Mac whose controllers the
profiler reports as separate sections, and a paired-device database that itself
holds a duplicate. The collections are read connected-first, which makes that the
precedence: the entry that survives is the one whose state the device is
actually in.

An address the normalizer cannot reduce names no device, so entries like it are
never merged — two of them are not necessarily the same device, and the merge
would cost a real one its row.

The level map reads in the same order and keeps the same precedence, and it
needed it more: its keys are addresses, so the disconnected copy of an address —
read second — overwrote the connected reading, and a row showing the current
charge fell back to the last value macOS had written down.

## Device classes and their glyphs

Every row draws a glyph for the class the report declares
(`BluetoothDeviceRowIcon.symbolName(for:)`), and the class comes from
`BluetoothDeviceKindResolver.kind(properties:)` — one table, unit-tested against
the wordings macOS and the Bluetooth assigned numbers actually use, rather than
a `switch` at the call site.

Two rules that table follows, each of which the previous one broke and thereby
hid a whole family of devices behind the generic glyph:

- **A minor slot never carries a major name.** macOS reports `Laptop` or
  `Smartphone` in the minor slot, never `Computer` or `Phone`. The previous
  table matched the major names against that key, so nothing classified and
  every phone and every Mac fell through to the placeholder.
- **`device_majorType` does not exist on current releases.** A full-detail
  report on macOS 26 carries no such key for any device, so the major table can
  only be a fallback for the older report shapes that do carry one — never the
  second half of the common path. The same wording is read from the
  `device_minorClassOfDevice_string` / `device_majorClassOfDevice_string` keys
  the older reports use.

Matching is exact on normalized wording first, then a substring pass ordered so
that `headphone`, `earphone` and `microphone` are all tested before `phone`: the
wording is manufacturer-supplied, and a phone glyph on a headset would be the
same class of bug as the mouse glyph on a keyboard. A major class of `Wearable`
is deliberately not guessed — its five minor classes are a watch, a pager, a
jacket, a helmet and glasses, so any single choice would be wrong for four
devices out of five.

A class the report does not describe — or describes with wording that names no
device the app can draw — is `unknown`, and it excludes the device from
anything that treats audio as special, which is what keeps an unrecognized
device from being offered a battery level it has none of.

### The glyphs

Each class resolves through a list of candidate symbol names, ordered most
faithful first, and the first name the running system actually ships is drawn
(`NSImage(systemSymbolName:)`). The last entry is therefore the one a macOS too
old to ship any of the others falls back to, and it must never be blank — the
same rule the audio output list already follows in
`AudioOutputDeviceIcon.symbolCandidates`.

`unknown` draws a radio (`dot.radiowaves.left.and.right`), not a question mark.
The question mark is what macOS reserves for a page the user has to fix, and an
unreported class is not a fault: it is the ordinary state of a manufacturer that
never filled the field in. Every comparable app draws a generic wireless glyph
here.

Audio devices keep resolving through `AudioOutputDeviceIcon` rather than the
class table, so an AirPods keeps the glyph macOS declares for its product ID and
the row and the output list cannot drift.

The device's own name can narrow the glyph further, ahead of the class list
(`namedCandidates`). The Bluetooth class stops at the family — a Mac mini, an
iMac and a Mac Pro all declare `Desktop` and nothing in the class tells them
apart — but Apple's products name themselves after the model, so `Mac mini`
draws `macmini`, `Mac Studio` draws `macstudio`, a `MacBook` draws the laptop
glyph and an `iPhone` draws `iphone`. The refinement is bounded on purpose: it
only runs inside the class the report already declared, so a mouse that happens
to be named like a Mac can never be drawn as one, and a name the app has no
model glyph for — an iMac or a Mac Pro, which Apple ships no symbol for —
changes nothing. The class list stays behind the named one as the fallback.

### Drawing an input device whose class cannot be trusted

The declared class is a manufacturer's claim about its product, not an
observation of what it does, and the two disagree in practice: a Logitech
`MX Keys` reports `Mouse` in `device_minorType` while the system enumerates
Generic Desktop keyboard for it — the interface macOS actually loads a keyboard
driver for. Trusting the report alone draws a mouse glyph on the keyboard the
user is typing on.

The I/O Registry describes the interfaces a device presents
(`BluetoothHIDUsageReader`), but for a keyboard/mouse composite that evidence is
itself ambiguous: a macro mouse and a keyboard both enumerate mouse *and*
keyboard interfaces, and nothing in the descriptor says which one the device
"is". Measured on one Mac, an MX Keys, a M585/M590 and a HECATE G3M Pro were
each a single `IOHIDDevice` node presenting both a mouse and a keyboard
collection — they differed only in the order the collections appeared.

So the app does not guess. `BluetoothInputIconClassifier` turns the declared
class and the observed capabilities into a *display* classification
(`BluetoothInputIconClassification`), and the row draws that — never a definite
mouse or keyboard glyph it cannot back up:

- The declared class and the observed interfaces agree → that glyph
  (`mouse`, `keyboard`, or a specialized `trackpad`/`gamepad` when the Digitizer
  or Gamepad usage is present).
- Both mouse and keyboard interfaces are present → **the generic input glyph**.
- The declared class and the only interface present conflict (a `Mouse` that
  presents only a keyboard, or the reverse) → **the generic input glyph**.
- A device the report did not classify, with exactly one interface → that glyph.
- Nothing recognizable observed → the declared class.

The generic input glyph is the same radio the unclassified class draws. Once a
device is classified generic it stays generic across reads
(`BluetoothInputIconStabilizer`), so a read that happens to enumerate only one
of the two interfaces cannot flicker the row back to a definite glyph.

The capabilities come from every usage pair the device declares, not only its
primary usage. A Bluetooth HID device is one `IOHIDDevice` node whose primary
usage is just the first collection in its report descriptor, so a mouse with
macro keys — one whose descriptor orders the keyboard collection first — would
otherwise present as a keyboard and lose the pointer usage that identifies it.
`DeviceUsagePairs` carries the whole list, and the primary usage is only the
fallback for a device that declares no pairs.

This classification is display-only. It never changes `BluetoothDevice.kind`,
which stays the class the report declared, so connection, disconnect
confirmation, ordering, battery handling and audio eligibility are unaffected.

Three bounds keep it from overreaching:

- **Only `peripheral` and `unknown` are classified.** An audio device, a phone
  or a computer never declares a peripheral class, so a stray HID interface on
  one of them must not move it into that family.
- **Only connected devices.** A paired but disconnected device has no Registry
  node and keeps the class the report declared.
- **The Registry is only walked when something could use it.** A Mac whose
  paired devices are all headphones and phones never pays for the read — the
  same rule that keeps `pmset` from running when the report already carries
  every battery level.

The walk runs inside the process (`IOServiceGetMatchingServices` /
`IORegistryEntryCreateCFProperties` over `IOHIDDevice`). There is no `ioreg` or
`hidutil` subprocess to hang the way `/usr/sbin/system_profiler` can, no
Bluetooth grant is involved, and the app is not sandboxed, so the Registry is
readable without a permission of any kind. `IOBluetoothDevice.pairedDevices()`
is not an alternative: a probe compiled against it aborts with `SIGABRT` in a
plain command-line process.

## Which levels the row reports

The row reports the level the report carries for every connected device, not
only for AirPods: a keyboard or a mouse level is as useful there as the detail
page already makes it, and showing it costs nothing extra, because the levels
come from the same report as the names. A device the report has no level for
keeps its name alone, so a row that mixes both kinds stays readable.

AirPods lead the row whatever they are called, and lead each group of the detail
list for the same reason (`BluetoothDevicePresentation.grouped`): they are the
devices whose multi-channel level the row headlines, and the order must not
depend on how a given language collates their name. Everything else follows in
the system's name order.

Battery levels come from the same `system_profiler SPBluetoothDataType` report.
The summary row is the only surface that claims that read, and the controller
tracks the claim by token rather than with a boolean — a shape the two-surface
days proved necessary: SwiftUI may run an outgoing surface's disappear hook
either before or after an incoming surface's appear hook, and a boolean let the
last writer win, so leaving one surface switched the read off right after the
other had asked for it, and every device row showed "Unavailable" while the
level it had just read was still on screen. A claim count makes the outcome the
same in either order; the read runs while any claim is held and stops when the
last is released. The row claims only while the setting is on
(on by default) and at least one device is connected — the connected devices are
the gate, not the presence of a readable level, so a just-connected device still
triggers the first read. A claim is dropped where the change arrives and not only
when the row disappears: switching the setting off while the row stays on screen
stops the read and clears the level it published. Closing the popover drops every
claim.

### The charging case is a glyph

A device's level is built as pieces (`BluetoothBatterySegment`) rather than as a
finished sentence, and one piece of an AirPods level is drawn instead of spelled
out: the charging case is `airpods.chargingcase`, with its percentage still text
beside it. The word it replaces — `Case` — was hard-coded English that none of
the twelve localizations carried, and a word is the part with no room in that
slot at the row's caption size anyway. The outline form is deliberate: at 10 to
11 points the filled variant is a solid blob that reads as nothing in particular.

Pieces also keep the text-only surfaces honest. `BluetoothBatteryLevel.summary`
is the pieces with every glyph spelled out by its label, so the wording its
tests pin, the appcast and the accessibility values are unchanged character for
character, and only the drawing differs. `BluetoothBatteryLevelText.drawn`
concatenates the pieces into one `Text` run — a `Text` and a
`Text(Image(systemName:))` add up to a single `Text` — so a row keeps one line,
one font and one truncation behaviour while one piece of it is a glyph. The
device rows and the popover's summary line draw the same pieces, which is what
stops the case from being a glyph on one surface and a word on the other. A
symbol a later macOS drops falls back to drawing its label, the same rule the
class glyph list follows rather than drawing a blank.

An inline image carries no label of its own, so the row's level run is hidden
from accessibility and the level is appended to the row's accessibility value
instead (`rowAccessibilityValue`): a combined element would otherwise announce
the case's percentage with nothing saying what it belongs to. The summary line
already overrides its label and needs no change.

## A second source for levels the report omits

The report stays the only source of every level the panel shows, and no second
source may change one. macOS also exposes the same accessory batteries through
the power manager, whose only command-line form is `pmset -g accps`, and that
view is consulted for exactly one purpose: a connected device the report carries
no level for. It can never take a level away and never overwrite one, because the
merge copies the report's levels through untouched and only adds an entry for an
address that has none. A device macOS can already read is therefore never
described by the other source.

The XML form is asked for rather than the plain-text one, because the text form
prints an accessory it cannot resolve with an empty name — the Mac this was
written on shows its AirPods as `- (id=…) 97%` — and the name is one of the two
things a reading is joined to a device by. `Vendor ID`/`Product ID` are the
identity when both sides carry the pair, so a rename cannot re-join a reading to
whichever device now happens to share its wording. The name is the fallback for a
report entry that carries no pair, and that comparison is exact rather than a
substring match, which would join an accessory to any device whose name happens
to contain it.

A reading is written to the channel its part names, and a part never writes the
device-wide level: `Part Identifier = Left` fills `left`, and only a reading with
no part can fill the device-wide slot. Without that rule one bud's charge could be
reported as the whole device's, and a merge would be less accurate than the report
it was meant to complete.

The subcommand is undocumented, so a macOS that stops answering it must cost
coverage and nothing else: a failed read reports no accessory, which leaves the
report as the only source, exactly as before. On a Mac where both sources agree —
measured here, byte for byte — the second source costs nothing at all, because it
is never consulted: with a level present for every connected device, no `pmset`
process is started. A failed read of the report keeps its line under the list
unless the second source actually supplied a level, so a report that failed
outright is never quietly replaced by a partial answer.

## Levels refresh on the system's own notifications

The safety-net poll stays, and is still deliberately slow, but a level that changes
is now re-read within a few seconds. While a surface is showing levels the
controller registers for the power manager's accessory notifications — `notify(3)`,
a public libSystem mechanism whose only Apple-specific part is the key names — and
one burst of them re-reads the report through the same coalescing path a connection
notification uses. The notification says the system's reading changed, which is
exactly what a cached report cannot show, so the read that follows re-fetches
rather than reuses.

Two details differ from the connection registration. The burst is held longer
(three seconds, against 750 ms for a connect), because an accessory discharging
posts these often and each event would otherwise start its own read. And the
registration follows the battery claim as well as the visible surface, where the
connect registration follows the surface alone: a panel that is on screen with
levels switched off has nothing to update, so it should not hold the registration.
Closing the panel discards a debounced read that has not run yet rather than
letting it fire against a surface that is gone.

A refused registration is not a failure. The keys can disappear in a future macOS,
and when they do the poll carries the levels on its own, which is the behaviour the
app shipped with. Worth knowing when verifying by hand: these notifications cannot
be simulated. The keys live in the `com.apple.system` namespace, which an ordinary
process may register for but may not post — `notifyutil -p` reports success and
delivers nothing, while `powerd` posts them for real. `notifyutil -1` (register and
wait for one) does observe them, so only a real accessory event exercises this path.

## Device levels in the list

The panel's list renders one level per device the same way the row does, and
covers every paired device, connected or not. A row shows a level only when the
report carries one for that device
(`BluetoothDevicePresentation.batteryLevelSegments(for:batteryLevels:)`); a
device macOS cannot read stays silent instead of repeating a placeholder on
every line.

A paired device with only a whole-device battery level keeps that level on the
same line as its name. When macOS reports a component level — left, right, or
charging case — the row places those levels on a second line, so the name gets
its width back instead of trading it against `L 85% · R 80% · Case 70%`. The
decision is based on the battery data rather than the device brand or model
(`BluetoothDevicePresentation.batteryLayout(for:batteryLevels:)`), so any
true-wireless headphones that report component levels use the same layout, and a
renamed AirPods is laid out no differently from one still carrying its name. A
single component channel is enough to take the second line: waiting until two or
more are present would make a row jump between one and two lines as the partner
earbud and the case report in, so the layout is fixed by data, not by count.

A report that could not be read is a different state from a report without
levels, so `BluetoothBatteryReading.read(completion:)` answers with an optional
dictionary: `nil` is a failed read, `[:]` is a successful read that carries
nothing. The controller publishes the difference as `batteryLevelsReadFailed`,
the panel shows it as one line under the list, and it clears wherever the levels
are cleared: the last claim released, an availability change, or `deactivate()`.

`SettingsStore.showsBluetoothBatteryLevels` defaults to on. It only decides who
claims the read: with no claim — no Bluetooth surface on screen — nothing is
read, so the default costs nothing on a Mac that never shows a Bluetooth
surface.

## Activation and permission

Reading the paired-device database needs no CoreBluetooth grant, but starting
the state monitor is what raises the system prompt. So
`BluetoothPanelActivation.shouldActivate(authorization:)` allows the popover to
activate the monitor on its own only when the grant is already `allowed`, which
refreshes the names the row reports. Every other grant state is only observed.

A refused grant is the one state the user can act on from the row, so the row is
a button there: it closes the popover and opens **Privacy & Security ›
Bluetooth**, the pane that gives the grant back
(`StatusBarController.bluetoothPermissionSettingsURLs`). That is deliberately not
the pane the gear opens — `bluetoothSettingsURLs` turns the radio on and off —
and a *restricted* grant gets no action at all, because a managed Mac or parental
controls leave the user nothing to change.

The popover re-evaluates this on each open, which is what replaced the previous
"open details to view device status" placeholder: the monitor is enabled by an
in-memory flag that a fresh launch does not restore, so the row used to start on
that placeholder every time. Permission is still only requested by the user's
tap, never by the popover appearing; that contract is covered by
`BluetoothPermissionTimingTests`.

## The device list in the status panel

`Settings › Bluetooth` can list paired devices under the Bluetooth row. The
connected group always leads; the saved order only reorders devices inside
their own group, so a drag can never lift a disconnected device above a
connected one, and devices with no saved rank land after the ranked ones in
their group. The limit is a total row count, which means a long connected
group can push every disconnected device out of the panel — the expansion
control holds the rest.

The rows stop at 330 points and scroll inside the panel beyond that, the same
bound the Wi-Fi list uses. Whether they overflow it is decided by the summed
height, not the device count: the list adds each row's own estimated height
(`BluetoothDeviceRowMetrics.estimatedHeight(for:batteryLevels:)`), so a
component-battery row counts for its two lines rather than the one an inline row
occupies. The summary popover has no scroll view of its own, so
without it an expanded list — or a limit the user raised to 20 — would keep
growing the popover past the screen. The scroll view appears only past that
bound: a list that fits is laid out directly, because a scroll view that is not
needed still flashes its scroller while an expansion animates through the moment
the content is taller than the shrinking frame, which a Mac with six devices
should never show. The expansion control sits outside the scroll region, so
collapsing a long list never needs a scroll to the bottom first, and the panel's
scroll-wheel handling already leaves a pointer over an `NSScrollView` to that
view rather than adjusting the volume.

Rows here are actionable: tapping one asks the system to connect or disconnect
that device (see *Acting on a device from its row* below). Nothing here starts a
new read: the list renders the paired-device report and the level map the row
already claims.

The row no longer opens a page. The list below it shows the same devices, with
the expansion control covering the ones the limit hides, so a second surface only
repeated it. What that page offered besides lives in the row now: the refresh
button beside the gear, and the one-line report of a failed level read under the
list.

The list is on by default, and the maximum visible count is clamped to `1...20`.
The row's own subtitle gives way to the list while the list is visible, because
the list already carries the connected names and repeating them reads as
duplication — the row's accessibility label drops them for the same reason, so
VoiceOver announces each device once. States only the row can explain keep the
subtitle: nothing connected, no permission, powered off, or a failed read.

`Settings › Bluetooth` also claims the monitor while its pane is on screen, so
a fresh launch that opens Settings lists the paired devices instead of the empty
state, and a read that lands after the pane appeared repaints it. The claim is
gated by `BluetoothPanelActivation.shouldActivate(authorization:)`, so the pane
never raises a permission prompt; releasing it stops the safety-net poll but
does not turn the panel's enabled flag off.

## Apple device battery rows

With **Show Apple devices and battery** enabled, verified iPhone and iPad
devices already trusted by this Mac and Apple Watch devices verified through a
trusted paired iPhone appear automatically in this same list. There is no
separate picker. Trusted discovery reads metadata only; arbitrary nearby Apple
broadcasts, names, and untrusted routes do not establish ownership.

Named Apple BLE discoveries appear as ordinary rows in the Bluetooth Settings
order list and, when the master option is enabled, in the status popover. UUIDs
are internal stable row identities only. Names and advertisements do not
establish ownership, and BLE rows never merge with classic Bluetooth rows by
name. Settings discovery never reads battery data.

A BLE battery read requires the global Bluetooth battery option, the Apple
device option, and a row actually intersecting the visible popover viewport.
Closing, hiding, folding, or scrolling a row out of view revokes its permit.
Scanner sessions are limited to two concurrent connections, an eight-second
deadline, and a per-device cooldown. A BLE row without a battery value, including
after a failed read, has no extra status label. Trusted helper devices continue
to use the helper's existing verification and USB/network routes.

Classic Bluetooth addresses generally cannot be mapped to helper UDIDs. When no
stable cross-provider identity exists, same-named rows stay separate rather
than sharing ownership, connection state, or battery values. The classic row
keeps its normal connection actions; the helper-backed row is read-only. See
[`apple-device-battery.md`](apple-device-battery.md) for migration and hardware
verification details.

## Acting on a device from its row

A device row is a button: tapping an unconnected device asks the system to
connect it, and tapping a connected one asks it to disconnect. The request goes
through `IOBluetoothDevice.openConnection()` / `closeConnection()` on a private
queue — those calls are synchronous and can block until the page timeout when a
device is out of range, so they never run on the main thread. Devices are
matched on the normalized address: IOBluetooth keeps reporting the name a device
had before it was renamed, while the report the UI is built from carries the
current one, so names cannot join the two sources.

Nothing here flips a row optimistically. The request only decides whether the
system accepted the command; the row's connection state still comes from the
device report, and the action is considered done only when that report changes.
A request that is refused, and one that is accepted but takes longer than ten
seconds to show up, both become a visible failure for a few seconds and then
clear. A failed row can be tapped again to retry.

Commands run in order on the performer's single queue, so two devices tapped in
quick succession are sent one after the other, and a command queued behind a
blocking one can have its own ten-second clock expire before it is even sent —
a transient failure that clears itself.

Disconnecting an input device — a keyboard, mouse, trackpad or gamepad, and a
peripheral whose class wording did not narrow it down — asks for confirmation in
the row itself, because disconnecting the keyboard or mouse the user is holding
would cut them off from their own Mac. The class the wording left unclassified
counts too: one wasted tap costs far less than disconnecting the keyboard the
user is typing on because its class field said something unrecognized. The
prompt lives in
the row rather than in an alert: the panel is transient, so a modal would close
it. The controller owns the pending confirmation, and `SystemStatusStore`
cancels it when the popover closes, so an unconfirmed disconnect is never sent:
the popover keeps its content view controller — and therefore its SwiftUI state —
alive for a minute after a close, which is why the cancellation cannot be left to
a view's own disappear hook. The prompt carries no device name — the
row already shows it — and it disappears on its own if the device stops being a
connected input device while it is open.

## Switching an AirPods listening mode from its row

A connected AirPods row whose listening mode the system exposes carries a small
capsule switch under the battery line: one capsule per mode the device reports it
supports — noise cancellation, transparency, adaptive, and the silent `off` state.
The modes and the current selection come from undocumented CoreAudio HAL
properties read off the device's own audio endpoint: `lsms` lists the modes the
device supports, `lstm` reports (and sets) the active one. Both are Global scope on
the Main element. Because these selectors are not a public API, the whole feature is
fail-closed: a device that does not answer them, one that exposes only a single
mode, one the property says is not settable, an identity the controller cannot pin
to one device, or an endpoint it cannot resolve — all render the ordinary row with
no control. An ordinary Bluetooth device can therefore never regress into a broken
half-switch.

Identity is matched on the normalized address exactly like connect/disconnect, never
on the device name. When a connected AirPods is the only controllable candidate the
controller resolves, a conservative single-device fallback maps the presentation to
it; more than one candidate and no exact address match means no control is published
for any of them, because guessing which pair a mode write belongs to is not a
decision the row should make.

Discovery and the mode write are governed by the `BluetoothListeningModeController`,
kept separate from `BluetoothDeviceController` so neither the delicate 1300-line
device controller nor its timings are disturbed. There is no polling: endpoints are
probed only when the panel becomes visible or the user refreshes, one pass per
`refresh(devices:)`, keyed by the joined addresses of connected AirPods. A mode tap
issues exactly one write. That write is not trusted blindly — the controller reads
`lstm` back within a bounded window, and only a read-back that equals the requested
mode counts as confirmed. An accepted-but-unverified write rolls the highlight back
to the last observed mode; a refused or unreadable one marks the capsule group with
a warning for a moment (the failure clears shortly after, on its own timer) and then
reverts to a fresh read of the device's actual mode. Nothing is presented as the
selection that the device has not confirmed.

The layout adapts rather than being fixed-width tuned. `BluetoothBatteryAndListeningModeRow`
uses `ViewThatFits` to keep the capsules on the battery's line when there is room
and wrap them to their own line when there is not — which is what a longer German or
Russian mode name does inside the panel's 302-point content width. The row is
measured, not guessed: `BluetoothDeviceRowMetrics.listeningModeContentHeight` is 54,
and `BluetoothListeningModeRowMetricsTests` renders the real row at the panel width
and asserts it still agrees, so a layout change fails the test instead of silently
drifting the list's scroll height away from what is drawn. The tall row is what
makes the list decide to scroll when the rows together outgrow the panel.

Accessibility is the point of the split-button row. The primary connect/disconnect
action stays a button over the name line, and the mode capsules are its *siblings*,
never nested inside it — SwiftUI swallows an inner button's tap when it lives inside
another `Button`, so nesting would make the capsules dead. The row is one
`.accessibilityElement(children: .contain)` (not `.combine`), so each capsule keeps
its own focus target and VoiceOver or the keyboard can land on a single mode;
selection rides on the `.isSelected` trait and an accent ring, not colour alone, and
a capsule already selected or already settling into a change is disabled rather than
firing a redundant write. The in-flight marker honours the system's Reduce Motion:
an animated progress dot normally, a static dot when Reduce Motion is on. All of the
mode names, the group label, and the failure message ship in every language
(`bluetooth.listeningMode.*`), guarded by the localization parity and
every-key-every-language tests.
