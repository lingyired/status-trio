# Power in the centre slot

The menu-bar and Dock icon can draw live whole-machine power in the centre slot.
It reuses the existing SMC `PSTR` read (`SystemPowerReader`) — no new sensor, no
helper, no privilege. The ring, the footer and every other icon region are
unchanged: power replaces only the centre content.

## One shared sampler

`PowerSamplingService` (owned by `SystemStatusStore`) is the only owner of
periodic system-power reads. Three surfaces register a demand instead of
starting their own timer:

| Demand | Registered by | Why |
| --- | --- | --- |
| `icon` | `StatusBarController` while the middle-slot setting is **Power** | the icon must keep updating with the panel closed |
| `panel` | `StatusPanelViewModel` while the status panel is open with the battery section visible | a Mac with no battery needs a reading for its title and entry |
| `details` | `BatteryDetailsController` while the battery details page is open | the page shows the system total |

The sampler stops only when every demand has ended. Closing the panel therefore
never cuts a sample the details page or the icon still needs. `BatteryDetailsReader`
receives the shared sample instead of opening its own system-power connection,
so the same refresh is never read twice.

Cadence is a single **2-second** rhythm for every demand: the panel, the
details page and an icon that keeps showing watts are equally live. The sampler
still stops as soon as the last demand ends.

This is not a promise of no extra wakeups: an icon that keeps showing watts
keeps a periodic read alive. A stopped sampler clears its last
value; a value that stops refreshing cannot be mistaken for a current one.

## Rendering

- The value is integer watts, no unit and no decimal point, laid out for at most
  three digits (`Int(watts.rounded())`, clamped to `0...999`).
- Every numeric centre mode (watts, the explicit **Battery Percentage** choice,
  the fallback percentage and the `--` placeholder) uses the same size rule:
  the **Wi-Fi Icon Size** setting (the centre-symbol scale). Switching between
  percentage and watts therefore never changes the number's size.
- The reading is shown only while it is fresh. There is never a fake `0 W`.
- On a Mac with a battery, an unreadable reading falls back to the battery
  percentage (the same value the previous centre-slot behaviour showed).
- On a Mac with no battery, an unreadable reading shows `--`. It never invents a
  percentage, because the value the ring would use (`BatteryStatus.percentage`
  returns `100` when absent) does not exist on that machine.

## No-battery Macs (issue #192)

The whole-machine total is the only power source a Mac mini has. The panel and
details page adapt instead of hiding the module:

- title: `Power · xx W` when a fresh reading exists, `Power · Unavailable`
  otherwise — never `Battery · 100%`;
- the details entry is enabled when there is a battery **or** a fresh power
  reading, and disabled with the reason in the subtitle otherwise;
- the details page hides voltage, current, adapter rating, time remaining,
  cycle count and charging power, keeping the power row, its timestamp, Low
  Power Mode and the sensor explanation.

`PSTR` has no cross-model contract; desktop read support is runtime-probed and
falls back to the unavailable state, never to a fabricated value.

## Provisional power info bar

A single line under the panel's battery module can show **Input / Battery /
System** power. It is **off by default** and enabled in
**Settings › Battery Display**. This bar is still under discussion; the notes
below describe what is implemented, not a frozen specification.

- Each rail is drawn as its own small card (plug / battery / laptop icon,
  label and a one-decimal wattage). A missing or stale rail is absent, and the
  bar hides when none is fresh. The three values are never added into a total.
- A Mac with no battery hides the **Battery** rail.
- It rides the same shared sampler as the icon and details page. Its demand is
  released when the panel closes or the option is switched off, and that must
  never interrupt an icon or details demand that is still live. Because it needs
  the input and battery rails, the sampler reads them only while this demand is
  registered; otherwise it reads the whole-machine total alone.
- Current rhythm is the same 2-second cadence as every other surface.
- Deliberately **not decided** here (left for discussion): 3–5 s panel refresh,
  5 s icon refresh, first-frame cache, cache-expiry threshold, and placeholder
  strategy. No cache or placeholder is implemented yet; only fresh readings are
  drawn.

## Verification status

- Unit coverage: sampler demand/cadence lifecycle, settings migration, mapper
  rendering (integer/three-digit/fallback/placeholder), no-battery panel title,
  entry availability, details rows, and the icon view model repainting from a
  shared sample.
- `bash scripts/verify-local.sh full` — recorded in the change's delivery notes.
- **NOT RUN**: a real Mac mini (no battery) runtime check; this workstation has
  a battery. The panel title, entry state and details rows for that case are
  proven by unit tests and previews only. The menu-bar accessibility value still
  describes battery/network/volume, not the centre watts.
