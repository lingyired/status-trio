# Input source in the centre slot

The centre slot of the menu bar icon and the Dock icon can draw the current
keyboard input source instead of the network icon, and the status panel can list
the enabled sources and switch between them. Both are off by default.

## API and permission boundary

Everything goes through the public Carbon Text Input Sources API in
`Sources/StatusTrioCore/InputSource/`:

- reads: `TISCopyCurrentKeyboardInputSource`, `TISCreateInputSourceList`,
  `TISGetInputSourceProperty` over `kTISPropertyInputSourceID`,
  `kTISPropertyLocalizedName`, `kTISPropertyInputSourceLanguages`,
  `kTISPropertyIconImageURL`, `kTISPropertyInputSourceIsEnabled`,
  `kTISPropertyInputSourceIsSelectCapable`;
- switching: `TISSelectInputSource` on the source whose
  `kTISPropertyInputSourceID` matches the row;
- change signals: `kTISNotifySelectedKeyboardInputSourceChanged` and
  `kTISNotifyEnabledKeyboardInputSourcesChanged` through
  `DistributedNotificationCenter`.

None of these requires a TCC grant, and the app asks for none: no accessibility,
no input monitoring, no automation. There is no key simulation and no private
symbol — the `FrontAppSelection`-style private workaround used by other input
switchers is deliberately not ported.

## Refresh and recovery

The controller is event-driven; it has no timer and no polling loop. Each TIS
notification triggers an immediate read and one cancellable re-read 75 ms later,
because TIS can post the notification just before it publishes the new selection.
A burst of notifications coalesces into at most one pending re-read.

The same read also runs when the app becomes active, when the system wakes, and
when the displays wake. Opening the status panel keeps its existing extra
refresh. These are fallbacks for a delayed or dropped TIS notification, not a
per-frame or per-second poll.

All distributed and system observers, plus both the selection-confirmation and
notification-recovery tasks, exist only between `start()` and `stop()`. Turning
both input-source surfaces off therefore releases every subscription and task;
there is no new cache and the delayed work is bounded to one task per scheduler.

## What is not implemented

- **`kTISPropertyIconRef`.** The icon path reads `kTISPropertyIconImageURL`
  only. Measured on this machine, the two properties are mutually exclusive per
  source: `com.tencent.inputmethod.wetype.pinyin` and
  `com.tencent.inputmethod.wetype` carry an icon image URL and no `IconRef`,
  while `com.apple.keylayout.ABC` is the other way round. ABC therefore draws
  its short label `A` — the same marker the system's own input-source menu shows
  — so the gap is a styling difference, not a wrong or missing icon. Drawing an
  `IconRef` would mean the deprecated Icon Services conversion path; revisit only
  if a source appears that is both `IconRef`-only and has no readable name.
- **App Sandbox.** Active switching from a sandboxed build is not covered. The
  app ships non-sandboxed with Developer ID; do not read this as an App Store
  compatibility claim.

## Priority and fallback

`ConnectionCenterSource.automatic` is the shipped default and its decision is
byte-identical to the previous release: the input-source branch sits behind it.
With `.inputSource` selected, the centre slot resolves in this order, and each
step is pinned by `InputSourceIconPresentationTests`:

| Priority | Condition | Drawn |
| --- | --- | --- |
| 1 | Battery percentage asked for in the connection slot | battery text |
| 2 | Network outage, when the warning toggle is on (default) | Wi-Fi error glyph |
| 3 | Current input source | its icon, else its short label, else `keyboard` |
| 4 | Bluetooth audio replacement, when enabled | the device icon |
| 5 | Network | Wi-Fi / wired as before |

A live wired link is never an outage, so a wired user with Wi-Fi switched off
keeps their input-source icon (`StatusMappings.isNetworkOffline`).

## Icon rendering

Input-source icons are files (usually PDF or PNG), and their visible ink is not
centred in the box `NSImage.size` reports. `StatusIconRenderer` measures the ink
centre the same way it does for SF Symbols and anchors that, so a lopsided icon
still lands on `StatusIconGeometry.artworkCenterX`; `Issue30WiFiAlignmentTests`
and `InputSourceIconRenderingTests` pin it for the menu bar and the Dock.
Decoding and the ink measurement are cached per URL (`IconImageDecodeCache`), so
a redraw never re-reads the file.

The input source takes over the slot the Wi-Fi glyph sits in, so it follows the
one size control that slot has: "Wi-Fi Icon Size" (100 %–180 %, default 160 %).
`IconPresentationMapper.inputSourceCenterState` receives that value as its scale
for the icon file, the short-label text and the keyboard fallback alike, and the
image's 42-unit box is calibrated against the Wi-Fi glyph's own ink width at the
same scale — 67.75 against 67.2 units at the default — so an adjustment moves
both together instead of resizing one of them.

The short-label path is text, and text in the centre slot is anchored by its own
visible ink (`StatusIconRenderer.centerTextInkCenter`), not by a baseline: the
slot's other occupants are ink-anchored symbols, and a label that grows with the
size control has to grow *around* the slot centre instead of sliding away from
it. The renderer used to place this text at a second, hand-tuned anchor and
"centre" it by subtracting the glyph bounds' `midY` inside a y-flipped text
matrix; the flip turns that subtraction into an addition, so the ink landed at
`87 - 2 * midY` — correct only at the default percentage size, and wrong by
twice its own half-height at every other one. At the 160 % default an
input-source marker (`A` for ABC) therefore climbed into the ring's charging
indicator: `Issue30WiFiAlignmentTests.testInputSourceLabelInkKeepsTheSlotCentreAtEveryScale`
pins the label and the Wi-Fi glyph to one centre at 100 %, 160 % and 180 %, for
both an ASCII marker and a CJK one.

The same path serves "battery percentage in the connection slot", which the
plan's fallback table keeps ahead of the input source. Its text moves with this
correction too — that is the intended effect, not a regression: it is the same
label shape in the same slot, and leaving it on the old anchor would leave one
of the two visibly off the glyphs they sit between.

## The status panel

The section is a row, not a picker: it reports the current source next to a
disclosure chevron and the keyboard-settings gear, and clicking it opens the
switching list in place of the panel, the same way the battery and network rows
open their detail pages. `InputSourcePanelLayoutTests` pins that the closed row
draws no per-source target.

Every row in the opened list draws one flat mark in the row's own colour, so the
list stays readable on a dark panel:

- a source that ships an icon file goes through `InputSourceIconMask`, which
  keeps the icon's *ink* rather than its palette — the WeChat input method's
  black disc with a light glyph becomes a light disc with the glyph knocked out,
  and the system's dark Pinyin art becomes a light glyph;
- a source with no icon file gets the rounded chip macOS itself shows for ABC,
  with the layout's letter inside it.

Both are cached per URL, so a panel redraw never re-reads or re-rasterises the
file.

## Middle-slot choice

The centre slot is one single-choice setting, not a set of independent toggles:

- **Automatic** — the shipped priority: battery percentage in the connection
  position, then Bluetooth audio, then Ethernet / Wi-Fi;
- **Current Input Source** — the selected input source, with the optional
  network-error override;
- **Battery Percentage** — the battery level in the centre slot, only on a Mac
  that has a battery; a Mac without one falls back to Automatic;
- **Power** — the live whole-machine wattage, described in
  [Power in the centre slot](power-center-slot.md).

The former `showsBatteryPercentageInConnectionSlot` switch is folded into this
choice. On the first launch after the upgrade a stored `true` migrates to
**Battery Percentage** — that switch won at draw time — and the legacy key is
then removed, so a later manual choice is not overridden. The ring's own
percentage text (`showsBatteryPercentage`) is a different setting and is
unchanged.

## Verification status

Run and passing on macOS 27.0.1 / Xcode 27.0 / Swift 6.4 (newer than the CI
toolchain, so not proof for it):

- `swift test` — 1584 tests, 7 skipped, 0 failures;
- `swift build -c release`;
- `swift test --filter Issue30WiFiAlignmentTests` — 5/5.

The Keyboard pane route was verified by the extension that loads
(`KeyboardSettings.appex`), not by `open`'s exit status; see
[System Settings pane routes](settings-pane-routes.md).

Not run, and not claimed:

- the non-publishing `release.yml` preflight on the CI toolchain;
- a real switch inside a focused app on a build of this branch, third-party IME
  behaviour with a candidate window open, sleep/wake and display changes;
- macOS 13, 15 and 26 devices. The package still targets macOS 13 and compiles
  against it; only the local macOS 27 machine was exercised.
