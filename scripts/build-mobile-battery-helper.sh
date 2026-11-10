#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Support/mobile-battery-dependencies.json"
WORK="$ROOT/.build/mobile-battery"
source "$ROOT/scripts/build-timing.sh"
trap 'build_timing_finish "$?"' EXIT
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MINIMUM_MACOS="13.0"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-0}"
BUILD_JOBS="${BUILD_JOBS:-$(sysctl -n hw.ncpu)}"
SOURCES_PREPARED=0
NOTICE_ROOT="$ROOT/Support/MobileBatteryHelper/ThirdPartyNotices"

if (( ${SDK_VERSION%%.*} < 26 )); then
    echo "Error: mobile battery helper requires macOS SDK 26 or newer; found ${SDK_VERSION}." >&2
    exit 2
fi
if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    ARCHES=(arm64 x86_64)
else
    ARCHES=("$(uname -m)")
fi

prepare_sources_if_needed() {
    if [[ "$SOURCES_PREPARED" == "1" ]]; then
        return
    fi
    build_phase mobile-source-checkout
    bash "$ROOT/scripts/prepare-mobile-battery-sources.sh" "$MANIFEST" "$WORK"
    build_timing_finish 0
    SOURCES_PREPARED=1
}

verify_reviewed_notices() {
    local sources_prepared="$1"
    python3 - "$WORK/sources" "$NOTICE_ROOT" "$sources_prepared" <<'PY'
from pathlib import Path
import sys

source_root, notices_root = Path(sys.argv[1]), Path(sys.argv[2])
sources_prepared = sys.argv[3] == "1"

def normalized(path: Path) -> str:
    text = path.read_text()
    return "\n".join(line.rstrip() for line in text.splitlines()).rstrip() + "\n"

for name in ("openssl", "libplist", "libimobiledevice-glue", "libusbmuxd", "libtatsu", "libimobiledevice"):
    source = source_root / name
    destination = notices_root / name
    candidates = ("LICENSE", "LICENSE.txt", "COPYING", "COPYING.LESSER")
    reviewed = [destination / filename for filename in candidates if (destination / filename).is_file()]
    if not reviewed:
        raise SystemExit(f"missing reviewed license files for {name}: {destination}")
    if not sources_prepared:
        continue
    source_files = [source / filename for filename in candidates if (source / filename).is_file()]
    if not source_files:
        raise SystemExit(f"missing upstream license files for {name}: {source}")
    source_names = [path.name for path in source_files]
    reviewed_names = [path.name for path in reviewed]
    if source_names != reviewed_names:
        raise SystemExit(
            f"reviewed license set differs from {name} source pins: "
            f"{reviewed_names} != {source_names}"
        )
    for source_file, reviewed_file in zip(source_files, reviewed):
        if normalized(source_file) != normalized(reviewed_file):
            raise SystemExit(
                f"reviewed license text differs from {name} source pin: "
                f"{reviewed_file.relative_to(notices_root)}"
            )
PY
}

strip_development_rpaths() {
    local binary="$1"
    local prefix="$2"
    local rpaths
    rpaths="$(otool -l "$binary" | python3 "$ROOT/scripts/otool-rpaths.py")"
    while IFS= read -r rpath; do
        case "$rpath" in
            "$prefix"/*) install_name_tool -delete_rpath "$rpath" "$binary" ;;
        esac
    done <<< "$rpaths"
}

for arch in "${ARCHES[@]}"; do
    build_phase "mobile-dependencies-$arch"
    arch_root="$WORK/$arch"
    build_root="$arch_root/build"
    source_root="$build_root/src"
    prefix="$arch_root/prefix"
    marker="$arch_root/.dependencies-cache.json"
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
    CLANG_VERSION="$("$CLANG" --version)"
    CLANG_VERSION="${CLANG_VERSION%%$'\n'*}"
    BUILD_KEY="$(python3 "$ROOT/scripts/mobile-battery-cache.py" prepare-key --root "$ROOT" --arch "$arch" --minimum-macos "$MINIMUM_MACOS")"
    REBUILD_DEPENDENCIES=1
    if [[ "${MOBILE_BATTERY_FORCE_SOURCE_BUILD:-0}" == "1" ]]; then
        echo "MobileBattery cache bypassed for $arch by MOBILE_BATTERY_FORCE_SOURCE_BUILD=1."
        rm -rf "$build_root" "$prefix" "$marker" "$arch_root/.dependencies-build-key"
        mkdir -p "$source_root" "$prefix" "$curl_pkgconfig"
    elif [[ -e "$prefix" || -e "$marker" ]]; then
        echo "MobileBattery cache candidate (restored/local) found for $arch."
        cache_log="$WORK/.cache-validation-$arch.log"
        cache_status=0
        python3 "$ROOT/scripts/mobile-battery-cache.py" validate \
            --root "$ROOT" --arch "$arch" \
            --minimum-macos "$MINIMUM_MACOS" \
            --expected-key "$BUILD_KEY" >"$cache_log" 2>&1 || cache_status=$?
        cat "$cache_log"
        case "$cache_status" in
            0)
                REBUILD_DEPENDENCIES=0
                echo "MobileBattery cache validated for $arch."
                echo "MobileBattery third-party dependency build skipped for $arch."
                ;;
            10|11)
                echo "MobileBattery cache rejected for $arch (status $cache_status); rebuilding pinned sources."
                rm -rf "$build_root" "$prefix" "$marker" "$arch_root/.dependencies-build-key"
                mkdir -p "$source_root" "$prefix" "$curl_pkgconfig"
                ;;
            *)
                echo "Error: MobileBattery cache inspection failed for $arch (status $cache_status); refusing to treat it as a cache miss." >&2
                exit "$cache_status"
                ;;
        esac
    else
        echo "MobileBattery cache miss for $arch; building pinned sources."
        rm -rf "$build_root" "$prefix" "$marker" "$arch_root/.dependencies-build-key"
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
    prepare_sources_if_needed
    verify_reviewed_notices 1
    build_phase "mobile-dependencies-$arch"
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

    python3 "$ROOT/scripts/mobile-battery-cache.py" seal \
        --root "$ROOT" --arch "$arch" \
        --minimum-macos "$MINIMUM_MACOS" \
        --expected-key "$BUILD_KEY"
    fi

    build_phase "mobile-helper-$arch"
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
    strip_development_rpaths "$helper" "$prefix"

    # Keep sealed prefixes immutable. Strip each thin staging copy before lipo,
    # since the architecture-specific rpath is absent from the other slice.
    package_libraries="$arch_root/package-libraries"
    rm -rf "$package_libraries"
    mkdir -p "$package_libraries"
    while IFS= read -r -d '' library; do
        cp -P "$library" "$package_libraries/"
    done < <(find "$prefix/lib" -maxdepth 1 \( -type f -o -type l \) -name '*.dylib*' ! -name 'libplist++*' -print0)
    while IFS= read -r -d '' library; do
        strip_development_rpaths "$library" "$prefix"
    done < <(find "$package_libraries" -maxdepth 1 -type f -name '*.dylib*' -print0)
done

build_phase mobile-package
PACKAGE="$WORK/package"
rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/Helpers" "$PACKAGE/Frameworks/MobileBattery" "$PACKAGE/Resources/MobileBatteryLicenses"

if [[ "${#ARCHES[@]}" -eq 1 ]]; then
    cp "${WORK}/${ARCHES[0]}/StatusTrioMobileBatteryHelper" "$PACKAGE/Helpers/StatusTrioMobileBatteryHelper"
    while IFS= read -r -d '' library; do
        cp -P "$library" "$PACKAGE/Frameworks/MobileBattery/"
    done < <(find "${WORK}/${ARCHES[0]}/package-libraries" -maxdepth 1 \( -type f -o -type l \) -name '*.dylib*' -print0)
else
    lipo -create "$WORK/arm64/StatusTrioMobileBatteryHelper" "$WORK/x86_64/StatusTrioMobileBatteryHelper" -output "$PACKAGE/Helpers/StatusTrioMobileBatteryHelper"
    while IFS= read -r -d '' library; do
        filename="$(basename "$library")"
        if [[ "$filename" == libplist++* ]]; then continue; fi
        other="$WORK/x86_64/package-libraries/$filename"
        if [[ ! -f "$other" ]]; then
            echo "Error: missing x86_64 library slice for $filename." >&2
            exit 1
        fi
        lipo -create "$library" "$other" -output "$PACKAGE/Frameworks/MobileBattery/$filename"
    done < <(find "$WORK/arm64/package-libraries" -maxdepth 1 -type f -name '*.dylib*' -print0)
    while IFS= read -r -d '' link; do
        filename="$(basename "$link")"
        if [[ "$filename" == libplist++* ]]; then continue; fi
        cp -P "$link" "$PACKAGE/Frameworks/MobileBattery/$filename"
    done < <(find "$WORK/arm64/package-libraries" -maxdepth 1 -type l -name '*.dylib*' -print0)
fi

[[ -f "$NOTICE_ROOT/NOTICE.md" ]] || {
    echo "Error: missing reviewed MobileBattery notice: $NOTICE_ROOT/NOTICE.md" >&2
    exit 1
}
verify_reviewed_notices 0

cp -R "$NOTICE_ROOT/." "$PACKAGE/Resources/MobileBatteryLicenses/"
cp "$MANIFEST" "$PACKAGE/Resources/MobileBatteryLicenses/dependencies.json"
echo "Built source-pinned mobile battery helper package at $PACKAGE"
