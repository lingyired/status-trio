# Version %VERSION% (Build %BUILD%)

### Battery

- Added battery power flow with estimated charger input, power flowing into the battery, and system power. Charger input is off by default; the other two readings are on by default.
- Added an optional CPU energy impact list showing up to five apps from recent samples. When energy counters are unavailable, it falls back to CPU activity and supports a 10–60 second sampling interval.
- On supported Apple silicon Macs running macOS 26.4 or later, Charge to Full Now and Cancel Charge to Full are available and enabled by default when the capability is available.

### External Displays

- Added a BetterDisplay volume control method for external displays or audio outputs whose volume macOS cannot control directly. It supports automatic or manual display association and reports connection and error states.
- Native writable volume remains preferred, Standard/DDC mode can be restored at any time, and Status Trio does not launch or change BetterDisplay settings when BetterDisplay is unavailable.

### Stability and Interface

- Improved Wi-Fi event handling by coalescing high-frequency CoreWLAN callbacks and limiting recovery frequency during abnormal states, reducing the risk of event storms amplifying CPU and memory pressure.
- The status panel now preserves the current detail page when reopened instead of returning to the root page.
- Improved the battery details layout, detail navigation, gear hit area, and live power refresh.
- Improved menu bar composition of the colored layer and template image. Unfocused displays now dim correctly while retaining system re-tinting when switching Spaces.

### Important Notes

- Charge to Full Now uses a private PowerUI interface and is available only on Apple silicon Macs running macOS 26.4 or later. There is no guarantee of behavior across macOS versions.
- After charging completes or the power adapter is reconnected, the charge limit may remain at 100%. Status Trio does not restore it automatically; use Cancel Charge to Full or restore the limit in System Settings.
- The CPU energy impact list is not total app energy usage and is not a copy of the macOS “Using Significant Energy” list.
- BetterDisplay volume control requires BetterDisplay to be running. Display volume and DDC behavior still depend on the hardware and connection.
