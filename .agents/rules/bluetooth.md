# Bluetooth rule

Read this before changing Bluetooth monitoring, battery readers, device
classification, listening-mode controls, nearby BLE discovery, or their tests.

- Keep `IOBluetooth`, `CoreBluetooth`, and HID paths behind their existing
  demand and permission boundaries. Do not widen scanning or retain hardware
  objects after the owning surface disappears.
- Test permission denial, unavailable hardware, empty lists, and device
  disconnect paths, not only the connected happy path.
- Run focused Bluetooth tests and, for lifecycle or callback changes, the full
  local profile.

See `docs/bluetooth-status.md`, `docs/apple-device-battery.md`, and
`docs/apple-watch-first-read.md`.
