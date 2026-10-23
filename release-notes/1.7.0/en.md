# Version %VERSION% (Build %BUILD%)

### New Features

- The connection slot can now show the current input source. It follows the Wi-Fi icon scale, and selecting the row opens the macOS input-source picker.
- A configurable global shortcut can open or close the status panel from anywhere.
- The status panel can switch Bluetooth radio power without opening System Settings.
- HUAWEI FreeBuds can switch between Noise Cancellation, Transparency, and Off through their real Bluetooth connection.
- The menu-bar guide now helps locate the icon and opens the correct Menu Bar settings page on every supported macOS release.
- The Dock can show an independent charging animation that shares the menu-bar animation clock.

### Improvements

- External display volume is matched to the display behind the current default audio output. DDC reads now probe both common request formats instead of assuming one.
- AirPods listening-mode controls are rediscovered when an audio route becomes available later.
- The audio panel restores a compact layout and keeps microphone volume, readback, and input-device state synchronized.
- Charging animation work is cached and demand-driven, reducing steady-state CPU use.
- Bluetooth monitoring, panel subscriptions, previews, and image caches now release memory when their UI is no longer visible.
- Power-helper, system-profiler, networksetup, Wi-Fi authorization, telemetry, accessibility, and single-instance lifecycle paths are more resilient.

### Notes

- Nothing is written to an external display until a valid DDC read has identified it.
- The closed-panel memory footprint depends on enabled features and connected hardware.
