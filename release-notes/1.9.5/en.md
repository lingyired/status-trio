# Version %VERSION% (Build %BUILD%)

### Panel & Bluetooth Audio

- AirPods now support Spatialize Stereo and Conversation Awareness.
- Added listening-mode switching for Redmi / Xiaomi earbuds.
- Fixed earbuds still showing "Connected" for about two minutes after being put back in the case.
- Fixed a single click on the status icon refreshing the panel instead of closing it, in regular mode, menu-bar-only mode, and when clicking the icon's edge (#224).
- Smoother scroll-wheel volume: it updates per event with a short easing on the slider, and each step is 1/16 to match the system volume keys.

### Battery & Power

- Battery remaining runtime now shows in the status panel and details, and details also show battery temperature (#298).
- "Maximum capacity" now uses the system health percentage to match what macOS shows (#317), and falls back to system info when the condition can't be read.
- Power breakdown splits USB output by port and names each accessory; fixed losing the whole USB output when the charging port hits the 300W cap, and fixed missing built-in display power on some models.
- Macs without a battery now show a full ring, with the top indicator switchable between bolt and plug (#310); the full ring only applies while connected to power (#318).
- "Charge to Full Now" now matches native behavior, and the extra restore-limit UI is gone.
- Power sampling and nearby Bluetooth scanning pause while the display sleeps and resume on wake, saving energy (#300).
- The power-mode segmented control now uses a translucent background to fit Liquid Glass.

### Icons & Appearance

- Added an option to use black & white icons while charging and connected (#309).
- The battery top indicator can now be configured separately per usage state (on battery / charging, etc.) (#315).
- Fixed the menu-bar top ring part being misaligned and drifting (#30).
- Fixed the Dock charging-animation icon shrinking to half size on 1x displays (#303).

### Displays & Brightness

- Brightness settings let you pick a BetterDisplay display manually, and hint at switching by hand when brightness is unavailable (#313).
- Fixed brightness being unavailable when an external display's identity is ambiguous (now falls back to the only external display).

### Network & Input Source

- Added a "confirm before turning off Wi-Fi" switch (#305).
- The Pinyin input-source indicator distinguishes Simplified and Traditional Pinyin; the 简/繁 marker is now optional and can show 中.

### Other

- Fixed the output device list disappearing when a volume read fails (#296).
