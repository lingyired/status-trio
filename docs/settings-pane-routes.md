# System Settings pane routes

Every pane a settings control can open is a separate Settings extension with its
own URL. This file records how the Wi-Fi route was lost twice, and how to verify a
route without a screen-recording or accessibility grant.

## The routes

| Control | First route | Pane it opens |
| --- | --- | --- |
| Wi-Fi gear, Wi-Fi row | `x-apple.systempreferences:com.apple.wifi-settings-extension` | Wi-Fi (`Wi-Fi.appex`) |
| A wired row's gear | `x-apple.systempreferences:com.apple.Network-Settings.extension` | Network (`Network.appex`) |
| Wired row's **Share Internet…** | `x-apple.systempreferences:com.apple.Sharing-Settings.extension` | Sharing (`Sharing.appex`) |
| Input-source section's **Keyboard Settings…** | `x-apple.systempreferences:com.apple.Keyboard-Settings.extension` | Keyboard (`KeyboardSettings.appex`) |

`com.apple.Network-Settings.extension?Wi-Fi` is **not** a Wi-Fi route. It opens the
Network pane — the list of network services — and its `?Wi-Fi` anchor does not
select the Wi-Fi section on macOS 15.

## Incident: the Wi-Fi route was dropped twice

1. **2026-09-17 — the fix for issue #27 was overwritten by a merge.** `0c20389`
   (`fix(wifi): open the Wi-Fi settings pane`) put
   `com.apple.wifi-settings-extension` first. A parallel branch had already
   reached the same region with a `majorVersion >= 27` branch instead
   (`76297b9`, `fix: open Wi-Fi settings directly`). The merge `6404ca4` resolved
   the region in favour of the version branch, so the fix never reached a
   release: **1.2.0 and 1.3.0 shipped the version branch**, every user on macOS 15
   through 26 landed on the Network pane, and macOS 27 was correct — which is why
   the maintainer's own machine looked fine and the report came back a release
   later.
2. **2026-09-20 — the re-fix was never merged.** `a07cb46` (`fix: open the Wi-Fi
   pane instead of the Network pane on macOS 15`) removed the version branch
   again, but it stayed on `fix/wifi-settings-pane`, 145 commits behind `main`
   and in no tag. 1.3.1 re-applies it.

The lesson is in the second failure: a merged fix is not a shipped fix. Confirm a
route in a tagged build, and read the pane order out of the shipped binary when a
report comes in.

## Verifying a route

System Settings launches even for an unknown pane identifier, and `open` still
exits 0, so an exit status proves nothing. Each pane is its own ExtensionKit
process, so ask which extension came up:

```bash
open "x-apple.systempreferences:com.apple.wifi-settings-extension"
sleep 3
pgrep -fl "ExtensionKit/Extensions" | sed -E 's/ -BSServiceDomains.*//'
```

Measured on macOS 27.0 (26A428):

| Opened route | Extension process |
| --- | --- |
| `com.apple.wifi-settings-extension` | `Wi-Fi.appex`, launch args `serviceName = com.apple.wifi-settings-extension`; `Network.appex` never started |
| `com.apple.Network-Settings.extension?Wi-Fi` | `Network.appex` |
| `com.apple.Sharing-Settings.extension` | `Sharing.appex` |
| `com.apple.Keyboard-Settings.extension` | `KeyboardSettings.appex` (measured on 27.0.1, 26A434). The Keyboard pane lists the input sources the section manages, so its own extension identifier comes first; `StatusMenuBuilderTests.testSystemSettingsURLFallbackOrder` pins the order and there is no `majorVersion` branch. |

`screencapture` fails without a screen-recording grant (`could not create image
from display`) and `log show` returns nothing in a sandboxed shell, so the process
list is the usable evidence.

## Not yet measured

Whether macOS 15 and 26 accept `com.apple.wifi-settings-extension` was never
tested on those systems. The identifier is not version-specific: `Wi-Fi.appex`
carries `BuildMachineOSBuild 23A344017` (a macOS 14 build machine) and
`allowsXAppleSystemPreferencesURLScheme = true`. Re-check on macOS 15 if this
route changes again.
