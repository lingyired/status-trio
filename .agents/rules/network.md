# Network rule

Read this before changing Wi-Fi, Ethernet, VPN, location-gated SSID, or Settings
pane routing code.

- Wi-Fi settings use `com.apple.wifi-settings-extension` first; wired settings
  use the Network extension. Never choose the route from the running macOS
  version.
- Preserve the Location permission boundary. Do not log or persist SSIDs beyond
  the existing presentation path, and never read or store Wi-Fi passwords.
- Run the focused network tests and `StatusMenuBuilderTests` for route changes.

See `docs/settings-pane-routes.md`, `docs/wifi-status-responsiveness.md`, and
`docs/vpn-status.md`.
