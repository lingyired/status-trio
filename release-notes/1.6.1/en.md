# Version %VERSION% (Build %BUILD%)

### Fixes

- External display volume (DDC/CI): the read request sent to a display is now chosen by probing the two common request checksums and read addresses against the display that macOS has selected, instead of assuming a single fixed request. Displays that previously reported no volume may now work.

### Notes

- Only the display behind the current default audio output is ever contacted, and nothing is written to a display until a read from it has been validated. Outputs that already expose a writable system volume still use it and never touch DDC.
