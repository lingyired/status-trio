# Version %VERSION% (Build %BUILD%)

## New Features

- Added a Memory Pressure option to the bottom indicator for an at-a-glance view of current memory usage.
- Disk details now list all mounted volumes (internal and external) with read/write speed per volume; the top percentage can optionally include external SSDs.
- The four hardware monitor rings can now split progress to both sides, so the top percentage no longer covers the ring.
- Added an Open Activity Monitor button to the hardware details page for quickly finding what is using resources.
- The high-usage / high-energy list now supports locking a row and force quitting it (including its child processes); cards show a refresh countdown and the item is removed immediately after it exits.

## Fixes

- Fixed the M3 Air GPU temperature that could not be read, and prevented the same zone from being counted twice.
- Optimized the CPU temperature calculation for M5 / M6.
- Added A18 Pro identification; unrecognized chips now show as unavailable instead of a wrong temperature.
- Fixed a case where some models still showed a 0.00 W display power without a real reading.
- Display power is now hidden when no real reading is available, instead of showing an estimate; stale values are no longer left when the screen is off or the lid is closed.
- 0 W display and USB power are no longer shown as real power.
- Fixed the first lid-sleep read failing on cold start; it now retries automatically.
- Fixed a false timeout where the app gave up before the background service; failure messages now include an error code for troubleshooting.
- Hid the volume slider when no audio device is available and show a "No devices available" hint instead.
- Polished some English copy and long text so it is no longer truncated.
