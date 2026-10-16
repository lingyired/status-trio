# On-demand battery details

Open the **Battery** page in the popover to view additional battery information.
The popover's battery row is the affordance: it carries a chevron and switches the
popover to a dedicated page with a back row, matching the Wi-Fi and Bluetooth rows.
Collection runs on a serial utility queue only while that page is visible,
refreshing every 15 seconds with 3 seconds of scheduling tolerance. Repeated
requests coalesce into one follow-up read. Leaving the page discards outstanding
results and cancels the collector's refresh loop; it adds no permanent polling timer.
The store explicitly deactivates collection when the popover closes, even while
its hosting view is retained, and reports the open page through
`hasActivePopoverDetails` so the popover does not reopen on the battery page.
Expired power is also removed on refresh requests while an earlier read is blocked.
The existing battery icon monitoring is unchanged.

## Meaning and sources

- **Adapter rating** comes from `IOPSCopyExternalPowerAdapterDetails` and
  `kIOPSPowerAdapterWattsKey`. It is not measured charging power.
- **Time remaining** uses `IOPSGetTimeRemainingEstimate`, only on battery power.
  Unknown/unlimited estimates remain unavailable; private `TimeRemaining` values
  are deliberately not used as a fallback.
- **Low Power Mode** uses the existing `ProcessInfo`-backed battery status.
- **Power** is one row whose source follows the power connection, not whether
  the battery is actively charging. On external power it shows **System power
  (estimate)** from SMC `PSTR` (system total), the same sensor used by Stats.
  On battery it shows **Battery discharge (estimate)**, the magnitude of net
  battery discharge. An idle battery at an 80% charge limit therefore no longer
  makes the primary power row show 0 W while plugged in. Missing system telemetry
  stays unavailable; the UI never substitutes a battery value or adapter rating.
- **Charging (estimate)** is a separate green row that appears only when the
  battery current is positive on external power. The primary row keeps describing
  the selected source, so charge power is never mixed into the system total. An
  idle battery at a charge limit shows no charging row, which is the state this
  page previously mislabeled as 0 W battery power.
- **Battery power** internally remains an estimate of net power entering/leaving the battery,
  computed from `Voltage` (mV) and signed `Amperage` (mA) from one
  `AppleSmartBattery` registry snapshot. It is not total Mac power consumption.
  It is not used as a fallback for a missing system-power sensor.
- **Battery voltage**, **battery current**, **sample time**, and **cycle count** are best-effort
  registry diagnostics. No battery health percentage is inferred from capacity
  ratios, and no `system_profiler`/`ioreg` subprocess is launched.

System power is read only for a Mac with a present battery on external power and
while the page is open, on the existing serial utility queue. Each read opens and
closes its own AppleSMC connection and sends only read-key-info (9) and
read-bytes (5) commands for `PSTR`. Supported encodings are `flt `, `fpe2`, and
`sp78`. Missing keys, failed IPC/firmware replies, unexpected sizes/types,
non-finite, nonpositive, and implausible (>1,000 W) readings stay unavailable.
Battery *reading* uses no privileged helper, sensor enumeration, persistent
connection, or additional polling loop. Writing Low Power Mode does: it is
handled by a separate opt-in privileged helper (see
[privileged helper](privileged-helper.md)), which is unrelated to this read path.

The timestamp follows the selected source: **System read at** records when the
SMC read started (SMC provides no hardware timestamp); **Battery sampled at**
uses the registry's `UpdateTime`. Both expire after 90 seconds, reject dates
more than five seconds in the future or before a power-state transition, and
are checked again before publication after delayed IPC. Battery voltage/current
remain explicitly labeled diagnostics with their own hardware update cadence.

AppleSMC exposes no "not sampled yet" signal, so it cannot be told apart from a
Mac that has no usable `PSTR` at all: a page on external power without a system
reading says **Unavailable**, never **Sampling…**. The battery path can tell the
difference, because `AppleSmartBattery` reports the previous power source while
macOS catches up, so only that row shows **Sampling…** during a transition.

IORegistry access is a public API, but these registry properties and the AppleSMC
sensor interface are not Apple-supported cross-model contracts. Neither estimate
is a wall-outlet measurement. Unsupported sources display unavailable rather
than a fabricated zero. A battery sample is rejected if fields are missing/implausible,
its charge state disagrees with the current battery state, its timestamp is more
than 90 seconds old or over 5 seconds in the future, or it predates an observed
power-state transition. Zero current while unplugged is treated as unavailable
because it can be a transitional reading. Zero current while connected to power
is retained internally as 0 W: the battery is neither charging nor discharging, which is
the normal state when macOS holds charge or the battery is full. Negative 64-bit
integer current is supported, including unsigned NSNumber representations of the
same bit pattern.

The hardware's sampling interval can be about a minute; the interface shows the
sample time rather than promising live per-second watts. Hardware validation so
far covers one Apple silicon Mac on battery. Charging transitions and other Mac
models still need field validation before making broad accuracy claims.

## Transition wording

After a power-source change the registry can keep reporting the previous source
for up to about a minute. That window is reported as **Sampling…** rather than
**Unavailable**: the reader distinguishes a lagging registry, a rejected
pre-transition sample, and an expired reading from telemetry this Mac does not
expose at all. Insufficient adapter power may produce negative battery current while connected;
the primary row still uses system power because the power source is connected.

Apple references:
- [IOPSCopyExternalPowerAdapterDetails](https://developer.apple.com/documentation/iokit/1523866-iopscopyexternalpoweradapterdeta)
- [IOPSGetTimeRemainingEstimate](https://developer.apple.com/documentation/iokit/iopsgettimeremainingestimate())
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)

SMC reference (protocol and sensor identity, not a supported Apple API):
- [Stats PSTR sensor definition](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift)
- [Stats AppleSMC wire layout](https://github.com/exelban/stats/blob/master/SMC/smc.swift)
