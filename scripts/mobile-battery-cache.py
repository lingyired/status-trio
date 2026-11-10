#!/usr/bin/env python3
"""Create and verify exact-path MobileBattery dependency prefix caches.

The cache intentionally contains only one architecture's installed prefix and
its marker. Source checkouts, build trees, the helper, package assembly, and
signing material are never cached. The canonical prefix path is part of the
key because libtool .la, pkg-config .pc, and Mach-O install names store it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
from typing import Iterable


CACHE_KEY_PREFIX = "status-trio-mobile-battery-v2"
SCHEMA = "mobile-battery-prefix-cache-v2"
MARKER_SCHEMA = 2
MARKER_NAME = ".dependencies-cache.json"
MINIMUM_SDK_MAJOR = 26

BUILD_SCRIPTS = (
    "scripts/build-mobile-battery-helper.sh",
    "scripts/mobile-battery-cache.py",
    "scripts/prepare-mobile-battery-sources.sh",
    "scripts/build-timing.sh",
    "scripts/verify-platform-version.sh",
    "scripts/otool-dependencies.py",
    "scripts/otool-rpaths.py",
)
REVIEWED_NOTICE_ROOT = "Support/MobileBatteryHelper/ThirdPartyNotices"

TOOL_FORMULAE = ("autoconf", "automake", "libtool", "pkg-config")
TOOL_COMMANDS = ("autoconf", "automake", "glibtool", "pkg-config", "make", "m4", "perl")

# Stable linker-facing names survive dependency ABI version bumps. The marker
# pins each relative target by inventory digest, so no version number needs a
# second hand-maintained copy here.
REQUIRED_LIBRARY_LINKS = (
    "libcrypto.dylib",
    "libssl.dylib",
    "libplist-2.0.dylib",
    "libimobiledevice-glue-1.0.dylib",
    "libusbmuxd-2.0.dylib",
    "libtatsu.dylib",
    "libimobiledevice-1.0.dylib",
)

REQUIRED_LIBTOOL_FILES = {
    "libimobiledevice-1.0.la": "libimobiledevice-1.0.dylib",
    "libimobiledevice-glue-1.0.la": "libimobiledevice-glue-1.0.dylib",
    "libplist++-2.0.la": "libplist++-2.0.dylib",
    "libplist-2.0.la": "libplist-2.0.dylib",
    "libtatsu.la": "libtatsu.dylib",
    "libusbmuxd-2.0.la": "libusbmuxd-2.0.dylib",
}

REQUIRED_HEADERS = (
    "include/libimobiledevice/companion_proxy.h",
    "include/libimobiledevice/libimobiledevice.h",
    "include/libimobiledevice/lockdown.h",
    "include/libimobiledevice-glue/collection.h",
    "include/libimobiledevice-glue/glue.h",
    "include/libtatsu/tatsu.h",
    "include/libtatsu/tss.h",
    "include/openssl/crypto.h",
    "include/openssl/evp.h",
    "include/openssl/ssl.h",
    "include/plist/plist++.h",
    "include/plist/plist.h",
    "include/usbmuxd-proto.h",
    "include/usbmuxd.h",
)

REQUIRED_PKGCONFIG = (
    "libcrypto",
    "libimobiledevice-1.0",
    "libimobiledevice-glue-1.0",
    "libplist++-2.0",
    "libplist-2.0",
    "libssl",
    "libtatsu-1.0",
    "libusbmuxd-2.0",
    "openssl",
)

SYSTEM_PREFIXES = (
    "/usr/lib/",
    "/System/Library/",
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/",
)


class CacheError(Exception):
    """A cache candidate is unsafe or cannot be inspected."""


class CacheMiss(CacheError):
    """No marker or prefix exists for the requested architecture."""


class CacheInvalid(CacheError):
    """A restored or local cache candidate failed validation."""


def run(
    command: list[str],
    *,
    input_text: str | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            input=input_text,
        )
    except FileNotFoundError as error:
        raise CacheError(f"required command is unavailable: {command[0]}") from error
    except subprocess.CalledProcessError as error:
        detail = ""
        if error.stderr:
            detail = f": {error.stderr.strip()}"
        raise CacheError(f"command failed ({error.returncode}): {' '.join(command)}{detail}") from error


def output(command: list[str]) -> str:
    return run(command).stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def reviewed_notices(root: Path) -> dict[str, str]:
    notices = root / REVIEWED_NOTICE_ROOT
    if notices.is_symlink() or not notices.is_dir():
        raise CacheError(f"reviewed notice root is missing or invalid: {notices}")

    def fail_walk(error: OSError) -> None:
        raise error

    files: dict[str, str] = {}
    try:
        for directory, dirnames, filenames in os.walk(notices, onerror=fail_walk):
            directory_path = Path(directory)
            for name in sorted(dirnames):
                path = directory_path / name
                relative = path.relative_to(root).as_posix()
                if path.is_symlink():
                    raise CacheError(
                        f"reviewed notice path must not be a symlink: {relative}"
                    )
            for name in sorted(filenames):
                path = directory_path / name
                relative = path.relative_to(root).as_posix()
                if path.is_symlink():
                    raise CacheError(
                        f"reviewed notice path must not be a symlink: {relative}"
                    )
                if not path.is_file():
                    raise CacheError(f"unsupported reviewed notice path: {relative}")
                files[relative] = sha256_file(path)
    except OSError as error:
        raise CacheError(f"unable to inspect reviewed notices: {notices}: {error}") from error

    if not files:
        raise CacheError(f"reviewed notice root is empty: {notices}")
    return files


def canonical_root(root: Path) -> Path:
    return root.resolve()


def architecture_root(root: Path, arch: str) -> Path:
    return canonical_root(root) / ".build" / "mobile-battery" / arch


def prefix_path(root: Path, arch: str) -> Path:
    return architecture_root(root, arch) / "prefix"


def canonical_prefix(prefix: Path) -> Path:
    return canonical_root(prefix.parent.parent.parent.parent) / ".build" / "mobile-battery" / prefix.parent.name / "prefix"


def marker_path(root: Path, arch: str) -> Path:
    return architecture_root(root, arch) / MARKER_NAME


def clang_path() -> Path:
    return Path(output(["xcrun", "--sdk", "macosx", "--find", "clang"]))


def clang_version() -> str:
    return output([str(clang_path()), "--version"]).splitlines()[0]


def sdk_identity() -> dict[str, str]:
    path = Path(output(["xcrun", "--sdk", "macosx", "--show-sdk-path"]))
    version = output(["xcrun", "--sdk", "macosx", "--show-sdk-version"])
    build = output(["xcrun", "--sdk", "macosx", "--show-sdk-build-version"])
    settings_hashes = {}
    for name in ("SDKSettings.json", "SDKSettings.plist"):
        settings = path / name
        if not settings.is_file():
            raise CacheError(f"missing SDK identity file: {settings}")
        settings_hashes[name] = sha256_file(settings)
    return {
        "path": str(path),
        "version": version,
        "build": build,
        "settingsSha256": settings_hashes,
    }


def command_version(command: str) -> str:
    path = Path(command)
    failures = []
    for arguments in (["--version"], ["-v"]):
        try:
            version = output([str(path), *arguments]).splitlines()
            if version:
                return version[0]
        except CacheError as error:
            failures.append(str(error))
    raise CacheError(
        f"unable to probe version for {command}: " + "; ".join(failures)
    )


def brew_version(formula: str) -> str:
    return output(["brew", "list", "--versions", formula])


def cache_identity(root: Path, arch: str, minimum_macos: str) -> dict[str, object]:
    root = canonical_root(root)
    manifest = root / "Support" / "mobile-battery-dependencies.json"
    if not manifest.is_file():
        raise CacheError(f"missing dependency manifest: {manifest}")

    tool_paths = {}
    for name in TOOL_COMMANDS:
        tool_paths[name] = output(["sh", "-c", f"command -v {name}"] ) if name != "sh" else "/bin/sh"

    scripts = {}
    for relative in BUILD_SCRIPTS:
        path = root / relative
        if not path.is_file():
            raise CacheError(f"missing cache-influencing script: {path}")
        scripts[relative] = sha256_file(path)

    return {
        "schema": SCHEMA,
        "arch": arch,
        "hostOS": output(["sh", "-c", "sw_vers -productVersion"]),
        "hostOSBuild": output(["sh", "-c", "sw_vers -buildVersion"]),
        "hostArch": output(["sh", "-c", "uname -m"]),
        "xcode": output(["xcodebuild", "-version"]),
        "xcodeSelect": output(["xcode-select", "-p"]),
        "swift": output(["swift", "--version"]).splitlines()[0],
        "clangPath": str(clang_path()),
        "clangVersion": clang_version(),
        "sdk": sdk_identity(),
        "minimumMacOS": minimum_macos,
        "manifestSha256": sha256_file(manifest),
        "scripts": scripts,
        "reviewedNotices": reviewed_notices(root),
        "configuration": {
            "optimization": "-O2",
            "openssl": "shared-no-tests",
            "autotools": "shared-static-disabled",
            "plistPython": "disabled",
            "plistTools": "disabled",
            "plistTests": "disabled",
            "usbmuxdInotify": "disabled",
            "imobiledeviceReadline": "disabled",
            "imobiledeviceOpenSSL": "enabled",
        },
        "tools": {
            "brew": {
                formula: brew_version(formula) for formula in TOOL_FORMULAE
            },
            "commands": {
                name: {
                    "path": path,
                    "version": command_version(path),
                }
                for name, path in tool_paths.items()
            },
        },
        "canonicalPrefix": str(prefix_path(root, arch)),
    }


def render_key(identity: dict[str, object]) -> str:
    payload = json.dumps(
        identity,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    )
    return f"{CACHE_KEY_PREFIX}-{sha256_text(payload)}"


def key_option(args: argparse.Namespace) -> str:
    return render_key(
        cache_identity(Path(args.root), args.arch, args.minimum_macos)
    )


def inventory(prefix: Path) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    if not prefix.is_dir():
        raise CacheMiss(f"cache miss: prefix is missing: {prefix}")

    for path in sorted(prefix.rglob("*")):
        relative = path.relative_to(prefix).as_posix()
        verify_expected_path(relative)
        if path.is_symlink():
            target = os.readlink(path)
            resolved = path.resolve(strict=False)
            if os.path.isabs(target):
                raise CacheInvalid(f"escaping symlink {relative}: absolute target {target}")
            try:
                resolved.relative_to(prefix.resolve())
            except ValueError as error:
                raise CacheInvalid(
                    f"escaping symlink {relative}: target {target}"
                ) from error
            if not path.exists():
                raise CacheInvalid(f"broken symlink {relative}: target {target}")
            entries.append(
                {
                    "path": relative,
                    "type": "symlink",
                    "target": target,
                }
            )
        elif path.is_file():
            entries.append(
                {
                    "path": relative,
                    "type": "file",
                    "size": path.stat().st_size,
                    "sha256": sha256_file(path),
                    "mode": oct(path.stat().st_mode & 0o777),
                }
            )
        elif path.is_dir():
            entries.append({"path": relative, "type": "directory"})
        else:
            raise CacheInvalid(f"unsupported file type in prefix: {relative}")
    return entries


def verify_expected_path(relative: str) -> None:
    allowed = (
        relative in {"bin", "include", "lib", "share"}
        or re.fullmatch(r"bin/[A-Za-z0-9_]+", relative)
        or re.fullmatch(
            r"include/(?:libimobiledevice(?:-glue)?|libtatsu|openssl|plist)",
            relative,
        )
        or re.fullmatch(r"include/(?:[^/]+/)*[^/]+\.h", relative)
        or relative in {
            "lib/cmake",
            "lib/cmake/OpenSSL",
            "lib/engines-3",
            "lib/ossl-modules",
            "lib/pkgconfig",
            "share/man",
            "share/man/man1",
        }
        or re.fullmatch(r"lib/[^/]+\.(?:[0-9]+\.)?dylib", relative)
        or re.fullmatch(r"lib/[^/]+\.(?:a|la)", relative)
        or re.fullmatch(r"lib/cmake/OpenSSL/[^/]+\.cmake", relative)
        or re.fullmatch(r"lib/(?:engines-3|ossl-modules)/[^/]+\.dylib", relative)
        or re.fullmatch(r"lib/pkgconfig/[^/]+\.pc", relative)
        or re.fullmatch(r"share/man/man1/[^/]+\.1", relative)
    )
    if not allowed:
        raise CacheInvalid(f"unexpected cache prefix entry: {relative}")


def parse_manifest(manifest: Path) -> tuple[list[str], dict[str, dict[str, object]]]:
    try:
        data = json.loads(manifest.read_text())
        names = data["sourceBuildOrder"]
        dependencies = data["dependencies"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise CacheError(f"invalid dependency manifest {manifest}: {error}") from error

    by_name: dict[str, dict[str, object]] = {}
    for dependency in dependencies:
        if not isinstance(dependency, dict):
            raise CacheError(f"invalid dependency entry in {manifest}")
        name = dependency.get("name")
        commit = dependency.get("commit")
        repository = dependency.get("repository")
        if not isinstance(name, str) or not isinstance(commit, str) or not isinstance(repository, str):
            raise CacheError(f"dependency entry lacks name/repository/commit in {manifest}")
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise CacheError(f"dependency {name} has a non-frozen commit: {commit}")
        by_name[name] = dependency
    if len(names) != len(set(names)):
        raise CacheError("sourceBuildOrder contains duplicate names")
    if set(names) != set(by_name):
        raise CacheError("sourceBuildOrder and dependencies do not name the same sources")
    return names, by_name


def verify_source_pins(root: Path) -> None:
    manifest = canonical_root(root) / "Support" / "mobile-battery-dependencies.json"
    names, by_name = parse_manifest(manifest)
    source_root = canonical_root(root) / ".build" / "mobile-battery" / "sources"
    for name in names:
        repository = source_root / name
        if not (repository / ".git").is_dir():
            raise CacheInvalid(f"missing pinned source checkout for {name}: {repository}")
        actual = output(["git", "-C", str(repository), "rev-parse", "HEAD"])
        expected = str(by_name[name]["commit"])
        if actual != expected:
            raise CacheInvalid(
                f"source pin mismatch for {name}: expected {expected}, found {actual}"
            )


def verify_library(
    root: Path,
    path: Path,
    arch: str,
    minimum_macos: str,
    prefix: Path,
) -> None:
    if not path.is_file() or path.is_symlink():
        raise CacheInvalid(f"required library is not a regular file: {path.name}")
    archs = output(["lipo", "-archs", str(path)]).split()
    if archs != [arch]:
        raise CacheInvalid(
            f"wrong architecture for {path.name}: {archs}, expected [{arch}]"
        )

    # Probe vtool directly so an inspection-tool failure stays a hard error
    # instead of masquerading as malformed metadata and triggering a rebuild.
    build_metadata = output(["vtool", "-show-build", str(path)])
    if not re.search(r"^\s*minos\s+\S+", build_metadata, re.MULTILINE) or not re.search(
        r"^\s*sdk\s+\S+", build_metadata, re.MULTILINE
    ):
        raise CacheInvalid(
            f"unable to parse LC_BUILD_VERSION for {path.name}"
        )
    try:
        run(
            [
                "bash",
                str(root / "scripts" / "verify-platform-version.sh"),
                str(path),
                minimum_macos,
                str(MINIMUM_SDK_MAJOR),
            ]
        )
    except CacheError as error:
        raise CacheInvalid(
            f"platform verification failed for {path.name}: {error}"
        ) from error

    dependencies_text = output(["otool", "-L", str(path)])
    dependencies = run(
        [
            "python3",
            str(root / "scripts" / "otool-dependencies.py"),
        ],
        input_text=dependencies_text,
    ).stdout.splitlines()
    if not dependencies:
        raise CacheInvalid(
            f"dependency parser returned no entries for {path.name}"
        )
    for dependency in dependencies:
        if dependency.startswith(str(prefix) + "/"):
            dependency_path = Path(dependency)
            try:
                dependency_path.resolve().relative_to(prefix.resolve())
            except ValueError as error:
                raise CacheInvalid(
                    f"{path.name} depends on a library outside its prefix: {dependency}"
                ) from error
            if not dependency_path.exists():
                raise CacheInvalid(
                    f"{path.name} depends on missing cached library: {dependency}"
                )
        elif dependency.startswith("@"):
            continue
        elif dependency.startswith(SYSTEM_PREFIXES):
            continue
        else:
            raise CacheInvalid(
                f"{path.name} has an unapproved dependency: {dependency}"
            )

    rpaths = run(
        [
            "python3",
            str(root / "scripts" / "otool-rpaths.py"),
        ],
        input_text=output(["otool", "-l", str(path)]),
    ).stdout.splitlines()
    for rpath in rpaths:
        if rpath in {
            "@executable_path/../Frameworks/MobileBattery",
            str(prefix / "lib"),
        }:
            continue
        if rpath.startswith(SYSTEM_PREFIXES):
            continue
        raise CacheInvalid(f"{path.name} has an unapproved LC_RPATH: {rpath}")


def required_library_paths(prefix: Path) -> list[Path]:
    resolved_libraries = []
    for link in REQUIRED_LIBRARY_LINKS:
        path = prefix / "lib" / link
        if not path.is_symlink():
            raise CacheInvalid(f"missing required library symlink: lib/{link}")
        target = os.readlink(path)
        if os.path.isabs(target):
            raise CacheInvalid(
                f"absolute symlink target for lib/{link}: {target}"
            )
        expected = (prefix / "lib" / target).resolve()
        try:
            expected.relative_to(prefix.resolve())
        except ValueError as error:
            raise CacheInvalid(
                f"library symlink escapes prefix: lib/{link} -> {target}"
            ) from error
        if not expected.is_file():
            raise CacheInvalid(
                f"missing required library for lib/{link}: target {target}"
            )
        if expected not in resolved_libraries:
            resolved_libraries.append(expected)
    for filename, link in REQUIRED_LIBTOOL_FILES.items():
        path = prefix / "lib" / filename
        if not path.is_file() or path.is_symlink():
            raise CacheInvalid(f"missing required libtool metadata: lib/{filename}")
        fields = {}
        for line in path.read_text(errors="replace").splitlines():
            key, separator, value = line.partition("=")
            if separator:
                fields[key] = value.strip().strip("'")
        dlname = fields.get("dlname", "")
        dlname_path = prefix / "lib" / dlname
        if (
            not dlname
            or Path(dlname).name != dlname
            or not dlname_path.is_file()
            or dlname_path.is_symlink()
        ):
            raise CacheInvalid(
                f"libtool dlname does not name a cached library: {filename}: {dlname}"
            )
        names = fields.get("library_names", "").split()
        if not names or Path(names[0]).name != names[0] or names[0] != dlname:
            raise CacheInvalid(
                f"libtool library_names does not match dlname: {filename}"
            )
        if link in names:
            if os.readlink(prefix / "lib" / link) != dlname:
                raise CacheInvalid(
                    f"libtool link does not match dlname: lib/{link} -> {dlname}"
                )
    return resolved_libraries


def pkgconfig_value(value: str, variables: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in variables:
            raise CacheInvalid(f"undefined pkg-config variable: {name}")
        return variables[name]

    expanded = value
    for _ in range(16):
        previous = expanded
        expanded = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", replace, expanded)
        if expanded == previous:
            return expanded
    raise CacheInvalid(f"pkg-config variable expansion is cyclic: {value}")


def allowed_metadata_path(path: str, prefix: Path, sdk_path: str) -> bool:
    if path == str(prefix) or path.startswith(str(prefix) + "/"):
        return True
    if path == sdk_path or path.startswith(sdk_path + "/"):
        return True
    return path.startswith(SYSTEM_PREFIXES)


def verify_required_files(prefix: Path) -> list[Path]:
    prefix = canonical_prefix(prefix)
    resolved_libraries = required_library_paths(prefix)
    for header in REQUIRED_HEADERS:
        if not (prefix / header).is_file():
            raise CacheInvalid(f"missing required header: {header}")
    for package in REQUIRED_PKGCONFIG:
        path = prefix / "lib" / "pkgconfig" / f"{package}.pc"
        if not path.is_file():
            raise CacheInvalid(f"missing pkg-config metadata: {path.relative_to(prefix)}")
        fields = {}
        for line in path.read_text(errors="replace").splitlines():
            key, separator, value = line.partition("=")
            if separator and key.strip() in {
                "prefix",
                "exec_prefix",
                "libdir",
                "includedir",
            }:
                fields[key.strip()] = value.strip()
        expected = {
            "prefix": str(prefix),
            "exec_prefix": "${prefix}",
            "libdir": "${exec_prefix}/lib",
            "includedir": "${prefix}/include",
        }
        if fields != expected:
            raise CacheInvalid(
                f"pkg-config metadata is not bound to canonical prefix: "
                f"{path.name}: {fields}"
            )
    return resolved_libraries


def verify_internal_paths(prefix: Path, sdk_path: str) -> None:
    """Reject an unexpected file or metadata path that escaped inventory review."""
    expected_prefix = str(prefix)
    for path in sorted(prefix.rglob("*")):
        relative = path.relative_to(prefix).as_posix()
        if path.is_symlink():
            target = os.readlink(path)
            if os.path.isabs(target):
                raise CacheInvalid(
                    f"absolute symlink target in prefix: {relative} -> {target}"
                )
            try:
                path.resolve(strict=True).relative_to(prefix.resolve())
            except (OSError, ValueError) as error:
                raise CacheInvalid(
                    f"escaping or broken symlink in prefix: {relative} -> {target}"
                ) from error
            continue
        if not path.is_file():
            continue
        if relative.endswith(".pc"):
            variables: dict[str, str] = {}
            for line in path.read_text(errors="replace").splitlines():
                key, separator, value = line.partition("=")
                if not separator or key.strip().startswith("#"):
                    continue
                key = key.strip()
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                    variables[key] = pkgconfig_value(value.strip(), variables)
                    value = variables[key]
                for token in re.findall(r"/[^\s\"']+", value):
                    token = os.path.normpath(token)
                    if token == expected_prefix or token.startswith(
                        expected_prefix + "/"
                    ):
                        continue
                    if token == sdk_path or token.startswith(sdk_path + "/"):
                        continue
                    raise CacheInvalid(
                        f"unexpected absolute path in {relative}: {token}"
                    )
        elif relative.endswith(".la"):
            libdirs: list[str] = []
            for line in path.read_text(errors="replace").splitlines():
                key, separator, value = line.partition("=")
                if not separator or key not in {"dependency_libs", "libdir"}:
                    continue
                try:
                    tokens = shlex.split(value)
                    if key == "dependency_libs" and len(tokens) == 1:
                        # Libtool quotes the entire list as one shell value.
                        # Decode that value before inspecting individual flags.
                        tokens = shlex.split(tokens[0])
                except ValueError as error:
                    raise CacheInvalid(
                        f"invalid quoted libtool metadata in {relative}: {error}"
                    ) from error
                if key == "libdir":
                    if len(tokens) != 1:
                        raise CacheInvalid(
                            f"libtool libdir must contain one path in {relative}"
                        )
                    expected_libdir = str(prefix / "lib")
                    if tokens[0] != expected_libdir:
                        raise CacheInvalid(
                            f"libtool libdir is not the canonical prefix/lib in "
                            f"{relative}: {tokens[0]}"
                        )
                    libdirs.append(tokens[0])
                    continue
                for token in tokens:
                    if token.startswith("-L") and len(token) > 2:
                        token = token[2:]
                    if not token.startswith("/"):
                        continue
                    token = os.path.normpath(token)
                    if not allowed_metadata_path(token, prefix, sdk_path):
                        raise CacheInvalid(
                            f"unexpected absolute path in {relative}: {token}"
                        )
            if not libdirs:
                raise CacheInvalid(f"libtool metadata has no libdir: {relative}")


def inventory_digest(entries: list[dict[str, object]]) -> str:
    return sha256_text(
        json.dumps(entries, sort_keys=True, separators=(",", ":"))
    )


def parse_inventory(
    value: object,
    *,
    marker: Path,
) -> list[dict[str, object]]:
    if not isinstance(value, list):
        raise CacheInvalid(f"cache marker has an invalid inventory in {marker}")

    entries: list[dict[str, object]] = []
    seen: set[str] = set()
    for index, entry in enumerate(value):
        if not isinstance(entry, dict):
            raise CacheInvalid(
                f"cache marker inventory entry {index} is not an object"
            )
        relative = entry.get("path")
        kind = entry.get("type")
        if not isinstance(relative, str) or not relative:
            raise CacheInvalid(
                f"cache marker inventory entry {index} has no valid path"
            )
        try:
            verify_expected_path(relative)
        except CacheInvalid as error:
            raise CacheInvalid(
                f"cache marker inventory entry {index} has an unexpected path: {relative}"
            ) from error
        if relative in seen:
            raise CacheInvalid(
                f"cache marker inventory contains duplicate path: {relative}"
            )
        seen.add(relative)

        if kind == "directory":
            expected_fields = {"path", "type"}
        elif kind == "file":
            expected_fields = {"path", "type", "size", "sha256", "mode"}
            size = entry.get("size")
            digest = entry.get("sha256")
            mode = entry.get("mode")
            if not isinstance(size, int) or isinstance(size, bool) or size < 0:
                raise CacheInvalid(
                    f"cache marker inventory entry {index} has invalid size"
                )
            if not isinstance(digest, str) or not re.fullmatch(
                r"[0-9a-f]{64}", digest
            ):
                raise CacheInvalid(
                    f"cache marker inventory entry {index} has invalid sha256"
                )
            if not isinstance(mode, str) or not re.fullmatch(
                r"0o[0-7]{3}", mode
            ):
                raise CacheInvalid(
                    f"cache marker inventory entry {index} has invalid mode"
                )
        elif kind == "symlink":
            expected_fields = {"path", "type", "target"}
            target = entry.get("target")
            if not isinstance(target, str) or not target or os.path.isabs(target):
                raise CacheInvalid(
                    f"cache marker inventory entry {index} has invalid symlink target"
                )
        else:
            raise CacheInvalid(
                f"cache marker inventory entry {index} has invalid type"
            )

        if set(entry) != expected_fields:
            raise CacheInvalid(
                f"cache marker inventory entry {index} has unexpected fields"
            )
        entries.append(dict(entry))
    return entries
def validate_inventory(
    prefix: Path,
    stored: list[dict[str, object]],
    sdk_path: str,
    marker: Path,
) -> None:
    stored = parse_inventory(stored, marker=marker)
    current = inventory(prefix)
    stored_by_path = {str(entry["path"]): entry for entry in stored}
    current_by_path = {str(entry["path"]): entry for entry in current}
    if set(stored_by_path) != set(current_by_path):
        added = sorted(set(current_by_path) - set(stored_by_path))
        removed = sorted(set(stored_by_path) - set(current_by_path))
        details = []
        if removed:
            details.append(f"missing={removed[:5]}")
        if added:
            details.append(f"unexpected={added[:5]}")
        raise CacheInvalid("prefix inventory mismatch: " + ", ".join(details))
    for relative, expected in stored_by_path.items():
        actual = current_by_path[relative]
        if actual != expected:
            raise CacheInvalid(
                f"prefix inventory digest mismatch for {relative}"
            )
    verify_internal_paths(prefix, sdk_path)


def read_marker(marker: Path) -> dict[str, object]:
    try:
        data = json.loads(marker.read_text())
    except FileNotFoundError as error:
        raise CacheInvalid(f"cache prefix exists without a marker: {marker.parent.parent}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise CacheInvalid(f"corrupt cache marker {marker}: {error}") from error
    if not isinstance(data, dict) or data.get("schema") != MARKER_SCHEMA:
        raise CacheInvalid(f"unsupported cache marker schema in {marker}")
    return data


def validate(
    root: Path,
    arch: str,
    expected_key: str,
    minimum_macos: str,
) -> dict[str, object]:
    root = canonical_root(root)
    prefix = prefix_path(root, arch)
    marker = marker_path(root, arch)
    if not prefix.exists() and not marker.exists():
        raise CacheMiss(f"cache miss: prefix is missing: {prefix}")
    if not prefix.is_dir():
        raise CacheInvalid(f"cache marker exists without a prefix: {prefix}")
    if not marker.exists():
        raise CacheInvalid(f"cache prefix exists without a marker: {prefix}")
    data = read_marker(marker)
    if data.get("cacheKey") != expected_key:
        raise CacheInvalid(
            f"stale cache key: marker {data.get('cacheKey')} != expected {expected_key}"
        )
    if data.get("arch") != arch:
        raise CacheInvalid(
            f"stale cache architecture: marker {data.get('arch')} != expected {arch}"
        )
    if data.get("canonicalPrefix") != str(prefix):
        raise CacheInvalid(
            "stale canonical prefix: the cache is not portable across workspace paths"
        )
    stored_inventory = data.get("inventory")
    if not isinstance(data.get("inventorySha256"), str):
        raise CacheInvalid("cache marker has no inventory digest")
    stored_inventory = parse_inventory(stored_inventory, marker=marker)
    actual_digest = inventory_digest(stored_inventory)
    if data["inventorySha256"] != actual_digest:
        raise CacheInvalid("cache marker inventory digest does not match")

    libraries = verify_required_files(prefix)
    validate_inventory(prefix, stored_inventory, sdk_identity()["path"], marker)
    for library in libraries:
        verify_library(root, library, arch, minimum_macos, prefix)
    return data


def seal(root: Path, arch: str, expected_key: str, minimum_macos: str) -> None:
    root = canonical_root(root)
    prefix = prefix_path(root, arch)
    marker = marker_path(root, arch)
    verify_source_pins(root)
    libraries = verify_required_files(prefix)
    entries = inventory(prefix)
    verify_internal_paths(prefix, sdk_identity()["path"])
    for library in libraries:
        verify_library(root, library, arch, minimum_macos, prefix)
    data = {
        "schema": MARKER_SCHEMA,
        "cacheKey": expected_key,
        "arch": arch,
        "canonicalPrefix": str(prefix),
        "minimumMacOS": minimum_macos,
        "inventorySha256": inventory_digest(entries),
        "inventory": entries,
    }
    marker.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        dir=marker.parent,
        prefix=".dependencies-cache.",
        delete=False,
    ) as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temporary = Path(handle.name)
    os.replace(temporary, marker)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    for command in ("prepare-key", "seal", "validate", "inventory"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--root", required=True)
        subparser.add_argument("--arch", choices=("arm64", "x86_64"), required=True)
        subparser.add_argument("--minimum-macos", default="13.0")
        if command in ("seal", "validate"):
            subparser.add_argument("--expected-key", required=True)
        if command == "prepare-key":
            subparser.add_argument("--github-output")
            subparser.add_argument("--output-name")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    root = Path(args.root)
    try:
        if args.command == "prepare-key":
            key = key_option(args)
            if args.github_output:
                output_path = Path(args.github_output)
                output_name = args.output_name or f"key_{args.arch}"
                with output_path.open("a") as handle:
                    handle.write(f"{output_name}={key}\n")
            print(key)
        elif args.command == "inventory":
            print(
                json.dumps(
                    inventory(prefix_path(root, args.arch)),
                    indent=2,
                    sort_keys=True,
                )
            )
        elif args.command == "validate":
            validate(root, args.arch, args.expected_key, args.minimum_macos)
            print(f"cache validated for {args.arch}")
        elif args.command == "seal":
            seal(root, args.arch, args.expected_key, args.minimum_macos)
            print(f"cache sealed for {args.arch}")
        else:
            raise AssertionError(args.command)
    except CacheMiss as error:
        print(str(error), file=sys.stderr)
        return 10
    except CacheInvalid as error:
        print(f"cache invalid: {error}", file=sys.stderr)
        return 11
    except CacheError as error:
        print(f"cache error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
