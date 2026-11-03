# Version %VERSION% (Build %BUILD%)

### Menu bar

- Configurable right-click quick actions on the status item (#209).
- Wi-Fi shortcuts added to the shortcut row: toggle Wi‑Fi, refresh, and open Wi‑Fi settings (#209).

### Panel

- Selectable panel background: liquid glass, solid, or classic material (#233).
- The panel now caps itself to the screen and scrolls tall content instead of overflowing (#237).
- When docked to the Dock, the panel hugs the Dock edge and keeps clear of a visible auto-hidden Dock (#229).
- Bluetooth device rows show the last known devices instantly on reopen while battery levels refresh in the background (#232).
- The Bluetooth subtitle hides until the first device read, and rows stay steady until battery levels land (#232).
- The power info bar is skeleton-reserved until the first read, removing the open flash; the reveal fade is shortened (#232).
- The panel shows battery discharge direction in the power info bar, says "no adapter" on battery, and styles the discharging battery source orange (#230).
- The charger-input card gets an adaptive silver surface (#238).
- Reduce-transparency fill is resolved against the effective appearance (#234).

### Battery

- The details page keeps the "Charge to Full Now" action; only the summary is gated (#231).
- Cancelling "Charge to Full Now" now restores the configured limit (#243).

### Displays

- DDC brightness now recognizes framebuffers by property with a name-agnostic fallback, including framebuffers registered as AppleCLCD2.

### Fixes

- Improved Wi‑Fi connected checkmark contrast (#242).

### Install

- The release DMG now ships a native bilingual install page.