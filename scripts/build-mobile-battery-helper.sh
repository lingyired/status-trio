#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Support/mobile-battery-dependencies.json"
WORK="$ROOT/.build/mobile-battery"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MINIMUM_MACOS="15.0"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-0}"
BUILD_JOBS="${BUILD_JOBS:-$(sysctl -n hw.ncpu)}"

if (( ${SDK_VERSION%%.*} < 26 )); then
    echo "Error: mobile battery helper requires macOS SDK 26 or newer; found ${SDK_VERSION}." >&2
    exit 2
fi
if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    ARCHES=(arm64 x86_64)
else
    ARCHES=("$(uname -m)")
fi

while IFS=$'\t' read -r name repository commit version; do
    source="$WORK/sources/$name"
    if [[ ! -d "$source/.git" ]]; then
        mkdir -p "$WORK/sources"
        git clone --filter=blob:none "$repository" "$source"
    fi
    git -C "$source" fetch --quiet origin "$commit"
    git -C "$source" checkout --quiet --detach "$commit"
    actual="$(git -C "$source" rev-parse HEAD)"
    if [[ "$actual" != "$commit" ]]; then
        echo "Error: source pin mismatch for $name: expected $commit, found $actual." >&2
        exit 1
    fi
done < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); by={x["name"]:x for x in d["dependencies"]}; [print("\t".join((n,by[n]["repository"],by[n]["commit"],by[n]["version"]))) for n in d["sourceBuildOrder"]]' "$MANIFEST")

for arch in "${ARCHES[@]}"; do
    arch_root="$WORK/$arch"
    build_root="$arch_root/build"
    source_root="$build_root/src"
    prefix="$arch_root/prefix"
    curl_pkgconfig="$build_root/apple-curl-pkgconfig"
    if [[ "$arch" == "arm64" ]]; then
        openssl_target="darwin64-arm64-cc"
        host="aarch64-apple-darwin"
    elif [[ "$arch" == "x86_64" ]]; then
        openssl_target="darwin64-x86_64-cc"
        host="x86_64-apple-darwin"
    else
        echo "Error: unsupported architecture: $arch" >&2
        exit 2
    fi

    export MACOSX_DEPLOYMENT_TARGET="$MINIMUM_MACOS"
    CLANG="$(xcrun --sdk macosx --find clang)"
    CLANGXX="$(xcrun --sdk macosx --find clang++)"
    CLANG_VERSION="$("$CLANG" --version | head -n 1)"
    BUILD_KEY="$(printf '%s\n%s\n%s\n%s\n%s\n' "$arch" "$SDK_VERSION" "$MINIMUM_MACOS" "$CLANG_VERSION" "source-pinned-dynamic-v1" "$(shasum -a 256 "$MANIFEST" | awk '{print $1}')" | shasum -a 256 | awk '{print $1}')"
    REBUILD_DEPENDENCIES=1
    if [[ "${MOBILE_BATTERY_FORCE_SOURCE_BUILD:-0}" != "1" && -f "$arch_root/.dependencies-build-key" && "$(cat "$arch_root/.dependencies-build-key")" == "$BUILD_KEY" && -f "$prefix/lib/libimobiledevice-1.0.dylib" && -f "$prefix/lib/libtatsu.dylib" ]]; then
        REBUILD_DEPENDENCIES=0
        echo "Reusing pinned $arch dependency build for SDK $SDK_VERSION."
    else
        rm -rf "$arch_root"
        mkdir -p "$source_root" "$prefix" "$curl_pkgconfig"
    fi
    export CC="$CLANG -arch $arch -isysroot $SDK_PATH"
    export CXX="$CLANGXX -arch $arch -isysroot $SDK_PATH"
    export CFLAGS="-O2 -arch $arch -isysroot $SDK_PATH -mmacosx-version-min=$MINIMUM_MACOS"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch $arch -isysroot $SDK_PATH -mmacosx-version-min=$MINIMUM_MACOS -L$prefix/lib -Wl,-rpath,$prefix/lib"
    export PKG_CONFIG_PATH=""
    export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/lib64/pkgconfig:$curl_pkgconfig"

    if [[ "$REBUILD_DEPENDENCIES" == "1" ]]; then
    while IFS=$'\t' read -r name repository commit version; do
        mkdir -p "$source_root/$name"
        git -C "$WORK/sources/$name" archive "$commit" | tar -x -C "$source_root/$name"
        printf '%s\n' "$version" > "$source_root/$name/.tarball-version"
    done < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); by={x["name"]:x for x in d["dependencies"]}; [print("\t".join((n,by[n]["repository"],by[n]["commit"],by[n]["version"]))) for n in d["sourceBuildOrder"]]' "$MANIFEST")

    cat > "$curl_pkgconfig/libcurl.pc" <<EOF
prefix=$SDK_PATH
exec_prefix=\${prefix}
libdir=\${exec_prefix}/usr/lib
includedir=\${prefix}/usr/include

Name: libcurl
Description: Apple SDK libcurl for source-built libtatsu
Version: 8.0.0
Libs: -L\${libdir} -lcurl
Cflags: -I\${includedir}
EOF

    openssl_source="$source_root/openssl"
    (cd "$openssl_source" && ./Configure "$openssl_target" shared no-tests --prefix="$prefix" --openssldir="$prefix/etc/ssl" && make -j"$BUILD_JOBS" && make install_sw)

    build_autotools() {
        local name="$1"
        shift
        local source="$source_root/$name"
        local build="$build_root/$name"
        mkdir -p "$build"
        (cd "$source" && NOCONFIGURE=1 ./autogen.sh)
        (cd "$build" && "$source/configure" --host="$host" --prefix="$prefix" --enable-shared --disable-static "$@" && make -j"$BUILD_JOBS" && make install)
    }

    build_autotools libplist --without-cython --without-tools --without-tests
    build_autotools libimobiledevice-glue
    build_autotools libusbmuxd --without-inotify
    build_autotools libtatsu
    build_autotools libimobiledevice --without-cython --without-readline --with-openssl

    printf '%s\n' "$BUILD_KEY" > "$arch_root/.dependencies-build-key"
    fi

    helper="$arch_root/StatusTrioMobileBatteryHelper"
    mkdir -p "$arch_root"
    HELPER_CFLAGS="$(pkg-config --cflags libimobiledevice-1.0 libusbmuxd-2.0 libplist-2.0)"
    HELPER_LIBS="$(pkg-config --libs libimobiledevice-1.0 libusbmuxd-2.0 libplist-2.0)"
    "$CLANG" $CFLAGS -fobjc-arc -O2 -I"$prefix/include" \
        $HELPER_CFLAGS \
        "$ROOT/Support/MobileBatteryHelper/main.m" \
        "$ROOT/Support/MobileBatteryHelper/NativeBatteryClient.m" \
        $HELPER_LIBS \
        -framework Foundation -framework CoreFoundation \
        -Wl,-rpath,@executable_path/../Frameworks/MobileBattery \
        -Wl,-headerpad_max_install_names \
        -o "$helper"
    chmod 755 "$helper"

    strip_development_rpaths() {
        local binary="$1"
        while IFS= read -r rpath; do
            case "$rpath" in
                "$prefix"/*) install_name_tool -delete_rpath "$rpath" "$binary" ;;
            esac
        done < <(otool -l "$binary" | python3 "$ROOT/scripts/otool-rpaths.py")
    }

    strip_development_rpaths "$helper"
    while IFS= read -r -d '' library; do
        strip_development_rpaths "$library"
    done < <(find "$prefix/lib" -maxdepth 1 -type f -name '*.dylib*' -print0)
done

PACKAGE="$WORK/package"
rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/Helpers" "$PACKAGE/Frameworks/MobileBattery" "$PACKAGE/Resources/MobileBatteryLicenses"

if [[ "${#ARCHES[@]}" -eq 1 ]]; then
    cp "${WORK}/${ARCHES[0]}/StatusTrioMobileBatteryHelper" "$PACKAGE/Helpers/StatusTrioMobileBatteryHelper"
    while IFS= read -r -d '' library; do
        cp -P "$library" "$PACKAGE/Frameworks/MobileBattery/"
    done < <(find "${WORK}/${ARCHES[0]}/prefix/lib" -maxdepth 1 \( -type f -o -type l \) -name '*.dylib*' ! -name 'libplist++*' -print0)
else
    lipo -create "$WORK/arm64/StatusTrioMobileBatteryHelper" "$WORK/x86_64/StatusTrioMobileBatteryHelper" -output "$PACKAGE/Helpers/StatusTrioMobileBatteryHelper"
    while IFS= read -r -d '' library; do
        filename="$(basename "$library")"
        if [[ "$filename" == libplist++* ]]; then continue; fi
        other="$WORK/x86_64/prefix/lib/$filename"
        if [[ ! -f "$other" ]]; then
            echo "Error: missing x86_64 library slice for $filename." >&2
            exit 1
        fi
        lipo -create "$library" "$other" -output "$PACKAGE/Frameworks/MobileBattery/$filename"
    done < <(find "$WORK/arm64/prefix/lib" -maxdepth 1 -type f -name '*.dylib*' -print0)
    while IFS= read -r -d '' link; do
        filename="$(basename "$link")"
        if [[ "$filename" == libplist++* ]]; then continue; fi
        cp -P "$link" "$PACKAGE/Frameworks/MobileBattery/$filename"
    done < <(find "$WORK/arm64/prefix/lib" -maxdepth 1 -type l -name '*.dylib*' -print0)
fi

mkdir -p "$ROOT/Support/MobileBatteryHelper/ThirdPartyNotices"
python3 - "$WORK/sources" "$ROOT/Support/MobileBatteryHelper/ThirdPartyNotices" <<'PY'
from pathlib import Path
import sys
source_root, notices_root = map(Path, sys.argv[1:])
for name in ("openssl", "libplist", "libimobiledevice-glue", "libusbmuxd", "libtatsu", "libimobiledevice"):
    source = source_root / name
    destination = notices_root / name
    destination.mkdir(parents=True, exist_ok=True)
    candidates = ("LICENSE", "LICENSE.txt", "COPYING", "COPYING.LESSER")
    for filename in candidates:
        path = source / filename
        if path.is_file():
            text = path.read_text()
            normalized = "\n".join(line.rstrip() for line in text.splitlines()).rstrip() + "\n"
            (destination / filename).write_text(normalized)
PY

cp -R "$ROOT/Support/MobileBatteryHelper/ThirdPartyNotices/." "$PACKAGE/Resources/MobileBatteryLicenses/"
cp "$MANIFEST" "$PACKAGE/Resources/MobileBatteryLicenses/dependencies.json"
echo "Built source-pinned mobile battery helper package at $PACKAGE"
