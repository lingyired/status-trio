# Version %VERSION% (Build %BUILD%)

### Battery

- The battery details page now shows a power-flow breakdown (built-in display, USB/accessory output and system) plus an optional live power info bar. Accessory output is read from the SMC port rails where available.
- Added a "Restore Limit After Cancelling" setting for Charge to Full Now, with clearer states when macOS itself starts the temporary override.
- Battery icon colours can follow custom status colours, with a separate choice for the connected indicator (bolt, plug or percentage). The menu bar and Dock share one scene.
- Added an optional "split" mode for the battery ring: when the top gap shows a bolt, plug or percentage, the left arc reads 0–50% and the right arc 50–100%, so 40–60% is no longer hidden. Off by default; applies to the menu bar and the Dock.

### Power

- The centre slot can show live whole-machine power instead of a connection source, and Macs without a built-in battery are fully supported.

### Displays

- Added display brightness control: external displays use direct DDC and built-in displays are driven directly through DisplayServices.

### Middle icon

- The middle-slot source is now one "Middle Icon" selector: network, Bluetooth device, current input source, battery percentage, or power. The two network-error switches are merged into one that covers every source, the non-working Bluetooth "replace network icon" toggle is gone, and old stored values migrate automatically.
- Fixed the middle icon not being vertically centred.

### Guide

- Polished the onboarding guide.

### Audio

- Input and output devices can be reordered, hidden and limited in count.
- The scroll-wheel volume feedback can be configured separately, and re-clicking the selected listening mode turns it off.

### Panel

- The status panel uses a squared-off, notchless style to match the macOS menu-bar panel, adds a bottom "more" menu, and adapts size and layout better under Liquid Glass.

### Fixes

- Wi-Fi connection information is still shown when Location permission is unavailable.
