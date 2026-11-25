# Version %VERSION% (Build %BUILD%)

## Fixes

- Fixed a false "unable to read the keep-awake-with-lid-closed state" error (code DS-R4) on Macs that had never enabled lid-close sleep. macOS only lists the setting after it has been used once, so the app now treats a missing value as off instead of a read failure.
- The keep-awake-with-lid-closed toggle now shows the correct initial state and works on the first click on those Macs, without running `sudo pmset -a disablesleep` manually.
