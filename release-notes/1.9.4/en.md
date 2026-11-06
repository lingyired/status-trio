# Version %VERSION% (Build %BUILD%)

### Battery & Power

- Battery details now show system maximum capacity, battery condition, and system uptime.
- High Power Mode now always appears as its own clear row in battery details, reading its state from pmset; unknown health and high power states are shown explicitly.
- When "Optimized Battery Charging" pauses charging at a 100% limit, "Charge to Full Now" now works: the request is sent the way macOS does it, and completing it does not restore the previous charge limit (#292).
- The details and Settings pages now explain why "Charge to Full Now" is unavailable or hidden (#280, #292).
- Settings explains that a 100% limit can still pause charging because of Optimized Battery Charging (#292).

### Brightness & Displays

- External displays gain an Automatic brightness backend: use BetterDisplay while it is running, otherwise direct DDC; an explicitly chosen backend is remembered and never overwritten.
- Built-in display brightness changes from keys, Control Center or Settings are now reflected in the panel immediately (#286).
- While the panel is visible, external display brightness refreshes at a bounded 2-second interval so keyboard changes reach the panel promptly.
- Fixed stutter when dragging DDC brightness, and correctly identify external displays so the built-in screen is not driven as an external one (#284, #285).

### Wi-Fi & Network

- Added a Clash Verge TUN power toggle: TUN is identified through the Mihomo read-only API, bare tunnels show as "TUN" instead of "VPN", and the toggle state stays in sync (#272).
- Refined the Wi-Fi summary row power switch visibility and the confirmation scope before turning a network off (#252).

### Input Source

- Fixed uppercase not being kept when Caps Lock and Shift are both on; the indicator now correctly shows a/A (#279).

### Bluetooth

- Added custom Bluetooth icon colour (#275).
- Stale battery readings from disconnected Bluetooth devices now expire instead of lingering.

### Panel & Settings

- Aligned the battery settings row hover decoration with the clickable button bounds and added breathing room (#281).
- Restored the rounded cards in the power flow diagram and masked the ribbon overflow (#282).
- Restored the original slider component for refresh intervals in Settings (#255).

### Performance & Stability

- Tightened monitoring thread lifetimes and polling cadence to reduce background cost and improve stability (#294).
- Refreshed cached output devices when the audio device topology changes (#293).
- Addressed performance and stability issues across icons, panel, Settings and monitoring.
