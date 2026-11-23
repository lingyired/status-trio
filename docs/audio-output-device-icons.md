# Audio output device icons

The volume output list shows one icon per device. Issue
[#12](https://github.com/lingyired/status-trio/issues/12) reported that every
device rendered as a speaker, including connected AirPods.

## Where the system keeps its icon table

The system UI does not hard-code device glyphs. It resolves a device type, then
reads the matching symbol from
`/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist`, whose
`UTTypeSymbolName` keys are the SF Symbols the system draws:

| Device type | Symbol |
| --- | --- |
| `public.speaker` | `hifispeaker.fill` |
| `public.display` | `display` |
| `com.apple.accessory.headphones` | `headphones` |
| `com.apple.airpods` | `airpods` |
| `com.apple.airpods-gen3` | `airpods.gen3` |
| `com.apple.airpods-pro` | `airpods.pro.gen1` |
| `com.apple.airpods-max` | `airpodsmax` |
| `com.apple.beats-*` | `beats.headphones`, `beats.powerbeatspro`, `beats.studiobuds`, `beats.fit.pro`, `beats.earphones` |
| `com.apple.homepod`, `com.apple.homepod-mini` | `homepod`, `homepodmini` |
| `com.apple.apple-tv` | `appletv` |
| `com.apple.mac.laptop` | `macbook` |
| `com.apple.macmini`, `com.apple.macstudio`, `com.apple.macpro` | `macmini.gen2`, `macstudio`, `macpro.gen3` |

`AudioOutputDeviceIcon` uses those exact symbol names, so the app draws what the
system draws for the same device class. Note that the system always uses the
filled speaker glyph; the app distinguishes the selected device with its accent
circle instead of a second symbol.

## Built-in output draws the machine

For a built-in output the system draws the machine itself, not a speaker: a
MacBook row shows the `macbook` symbol. `HostMacKind` reproduces that from the
device name, which carries the family (`MacBook Pro扬声器`, `Mac mini扬声器`),
and falls back to `hw.model` when the name does not name the machine. Apple
Silicon identifiers such as `Mac15,9` no longer encode the family, which is why
the device name is read first.

A Mac with a headphone jack keeps one built-in output device and switches its
data source, so plugging headphones in switches the row from the machine symbol
to the headphones symbol.

## AirPlay

AirPlay outputs use `airplayaudio`, the AirPlay glyph, unless the device name
identifies an Apple TV (`appletv`) or a HomePod (`homepod`, `homepodmini`).

## Driver supplied icons

`kAudioDevicePropertyIcon` is an optional public property that returns a
`CFURLRef` to an image file the driver ships. HAL plugin devices use it, for
example `Background Music` points at
`/Library/Audio/Plug-Ins/HAL/Background Music Device.driver/Contents/Resources/DeviceIcon.icns`.
Built-in hardware and most USB devices do not provide it and return
`kAudioHardwareUnknownPropertyError` instead.

`AudioOutputDeviceIcon.source(for:)` therefore returns the driver image when the
file exists and the class symbol otherwise. `AudioOutputDeviceIconView` draws
that image as a template so it takes the same tint as the symbol it replaces.

Several of those symbols are recent additions. `airpods.pro.gen1` ships with
macOS 26, so every class also carries an older fallback and
`AudioOutputDeviceIcon.symbolName(for:)` returns the first symbol the running
system actually provides. That keeps macOS 15 correct instead of blank.

## How a device is classified

Three public CoreAudio properties describe an output device:

| Property | Scope | What it reports |
| --- | --- | --- |
| `kAudioDevicePropertyTransportType` | global | Hardware family: `bltn` built-in, `blue`/`blea` Bluetooth, `usb `, `hdmi`, `dprt` display, `thun`, `airp`, `grup`, `virt` |
| `kAudioDevicePropertyDataSource` | output | Live source on built-in hardware: `ispk` internal speakers, `hdpn` headphones, `espk` external speakers |
| `kAudioDevicePropertyModelUID` | global | A Bluetooth device's product and vendor IDs (`200f 4c`); built-in and USB hardware report a name instead (`Speaker`, `Digital Mic`) |

`kAudioDevicePropertyDataSource` is what lets a built-in output show the
headphones icon while something is plugged into the headphone jack, matching the
system menu. `kAudioDevicePropertyModelUID` is what lets an AirPods keep the
glyph macOS declares for its model after the user renames it.

## What the product ID identifies

macOS declares its own accessory classes. Every `com.apple.airpods*` type in
`CoreTypes.bundle/Contents/Info.plist` carries a
`public.bluetooth-vendor-product-id` tag written as
`<vendor decimal>:<product decimal>`, for example `76:8207` for
`com.apple.airpods-gen2`, which is AirPods (2nd generation). Apple's Bluetooth
vendor ID is 76, or `0x004C`.

That pair reaches the app through two public sources:

| Source | Property | Example |
| --- | --- | --- |
| CoreAudio | `kAudioDevicePropertyModelUID` | `200f 4c` |
| `system_profiler SPBluetoothDataType` | `device_productID` / `device_vendorID` | `0x200F` / `0x004C` |

`AirPodsModel` maps the product ID to the model, and refuses any ID whose vendor
is not Apple, so another vendor's earbuds cannot borrow an AirPods glyph. The
product ID decides the model before the name does, because a rename erases every
hint the name carried. AirPods (2nd generation, A2031/A2032) is the case that
reported this: renamed to something like `小王的耳机`, it fell back to the
generic headphones glyph.

The same identification decides whether the popover's Bluetooth row claims a
battery read, so a renamed AirPods reports its levels instead of staying silent
about them. The name remains the fallback signal there for a device whose
product ID is not in the table.

The table handles 1st through 4th generation, the Pro family, and Max. The
1st/2nd/3rd generation, Pro, and Max rows are the tags the shipping macOS 26
`CoreTypes.bundle` declares; the 4th generation and Pro 3 rows follow Apple's
`Device1,<decimal product ID>` identifiers, which that file does not carry yet.

A product ID the table does not know falls back to the device name, which is
usually `xxx的AirPods`. Beats, HomePod, and Apple TV stay name based; the table
covers the AirPods family only. Bluetooth audio recognized neither way defaults
to the headphones symbol, because Bluetooth audio is overwhelmingly headphones
and earbuds.

## Where the mapping lives

`Sources/StatusTrioCore/Audio/AudioOutputDeviceIcon.swift` holds the transport
and data-source value types plus `AudioOutputDeviceIcon`, which maps a device to
an `AudioOutputDeviceKind` and then to an SF Symbol name. Both the popup output
list (`OutputDeviceRow`) and the settings output-order list
(`AudioSectionView`) use it so the two surfaces stay aligned.

`Sources/StatusTrioCore/Audio/AirPodsModel.swift` holds the product-ID table and
its two parsers. `AudioDeviceIdentity`, next to `AudioOutputDeviceIcon`, carries
the signals that identify a device, so it can be classified however it was read.
The Bluetooth paired-device list reads its devices from the system profiler
instead of CoreAudio, and `BluetoothDeviceRowIcon` builds an identity from the
profiler's product ID and name and resolves it through the same mapping, so a
paired AirPods row and the popup's output row cannot drift apart.

## Center status icon size contract

The center status icon has one shared size contract regardless of whether it
draws Wi-Fi or a Bluetooth audio device:

- The base point size is `38 pt`.
- The default scale is `160%`, producing a `60.8 pt` center icon.
- The adjustable range is `100%–180%` in the legacy Wi-Fi/Bluetooth controls;
  Icon Designer stores its shared center Appearance scale in `1.0–3.0`.
- The menu bar and Dock renderers receive one resolved scene and therefore use
  the same base size and scale semantics.

Wi-Fi scale consolidation

The Icon Designer's Appearance value is now the single persisted center scale.
Older V1 payloads stored a Wi-Fi source scale in addition to center Appearance;
loading them folds that scale into Appearance once and writes a migration marker.
The composition resolver supplies neutral Wi-Fi source scale (`1.0`) because
`IconPaletteResolver` applies center Appearance after mapping. The separate
legacy compatibility projection supplies the effective Wi-Fi multiplier for
callers that do not run that Appearance pass.

Migration is selection-aware: the old Wi-Fi multiplier is folded when the
configured center primary is Network or `automaticLegacy`. An explicit
Bluetooth-audio or Mac battery-percentage primary keeps its saved Appearance
size; a Wi-Fi fallback in that configuration loses its old Wi-Fi-only scale.
When Network is primary, any configured fallback shares the migrated center
Appearance size. `automaticLegacy` can also resolve to non-Wi-Fi content, which
shares the migrated size. These are the unavoidable tradeoffs of the existing
shared center Appearance slot; live simulation state is never persisted to
choose a migration outcome.

`SettingsStore.wifiSymbolScale` remains a compatibility bridge: reads expose the
effective multiplier and writes update the unified Appearance value.
