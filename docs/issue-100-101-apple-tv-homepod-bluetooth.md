# Issue #100 / #101 — Apple TV and HomePod in the Bluetooth device list

Issues [#100](https://github.com/lingyired/status-trio/issues/100) (two HomePods
show as two Bluetooth devices with the wrong glyph) and
[#101](https://github.com/lingyired/status-trio/issues/101) (an Apple TV is not
listed among Bluetooth devices, nor in the audio-output list) ask the same
question: can these devices be identified inside the Bluetooth device list, and
given that identity, draw their own icon?

## Verdict

Neither device can be given a trustworthy identity from the data Status Trio
already reads, so — following the rule stated on the issues ("if it cannot be
identified, do not support it") — the Bluetooth device list does **not** get a
special HomePod / Apple TV path. The app keeps the existing name-based audio
glyph for any audio device whose name still says what it is, and does not guess
beyond that.

- **Apple TV (#101).** An Apple TV is not a normal Bluetooth audio device. Its
  real identity lives on AirPlay (Bonjour `_airplay._tcp`, e.g. `model=AppleTV14,1`
  and a room name), which is a different subsystem from the paired-device
  report. CoreAudio does not expose it as an output device unless it is already
  the active system route, and even then without a model name. If it ever shows
  up in the paired-device table, that is an accident of one setup, not a signal
  the app can rely on.
- **HomePod (#100).** When macOS has paired a HomePod over Bluetooth the report
  carries one entry per unit. That report has no stereo-pair or room grouping and
  no verified product identity, so a pair cannot be folded into one row, and the
  glyph can only follow a name that still contains "HomePod". A unit renamed to
  its room name falls back to the generic audio glyph.

## What each subsystem actually reports

### The Bluetooth paired list

`system_profiler -json SPBluetoothDataType` (see
[`bluetooth-status.md`](bluetooth-status.md#device-names-come-from-the-system-profiler))
is the only source for the paired rows. A full-detail record carries the address,
name, `device_minorType`, `device_vendorID` / `device_productID`, firmware, and —
for headphones — case and left/right fields. Apple devices carry the vendor and
product ID. What it does **not** carry:

- a stereo-pair or room identifier, so two HomePods in one pair are two rows with
  two addresses and nothing in the report says they belong together;
- a HomePod model. The AirPlay identifiers people see (`AudioAccessory1,1`,
  `AudioAccessory5,1`, …) are AirPlay **model** strings from Bonjour, not
  Bluetooth product IDs, so they never reach this report;
- a reliable class for a renamed or room-named unit. `device_minorType` may be
  `Speaker`, may be a broad wording, or may be missing entirely.

### The glyph

`BluetoothDeviceKindResolver` turns the declared class into `.audio`, and
`BluetoothDeviceRowIcon` hands an audio row to `AudioOutputDeviceIcon`, the same
table the output list uses. That table resolves `homepod`, `homepod mini`,
`apple tv`, AirPods and Beats **by name**. It deliberately only refines the class
the report already declared — name never overrides the class (see
`BluetoothDeviceRowIconTests.theNameNeverCrossesTheDeclaredClass`), which is what
keeps a mouse named like a Mac from being drawn as one.

The consequence for issue #100: if the HomePod's Bluetooth name still contains
"HomePod" the correct `homepod` glyph is already drawn; if the unit was renamed to
its room name ("客厅"), the name no longer says what it is, the class only says
"audio", and the row falls back to the generic audio glyph. There is no field
that recovers the model after the name is gone.

### AirPlay and CoreAudio

A HomePod / Apple TV that is the **active** system output appears in CoreAudio
with transport `'airp'`, and `AudioOutputDeviceIcon` would draw the right glyph if
the name identifies it. But `kAudioHardwarePropertyDevices` does not list an
AirPlay output while it is not the selected route (see the Apple Developer Forums
threads below), so the audio-output list cannot *discover* an idle Apple TV or
HomePod; it only ever sees the one that is already streaming. That is why #101's
"not in the audio output list" is not a glyph bug — there is nothing to draw.

### Nearby BLE

The nearby scan only reads Apple **mobile** battery advertisements
(iPhone / iPad / Watch, see [`apple-device-battery.md`](apple-device-battery.md)).
It does not surface HomePod or Apple TV, and BLE rows never merge with classic
Bluetooth rows by name.

## Why the two HomePods cannot be folded into one row

Every consumer treats the Bluetooth **address** as a device's identity, and a
stereo pair is two addresses. The only field the two units share is the name, and
the app's existing rule is explicit: same-named rows stay separate rather than
sharing ownership or state ([`bluetooth-status.md`](bluetooth-status.md#apple-device-battery-rows)).
Folding on the name alone would also merge unrelated devices that happen to share
a name. There is no pair identifier in the report to merge on, so "两个 HomePod
合成一个" is not implementable from the Bluetooth data — it is something only the
AirPlay layer knows.

## What full support would actually require

Recognising these devices by identity (not by a renamable string) needs the AirPlay
side, a separate subsystem from Bluetooth:

1. Browse `_airplay._tcp` over Bonjour (requires the Local Network permission and
   an opt-in discovery lifecycle), read the `model` TXT record
   (`AppleTV*` → `appletv`, `AudioAccessory5*` → `homepod.mini`, other
   `AudioAccessory*` → `homepod`).
2. For the **active** route, read its real name / model / volume through an AirPlay
   route helper, because CoreAudio alone exposes only an opaque device.
3. Optionally present a discovered-but-idle device and hand the user to System
   Settings to route to it; there is no public API to switch the whole-system
   output without user selection.

That is a distinct feature with its own permission, discovery and lifecycle
design, not a change to the Bluetooth device list, so it is out of scope for these
two issues.

## Decision

- Do not add a special HomePod / Apple TV path to the Bluetooth device list.
- Keep the existing name-based audio glyph; do not merge same-named pairs; do not
  guess an Apple TV into the Bluetooth list.
- Record the boundary in [`known-limitations.md`](known-limitations.md).
- If AirPlay/HomePod identity is wanted later, build it as the Bonjour + route
  helper feature above, on its own issues.

## Sources

- owntone-server issue #1291 — stereo HomePods discovered as two devices over
  AirPlay: <https://github.com/owntone/owntone-server/issues/1291>
- `fanglinwei/Combo` research (independent open-source investigation of the same
  problem): `docs/airplay-homepod-icon-research.md` and
  `docs/bluetooth-audio-device-icon-research.md` —
  <https://github.com/fanglinwei/Combo>
- Apple Developer Forums — "kAudioHardwarePropertyDevices does not list AirPlay
  sound output device": <https://developer.apple.com/forums/thread/750483>
- Apple Developer Forums — "AirPlay no longer enumerable in 10.11 unless selected
  for system": <https://developer.apple.com/forums/thread/17664>
- Local: [`bluetooth-status.md`](bluetooth-status.md),
  [`audio-output-device-icons.md`](audio-output-device-icons.md),
  `BluetoothDeviceRowIcon`, `AudioOutputDeviceIcon`,
  `BluetoothDeviceKindResolver`.
