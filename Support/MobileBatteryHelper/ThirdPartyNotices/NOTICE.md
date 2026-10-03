# Mobile battery helper dependency notices

The helper dynamically links source-built copies of the libraries listed in `dependencies.json`. Each dependency's license text is included in its directory. The graph is not wholly Apache-2.0: OpenSSL is Apache-2.0, while libplist, libimobiledevice-glue, libusbmuxd, libtatsu, and libimobiledevice are distributed under the GNU LGPL (and some source trees also include the GPL text for their tools). The helper package contains runtime libraries only; upstream command-line tools are not shipped.

## Source and build instructions

From the repository root, install the build-only tools `autoconf`, `automake`, `libtool`, and `pkg-config`, then run:

```sh
UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
```

The script checks out every commit recorded in `dependencies.json`, verifies `HEAD` equality, builds arm64 and x86_64 separately with the macOS SDK and a macOS 15 deployment target, then combines the matching slices. OpenSSL is built with its shared libraries and no tests. libtatsu links Apple's SDK libcurl; no Homebrew curl library is part of the runtime. Build intermediates and installed headers remain under `.build/mobile-battery/` and are not copied into the app.

## Replacing a bundled library

The dylibs live in `Status Trio.app/Contents/Frameworks/MobileBattery/` and are loaded through `@rpath`. A recipient may rebuild a dependency from the matching pinned source, replace its bundled dylib with an ABI-compatible build for the app's supported architectures and macOS 15 floor, preserve the `@rpath/<dylib-name>` install name, and re-sign the replacement dylib and enclosing app. The corresponding source, build configuration, and license text are identified here and in `dependencies.json`; source can be retrieved from each listed upstream repository at its recorded commit. Re-run `scripts/verify-mobile-battery-bundle.sh` after replacement.
