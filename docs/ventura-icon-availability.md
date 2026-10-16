# Ventura icon availability audit

The app targets macOS 13.0. A SwiftUI `Image(systemName:)` whose symbol the
running macOS does not ship draws nothing and raises nothing, so a glyph added
in macOS 14 or later is invisible on Ventura with no crash to point at it. This
document records how the whole source tree was checked against the release that
introduced each SF Symbol, and what the check found.

## Where the release list comes from

macOS ships the authoritative table:

```
/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist
```

It has two keys:

- `symbols`: symbol name -> SF Symbols release year key, for example
  `"battery.100percent" -> "2023"`.
- `year_to_release`: release year key -> the OS version that shipped it, for
  example `"2023" -> ["macOS": "14.0", "iOS": "17.0", ...]`.

Joining the two gives every symbol's first macOS release. Extracting the table
on a current Mac produces 9,524 names, of which 5,066 shipped on macOS 13.0 or
earlier and 4,458 came after Ventura.

The list is a historical table, not a predicate. The runtime check the app
itself uses is:

```swift
NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
```

## What the audit checked

Every string literal under `Sources` was matched against the table. The source
uses 166 SF Symbol names. Of those, 26 were introduced after macOS 13.0.

Three are not icons at all:

| Name | Where | What it is |
| --- | --- | --- |
| `left` | `BluetoothAccessoryBatteryReader` | Battery-key parser case |
| `right` | `BluetoothAccessoryBatteryReader` | Battery-key parser case |
| `microphone` | `BluetoothDeviceKind` | Bluetooth class name -> kind |

One is a forward-looking candidate that no current macOS ships:

| Name | Where | Behaviour |
| --- | --- | --- |
| `airpods.gen5` | `AudioOutputDeviceIcon.symbolCandidates` | Not in the table; resolves to `airpods.gen4`, then `airpods`, then `headphones` |

The other 23 are drawable symbols. Twenty-one participate in fallback chains
whose last entry Ventura ships. Some newer audio glyph names are also raw
choices in the explicit picker, which omits each choice unavailable on the
running OS; `headset` and `headphones.over.ear` have no Ventura-safe picker
symbol:

| Newer symbol | Introduced | Ventura behaviour |
| --- | --- | --- |
| `battery.100percent` | 14.0 | `battery.100` |
| `battery.75percent` | 14.0 | `battery.75` |
| `beats.fitpro` | 14.0 | `beats.headphones` -> `headphones` |
| `flask.fill` | 14.0 | `testtube.2` |
| `macbook` | 14.0 | `laptopcomputer` (the laptop speaker chain now leads with it) |
| `smartphone` | 14.0 | `iphone` |
| `watch.analog` | 14.0 | `applewatch` -> `clock` |
| `translate` | 14.4 | `character.bubble` -> `globe` |
| `beats.pill` | 14.6 | `beats.headphones` -> `headphones` |
| `beats.solobuds` | 14.6 | `beats.studiobuds` -> `beats.headphones` -> `headphones` |
| `powerplug.portrait.fill` | 15.0 | `powerplug.fill` -> `bolt.fill` |
| `airpods.pro` | 15.0 | `airpodspro` -> `headphones` |
| `airpods.max` | 15.0 | `headphones` |
| `beats.studiobuds.plus` | 15.0 | `beats.studiobuds` -> `beats.headphones` -> `headphones` |
| `beats.powerbeats.pro` | 15.0 | `beats.powerbeatspro` -> `beats.headphones` -> `headphones` |
| `homepod.mini` | 15.0 | `homepod` -> `hifispeaker.fill` |
| `airpods.gen4` | 15.2 | `airpods` -> `headphones` |
| `macmini.gen2` | 15.4 | `macmini` -> `desktopcomputer` |
| `beats.powerbeats.pro.2` | 15.5 | `beats.powerbeatspro` -> `beats.headphones` -> `headphones` |
| `airpods.pro.gen1` | 27.0 | `airpods.pro` -> `airpodspro` -> `headphones` |
| `airpods.pro.gen3` | 27.0 | `airpods.pro` -> `airpodspro` -> `headphones` |
| `headset` | 15.0 | Omitted from the explicit picker; still parsed as a Bluetooth class name |
| `headphones.over.ear` | 26.0 | Omitted from the explicit Bluetooth icon picker |

`headset` also remains a Bluetooth class-name-to-kind value; unlike the prior
audit, it is now displayed as a picker choice on systems that provide the
symbol. The picker enumerates all 30 custom choices and checks each raw symbol
with `NSImage(systemSymbolName:accessibilityDescription:)`; choices unavailable
on the running OS are omitted. A previously saved unsupported raw value is
retained in preferences but resolves to Automatic, so it can become active
again after an OS upgrade. Automatic continues to use the active device's
resolved icon, including the existing `headphones` fallback on Ventura.

Newer names in existing audio and paired-device candidate chains remain
runtime-filtered too: the chain selects the first symbol the OS provides and
ends at its Ventura-safe fallback. The explicit picker is separate; it does not
show a newer raw choice merely because that choice has a fallback elsewhere.

Two names sit exactly on the boundary and are safe: `apple.logo` and
`macstudio` both shipped in macOS 13.0.

## How the result is kept honest

Four pieces of code hold the audit in place:

- `SymbolFallback.name(_:_:)` picks the first candidate the running macOS
  actually ships and ends on a caller-supplied name that predates Ventura.
- `AudioOutputDeviceIcon.symbolCandidates` and
  `BluetoothDeviceRowIcon.candidateSymbols` keep their newest names first and
  their Ventura-safe name last, resolved through the same runtime check.
- `BluetoothAudioIconChoice.availableChoices` filters the explicit picker with
  the same AppKit system-symbol lookup. Its table-driven Ventura simulation
  checks all 30 custom choices and confirms unsupported saved choices resolve
  to Automatic while Automatic keeps the active-device icon path.
- `MacOS13UICompatibilityTests.testSourcesOnlyUseSymbolsTheVenturaAuditCovers`
  re-reads the CoreGlyphs table on the test host, rescans every literal under
  `Sources`, and fails by name when a symbol newer than macOS 13.0 is not on the
  audited list above. The test skips, rather than guesses, on a host without the
  table.

Adding a post-Ventura glyph without a fallback therefore fails the suite instead
of shipping a blank icon to a Ventura user.

## Regenerating the lists

The CSVs used while auditing live outside the repository, in
`dist-test/`: `sf-symbols-ventura-available.csv`,
`sf-symbols-after-ventura.csv`, `sf-symbols-all-availability.csv`, and
`sf-symbols-used-by-status-trio.csv`. They are generated by joining
`name_availability.plist` with the string literals under `Sources`, and they are
reproducible on any Mac that still carries the bundle.
