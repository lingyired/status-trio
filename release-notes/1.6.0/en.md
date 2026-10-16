# Version %VERSION% (Build %BUILD%)

### New Features

- Low Power Mode control: an optional switch in the battery details turns Low Power Mode on or off without opening System Settings. It requires a one-time approval in System Settings › General › Login Items under "Allow in the Background", and the helper it registers does nothing else, runs only while the app is using it, and exits itself when idle. The approval hint stays under the control, and the whole row opens Login Items.
- Full ring level: choose the charge level at which the battery ring counts as full (50%–100%, default 100%). Useful on a Mac whose charge limit holds the battery below 100%; "Use the charge limit" fills the slider in from the system. The menu bar and the Dock follow together.
- Local IP address: an optional Network setting that shows this Mac's private LAN address on the network row's second line, before the Wi-Fi details. Off by default.
- Internet Sharing: the Wi-Fi and wired details pages can open the Sharing pane directly, where Internet Sharing is switched on. The app opens the pane; it does not switch sharing on or off itself.

### Fixes

- Wi-Fi signal: bridge CoreWLAN's intermittent invalid readings, so a connected icon no longer dims or reads 0 bars.
- Bluetooth device icons: draw the glyph only from the class the device itself declares (`device_minorType`), so connecting or disconnecting no longer changes it. When a vendor misdeclares a device's class — a keyboard reporting itself as a mouse, for example — the icon follows that declaration, and the app no longer corrects it.
- Menu bar icon: the monochrome chrome re-tints live while a Space is being dragged.
- Icon alignment: centre SF Symbols by their measured ink instead of their layout box, so the Wi-Fi glyph no longer sits off-centre in the ring.
- Audio: removed the duplicated volume output summary row.

### Notes

- While a Space switch is being dragged, only an icon that is monochrome throughout follows the target Space; the primitives that carry a status colour (low battery, Low Power Mode, connected power, Bluetooth) settle once the switch commits.
