# Version %VERSION% (Build %BUILD%)

### New Features

- Input-source icon: The center connection icon can show the current input method or input source. Selecting its row opens the macOS input-source picker. You can change this in the app's Settings > Network.
- Global shortcut: Set a custom shortcut to open or close the status panel from anywhere.
- Bluetooth switch: Turn Bluetooth on or off directly from the status panel without opening System Settings.
- HUAWEI FreeBuds listening modes: Switch between Noise Cancellation, Transparency, and Off over a Bluetooth connection.
- Dock charging animation: The Dock can show its own charging animation, synchronized with the menu-bar animation.

### Experience Improvements and Fixes

- Input-source icon rendering: Fixed missing or undersized icons in the menu bar and Dock for input sources that use PDF icons, such as WeType.
- External display volume: Volume controls now match the display associated with the current default audio output, with improved DDC compatibility.
- Audio panel: Restored a compact layout and improved synchronization between the microphone volume slider and device state. Fixed missing listening-mode controls on some AirPods after their audio route becomes ready.
- Panel control alignment: Aligned buttons and controls across the battery, network, Bluetooth, and audio sections.
- Menu-bar icon guide: Improved icon location and navigation to System Settings, and fixed repeated flashing of the guide highlight.
- App activation: Fixed how the status panel and Settings window open when the app is activated through the Dock, Finder, or Spotlight.

### Performance and Stability

- Optimized charging-animation caching and scheduling to reduce CPU use during continuous playback.
- Memory used by Bluetooth monitoring, panel subscriptions, previews, and image caches is now released when the corresponding interface is closed or no longer visible.
- Improved Bluetooth permission handling, the power helper, system-command timeouts, and app lifecycle management for more stable long-running operation.
