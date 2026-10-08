# Version %VERSION% (Build %BUILD%)

### Improvements

- Improved consistency of status panel updates while preserving the existing controls, layout, and navigation.
- Improved reliability of panel presentation as device, network, and audio status changes.
- When the currently connected Wi-Fi network is recognized as a Personal Hotspot, it appears in its own "Personal Hotspot" section, with a hotspot icon, connected checkmark, and connection details. Discovery and grouping of unconnected networks are unchanged.

### Privacy

- Added optional usage statistics. On new installs the choice defaults on, but no heartbeat is sent until you finish the guide or choose Customize. Upgrades stay off until enabled in Settings.
- The heartbeat contains a random installation ID plus app/macOS versions, system and app language, and icon placement. See [telemetry and privacy](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md) for the full details.
- No third-party analytics SDK is included.
