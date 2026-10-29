#!/usr/bin/env bash
# Synthetic cache contract tests. They compile tiny Mach-O fixtures outside
# .build; OpenSSL and the MobileBattery repositories are never built here.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioMobileBatteryCache.XXXXXX")"
TEST_ROOT="$(cd -- "$TEST_ROOT" && pwd -P)"
trap 'rm -rf "$TEST_ROOT"' EXIT

CACHE_SCRIPT="$ROOT/scripts/mobile-battery-cache.py"
if [[ ! -f "$CACHE_SCRIPT" ]]; then
    echo "FAIL: missing scripts/mobile-battery-cache.py" >&2
    exit 1
fi

PROJECT="$TEST_ROOT/project"
OTHER_PROJECT="$TEST_ROOT/other-project"
BIN="$TEST_ROOT/bin"
SDK_PATH="$("$(command -v xcrun)" --sdk macosx --show-sdk-path)"
SDK_IDENTITY_PATH="$TEST_ROOT/sdk"
REAL_CLANG="$("$(command -v xcrun)" --sdk macosx --find clang)"
HOST_ARCH="$(/usr/bin/uname -m)"
if [[ "$HOST_ARCH" == "arm64" ]]; then
    OTHER_ARCH="x86_64"
else
    OTHER_ARCH="arm64"
fi

mkdir -p "$BIN" "$SDK_IDENTITY_PATH"
cp "$SDK_PATH/SDKSettings.json" "$SDK_IDENTITY_PATH/"
cp "$SDK_PATH/SDKSettings.plist" "$SDK_IDENTITY_PATH/"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

write_tool_versions() {
    cat > "$BIN/uname" <<'SH'
#!/bin/sh
case "${1:-}" in
    -m) printf '%s\n' "${FIXTURE_HOST_ARCH:?}" ;;
    -s) printf 'Darwin\n' ;;
    *) /usr/bin/uname "$@" ;;
esac
SH

    cat > "$BIN/sw_vers" <<'SH'
#!/bin/sh
case "${1:-}" in
    -productVersion) printf '%s\n' "${FIXTURE_OS_VERSION:-27.0.1}" ;;
    -buildVersion) printf '%s\n' "${FIXTURE_OS_BUILD:-26A434}" ;;
    *) exit 2 ;;
esac
SH

    cat > "$BIN/xcodebuild" <<'SH'
#!/bin/sh
printf 'Xcode %s\nBuild version %s\n' \
    "${FIXTURE_XCODE_VERSION:-27.0}" "${FIXTURE_XCODE_BUILD:-27A266a}"
SH

    cat > "$BIN/xcode-select" <<'SH'
#!/bin/sh
printf '%s\n' "${FIXTURE_DEVELOPER_DIR:-/Applications/Xcode-fixture.app/Contents/Developer}"
SH

    cat > "$BIN/swift" <<'SH'
#!/bin/sh
printf 'swift-driver version: fixture Apple Swift version %s\n' \
    "${FIXTURE_SWIFT_VERSION:-6.4}"
SH

    cat > "$BIN/xcrun" <<'SH'
#!/bin/sh
case "$*" in
    "--sdk macosx --show-sdk-path") printf '%s\n' "${FIXTURE_SDK_PATH:?}" ;;
    "--sdk macosx --show-sdk-version") printf '%s\n' "${FIXTURE_SDK_VERSION:-27.0}" ;;
    "--sdk macosx --show-sdk-build-version") printf '%s\n' "${FIXTURE_SDK_BUILD:-27A123}" ;;
    "--sdk macosx --find clang") printf '%s\n' "${FIXTURE_CLANG:?}" ;;
    "--sdk macosx --find clang++") printf '%s\n' "${FIXTURE_CLANGXX:-${FIXTURE_CLANG:?}}" ;;
    *) echo "unexpected xcrun fixture arguments: $*" >&2; exit 2 ;;
esac
SH

    cat > "$BIN/clang" <<'SH'
#!/bin/sh
if [[ "${1:-}" == "--version" ]]; then
    printf 'Apple clang version %s (fixture)\n' "${FIXTURE_CLANG_VERSION:-21.0.0}"
    exit 0
fi
printf 'clang\n' >> "${FIXTURE_CLANG_LOG:?}"
args=()
for argument in "$@"; do
    if [[ "$argument" == "${FIXTURE_SDK_PATH:?}" ]]; then
        args+=("${FIXTURE_REAL_SDK_PATH:?}")
    else
        args+=("$argument")
    fi
done
exec "${FIXTURE_REAL_CLANG:?}" "${args[@]}"
SH

    cat > "$BIN/brew" <<'SH'
#!/bin/sh
if [[ "${1:-}" != "list" || "${2:-}" != "--versions" || -z "${3:-}" ]]; then
    echo "unexpected brew fixture arguments: $*" >&2
    exit 2
fi
case "$3" in
    autoconf) version="${FIXTURE_AUTOCONF_VERSION:-2.73}" ;;
    automake) version="${FIXTURE_AUTOMAKE_VERSION:-1.19}" ;;
    libtool) version="${FIXTURE_LIBTOOL_VERSION:-2.6.2}" ;;
    pkg-config) package="pkgconf"; version="${FIXTURE_PKGCONF_VERSION:-3.0.10}" ;;
    *) echo "unexpected brew formula fixture: $3" >&2; exit 2 ;;
esac
printf '%s %s\n' "${package:-$3}" "$version"
SH

    for tool in autoconf automake libtool make m4 perl pkg-config; do
        variable="FIXTURE_$(printf '%s' "$tool" | tr '[:lower:]-' '[:upper:]_')_VERSION"
        default="fixture-${tool}-1"
        cat > "$BIN/$tool" <<SH
#!/bin/sh
if [[ "\${1:-}" == "--version" || "\${1:-}" == "-v" ]]; then
    printf '%s %s\n' "$tool" "\${$variable:-$default}"
    exit 0
fi
exit 0
SH
    done

    cat > "$BIN/glibtool" <<'SH'
#!/bin/sh
printf 'glibtool (GNU libtool) %s\n' "${FIXTURE_LIBTOOL_VERSION:-2.6.2}"
SH

    cat > "$BIN/pkg-config" <<'SH'
#!/bin/sh
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "${FIXTURE_PKGCONF_VERSION:-3.0.10}"
else
    exit 0
fi
SH

    cat > "$BIN/make" <<'SH'
#!/bin/sh
if [[ "${1:-}" == "--version" || "${1:-}" == "-v" ]]; then
    printf 'GNU Make %s\n' "${FIXTURE_MAKE_VERSION:-3.81}"
    exit 0
fi
target=""
for argument in "$@"; do
    case "$argument" in
        install|install_sw|install-strip) target="$argument" ;;
    esac
done
if [[ -z "$target" ]]; then
    printf 'build\t%s\n' "$PWD" >> "${FIXTURE_MAKE_LOG:?}"
    exit 0
fi
prefix="$(sed -n 's/^PREFIX=//p' Makefile)"
[[ -n "$prefix" ]] || {
    echo "fixture make: Configure did not write PREFIX" >&2
    exit 1
}
arch="$(basename "$(dirname "$prefix")")"
template="${FIXTURE_PREFIX_TEMPLATE_ROOT:?}/prefix-template-$arch"
printf '%s\t%s\n' "$target" "$prefix" >> "${FIXTURE_MAKE_LOG:?}"
mkdir -p "$prefix"
if [[ "$target" == "install" ]]; then
    ditto "$template" "$prefix"
else
    mkdir -p "$prefix/include/openssl" "$prefix/lib/pkgconfig"
    printf '/* fixture OpenSSL */\n' > "$prefix/include/openssl/ssl.h"
    printf '/* fixture OpenSSL */\n' > "$prefix/include/openssl/crypto.h"
    printf '/* fixture OpenSSL */\n' > "$prefix/include/openssl/evp.h"
    printf 'prefix=%s\nexec_prefix=${prefix}\nlibdir=${exec_prefix}/lib\nincludedir=${prefix}/include\n' \
        "$prefix" > "$prefix/lib/pkgconfig/libcrypto.pc"
    cp "$prefix/lib/pkgconfig/libcrypto.pc" "$prefix/lib/pkgconfig/libssl.pc"
    cp "$prefix/lib/pkgconfig/libcrypto.pc" "$prefix/lib/pkgconfig/openssl.pc"
    for library in libcrypto.3.dylib libssl.3.dylib; do
        cp "$template/lib/$library" "$prefix/lib/$library"
    done
fi
SH

    chmod +x "$BIN"/*
}

write_sdk_utility() {
    local name="$1"
    cat > "$BIN/$name" <<SH
#!/bin/sh
exec "${SDK_PATH}/usr/bin/$name" "\$@"
SH
    chmod +x "$BIN/$name"
}

# Keep the real Mach-O inspection tools available while the compiler facade
# records helper invocations.
for tool in lipo vtool otool install_name_tool; do
    real="$(command -v "$tool" 2>/dev/null || true)"
    [[ -n "$real" ]] || fail "required host tool is missing: $tool"
    cat > "$BIN/$tool" <<SH
#!/bin/sh
if [[ -n "\${FIXTURE_${tool}_STATUS:-}" ]]; then
    echo "fixture $tool failure" >&2
    exit "\${FIXTURE_${tool}_STATUS}"
fi
if [[ "$tool" == "lipo" && "\${1:-}" == "-create" &&
    -n "\${FIXTURE_LIPO_CREATE_STATUS:-}" ]]; then
    echo "fixture lipo creation failure" >&2
    exit "\${FIXTURE_LIPO_CREATE_STATUS}"
fi
exec "$real" "\$@"
SH
    chmod +x "$BIN/$tool"
done

cat > "$BIN/python3" <<'SH'
#!/bin/sh
if [[ -n "${FIXTURE_PARSER_STATUS:-}" ]]; then
    case "$*" in
        *otool-dependencies.py|*otool-rpaths.py)
            echo "fixture parser failure" >&2
            exit "$FIXTURE_PARSER_STATUS"
            ;;
    esac
fi
exec /usr/bin/python3 "$@"
SH
chmod +x "$BIN/python3"

write_tool_versions

tool_env() {
    local arch="$1"
    shift
    env \
        PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
        FIXTURE_HOST_ARCH="$HOST_ARCH" \
        FIXTURE_SDK_PATH="$SDK_IDENTITY_PATH" \
        FIXTURE_REAL_SDK_PATH="$SDK_PATH" \
        FIXTURE_CLANG="$BIN/clang" \
        FIXTURE_CLANGXX="$BIN/clang" \
        CFLAGS="" \
        FIXTURE_REAL_CLANG="$REAL_CLANG" \
        FIXTURE_CLANG_LOG="$TEST_ROOT/clang.log" \
        FIXTURE_MAKE_LOG="$TEST_ROOT/make.log" \
        FIXTURE_PREFIX_TEMPLATE_ROOT="$TEST_ROOT" \
        "$@"
}

prepare_key() {
    local project="$1"
    local arch="$2"
    shift 2
    tool_env "$arch" \
        python3 "$project/scripts/mobile-battery-cache.py" prepare-key \
        --root "$project" \
        --arch "$arch" \
        --minimum-macos "${KEY_MINIMUM_MACOS:-13.0}" "$@"
}

prepare_github_output_key() {
    local output_file="$1"
    local output_name="$2"
    tool_env "$HOST_ARCH" \
        python3 "$PROJECT/scripts/mobile-battery-cache.py" prepare-key \
        --root "$PROJECT" \
        --arch "$HOST_ARCH" \
        --minimum-macos 13.0 \
        --github-output "$output_file" \
        --output-name "$output_name"
}

make_seed_repository() {
    local name="$1"
    local destination="$2"
    git init --quiet --initial-branch=main "$destination"
    git -C "$destination" config user.name "Status Trio Cache Tests"
    git -C "$destination" config user.email "cache-tests@status-trio.invalid"
    cp "$TEST_ROOT/seed-Configure" "$destination/Configure"
    cp "$TEST_ROOT/seed-autogen.sh" "$destination/autogen.sh"
    cp "$TEST_ROOT/seed-configure" "$destination/configure"
    chmod +x "$destination/Configure" "$destination/autogen.sh" "$destination/configure"
    printf '%s fixture license\n' "$name" > "$destination/LICENSE"
    git -C "$destination" add .
    git -C "$destination" commit --quiet -m "fixture source"
}

write_seed_build_files() {
    cat > "$TEST_ROOT/seed-Configure" <<'SH'
#!/bin/sh
prefix=""
openssldir=""
for argument in "$@"; do
    case "$argument" in
        --prefix=*) prefix="${argument#--prefix=}" ;;
        --openssldir=*) openssldir="${argument#--openssldir=}" ;;
    esac
done
[[ -n "$prefix" && -n "$openssldir" ]] || exit 2
printf 'PREFIX=%s\nOPENSSLDIR=%s\n' "$prefix" "$openssldir" > Makefile
SH
    cat > "$TEST_ROOT/seed-configure" <<'SH'
#!/bin/sh
prefix=""
for argument in "$@"; do
    case "$argument" in
        --prefix=*) prefix="${argument#--prefix=}" ;;
    esac
done
[[ -n "$prefix" ]] || exit 2
printf 'PREFIX=%s\n' "$prefix" > Makefile
SH
    cat > "$TEST_ROOT/seed-autogen.sh" <<'SH'
#!/bin/sh
exit 0
SH
}

write_project() {
    local project="$1"
    local seed_commit="${2:-}"
    mkdir -p \
        "$project/scripts" \
        "$project/Support/MobileBatteryHelper/ThirdPartyNotices" \
        "$project/.build/mobile-battery/sources"

    cp "$ROOT/scripts/build-mobile-battery-helper.sh" "$project/scripts/"
    cp "$ROOT/scripts/mobile-battery-cache.py" "$project/scripts/"
    cp "$ROOT/scripts/build-timing.sh" "$project/scripts/"
    cp "$ROOT/scripts/verify-platform-version.sh" "$project/scripts/"
    cp "$ROOT/scripts/check-mobile-battery-dependency.sh" "$project/scripts/"
    cp "$ROOT/scripts/check-mobile-battery-rpath.sh" "$project/scripts/"
    cp "$ROOT/scripts/otool-dependencies.py" "$project/scripts/"
    cp "$ROOT/scripts/otool-rpaths.py" "$project/scripts/"

    cat > "$project/scripts/prepare-mobile-battery-sources.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'prepare-mobile-battery-sources called\n' >> "${FIXTURE_PREPARE_LOG:?}"
SH
    chmod +x "$project/scripts/prepare-mobile-battery-sources.sh"

    cat > "$project/Support/MobileBatteryHelper/main.m" <<'OBJC'
#include <stdlib.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/companion_proxy.h>
#include <libimobiledevice/lockdown.h>
#include <plist/plist.h>
#include <usbmuxd.h>
int main(void) { return 0; }
OBJC
    printf 'int status_trio_native_client_fixture(void) { return 0; }\n' \
        > "$project/Support/MobileBatteryHelper/NativeBatteryClient.m"
    printf '#import <Foundation/Foundation.h>\n' \
        > "$project/Support/MobileBatteryHelper/NativeBatteryClient.h"
    printf '# Fixture notices\n' \
        > "$project/Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md"
    for name in \
        openssl libplist libimobiledevice-glue libusbmuxd libtatsu libimobiledevice; do
        mkdir -p "$project/Support/MobileBatteryHelper/ThirdPartyNotices/$name"
        printf 'fixture source license\n' \
            > "$project/Support/MobileBatteryHelper/ThirdPartyNotices/$name/LICENSE"
    done

    [[ -n "$seed_commit" ]] || return 0
    python3 - "$project/Support/mobile-battery-dependencies.json" \
        "$seed_commit" "$TEST_ROOT/source-seed" <<'PY'
import json
import sys

path, commit, repository = sys.argv[1:]
names = [
    "openssl",
    "libplist",
    "libimobiledevice-glue",
    "libusbmuxd",
    "libtatsu",
    "libimobiledevice",
]
manifest = {
    "schemaVersion": 1,
    "minimumMacOS": "13.0",
    "sourceBuildOrder": names,
    "dependencies": [
        {
            "name": name,
            "repository": repository,
            "version": "1.0.0",
            "commit": commit,
        }
        for name in names
    ],
}
with open(path, "w") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
    for name in \
        openssl libplist libimobiledevice-glue libusbmuxd libtatsu libimobiledevice; do
        git clone --quiet "$TEST_ROOT/source-seed" \
            "$project/.build/mobile-battery/sources/$name"
    done
}

make_dylib() {
    local arch="$1"
    local install_name="$2"
    local output="$3"
    local prefix="${install_name%/*}"
    "$REAL_CLANG" -arch "$arch" -dynamiclib -isysroot "$SDK_PATH" \
        -mmacosx-version-min=13.0 \
        -install_name "$install_name" \
        -Wl,-rpath,"$prefix" \
        "$TEST_ROOT/fixture.c" \
        -o "$output"
}

make_prefix_template() {
    local arch="$1"
    local prefix="$2"
    local template="$3"
    rm -rf "$template"
    mkdir -p "$template/include/libimobiledevice" \
        "$template/include/libimobiledevice-glue" \
        "$template/include/libtatsu" \
        "$template/include/openssl" \
        "$template/include/plist" \
        "$template/lib/pkgconfig"

    local actual_libraries=(
        libcrypto.3.dylib
        libssl.3.dylib
        libplist-2.0.12.dylib
        libplist++-2.0.12.dylib
        libimobiledevice-glue-1.0.0.dylib
        libusbmuxd-2.0.7.dylib
        libtatsu.0.dylib
        libimobiledevice-1.0.6.dylib
    )
    local library
    for library in "${actual_libraries[@]}"; do
        make_dylib "$arch" "$prefix/lib/$library" "$template/lib/$library"
    done
    ln -s libcrypto.3.dylib "$template/lib/libcrypto.dylib"
    ln -s libssl.3.dylib "$template/lib/libssl.dylib"
    ln -s libplist-2.0.12.dylib "$template/lib/libplist-2.0.dylib"
    ln -s libimobiledevice-glue-1.0.0.dylib \
        "$template/lib/libimobiledevice-glue-1.0.dylib"
    ln -s libusbmuxd-2.0.7.dylib "$template/lib/libusbmuxd-2.0.dylib"
    ln -s libtatsu.0.dylib "$template/lib/libtatsu.dylib"
    ln -s libimobiledevice-1.0.6.dylib "$template/lib/libimobiledevice-1.0.dylib"
    ln -s libplist++-2.0.12.dylib "$template/lib/libplist++-2.0.dylib"

    cat > "$template/lib/libplist-2.0.la" <<'LA'
dlname='libplist-2.0.12.dylib'
library_names='libplist-2.0.12.dylib libplist-2.0.dylib'
libdir='PREFIX/lib'
LA
    cat > "$template/lib/libplist++-2.0.la" <<'LA'
dlname='libplist++-2.0.12.dylib'
library_names='libplist++-2.0.12.dylib libplist++-2.0.dylib'
libdir='PREFIX/lib'
LA
    cat > "$template/lib/libimobiledevice-glue-1.0.la" <<'LA'
dlname='libimobiledevice-glue-1.0.0.dylib'
library_names='libimobiledevice-glue-1.0.0.dylib libimobiledevice-glue-1.0.dylib'
libdir='PREFIX/lib'
LA
    cat > "$template/lib/libusbmuxd-2.0.la" <<'LA'
dlname='libusbmuxd-2.0.7.dylib'
library_names='libusbmuxd-2.0.7.dylib libusbmuxd-2.0.dylib'
libdir='PREFIX/lib'
LA
    cat > "$template/lib/libtatsu.la" <<'LA'
dlname='libtatsu.0.dylib'
library_names='libtatsu.0.dylib libtatsu.dylib'
libdir='PREFIX/lib'
LA
    cat > "$template/lib/libimobiledevice-1.0.la" <<'LA'
dlname='libimobiledevice-1.0.6.dylib'
library_names='libimobiledevice-1.0.6.dylib libimobiledevice-1.0.dylib'
libdir='PREFIX/lib'
dependency_libs=''
LA
    local file
    while IFS= read -r -d '' file; do
        perl -0pi -e "s#PREFIX#$prefix#g" "$file"
    done < <(find "$template/lib" -maxdepth 1 -name '*.la' -print0)

    local header
    for header in \
        include/libimobiledevice/companion_proxy.h \
        include/libimobiledevice/libimobiledevice.h \
        include/libimobiledevice/lockdown.h \
        include/libimobiledevice-glue/collection.h \
        include/libimobiledevice-glue/glue.h \
        include/libtatsu/tatsu.h \
        include/libtatsu/tss.h \
        include/openssl/crypto.h \
        include/openssl/evp.h \
        include/openssl/ssl.h \
        include/plist/plist++.h \
        include/plist/plist.h \
        include/usbmuxd-proto.h \
        include/usbmuxd.h; do
        mkdir -p "$template/$(dirname "$header")"
        printf '/* fixture %s */\n' "$header" > "$template/$header"
    done

    local pc
    for pc in \
        libcrypto \
        libimobiledevice-1.0 \
        libimobiledevice-glue-1.0 \
        libplist++-2.0 \
        libplist-2.0 \
        libssl \
        libtatsu-1.0 \
        libusbmuxd-2.0 \
        openssl; do
        cat > "$template/lib/pkgconfig/$pc.pc" <<EOF
prefix=$prefix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: $pc
Description: synthetic cache fixture
Version: 1.0.0
Libs: -L\${libdir}
Cflags: -I\${includedir}
EOF
    done
}

write_seed_build_files
printf 'int status_trio_cache_fixture(void) { return 42; }\n' > "$TEST_ROOT/fixture.c"

git init --quiet --initial-branch=main "$TEST_ROOT/source-seed"
git -C "$TEST_ROOT/source-seed" config user.name "Status Trio Cache Tests"
git -C "$TEST_ROOT/source-seed" config user.email "cache-tests@status-trio.invalid"
cp "$TEST_ROOT/seed-Configure" "$TEST_ROOT/source-seed/Configure"
cp "$TEST_ROOT/seed-autogen.sh" "$TEST_ROOT/source-seed/autogen.sh"
cp "$TEST_ROOT/seed-configure" "$TEST_ROOT/source-seed/configure"
chmod +x \
    "$TEST_ROOT/source-seed/Configure" \
    "$TEST_ROOT/source-seed/autogen.sh" \
    "$TEST_ROOT/source-seed/configure"
printf 'fixture source license\n' > "$TEST_ROOT/source-seed/LICENSE"
git -C "$TEST_ROOT/source-seed" add .
git -C "$TEST_ROOT/source-seed" commit --quiet -m "fixture source"
SEED_COMMIT="$(git -C "$TEST_ROOT/source-seed" rev-parse HEAD)"

write_project "$PROJECT" "$SEED_COMMIT"
PREFIX="$PROJECT/.build/mobile-battery/$HOST_ARCH/prefix"
MARKER="$PROJECT/.build/mobile-battery/$HOST_ARCH/.dependencies-cache.json"
SEED_PREFIX_TEMPLATE="$TEST_ROOT/prefix-template-$HOST_ARCH"
make_prefix_template "$HOST_ARCH" \
    "$PREFIX" \
    "$SEED_PREFIX_TEMPLATE"
make_prefix_template "$OTHER_ARCH" \
    "$PROJECT/.build/mobile-battery/$OTHER_ARCH/prefix" \
    "$TEST_ROOT/prefix-template-$OTHER_ARCH"
mkdir -p "$PREFIX"
cp -RP "$SEED_PREFIX_TEMPLATE/." "$PREFIX/"

export FIXTURE_PREPARE_LOG="$TEST_ROOT/prepare.log"
BASELINE_KEY="$(prepare_key "$PROJECT" "$HOST_ARCH")"
[[ "$BASELINE_KEY" =~ ^status-trio-mobile-battery-v2- ]] ||
    fail "cache key has an unexpected shape: $BASELINE_KEY"

GITHUB_OUTPUT="$TEST_ROOT/github-output"
: > "$GITHUB_OUTPUT"
OUTPUT_KEY="$(prepare_github_output_key "$GITHUB_OUTPUT" key_ci)"
[[ "$OUTPUT_KEY" == "$BASELINE_KEY" ]] ||
    fail "GitHub output key differs from the printed key"
grep -Fxq "key_ci=$BASELINE_KEY" "$GITHUB_OUTPUT" ||
    fail "prepare-key did not append the requested GitHub output"

expect_key_change() {
    local label="$1"
    local key="$2"
    [[ "$key" != "$BASELINE_KEY" ]] ||
        fail "$label did not invalidate the cache key"
}

KEY_MINIMUM_MACOS=13.1 expect_key_change \
    "deployment target" "$(KEY_MINIMUM_MACOS=13.1 prepare_key "$PROJECT" "$HOST_ARCH")"

FIXTURE_XCODE_VERSION=27.0.1 expect_key_change \
    "Xcode version" "$(FIXTURE_XCODE_VERSION=27.0.1 prepare_key "$PROJECT" "$HOST_ARCH")"
FIXTURE_SWIFT_VERSION=6.4.1 expect_key_change \
    "Swift version" "$(FIXTURE_SWIFT_VERSION=6.4.1 prepare_key "$PROJECT" "$HOST_ARCH")"
FIXTURE_CLANG_VERSION=21.0.1 expect_key_change \
    "Clang version" "$(FIXTURE_CLANG_VERSION=21.0.1 prepare_key "$PROJECT" "$HOST_ARCH")"
FIXTURE_SDK_VERSION=27.1 expect_key_change \
    "SDK version" "$(FIXTURE_SDK_VERSION=27.1 prepare_key "$PROJECT" "$HOST_ARCH")"
cp "$SDK_IDENTITY_PATH/SDKSettings.json" "$TEST_ROOT/sdk-settings.saved"
printf '\n' >> "$SDK_IDENTITY_PATH/SDKSettings.json"
SDK_SETTINGS_KEY="$(prepare_key "$PROJECT" "$HOST_ARCH")"
cp "$TEST_ROOT/sdk-settings.saved" "$SDK_IDENTITY_PATH/SDKSettings.json"
expect_key_change "SDK settings contents" "$SDK_SETTINGS_KEY"
FIXTURE_AUTOCONF_VERSION=2.74 expect_key_change \
    "Homebrew tool version" \
    "$(FIXTURE_AUTOCONF_VERSION=2.74 prepare_key "$PROJECT" "$HOST_ARCH")"

cp "$PROJECT/Support/mobile-battery-dependencies.json" "$TEST_ROOT/manifest.saved"
printf '\n' >> "$PROJECT/Support/mobile-battery-dependencies.json"
MANIFEST_KEY="$(prepare_key "$PROJECT" "$HOST_ARCH")"
cp "$TEST_ROOT/manifest.saved" \
    "$PROJECT/Support/mobile-battery-dependencies.json"
expect_key_change "manifest" "$MANIFEST_KEY"

cp "$PROJECT/scripts/prepare-mobile-battery-sources.sh" "$TEST_ROOT/prepare.saved"
printf '# key invalidation fixture\n' >> \
    "$PROJECT/scripts/prepare-mobile-battery-sources.sh"
SCRIPT_KEY="$(prepare_key "$PROJECT" "$HOST_ARCH")"
cp "$TEST_ROOT/prepare.saved" \
    "$PROJECT/scripts/prepare-mobile-battery-sources.sh"
expect_key_change "source preparation script" "$SCRIPT_KEY"

cp -R "$PROJECT" "$OTHER_PROJECT"
PATH_KEY="$(prepare_key "$OTHER_PROJECT" "$HOST_ARCH")"
expect_key_change "canonical prefix path" "$PATH_KEY"

if tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
    validate --root "$PROJECT" --arch "$HOST_ARCH" \
    --expected-key "$BASELINE_KEY" \
    > "$TEST_ROOT/pre-marker.log" 2>&1; then
    fail "cache prefix without a marker was accepted"
else
    status=$?
    [[ "$status" == "11" ]] ||
        fail "cache prefix without a marker exited $status instead of 11"
fi
grep -Fqi 'without a marker' "$TEST_ROOT/pre-marker.log" ||
    fail "prefix-without-marker failure was not explained"

tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
    seal --root "$PROJECT" --arch "$HOST_ARCH" \
    --expected-key "$BASELINE_KEY"
tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
    validate --root "$PROJECT" --arch "$HOST_ARCH" \
    --expected-key "$BASELINE_KEY"

expect_invalid() {
    local label="$1"
    if tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
        validate --root "$PROJECT" --arch "$HOST_ARCH" \
        --expected-key "$BASELINE_KEY" \
        > "$TEST_ROOT/invalid.log" 2>&1; then
        fail "$label was accepted"
    else
        status=$?
        [[ "$status" == "11" ]] ||
            fail "$label exited $status instead of 11"
    fi
}

refresh_marker_inventory() {
    tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
        inventory --root "$PROJECT" --arch "$HOST_ARCH" \
        > "$TEST_ROOT/inventory.json"
    python3 - "$MARKER" "$TEST_ROOT/inventory.json" <<'PY'
import hashlib
import json
import sys

marker_path, inventory_path = sys.argv[1:]
with open(marker_path) as handle:
    marker = json.load(handle)
with open(inventory_path) as handle:
    entries = json.load(handle)
payload = json.dumps(entries, sort_keys=True, separators=(",", ":"))
marker["inventory"] = entries
marker["inventorySha256"] = hashlib.sha256(payload.encode()).hexdigest()
with open(marker_path, "w") as handle:
    json.dump(marker, handle)
PY
}

PREFIX="$PROJECT/.build/mobile-battery/$HOST_ARCH/prefix"
MARKER="$PROJECT/.build/mobile-battery/$HOST_ARCH/.dependencies-cache.json"

PREFIX_KEY="$(prepare_key "$PROJECT" "$HOST_ARCH")"
tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
    validate --root "$PROJECT" --arch "$HOST_ARCH" \
    --expected-key "$PREFIX_KEY"

PREFIX_INODE_BEFORE="$(stat -f '%i' "$PREFIX")"
PREFIX_MTIME_BEFORE="$(stat -f '%m' "$PREFIX")"
SDK_PATH_KEY_BEFORE="$PREFIX_KEY"
SDK_PATH_KEY_AFTER="$(prepare_key "$PROJECT" "$HOST_ARCH")"
[[ "$SDK_PATH_KEY_AFTER" == "$SDK_PATH_KEY_BEFORE" ]] ||
    fail "SDK key changed on an unchanged SDK tree"
[[ "$(stat -f '%i' "$PREFIX")" == "$PREFIX_INODE_BEFORE" &&
    "$(stat -f '%m' "$PREFIX")" == "$PREFIX_MTIME_BEFORE" ]] ||
    fail "key generation or validation mutated the cached prefix"

cp "$PREFIX/include/libimobiledevice/lockdown.h" "$TEST_ROOT/lockdown.saved"
printf 'corrupt\n' >> "$PREFIX/include/libimobiledevice/lockdown.h"
expect_invalid "corrupt required header"
grep -Fqi 'digest' "$TEST_ROOT/invalid.log" ||
    fail "corruption failure did not report a digest mismatch"
cp "$TEST_ROOT/lockdown.saved" "$PREFIX/include/libimobiledevice/lockdown.h"

rm "$PREFIX/lib/libtatsu.0.dylib"
expect_invalid "missing required library"
grep -Fqi 'libtatsu' "$TEST_ROOT/invalid.log" ||
    fail "missing library failure did not name the library"
cp "$TEST_ROOT/prefix-template-$HOST_ARCH/lib/libtatsu.0.dylib" "$PREFIX/lib/"

rm "$PREFIX/include/usbmuxd.h"
expect_invalid "missing required header"
grep -Fqi 'usbmuxd.h' "$TEST_ROOT/invalid.log" ||
    fail "missing header failure did not name the header"
cp "$TEST_ROOT/prefix-template-$HOST_ARCH/include/usbmuxd.h" "$PREFIX/include/"

rm "$PREFIX/lib/pkgconfig/libcrypto.pc"
expect_invalid "missing pkg-config metadata"
grep -Fqi 'pkg-config' "$TEST_ROOT/invalid.log" ||
    fail "missing pkg-config failure was not explained"
cp "$TEST_ROOT/prefix-template-$HOST_ARCH/lib/pkgconfig/libcrypto.pc" \
    "$PREFIX/lib/pkgconfig/"

ln -sfn ../../../../outside "$PREFIX/lib/libplist-2.0.dylib"
expect_invalid "escaping symlink"
grep -Fqi 'symlink' "$TEST_ROOT/invalid.log" ||
    fail "escaping symlink failure was not explained"
ln -sfn libplist-2.0.12.dylib "$PREFIX/lib/libplist-2.0.dylib"

ln -sfn missing-libplist.dylib "$PREFIX/lib/libplist-2.0.dylib"
expect_invalid "broken symlink"
grep -Fqi 'required library' "$TEST_ROOT/invalid.log" ||
    fail "broken symlink failure was not explained"
ln -sfn libplist-2.0.12.dylib "$PREFIX/lib/libplist-2.0.dylib"

printf 'unexpected\n' > "$PREFIX/lib/unexpected.txt"
expect_invalid "unexpected file"
grep -Fqi 'unexpected' "$TEST_ROOT/invalid.log" ||
    fail "unexpected file failure was not explained"
rm "$PREFIX/lib/unexpected.txt"

cp "$PREFIX/lib/pkgconfig/libcrypto.pc" "$TEST_ROOT/libcrypto.pc.saved"
sed -i '' 's#^prefix=.*#prefix=/tmp/not-the-cached-prefix#' \
    "$PREFIX/lib/pkgconfig/libcrypto.pc"
expect_invalid "pkg-config path outside prefix"
grep -Fqi 'pkg-config' "$TEST_ROOT/invalid.log" ||
    fail "pkg-config path failure was not explained"
cp "$TEST_ROOT/libcrypto.pc.saved" "$PREFIX/lib/pkgconfig/libcrypto.pc"

cp "$MARKER" "$TEST_ROOT/marker.before-libtool.saved"
cp "$PREFIX/lib/libimobiledevice-1.0.la" "$TEST_ROOT/libimobiledevice.la.saved"
python3 - "$PREFIX/lib/libimobiledevice-1.0.la" <<'PY'
import sys

path = sys.argv[1]
with open(path) as handle:
    lines = handle.readlines()
with open(path, "w") as handle:
    for line in lines:
        if line.startswith("dependency_libs="):
            line = "dependency_libs='-L/tmp/not-the-cached-prefix/lib -lssl'\n"
        handle.write(line)
PY
refresh_marker_inventory
expect_invalid "libtool path outside prefix"
grep -Fqi 'absolute path' "$TEST_ROOT/invalid.log" ||
    fail "libtool path failure was not explained"
cp "$TEST_ROOT/libimobiledevice.la.saved" \
    "$PREFIX/lib/libimobiledevice-1.0.la"
cp "$TEST_ROOT/marker.before-libtool.saved" "$MARKER"

sed -i '' \
    's#^libdir=.*#libdir='\''/tmp/not-the-cached-prefix/lib'\''#' \
    "$PREFIX/lib/libimobiledevice-1.0.la"
refresh_marker_inventory
expect_invalid "libtool libdir outside prefix"
grep -Fqi 'libtool libdir' "$TEST_ROOT/invalid.log" ||
    fail "libtool libdir failure was not explained"
cp "$TEST_ROOT/libimobiledevice.la.saved" \
    "$PREFIX/lib/libimobiledevice-1.0.la"
cp "$TEST_ROOT/marker.before-libtool.saved" "$MARKER"

cp "$MARKER" "$TEST_ROOT/marker.saved"
python3 - "$MARKER" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    marker = json.load(handle)
marker["cacheKey"] = "tampered"
with open(path, "w") as handle:
    json.dump(marker, handle)
PY
expect_invalid "stale marker key"
cp "$TEST_ROOT/marker.saved" "$MARKER"

mutate_marker_inventory() {
    local mutation="$1"
    python3 - "$MARKER" "$mutation" <<'PY'
import json
import sys

path, mutation = sys.argv[1:]
with open(path) as handle:
    marker = json.load(handle)
if mutation == "null-entry":
    marker["inventory"].append(None)
elif mutation == "path-only-entry":
    marker["inventory"].append({"path": "lib"})
elif mutation == "duplicate-path":
    marker["inventory"].append(dict(marker["inventory"][0]))
elif mutation == "inventory-digest":
    marker["inventorySha256"] = "0" * 64
else:
    raise SystemExit(f"unknown marker mutation: {mutation}")
with open(path, "w") as handle:
    json.dump(marker, handle)
PY
}

for mutation in null-entry path-only-entry duplicate-path inventory-digest; do
    cp "$TEST_ROOT/marker.saved" "$MARKER"
    mutate_marker_inventory "$mutation"
    expect_invalid "malformed marker inventory ($mutation)"
done
cp "$TEST_ROOT/marker.saved" "$MARKER"

cp "$PREFIX/lib/libtatsu.0.dylib" "$TEST_ROOT/libtatsu.arm64.saved"
cp "$MARKER" "$TEST_ROOT/marker.before-wrong-arch.saved"
make_dylib "$OTHER_ARCH" "$PREFIX/lib/libtatsu.0.dylib" \
    "$PREFIX/lib/libtatsu.0.dylib"
refresh_marker_inventory
expect_invalid "wrong architecture"
grep -Fqi 'architecture' "$TEST_ROOT/invalid.log" ||
    fail "wrong architecture failure was not explained"
cp "$TEST_ROOT/libtatsu.arm64.saved" "$PREFIX/lib/libtatsu.0.dylib"
cp "$TEST_ROOT/marker.before-wrong-arch.saved" "$MARKER"

if tool_env "$HOST_ARCH" FIXTURE_vtool_STATUS=71 python3 \
    "$PROJECT/scripts/mobile-battery-cache.py" validate \
    --root "$PROJECT" --arch "$HOST_ARCH" --expected-key "$BASELINE_KEY" \
    > "$TEST_ROOT/tool-failure.log" 2>&1; then
    fail "vtool failure was accepted"
else
    status=$?
    [[ "$status" == "2" ]] ||
        fail "vtool failure exited $status instead of hard-error status 2"
fi
grep -Fqi 'command failed' "$TEST_ROOT/tool-failure.log" ||
    fail "vtool failure was not distinguished from a cache miss"

if tool_env "$HOST_ARCH" FIXTURE_lipo_STATUS=72 python3 \
    "$PROJECT/scripts/mobile-battery-cache.py" validate \
    --root "$PROJECT" --arch "$HOST_ARCH" --expected-key "$BASELINE_KEY" \
    > "$TEST_ROOT/tool-failure.log" 2>&1; then
    fail "lipo failure was accepted"
else
    status=$?
    [[ "$status" == "2" ]] ||
        fail "lipo failure exited $status instead of hard-error status 2"
fi

if tool_env "$HOST_ARCH" FIXTURE_otool_STATUS=73 python3 \
    "$PROJECT/scripts/mobile-battery-cache.py" validate \
    --root "$PROJECT" --arch "$HOST_ARCH" --expected-key "$BASELINE_KEY" \
    > "$TEST_ROOT/tool-failure.log" 2>&1; then
    fail "otool failure was accepted"
else
    status=$?
    [[ "$status" == "2" ]] ||
        fail "otool failure exited $status instead of hard-error status 2"
fi

if tool_env "$HOST_ARCH" FIXTURE_PARSER_STATUS=74 python3 \
    "$PROJECT/scripts/mobile-battery-cache.py" validate \
    --root "$PROJECT" --arch "$HOST_ARCH" --expected-key "$BASELINE_KEY" \
    > "$TEST_ROOT/parser-failure.log" 2>&1; then
    fail "otool parser failure was accepted"
else
    status=$?
    [[ "$status" == "2" ]] ||
        fail "otool parser failure exited $status instead of hard-error status 2"
fi
grep -Fqi 'command failed' "$TEST_ROOT/parser-failure.log" ||
    fail "otool parser failure was not distinguished from a cache miss"

rm -rf "$PREFIX"
expect_invalid "missing prefix with stale marker"

# Rebuild the synthetic fixture from scratch through the production script.
# The fake dependency installer is quick, while all cache inspection uses the
# real lipo/vtool/otool binaries.
rm -rf "$PROJECT/.build/mobile-battery/$HOST_ARCH"
: > "$TEST_ROOT/make.log"
: > "$TEST_ROOT/clang.log"
: > "$FIXTURE_PREPARE_LOG"
status=0
tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=0 \
    BUILD_JOBS=1 \
    BUILD_TIMING_FILE="$TEST_ROOT/timing.tsv" \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/cold-build.log" 2>&1 || status=$?
if (( status != 0 )); then
    cat "$TEST_ROOT/cold-build.log" >&2
    fail "cold build exited $status"
fi

grep -Fqi 'cache miss' "$TEST_ROOT/cold-build.log" ||
    fail "cold build did not report a cache miss"
grep -Fqi 'third-party dependency build skipped' "$TEST_ROOT/cold-build.log" &&
    fail "cold build reported a skipped dependency build"
[[ -f "$MARKER" ]] || fail "cold build did not seal the cache marker"
[[ -x "$PROJECT/.build/mobile-battery/package/Helpers/StatusTrioMobileBatteryHelper" ]] ||
    fail "cold build did not produce a helper"
COLD_MAKE_LINES="$(wc -l < "$TEST_ROOT/make.log" | tr -d ' ')"
COLD_CLANG_LINES="$(wc -l < "$TEST_ROOT/clang.log" | tr -d ' ')"
[[ "$COLD_MAKE_LINES" == 12 ]] ||
    fail "cold build did not exercise the synthetic dependency installers"
[[ "$(wc -l < "$FIXTURE_PREPARE_LOG" | tr -d ' ')" == "1" ]] ||
    fail "cold build did not verify pinned sources exactly once"

tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=0 \
    BUILD_JOBS=1 \
    BUILD_TIMING_FILE="$TEST_ROOT/timing.tsv" \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/warm-build.log" 2>&1

grep -Fqi 'cache candidate' "$TEST_ROOT/warm-build.log" ||
    fail "warm build did not report the restored/local cache candidate"
grep -Fqi 'cache validated' "$TEST_ROOT/warm-build.log" ||
    fail "warm build did not report validation"
grep -Fqi 'third-party dependency build skipped' "$TEST_ROOT/warm-build.log" ||
    fail "warm build did not report the skipped dependency build"
[[ "$(wc -l < "$TEST_ROOT/make.log" | tr -d ' ')" == "$COLD_MAKE_LINES" ]] ||
    fail "warm build invoked a synthetic dependency installer"
[[ "$(wc -l < "$TEST_ROOT/clang.log" | tr -d ' ')" -gt "$COLD_CLANG_LINES" ]] ||
    fail "warm build did not rebuild the final helper"
[[ "$(wc -l < "$FIXTURE_PREPARE_LOG" | tr -d ' ')" == "1" ]] ||
    fail "warm build checked out pinned sources despite a validated cache"

grep -Fq $'mobile-dependencies-'"$HOST_ARCH"$'\t' "$TEST_ROOT/timing.tsv" ||
    fail "dependency phase timing was not recorded"
grep -Fq $'mobile-helper-'"$HOST_ARCH"$'\t' "$TEST_ROOT/timing.tsv" ||
    fail "helper phase timing was not recorded"
grep -Fq $'mobile-source-checkout\t' "$TEST_ROOT/timing.tsv" ||
    fail "source checkout phase timing was not recorded"
grep -Fq $'mobile-package\t' "$TEST_ROOT/timing.tsv" ||
    fail "package phase timing was not recorded"

assert_universal_slices() {
    local binary="$1"
    local archs
    archs="$(lipo -archs "$binary" | tr '\n\t' '  ')"
    [[ " $archs " == *" arm64 "* ]] ||
        fail "universal binary is missing arm64: $binary ($archs)"
    [[ " $archs " == *" x86_64 "* ]] ||
        fail "universal binary is missing x86_64: $binary ($archs)"
}

assert_no_development_rpaths() {
    local binary="$1"
    local rpaths
    rpaths="$(otool -l "$binary" |
        python3 "$PROJECT/scripts/otool-rpaths.py")"
    [[ "$rpaths" != *"/.build/mobile-battery/"* ]] ||
        fail "packaged binary retains a development rpath: $binary ($rpaths)"
}

# Universal links must strip each architecture's prefix rpath before lipo.
# The synthetic prefixes intentionally carry distinct arm64/x86_64 rpaths.
rm -rf \
    "$PROJECT/.build/mobile-battery/$HOST_ARCH" \
    "$PROJECT/.build/mobile-battery/$OTHER_ARCH"
: > "$TEST_ROOT/make.log"
: > "$TEST_ROOT/clang.log"
: > "$FIXTURE_PREPARE_LOG"
status=0
tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=1 \
    BUILD_JOBS=1 \
    BUILD_TIMING_FILE="$TEST_ROOT/timing.tsv" \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/universal-cold-build.log" 2>&1 || status=$?
if (( status != 0 )); then
    cat "$TEST_ROOT/universal-cold-build.log" >&2
    fail "universal cold build exited $status"
fi

grep -Fqi 'cache miss for arm64' "$TEST_ROOT/universal-cold-build.log" ||
    fail "universal cold build did not report the arm64 cache miss"
grep -Fqi 'cache miss for x86_64' "$TEST_ROOT/universal-cold-build.log" ||
    fail "universal cold build did not report the x86_64 cache miss"
[[ "$(wc -l < "$TEST_ROOT/make.log" | tr -d ' ')" == "24" ]] ||
    fail "universal cold build did not exercise both dependency installers"

PACKAGE_HELPER="$PROJECT/.build/mobile-battery/package/Helpers/StatusTrioMobileBatteryHelper"
[[ -x "$PACKAGE_HELPER" ]] ||
    fail "universal cold build did not produce an executable helper"
assert_universal_slices "$PACKAGE_HELPER"
assert_no_development_rpaths "$PACKAGE_HELPER"

PACKAGE_LIBRARY_COUNT=0
while IFS= read -r -d '' library; do
    assert_universal_slices "$library"
    assert_no_development_rpaths "$library"
    PACKAGE_LIBRARY_COUNT=$((PACKAGE_LIBRARY_COUNT + 1))
done < <(
    find "$PROJECT/.build/mobile-battery/package/Frameworks/MobileBattery" \
        -maxdepth 1 -type f -name '*.dylib*' -print0
)
[[ "$PACKAGE_LIBRARY_COUNT" == "7" ]] ||
    fail "unexpected universal package library count: $PACKAGE_LIBRARY_COUNT"

for arch in arm64 x86_64; do
    arch_key="$(prepare_key "$PROJECT" "$arch")"
    tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
        validate --root "$PROJECT" --arch "$arch" \
        --minimum-macos 13.0 --expected-key "$arch_key"
done
prefix_rpaths="$(otool -l \
    "$PROJECT/.build/mobile-battery/arm64/prefix/lib/libplist-2.0.12.dylib" |
    python3 "$PROJECT/scripts/otool-rpaths.py")"
[[ "$prefix_rpaths" == *"/.build/mobile-battery/arm64/prefix/lib"* ]] ||
    fail "universal packaging mutated the sealed arm64 prefix"

COLD_UNIVERSAL_MAKE_LINES="$(wc -l < "$TEST_ROOT/make.log" | tr -d ' ')"
COLD_UNIVERSAL_CLANG_LINES="$(wc -l < "$TEST_ROOT/clang.log" | tr -d ' ')"
tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=1 \
    BUILD_JOBS=1 \
    BUILD_TIMING_FILE="$TEST_ROOT/timing.tsv" \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/universal-warm-build.log" 2>&1

[[ "$(grep -Fc 'MobileBattery cache validated for ' \
    "$TEST_ROOT/universal-warm-build.log")" == "2" ]] ||
    fail "universal warm build did not validate both dependency caches"
[[ "$(wc -l < "$TEST_ROOT/make.log" | tr -d ' ')" == "$COLD_UNIVERSAL_MAKE_LINES" ]] ||
    fail "universal warm build invoked a synthetic dependency installer"
[[ "$(wc -l < "$TEST_ROOT/clang.log" | tr -d ' ')" -eq "$((COLD_UNIVERSAL_CLANG_LINES + 2))" ]] ||
    fail "universal warm build did not rebuild both final helpers"
[[ "$(wc -l < "$FIXTURE_PREPARE_LOG" | tr -d ' ')" == "1" ]] ||
    fail "universal warm build checked out pinned sources despite validated caches"
assert_universal_slices "$PACKAGE_HELPER"
assert_no_development_rpaths "$PACKAGE_HELPER"
for arch in arm64 x86_64; do
    arch_key="$(prepare_key "$PROJECT" "$arch")"
    tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
        validate --root "$PROJECT" --arch "$arch" \
        --minimum-macos 13.0 --expected-key "$arch_key"
done

UNIVERSAL_CACHE_SNAPSHOT="$TEST_ROOT/universal-cache-before-notice-drift"
for arch in arm64 x86_64; do
    arch_root="$PROJECT/.build/mobile-battery/$arch"
    mkdir -p "$UNIVERSAL_CACHE_SNAPSHOT/$arch"
    cp -RP "$arch_root/prefix" "$UNIVERSAL_CACHE_SNAPSHOT/$arch/prefix"
    cp "$arch_root/.dependencies-cache.json" \
        "$UNIVERSAL_CACHE_SNAPSHOT/$arch/.dependencies-cache.json"
done

restore_universal_cache_snapshot() {
    for arch in arm64 x86_64; do
        arch_root="$PROJECT/.build/mobile-battery/$arch"
        rm -rf "$arch_root"
        mkdir -p "$arch_root"
        cp -RP "$UNIVERSAL_CACHE_SNAPSHOT/$arch/prefix" "$arch_root/prefix"
        cp "$UNIVERSAL_CACHE_SNAPSHOT/$arch/.dependencies-cache.json" \
            "$arch_root/.dependencies-cache.json"
    done
}

NOTICE_COPY="$PROJECT/Support/MobileBatteryHelper/ThirdPartyNotices/libplist/LICENSE"
NOTICE_KEY_BEFORE="$(prepare_key "$PROJECT" "$HOST_ARCH")"
cp "$NOTICE_COPY" "$TEST_ROOT/libplist-notice.saved"
printf '\nfixture drift\n' >> "$NOTICE_COPY"
NOTICE_KEY_AFTER="$(prepare_key "$PROJECT" "$HOST_ARCH")"
status=0
tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=1 \
    BUILD_JOBS=1 \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/notice-warm-drift.log" 2>&1 || status=$?
[[ "$status" != "0" ]] ||
    fail "changed reviewed notice was accepted by an existing warm cache"
[[ "$NOTICE_KEY_AFTER" != "$NOTICE_KEY_BEFORE" ]] ||
    fail "reviewed notice contents did not invalidate the cache key"
grep -Fq 'reviewed license text differs' "$TEST_ROOT/notice-warm-drift.log" ||
    fail "warm notice drift did not report its source-pin mismatch"

status=0
tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=1 \
    BUILD_JOBS=1 \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/notice-warm-drift-repeat.log" 2>&1 || status=$?
[[ "$status" != "0" ]] ||
    fail "a repeated build accepted a marker sealed before notice verification"
grep -Fq 'reviewed license text differs' "$TEST_ROOT/notice-warm-drift-repeat.log" ||
    fail "repeated notice drift did not report its source-pin mismatch"
for arch in arm64 x86_64; do
    marker="$PROJECT/.build/mobile-battery/$arch/.dependencies-cache.json"
    [[ ! -e "$marker" ]] && continue
    drift_key="$(prepare_key "$PROJECT" "$arch")"
    marker_key="$(python3 - "$marker" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    print(json.load(handle).get("cacheKey", ""))
PY
)"
    [[ "$marker_key" != "$drift_key" ]] ||
        fail "failed notice verification left a reusable $arch cache marker"
done

cp "$TEST_ROOT/libplist-notice.saved" "$NOTICE_COPY"
restore_universal_cache_snapshot

cp "$NOTICE_COPY" "$TEST_ROOT/libplist-notice.saved"
printf '\nfixture drift\n' >> "$NOTICE_COPY"
rm -rf "$PROJECT/.build/mobile-battery/$HOST_ARCH"
status=0
tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=0 \
    BUILD_JOBS=1 \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/notice-drift.log" 2>&1 || status=$?
[[ "$status" != "0" ]] ||
    fail "a cold rebuild accepted reviewed license text that differed from its source pin"
grep -Fq 'reviewed license text differs' "$TEST_ROOT/notice-drift.log" ||
    fail "license drift did not report its source-pin mismatch"
cp "$TEST_ROOT/libplist-notice.saved" "$NOTICE_COPY"
restore_universal_cache_snapshot

rm -rf "$PROJECT/.build/mobile-battery/sources"
PREPARE_COUNT_BEFORE_WITHOUT_SOURCES="$(wc -l < "$FIXTURE_PREPARE_LOG" | tr -d ' ')"
status=0
tool_env "$HOST_ARCH" \
    UNIVERSAL_BUILD=1 \
    BUILD_JOBS=1 \
    BUILD_TIMING_FILE="$TEST_ROOT/timing.tsv" \
    bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
    > "$TEST_ROOT/universal-no-sources-warm-build.log" 2>&1 || status=$?
if (( status != 0 )); then
    cat "$TEST_ROOT/universal-no-sources-warm-build.log" >&2
    fail "validated caches still required the pinned source checkout"
fi
[[ "$(wc -l < "$FIXTURE_PREPARE_LOG" | tr -d ' ')" == "$PREPARE_COUNT_BEFORE_WITHOUT_SOURCES" ]] ||
    fail "warm build without sources called source preparation"

for arch in arm64 x86_64; do
    grep -Fq $'mobile-dependencies-'"$arch"$'\t' "$TEST_ROOT/timing.tsv" ||
        fail "universal dependency timing was not recorded for $arch"
    grep -Fq $'mobile-helper-'"$arch"$'\t' "$TEST_ROOT/timing.tsv" ||
        fail "universal helper timing was not recorded for $arch"
done

NOTICE_ROOT="$PROJECT/Support/MobileBatteryHelper/ThirdPartyNotices"
NOTICE_EXTRA="$NOTICE_ROOT/cache-key-extra.txt"
printf 'fixture extra reviewed notice\n' > "$NOTICE_EXTRA"
NOTICE_FILE_SET_KEY="$(prepare_key "$PROJECT" "$HOST_ARCH")"
rm "$NOTICE_EXTRA"
expect_key_change "reviewed notice file set" "$NOTICE_FILE_SET_KEY"

mv "$NOTICE_ROOT" "$TEST_ROOT/notices.saved"
if prepare_key "$PROJECT" "$HOST_ARCH" > "$TEST_ROOT/notices-missing.log" 2>&1; then
    fail "missing reviewed notice root was accepted"
else
    status=$?
    [[ "$status" == "2" ]] ||
        fail "missing reviewed notice root exited $status instead of 2"
fi
grep -Fqi 'reviewed notice' "$TEST_ROOT/notices-missing.log" ||
    fail "missing reviewed notice root failure was not explained"
mv "$TEST_ROOT/notices.saved" "$NOTICE_ROOT"

ln -s libplist/LICENSE "$NOTICE_ROOT/cache-key-link"
if prepare_key "$PROJECT" "$HOST_ARCH" > "$TEST_ROOT/notices-symlink.log" 2>&1; then
    fail "symlink in reviewed notice root was accepted"
else
    status=$?
    [[ "$status" == "2" ]] ||
        fail "symlink in reviewed notice root exited $status instead of 2"
fi
grep -Fqi 'symlink' "$TEST_ROOT/notices-symlink.log" ||
    fail "symlink in reviewed notice root failure was not explained"
rm "$NOTICE_ROOT/cache-key-link"

NOTICE_UNREADABLE="$NOTICE_ROOT/cache-key-unreadable"
mkdir "$NOTICE_UNREADABLE"
printf 'fixture unreadable reviewed notice\n' > "$NOTICE_UNREADABLE/LICENSE"
chmod 000 "$NOTICE_UNREADABLE"
if prepare_key "$PROJECT" "$HOST_ARCH" \
    > "$TEST_ROOT/notices-unreadable.log" 2>&1; then
    chmod 700 "$NOTICE_UNREADABLE"
    rm "$NOTICE_UNREADABLE/LICENSE"
    rmdir "$NOTICE_UNREADABLE"
    fail "unreadable reviewed notice directory was silently skipped"
else
    status=$?
    chmod 700 "$NOTICE_UNREADABLE"
    rm "$NOTICE_UNREADABLE/LICENSE"
    rmdir "$NOTICE_UNREADABLE"
    [[ "$status" == "2" ]] ||
        fail "unreadable reviewed notice directory exited $status instead of 2"
fi
grep -Fqi 'unable to inspect reviewed notices' "$TEST_ROOT/notices-unreadable.log" ||
    fail "unreadable reviewed notice directory failure was not explained"

for failure in strip lipo; do
    case "$failure" in
        strip) injection="FIXTURE_install_name_tool_STATUS=75"; expected=75 ;;
        lipo) injection="FIXTURE_LIPO_CREATE_STATUS=76"; expected=76 ;;
    esac
    status=0
    tool_env "$HOST_ARCH" \
        UNIVERSAL_BUILD=1 BUILD_JOBS=1 "$injection" \
        bash "$PROJECT/scripts/build-mobile-battery-helper.sh" \
        > "$TEST_ROOT/universal-$failure-failure.log" 2>&1 || status=$?
    [[ "$status" == "$expected" ]] ||
        fail "universal $failure failure exited $status instead of $expected"
    for arch in arm64 x86_64; do
        arch_key="$(prepare_key "$PROJECT" "$arch")"
        tool_env "$HOST_ARCH" python3 "$PROJECT/scripts/mobile-battery-cache.py" \
            validate --root "$PROJECT" --arch "$arch" \
            --minimum-macos 13.0 --expected-key "$arch_key"
    done
done

echo "mobile battery build cache: key, reviewed notices, inventory, corruption and cold/warm fixtures passed"
