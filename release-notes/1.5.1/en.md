# Version %VERSION% (Build %BUILD%)

### New Features

- Now supports macOS 13 and later.
- Added optional anonymous usage statistics, off by default; turn it on yourself in Settings.
- Apple device battery: read a paired Apple Watch's battery through a connected iPhone, and show trusted Apple devices as unified rows in the Bluetooth list. Adds background battery refresh with a configurable interval, and battery is read only for selected devices that are visible in the panel.
- You can now customize the Bluetooth audio icon.

### Improvements

- Improved the icon and status panel update logic.

### Fixes

- Icon rendering: restored fidelity of cached bitmaps, steady animation resizing, the charging-bolt heartbeat tint, and menu bar and Dock alignment.
- The first Bluetooth refresh no longer opens Settings unexpectedly.

### Privacy

- Explains the optional anonymous usage statistics, what a heartbeat contains, and that no third-party analytics SDK is included. See [telemetry and privacy](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md) for the full details.
