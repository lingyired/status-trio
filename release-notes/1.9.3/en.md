# Version %VERSION% (Build %BUILD%)

### Settings

- Redesigned Settings so categories are clearer and easier to find; icon-related settings are grouped under "App Icon".
- Added a Brightness page: choose per display whether it appears in the status panel, and optionally use BetterDisplay as the brightness backend (#241, #239).

### Panel

- Volume and brightness now use a unified capsule slider: click or drag to adjust, and volume, brightness and audio input all support scroll adjustment (#245, #213, #256).
- Fixed a brief CPU spike when adjusting volume (#263).
- Stabilized the panel's dynamic height and scroll layout (#283).
- Added a "Return to the main page on every open" option (#262).
- Fixed the status panel not disappearing when clicking the Settings window after opening Settings (#267).
- Added a gear button to the brightness row that opens the system Displays settings; the brightness scroll wheel now applies immediately.

### Menu bar and icons

- Added a "Charging status inside the ring" option: the top ring stays, and the center icon switches to the charging state when plugged in (#253).
- Fixed the left-side gradient tail left behind when the charging animation crosses the top gap (#254).
- Aligned the Dock icon's base plate to the system grid so it no longer looks bigger than other apps (#260).

### Battery and power

- Added High Power Mode, switchable with one click like Low Power Mode (#235).
- Added automatic Low Power Mode (#246).

### Wi-Fi and network

- Added a power switch to the Wi-Fi summary row (shown by default); turning off a connected network asks for confirmation (#252).
- Wi-Fi name permission: the details page now uses an obvious button and the Network settings page has a permission section at the top; without location permission it prompts and can request it directly (#247, #276).
- Fixed high CPU / hangs after opening the Wi-Fi details page (#259).

### Bluetooth, Apple Watch and AirPods

- Improved AirPods battery display and fixed crossed values (#248).
- Improved Apple Watch battery display and discovery diagnostics (#249).
- Fixed the device list still showing cached devices and connection badges after Bluetooth is turned off (#265).
- Note: Bluetooth battery fixes (AirPods, Apple Watch and related) are still being followed up and will keep improving in later releases.

### Installer

- The installer now uses the new drag-to-install page (bilingual instructions with an arrow guide) (#244).

### Fixes

- Fixed an occasional issue when reading pipes as a monitoring process exits (#268).
- The listening mode switch now also takes effect for Huawei earbuds.
