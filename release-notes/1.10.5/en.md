# Version %VERSION% (Build %BUILD%)

## Sensors & Temperatures

- M3 Air (Mac15,12) GPU temperature works again: the unreadable Tf sensors are replaced by the verified-readable Tg sensors, grouped as six pairs so one physical zone is not counted twice.
- M5 and M6 CPU temperatures now group probes that belong to the same core; multiple probes no longer inflate the core count or the average.
- Added A18 Pro identification. Unknown chips no longer borrow another generation's temperature keys; they show no reading instead of a plausible but wrong number.

## Display Power

- Fixed Issue #374: an M3 Air with no PDBR and a PBLR stuck at 0 no longer shows a 0.00 W display branch.
- When no measured backlight rail is usable, display power can fall back to an AppleARMBacklight estimate. The 6 V assumption is not a measurement, so the value is marked with ≈ and the system residual is marked as estimated too.
- Zero-watt display and USB branches are hidden instead of being drawn as real power.

## Monitoring & Performance

- Sensor capability is probed once and cached; keys that do not exist back off instead of being retried on every refresh.
- No new background timers, helper or privileged access. Temperature and backlight collection still stops when the relevant panel closes.
