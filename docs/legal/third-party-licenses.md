# Third-party licenses

Status Trio is licensed under the **Apache License, Version 2.0** (see
[`LICENSE`](../../LICENSE) and [`NOTICE`](../../NOTICE)). Status Trio also uses and,
in some cases, redistributes third-party components that were developed
independently and carry their own licenses. Those licenses are **not** the
Apache-2.0 license, and they do **not** replace or relicense the project as a
whole. Each third-party component remains under its own terms.

This document lists the third-party components, their licenses, the exact
shipped versions, and how to obtain and rebuild their corresponding source. It
complements the notices that ship inside the app bundle and the tested
verification in [`scripts/verify-mobile-battery-bundle.sh`](../../scripts/verify-mobile-battery-bundle.sh).

## Status Trio's own license

- Status Trio source, the `StatusTrio` app, and the Swift targets are
  Apache-2.0.
- `Sources/PowerUIPrivateAPI` is a first-party wrapper written for Status Trio
  and is covered by the project's Apache-2.0 license; it is not a separate
  third-party component.
- Including or linking a differently-licensed third-party component does not
  change the license of the Status Trio project as a whole.

## Bundled third-party components

| Component | License | Where it ships | License text |
| --- | --- | --- | --- |
| Mobile battery helper dependencies (see table below) | Apache-2.0 / LGPL-2.1-or-later | `Status Trio.app/Contents/Frameworks/MobileBattery/` (dylibs); `Status Trio.app/Contents/Resources/MobileBatteryLicenses/` (licenses) | [`ThirdPartyNotices/`](../../Support/MobileBatteryHelper/ThirdPartyNotices/) and [`NOTICE.md`](../../Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md) |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT (plus bundled external licenses) | `Status Trio.app/Contents/Frameworks/Sparkle.framework` | Upstream `LICENSE` shipped inside `Sparkle.framework` |
| [AirPodsAudioContext](https://github.com/lingyired/status-trio) (internal compatibility library, `Copyright (c) 2026 Raul`) | MIT | `Status Trio.app/Contents/Helpers/libAirPodsAudioContext.dylib` | [`Sources/AirPodsAudioContext/LICENSE`](../../Sources/AirPodsAudioContext/LICENSE); copied into the bundle as `Contents/Resources/AirPodsAudioContext-LICENSE` |
| [DDCPrivateAPI](https://github.com/waydabber/AppleSiliconDDC)-derived helper | MIT (`Copyright (c) 2021 Istvan T.`) | Compiled into the app binary (source target) | [`Sources/DDCPrivateAPI/LICENSE-AppleSiliconDDC.txt`](../../Sources/DDCPrivateAPI/LICENSE-AppleSiliconDDC.txt) |

The resolved Sparkle version is recorded in
[`Package.resolved`](../../Package.resolved). The helper dependency versions are
recorded in
[`Support/mobile-battery-dependencies.json`](../../Support/mobile-battery-dependencies.json),
which is the single source of truth for that graph.

## Mobile battery helper dependency graph

The helper links source-built copies of the following libraries. OpenSSL is
Apache-2.0; the other libraries are GNU LGPL-2.1-or-later. The table below is
generated from
[`Support/mobile-battery-dependencies.json`](../../Support/mobile-battery-dependencies.json)
by [`scripts/render-mobile-battery-license-table.py`](../../scripts/render-mobile-battery-license-table.py);
edit the JSON, not this table, when a dependency changes.
[`scripts/check-third-party-licenses.sh`](../../scripts/check-third-party-licenses.sh)
verifies that the two stay in sync.

<!-- BEGIN GENERATED: mobile-battery-dependencies -->
| Component | License | Version | Upstream repository | Commit |
| --- | --- | --- | --- | --- |
| openssl | Apache-2.0 | 3.5.9 | https://github.com/openssl/openssl.git | 45e844fa2a14ec92d146bd8f5778ac130b6625fb |
| libplist | LGPL-2.1-or-later | 2.8.0 | https://github.com/libimobiledevice/libplist.git | fe3dc34dc3484006e12b403f7ceb06f0ad40b6f4 |
| libimobiledevice-glue | LGPL-2.1-or-later | 1.3.2 | https://github.com/libimobiledevice/libimobiledevice-glue.git | aef2bf0f5bfe961ad83d224166462d87b1df2b00 |
| libusbmuxd | LGPL-2.1-or-later | 2.1.1 | https://github.com/libimobiledevice/libusbmuxd.git | adf9c22b9010490e4b55eaeb14731991db1c172c |
| libtatsu | LGPL-2.1-or-later | 1.0.5 | https://github.com/libimobiledevice/libtatsu.git | 42329cb756682535c7c0f087987b78d1dd5b16c8 |
| libimobiledevice | LGPL-2.1-or-later | 1.4.0 | https://github.com/libimobiledevice/libimobiledevice.git | 149f7623c672c1fa73122c7119a12bfc0012f2ac |
<!-- END GENERATED: mobile-battery-dependencies -->

Some upstream source trees include a `COPYING` file containing the GNU GPL text
for their command-line tools. Those tools are **not** shipped: the helper bundle
contains runtime libraries only. Do not read a GPL `COPYING` file in a source
tree as a statement that the distributed dylib itself is GPL. Verify licenses
against the actual distributed components, their source files, and their
per-file license declarations.

## Modified and unmodified components

- **Mobile battery helper dependencies** — built **unmodified** from the pinned
  upstream commits above. [`scripts/prepare-mobile-battery-sources.sh`](../../scripts/prepare-mobile-battery-sources.sh)
  checks out each recorded commit, verifies `HEAD` equality, and no source
  patches are applied.
- **Sparkle** — the upstream release framework, used **unmodified**.
- **AirPodsAudioContext** — the internal compatibility library shipped as-is,
  under its own MIT license.
- **DDCPrivateAPI** — a vendored MIT-licensed source component; its original
  copyright and license notices are retained.

If you modify any third-party source, keep the original license and copyright
notices, and mark the changes clearly. Modified LGPL libraries remain under the
LGPL.

## Where the license texts are

- Mobile battery helper libraries: one directory per dependency under
  [`Support/MobileBatteryHelper/ThirdPartyNotices/`](../../Support/MobileBatteryHelper/ThirdPartyNotices/),
  with the upstream `COPYING`, `COPYING.LESSER`, or `LICENSE.txt`. These are
  copied into the app at `Contents/Resources/MobileBatteryLicenses/`, together
  with [`NOTICE.md`](../../Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md)
  and `dependencies.json`.
- Sparkle: the `LICENSE` file inside `Sparkle.framework`.
- AirPodsAudioContext: bundled as `Contents/Resources/AirPodsAudioContext-LICENSE`.
- DDCPrivateAPI: [`Sources/DDCPrivateAPI/LICENSE-AppleSiliconDDC.txt`](../../Sources/DDCPrivateAPI/LICENSE-AppleSiliconDDC.txt).

## Getting the corresponding source

- **Mobile battery helper dependencies** — clone each upstream repository at the
  exact commit in the generated table above.
  [`scripts/build-mobile-battery-helper.sh`](../../scripts/build-mobile-battery-helper.sh)
  does this automatically from the manifest.
- **Sparkle** — clone <https://github.com/sparkle-project/Sparkle> at the version
  resolved in [`Package.resolved`](../../Package.resolved) (or run
  `swift package resolve`).
- **AirPodsAudioContext / DDCPrivateAPI** — the corresponding source is in this
  repository under [`Sources/AirPodsAudioContext`](../../Sources/AirPodsAudioContext)
  and [`Sources/DDCPrivateAPI`](../../Sources/DDCPrivateAPI).

## Rebuilding and replacing the bundled runtime libraries

Rebuild the mobile battery helper from the pinned sources:

```sh
# Build-only tools: autoconf, automake, libtool, pkg-config
UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
```

The script builds arm64 and x86_64 separately against the macOS SDK, combines
the matching slices, and produces a package under
`.build/mobile-battery/package`. A full app bundle is assembled by
[`scripts/build-app.sh`](../../scripts/build-app.sh).

To replace a bundled library in an existing app, see the step-by-step
instructions in
[`Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md`](../../Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md)
(`Replacing a bundled library`). In short: rebuild the dependency from the
matching pinned source, replace the dylib in
`Contents/Frameworks/MobileBattery/` with an ABI-compatible build for the app's
supported architectures and macOS floor, preserve the `@rpath/<dylib-name>`
install name, then re-sign the replacement dylib and the enclosing app and run
[`scripts/verify-mobile-battery-bundle.sh`](../../scripts/verify-mobile-battery-bundle.sh).

Re-signing produces your own signature. It does not retain the original
developer's signature identity or the original notarization; re-notarization
is your responsibility.

## If you distribute a modified build

- Keep the Apache-2.0 `LICENSE`/`NOTICE` for the Status Trio project.
- Keep every third-party copyright and license notice, including the LGPL
  notices and license texts for the mobile battery helper libraries.
- Provide the corresponding source for the LGPL libraries you ship, at the
  version you shipped, per the LGPL.
- If you modify an LGPL library, state the changes and keep it under the LGPL.

This document is a practical guide, not legal advice. When in doubt, consult the
full license texts listed above and the upstream projects' own notices.
