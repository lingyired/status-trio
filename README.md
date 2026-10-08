<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Eight Status Trio Dock icon states with symmetrically arranged dark and light backgrounds, including Wi-Fi, Bluetooth audio, battery, dots, and arc states">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Status Trio app icon">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>Three system signals. One native macOS status icon — in your menu bar or the Dock.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2015%2B-000000?logo=apple&logoColor=white&style=for-the-badge" alt="Download for macOS — universal build, macOS 15 or later"></a>
</p>

<p align="center">
  Want to see it in action first? Open <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a> to simulate every icon state in your browser.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="Latest release"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Build and Release macOS workflow status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="License: Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B%20supported-blue?logo=apple&logoColor=white" alt="macOS 15 or later supported">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Universal binary for Apple Silicon and Intel">
</p>

<p align="center">
  <strong>English</strong> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Status Trio menu bar icon showing the Wi-Fi glyph while connected to Wi-Fi, with its status popover open">
</p>

Status Trio is a native macOS status app that combines Wi-Fi, battery, and volume into one compact, configurable icon, shown in the menu bar, in the Dock, or in both. Its popover goes deeper than the icon: a Wi-Fi panel for nearby networks and link details, a Bluetooth panel for paired devices, a Battery Details page, and the audio devices that are playing. It is inspired by the iPhone Duo's combined status bar icon for Wi-Fi, Battery, and Cellular Data, adapted for Mac with Volume instead of Cellular Data.

> Status Trio is an independent project and is not affiliated with Apple.

## Highlights

- **One icon, three signals** — battery, Wi-Fi, and volume share one icon in the menu bar, the Dock, or both, and a Bluetooth device that is playing can take the middle spot with its own symbol.
- **Bluetooth** — the volume indicator turns blue while it plays. The panel lists paired devices you can tap to connect or disconnect, shows battery levels by default, and stays off until you enable it.
- **Battery** — percentage, charging or plugged in, time to full, and a color when it runs low. Open the row for adapter power, voltage, current, cycle count, and Low Power Mode.
- **Wi-Fi** — the network you are on and how strong the signal is. Open it to see nearby networks, check the link details, or switch Wi-Fi off. Switching between networks happens in the Wi-Fi pane of System Settings.
- **Volume** — level, mute, and the output device, drawn as dots or an arc. Scroll the whole panel or just the control, and pick which direction turns it up.
- **Make it yours** — icon size, symbol scale, ring thickness, status colors, and which sections the popover shows, in the order you want.
- **Menu bar, Dock, or both** — and the Dock icon can follow the system style or stay dark or light.
- **Native on macOS** — left-click opens the popover, right-click opens the menu, and a first-launch guide explains each part of the icon. Ethernet, a hotspot, or Internet Sharing can keep the Wi-Fi glyph if you prefer.
- **Stays current** — status comes from system events with a slow poll as a fallback, and Sparkle updates the app through a signed feed.
- **Also included** — twelve languages, and an optional launch at login.

## Bluetooth audio

While audio plays over Bluetooth, two switches under **Settings › Bluetooth** let the middle glyph become that device's own symbol — AirPods, headphones, speakers, and other devices supply their own — and let the volume dots or arc turn blue. Both are off by default. **Let network errors take priority**, on by default, keeps the network icon while the connection itself is in trouble:

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Status Trio menu bar icon showing the AirPods glyph while AirPods are connected, with its status popover open">
</p>

The popover's Bluetooth row reports live state: the names of connected devices and, for AirPods, left, right, and case battery. The Bluetooth panel lists paired devices and their connection state: tap a device to connect it, tap a connected one to disconnect — keyboards, mice, trackpads and gamepads ask for confirmation in the row first. The panel is off by default, is enabled under **Settings › Status Panel**, and asks for Bluetooth permission on first use. **Settings › Bluetooth** also controls whether the battery levels are read — on by default — lists the paired devices so you can drag them into the order the panel shows and set how many appear, and scales the Bluetooth icon from 100% to 180%.

## Dock icon

The same live icon can live in the Dock instead of the menu bar, or in both places at once:

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Status Trio live icon in the Dock with dark appearance">
  <br>
  <sub>Dock icon in dark appearance</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Status Trio live icon in the Dock with light appearance">
  <br>
  <sub>Dock icon in light appearance</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Status Trio in the Dock with the Bluetooth panel shown, light appearance">
  <br>
  <sub>Bluetooth panel preview</sub>
</p>

The Dock icon draws the same combined icon as the menu bar, so with Bluetooth audio replacement enabled the device glyph takes over the middle there too. Its background can follow the system icon style or be pinned to a fixed shade:

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Status Trio Dock icon in dark, light, and clear backgrounds, in two rows: the Wi-Fi state and Bluetooth audio replacing the Wi-Fi icon with blue volume dots">
</p>

## Icon states

Every state the combined icon can show, drawn by the app's own renderer — battery indicators on top, Wi-Fi (or the Bluetooth audio device that can replace it, when that option is on) in the middle, and volume dots or the arc at the bottom, turning blue while a Bluetooth device is playing:

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio icon states: charging, plugged in, percentage, low battery, and Low Power Mode at the top; Wi-Fi signal, hotspot, temporary, shared, and wired states in the middle; Bluetooth audio replacing the Wi-Fi icon, keeping Wi-Fi during a network error, and blue volume dots and arc below that; volume dots and arc styles for every level at the bottom">
</p>

The same states rendered for a dark menu bar:

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="The same Status Trio icon states in dark appearance: white glyphs on dark chips, green charging, red low battery and yellow Low Power Mode accents, and the brighter blue the app uses for Bluetooth audio on a dark menu bar">
</p>

## Requirements

- macOS 15 or later to run the app
- Swift 6 toolchain with the macOS 26 SDK (Xcode 26 or later) to build it. Building against an
  older SDK silently produces the pre-Tahoe popover appearance, so `scripts/build-app.sh` fails
  when the SDK is older than 26.

## Run from source

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## Build a local app

Build an ad-hoc-signed app bundle and launch it:

```bash
bash scripts/build-app.sh release
```

The bundle is created at `dist/StatusTrio.app`. To build without quitting or launching an existing instance, run:

```bash
bash scripts/build-app.sh release no-open
```

The ad-hoc-signed bundle is intended for local personal use. Gatekeeper may reject it if the bundle is transferred with quarantine metadata.

## Install a GitHub Release

Download the latest `StatusTrio-*.dmg` from the [GitHub Releases page](https://github.com/lingyired/status-trio/releases), open it, and copy `Status Trio.app` into `/Applications`.

The current public build is ad-hoc signed but is not notarized by Apple. macOS may show this warning on first launch:

> Apple cannot verify “Status Trio” is free of malware that may harm your Mac or compromise your privacy.

This is a Gatekeeper warning caused by the missing Developer ID signature and Apple notarization. It does not by itself mean the app contains malware. Only bypass the warning when the DMG was downloaded from the official GitHub Releases page and its published SHA-256 checksum matches.

After copying the app into `/Applications`, remove the quarantine attribute and open it:

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

Alternatively, try to open the app once, then go to **System Settings → Privacy & Security** and choose **Open Anyway**.

Do not disable Gatekeeper globally. Subsequent Sparkle updates are authenticated with the app's EdDSA signing key; the `xattr` command is normally needed only for the first manual installation.

## Usage

- **Left-click** the menu bar icon or the Dock icon to open the status popover.
- **Right-click** either icon for the native menu, including version and quit actions.
- Select the Wi-Fi or battery row in the popover to open its page: nearby networks and link details, or Battery Details. The Bluetooth row lists its paired devices in place — tap one to connect or disconnect — with an Expand control when they do not all fit.
- Open **Settings** to choose where the icon is shown (menu bar, Dock, or both) and to change its size, colors, ring thickness, the panel sections and their order, scroll-to-adjust behavior, language, update checks, and launch at login.
- Reopen the **Meet your icon** guide any time from **Settings › App Icon › Open Guide**.
- Enable the current Wi-Fi network name when prompted; macOS requests location access for this optional detail.

## Known limitations

Two boundaries macOS and this project draw deliberately. Both are explained in [Known limitations](docs/known-limitations.md).

- **Switching networks happens in System Settings.** Choosing a network in the popover opens the Wi-Fi pane; Status Trio never reads or stores Wi-Fi passwords, because macOS offers no public API to connect with a saved password and every alternative ends with the app holding them.
- **"Charge to Full Now" stays in macOS.** When optimized battery charging or a charge limit pauses charging, the popover reports the paused state and links to the Battery pane; no public API lets an app resume charging past the limit, and Status Trio does not write to the SMC or ship a privileged helper to do it.

## Languages

Status Trio follows the macOS preferred language by default and includes English, Simplified Chinese, Traditional Chinese, Japanese, Korean, Spanish, French, German, Italian, Brazilian Portuguese, Russian, and Arabic.

## Privacy

Status Trio reads system status through public macOS frameworks. Optional anonymous usage statistics send a small heartbeat to the first-party service only after you enable them; upgrades start with statistics off, and new installs ask for a choice during onboarding. The heartbeat contains a random installation ID, app and macOS versions, language, and icon placement. It contains no names, account details, network details, or hardware identifiers. See [telemetry and privacy](docs/privacy-telemetry.md) for the full payload, consent, and retention details. Status Trio does not read or store Wi-Fi passwords and never asks for Keychain access. Location access is optional and requested only when you choose to display the current Wi-Fi network name or open Wi-Fi details. Bluetooth access is requested only when the Bluetooth panel is shown, and it exists to show paired-device connection status.

## Development

Run the test suite:

```bash
swift test
```

Run a focused XCTest filter through the helper:

```bash
bash scripts/test.sh BatteryMonitorTests
```

To build a worktree app alongside the main installation:

```bash
bash scripts/build-worktree.sh release
```

The helper derives a development bundle identifier and display name from the current branch. Both values can be overridden:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

The single-instance lock is scoped by bundle identifier, so differently identified builds can run at the same time.

### Icon presentation API

For the three icon regions, update timing, Swift examples, and extension boundaries, see [三图形展示与更新 API](docs/api/icon-presentation.md). This documents the current internal API; an external plugin SDK is not implemented.

## Technical baseline

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` menu bar accessory that switches to a regular activation policy while the Dock icon is shown
- Sparkle for update checks

## Documentation

- [Known limitations](docs/known-limitations.md)
- [Automated GitHub Actions releases](docs/github-actions-release.md)
- [Status Trio design specification](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [Menu bar icon SVG](status-menubar.svg)
- [Data-driven icon demo](status-menubar-demo.html)

## License

Copyright 2026 lingyired.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Author

Created and maintained by [lingyired](https://github.com/lingyired).<br>
Website: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
