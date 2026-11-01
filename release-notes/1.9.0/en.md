# Version %VERSION% (Build %BUILD%)

### Battery

- Added an optional "split" mode for the battery ring. When the top gap shows a bolt, plug or percentage, the left visible half now reads 0–50% and the right half 50–100%, so levels between 40% and 60% no longer hide behind the gap. It is off by default and applies to both the menu bar and the Dock.
- Battery icon colours can now follow custom status colours, with a separate choice for the connected indicator (bolt, plug or percentage). The menu bar and Dock share one scene.
- The battery details page now shows a power-flow breakdown (built-in display, USB/accessory output, and system) and an optional live power info bar. Accessory output is read from the SMC port rails where available.
- Added a "Restore Limit After Cancelling" setting for Charge to Full Now, and clearer states when macOS itself starts the temporary override.

### Power

- The centre slot can show live whole-machine power instead of a connection source, and Macs without a built-in battery are fully supported.

### Displays

- Added display brightness control: external displays use direct DDC, and built-in displays are driven directly through DisplayServices, so BetterDisplay is no longer required for built-in screens.

### Audio

- Input and output devices can be reordered, hidden, and limited in count. A lone listening-mode-capable device keeps its noise-control buttons even when other outputs are hidden.
- The scroll-wheel volume feedback can be configured separately, and re-clicking the selected listening mode turns it off.

### Panel

- The status panel now uses a squared-off, notchless style, adds a bottom "more" menu, and adapts size and layout better under Liquid Glass.

### Fixes

- Restarting during a Charge to Full Now session keeps the originally derived restore limit instead of falling back to 100%.
- Closing the status panel releases its power-info-bar sampling; the icon keeps sampling at 2 seconds only while it is showing power.
- Toggling the power info bar while the panel is open now uses the new value immediately.
- A verified battery power-flow split is no longer dropped as soon as the Mac is unplugged.
- Hot-plugging a display refreshes the brightness list and drops the stale DDC connection.
- An unconfirmed DDC brightness write now shows an unavailable message instead of losing both the slider and the explanation.
- Wi-Fi connection information is still shown when Location permission is unavailable.
