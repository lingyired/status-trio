# Version %VERSION% (Build %BUILD%)

### New Features

- Added an opt-in Nearby section that reads battery levels from nearby BLE devices providing the standard Battery Service.
- Added a battery panel action setting to open Battery Settings, AlDente, BatFi, a selected app, or a custom URL. Unavailable targets fall back to Battery Settings.

### Improvements & Fixes

- Nearby scanning is off by default, runs only while the Bluetooth status panel is visible, and leaves paired-device information unchanged. Support varies by device; iPhone and iPad battery readings are not guaranteed.
