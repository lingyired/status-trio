# Version %VERSION% (Build %BUILD%)

### Battery & Power

- Battery details now include system maximum capacity, battery condition, system uptime, and High Power Mode state.
- When "Optimized Battery Charging" pauses charging at a 100% limit, you can now "Charge to Full Now"; when it is unavailable, the details and Settings pages explain why (#292, #280).

### Brightness & Displays

- External displays gain an "Automatic" brightness backend: use BetterDisplay while it runs, otherwise direct DDC.
- Built-in display brightness changes from keys, Control Center or Settings now refresh the panel immediately (#286).
- While the panel is open, external display brightness adjustments are also reflected in the panel promptly.
- Fixed stutter when dragging DDC brightness, and correctly identify external displays (#284, #285).

### Wi-Fi & Network

- The summary row for system VPN services now has a power switch; Clash Verge TUN connections are no longer shown as "VPN" but correctly as "TUN" (labeled Clash Verge when applicable), and that row stays read-only with no switch (#272).

### Input Source

- The ABC input-source indicator now shows a/A according to letter case (#279).

### Bluetooth

- Improved the ghost-device issue for Bluetooth devices (#248).
- Added custom Bluetooth icon colour (#275).

### Panel & Settings

- Refined the battery settings row hover and clickable area (#281).
- Refined the power flow diagram's corner styling (#282).
- Status refresh interval is now set separately for "On Battery / Plugged In" (#255).

### Performance & Stability

- Reduced background refresh frequency and resource usage, lowering power draw and improving stability (#294).
- Fixed the output device list not refreshing after switching audio devices (#293).
