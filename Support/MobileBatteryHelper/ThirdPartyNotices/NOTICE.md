# Mobile battery helper dependency notices

Status Trio's mobile battery helper dynamically links source-built copies of the
libraries listed in `dependencies.json`. The helper package ships runtime
libraries only; the upstream command-line tools are not shipped.

## 1. Components and copyright attribution

| Component | License | Copyright / upstream |
| --- | --- | --- |
| openssl | Apache-2.0 | Copyright the OpenSSL Project Authors — <https://github.com/openssl/openssl> |
| libplist | LGPL-2.1-or-later | Copyright the libimobiledevice project contributors — <https://github.com/libimobiledevice/libplist> |
| libimobiledevice-glue | LGPL-2.1-or-later | Copyright the libimobiledevice project contributors — <https://github.com/libimobiledevice/libimobiledevice-glue> |
| libusbmuxd | LGPL-2.1-or-later | Copyright the libimobiledevice project contributors — <https://github.com/libimobiledevice/libusbmuxd> |
| libtatsu | LGPL-2.1-or-later | Copyright the libimobiledevice project contributors — <https://github.com/libimobiledevice/libtatsu> |
| libimobiledevice | LGPL-2.1-or-later | Copyright the libimobiledevice project contributors — <https://github.com/libimobiledevice/libimobiledevice> |

The dependency graph is not wholly Apache-2.0: OpenSSL is Apache-2.0, while the
other libraries are distributed under the GNU LGPL. Some upstream source trees
also include the GNU GPL text (`COPYING`) for their command-line tools. Those
tools are **not** part of the shipped helper, and the presence of that text does
not make the distributed library itself GPL. Verify licenses against the actual
distributed components and their source files.

## 2. LGPL licensing

libplist, libimobiledevice-glue, libusbmuxd, libtatsu, and libimobiledevice are
distributed under the **GNU Lesser General Public License, version 2.1 or (at
your option) any later version** (LGPL-2.1-or-later).

Dynamic linking does **not** mean the LGPL obligations can be ignored. Status
Trio links these libraries dynamically, which keeps them separate from the
Apache-2.0 application, but the LGPL terms still apply to the libraries
themselves:

- Status Trio as a whole remains under the **Apache License 2.0**; the third-party
  licenses do not relicense the app.
- You have the LGPL rights to modify these libraries and to reverse-engineer and
  debug the combined work for the purpose of developing and testing such
  modifications.
- You may replace a bundled library with an ABI-compatible version that you build
  yourself. The app's design must not unreasonably prevent this; the replacement
  steps below describe the supported route.

## 3. License file locations

- **In this repository:** one directory per component under
  `Support/MobileBatteryHelper/ThirdPartyNotices/` (each contains the upstream
  `COPYING`, `COPYING.LESSER`, or `LICENSE.txt`).
- **In the installed app:** `Status Trio.app/Contents/Resources/MobileBatteryLicenses/`,
  which contains one directory per component, together with this `NOTICE.md` and
  `dependencies.json`.
- **Runtime libraries:** `Status Trio.app/Contents/Frameworks/MobileBattery/`.

## 4. Corresponding source and exact versions

The exact version and commit of every library is recorded in `dependencies.json`
(copied into the app next to this file). The corresponding source for each
component is the upstream repository at the recorded commit. The table below is
generated from `dependencies.json`; the JSON is the single source of truth and
the repository-level document `docs/legal/third-party-licenses.md` carries the
same table.

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

## 5. Obtaining source and rebuilding

From the repository root, install the build-only tools `autoconf`, `automake`,
`libtool`, and `pkg-config`, then run:

```sh
UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
```

The script checks out every commit recorded in `dependencies.json`, verifies
`HEAD` equality, builds arm64 and x86_64 separately with the macOS SDK and a
macOS 13.0 deployment target, then combines the matching slices. OpenSSL is
built with its shared libraries and no tests. libtatsu links Apple's SDK
libcurl; no Homebrew curl library is part of the runtime. Build intermediates and
installed headers remain under `.build/mobile-battery/` and are not copied into
the app.

## 6. Replacing a bundled library

The dylibs live in `Status Trio.app/Contents/Frameworks/MobileBattery/` and are
loaded through `@rpath`. To replace one:

1. Rebuild the dependency from the matching pinned source (see above).
2. Produce an ABI-compatible build for the app's supported architectures and the
   macOS 13.0 floor.
3. Replace the bundled dylib, preserving the `@rpath/<dylib-name>` install name.
4. Re-sign the replacement dylib and then the enclosing app (see section 7).
5. Re-run `scripts/verify-mobile-battery-bundle.sh` against the app.

The corresponding source, build configuration, and license text are identified
here and in `dependencies.json`; source can be retrieved from each listed
upstream repository at its recorded commit.

## 7. macOS signing, runtime compatibility, and verification

- Build with the macOS SDK required by the project (macOS SDK 26 or newer) and the
  macOS 13.0 deployment floor; release builds use arm64 and x86_64.
- The helper resolves its libraries through `@executable_path/../Frameworks/MobileBattery`;
  keep that run path and the install names intact when replacing a dylib.
- After any replacement, re-sign the dylib and the enclosing app, then run
  `scripts/verify-mobile-battery-bundle.sh` to confirm architectures, run paths,
  dependencies, platform version, and code signatures.
- Re-signing produces **your own** signature. It does not retain the original
  developer's signature identity or the original notarization; you are
  responsible for your own signing and notarization.

## 8. Full license texts

The complete license text for each component is in its directory under
`Support/MobileBatteryHelper/ThirdPartyNotices/`, and is shipped in
`Status Trio.app/Contents/Resources/MobileBatteryLicenses/`:

- `openssl/LICENSE.txt` — Apache License 2.0
- `libplist/COPYING` and `libplist/COPYING.LESSER` — GPL-2.0 / LGPL-2.1
- `libimobiledevice-glue/COPYING` — LGPL-2.1
- `libusbmuxd/COPYING` — LGPL-2.1
- `libtatsu/COPYING` — LGPL-2.1
- `libimobiledevice/COPYING` and `libimobiledevice/COPYING.LESSER` — GPL-2.0 / LGPL-2.1
