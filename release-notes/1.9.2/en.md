# Version %VERSION% (Build %BUILD%)

### Menu bar

- Configurable right-click quick actions on the status item: show the context menu, toggle Low Power Mode, charge to full or cancel, mute, toggle Wi-Fi, refresh, or open the Wi-Fi, Bluetooth, Battery or Sound settings pane (#209).

### Panel

- Fixed the panel opening in the wrong position from the Dock icon (#229).
- Fixed the panel overflowing the screen (#237).
- Selectable panel background: liquid glass, solid, or classic material (#233).
- Reduced the stutter when opening the status panel (#232):
  - Bluetooth rows show the last known devices instantly on reopen while battery levels refresh;
  - the Bluetooth subtitle hides until the first device read, and rows stay steady until battery levels land;
  - the power info bar is skeleton-reserved until the first read, removing the open flash, with a shorter reveal fade.
- Polished the power info bar UI (#230, #238): it shows battery discharge direction, says "no adapter" on battery, styles the discharging source orange, and the charger-input card uses an adaptive silver surface.
- Reduce-transparency fill is resolved against the effective appearance (#234).
- A single status-item click now takes effect immediately when the panel is open (#224).

### Battery

- The "Charge to Full Now" button now only affects the first level of the status panel (#231).
- Fixed the error when cancelling after "Charge to Full Now" (#243).

### Displays

- Improved display brightness compatibility (#202): framebuffers are recognized by property with a name-agnostic fallback, including those registered as AppleCLCD2.

### Fixes

- Improved Wi-Fi connected checkmark contrast (#242).
