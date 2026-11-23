# Version %VERSION% (Build %BUILD%)

### System Monitor

- The status panel now monitors CPU, GPU, memory, network, disk, and fan speed; click any of them to open its detail page.
- Custom colors for the CPU, GPU, memory, network, disk, and fan-speed metrics.
- Customize the update interval and the history time range.
- System monitor samples on demand: metrics are read only while actually shown, and background history is off by default, reducing background load.

### Menu Bar Icon & Ring

- New system-monitor data sources for the outer ring, with single-ring and left/right dual-ring layouts. Ring arcs can use CPU usage, CPU temperature, GPU usage, GPU temperature, memory usage, battery temperature, battery level, fan speed, download speed, upload speed, volume, and Wi-Fi signal.
- The ring's battery-level arc follows the system battery colors, and a new "Discharging (not on power)" color role lets you customize charging, low, high-power, critical, and discharging colors separately (#357).
- New AirPods mode for the top indicator: the dual rings can show the left and right earbud battery (single-ear supported), and fall back to the Mac battery or a custom ring when disconnected.
- The bottom indicator supports a custom data source: volume, Wi-Fi signal, or battery level (or hidden).

### Panel & Interaction

- Hover the menu bar icon to reveal the panel; click to pin it (#355).
- Details now open in a side panel next to the status panel, with smoother switching.
- Added the hardware-monitor card.
- Refined the numeric sliders (volume and brightness) with a look closer to macOS 26+ and smoother motion; sliders support horizontal trackpad swipes (#351).
- Wi-Fi and Bluetooth icons are tinted by connection state (#352).
- The "Charge to Full Now" button gained a liquid-glass hover sheen.
- Removed bold text in the status panel; values and units use a monospaced font.

### Keep Awake & Sleep

- Added "Keep Screen On" and "Lid-Sleep Off", each with a customizable duration (#295).

### Brightness

- Added the "Use BetterDisplay combined brightness" toggle (#344).

### Battery & Audio

- Fixed the trickle-charging copy and the charging row at 100%.
- Fixed muting at exactly zero volume and restoring only automatic mute.
- Fixed the time-to-full estimate to respect the macOS charge limit (#349).

### Other Fixes

- Fixed detail history not being isolated per metric kind.
- Improved background sampling and process-pipe stability, reducing panel stutter and cross-talk.
- Fixed the AirPods listening-mode row height flicker when opening the panel (#354).
