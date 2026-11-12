# Network rule

Read this before changing Wi-Fi, Ethernet, VPN, location-gated SSID, or Settings
pane routing code.

- Wi-Fi settings use `com.apple.wifi-settings-extension` first; wired settings
  use the Network extension. Never choose the route from the running macOS
  version.
- Preserve the Location permission boundary. Do not log or persist SSIDs beyond
  the existing presentation path.
- In-app join is opt-in (`SettingsStore.joinsWiFiInApp`, off by default, asked once in
  the first-launch guide, excluded from settings transfer; turning it off deletes
  the saved passwords) and limited to open and personal networks
  (`WiFiSecurityKind.canJoinInApp`); every other row, and every row while it is
  off, opens System Settings. The
  row action must never depend on `isKnown` (that caused the removed 1.2.0 loop).
- Wi-Fi passwords: never read the macOS keychain or macOS-saved passwords, and
  never log a password or put it in published state, the environment, analytics
  or settings export. The only persisted copy is the one the user typed, saved
  after a successful join by `FileWiFiPasswordStore` as plain text at
  `~/.status-trio/wifi-passwords.json` (`0700` directory, `0600` file). Keep all
  access behind `WiFiPasswordStoring` and off the main actor. See
  `docs/known-limitations.md`.
- Run the focused network tests and `StatusMenuBuilderTests` for route changes.

See `docs/settings-pane-routes.md`, `docs/wifi-status-responsiveness.md`, and
`docs/vpn-status.md`.
