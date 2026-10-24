#!/usr/bin/env python3
"""Fail-closed static audit for an App Store Status Trio bundle.

This is evidence for a compiled artifact, not proof of sandbox runtime behavior
or source-level compliance. It rejects unreadable content, unsafe symlinks,
forbidden code/components, and known private binary references.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Optional


STORE_IDS = (
    re.compile(r"^com\.lingsmbp\.StatusTrio\.AppStore$"),
    re.compile(r"^com\.lingsmbp\.StatusTrio\.AppStore\.dev\.[A-Za-z0-9][A-Za-z0-9.-]*$"),
)

SU_KEY_PATTERN = re.compile(r"^SU[A-Z][A-Za-z0-9_]*$")

FORBIDDEN_ENTITLEMENT_PREFIXES = (
    "com.apple.security.temporary-exception.",
    "com.apple.private.",
)

FORBIDDEN_ENTITLEMENT_KEYS = {
    "com.apple.security.inherit",
}

FORBIDDEN_ENTITLEMENTS = {
    "com.apple.security.cs.allow-dyld-environment-variables",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "com.apple.security.cs.debugger",
    "com.apple.security.cs.disable-executable-page-protection",
    "com.apple.security.cs.disable-library-validation",
}

FORBIDDEN_COMPONENT_NAMES = (
    "Sparkle.framework",
    "DDCPrivateAPI",
    "DDCPrivateAPI.framework",
    "StatusTrioPowerHelper",
    "StatusTrioMobileBatteryHelper",
)

FORBIDDEN_NAME_PATTERNS = (
    re.compile(r"^com\.lingsmbp\.StatusTrio\.PowerHelper(?:\.plist)?$"),
    re.compile(r"^com\.lingsmbp\.StatusTrio\.MobileBatteryHelper", re.IGNORECASE),
    re.compile(r"^MobileBatteryHelper", re.IGNORECASE),
)

FORBIDDEN_SYMBOL_PATTERNS = (
    re.compile(r"IOAVService"),
    re.compile(r"IOBluetoothPreference"),
    re.compile(r"(?<![A-Za-z0-9_])_?IOBluetoothLocalDeviceSetPowerState(?![A-Za-z0-9_])"),
    re.compile(r"(?<![A-Za-z0-9_])_?IOBluetoothLocalDeviceSupportsPowerOff(?![A-Za-z0-9_])"),
    re.compile(r"(?<![A-Za-z0-9_])_?CoreDisplay[A-Za-z0-9_]*(?![A-Za-z0-9_])"),
    re.compile(r"AppleSMC"),
    re.compile(r"/Library/Preferences/com\.apple\.powerd\.charging\.plist"),
    re.compile(r"SPUUpdater"),
    re.compile(r"Sparkle"),
)

FORBIDDEN_TEXT_PATTERNS = (
    re.compile(r"\bIOAVService[A-Za-z0-9_]*"),
    re.compile(r"\bIOBluetoothPreference[A-Za-z0-9_]*"),
    re.compile(r"(?<![A-Za-z0-9_])IOBluetoothLocalDeviceSetPowerState(?![A-Za-z0-9_])"),
    re.compile(r"(?<![A-Za-z0-9_])IOBluetoothLocalDeviceSupportsPowerOff(?![A-Za-z0-9_])"),
    re.compile(r"(?<![A-Za-z0-9_])CoreDisplay[A-Za-z0-9_]*(?![A-Za-z0-9_])"),
    re.compile(r"\bAppleSMC[A-Za-z0-9_]*"),
    re.compile(r"(?:SPUUpdater|Sparkle\.framework|DDCPrivateAPI)"),
    re.compile(r"/Library/Preferences/com\.apple\.powerd\.charging\.plist"),
    re.compile(r"(?<![A-Za-z0-9_.])com\.lingsmbp\.StatusTrio\.PowerHelper(?![A-Za-z0-9_.])"),
)

FORBIDDEN_PATH_PATTERNS = (
    re.compile(r"(?:^|/)CoreDisplay\.framework(?:/|$)"),
    re.compile(r"(?:^|/)Sparkle\.framework(?:/|$)"),
    re.compile(r"(?:^|/)DDCPrivateAPI(?:\.framework)?(?:/|$)"),
    re.compile(r"(?:^|/)StatusTrioPowerHelper(?:$|/)"),
    re.compile(r"(?:^|/)StatusTrioMobileBatteryHelper(?:$|/)"),
    re.compile(r"(?:^|/)com\.lingsmbp\.StatusTrio\.PowerHelper(?:\.plist)?$"),
    re.compile(r"(?:^|/)com\.apple\.powerd\.charging\.plist$"),
)

MACHO_MAGICS = (
    b"\xfe\xed\xfa\xce",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe",
    b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf",
    b"\xbf\xba\xfe\xca",
)

EXECUTABLE_CODE_BUNDLE_SUFFIXES = frozenset({"app", "appex", "xpc"})
MH_EXECUTE = 0x2
MAX_FAT_ARCHES = 64

THIN_MACHO_HEADERS = {
    b"\xfe\xed\xfa\xce": ("big", 28),
    b"\xce\xfa\xed\xfe": ("little", 28),
    b"\xfe\xed\xfa\xcf": ("big", 32),
    b"\xcf\xfa\xed\xfe": ("little", 32),
}

FAT_MACHO_HEADERS = {
    b"\xca\xfe\xba\xbe": ("big", False, 20),
    b"\xbe\xba\xfe\xca": ("little", False, 20),
    b"\xca\xfe\xba\xbf": ("big", True, 32),
    b"\xbf\xba\xfe\xca": ("little", True, 32),
}


class AuditFailure(Exception):
    """A deterministic contract failure."""


def fail(message: str) -> None:
    raise AuditFailure(message)


def run_tool(argv: list[str]) -> bytes:
    try:
        result = subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        fail(f"could not execute {argv[0]}: {exc}")
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        fail(f"{' '.join(argv)} failed ({result.returncode}): {detail}")
    return result.stdout


def normalized_relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def ensure_regular_file(path: Path, label: str) -> None:
    try:
        info = path.lstat()
    except OSError as exc:
        fail(f"cannot stat {label} at {path}: {exc}")
    if not stat.S_ISREG(info.st_mode):
        fail(f"{label} is not a regular file: {path}")
    try:
        with path.open("rb"):
            pass
    except OSError as exc:
        fail(f"cannot read {label} at {path}: {exc}")


def safe_walk(root: Path) -> list[Path]:
    """Enumerate every entry without following symlinks."""
    entries: list[Path] = []
    pending = [root]
    while pending:
        current = pending.pop()
        try:
            with os.scandir(current) as iterator:
                children = sorted(iterator, key=lambda item: item.name)
        except OSError as exc:
            fail(f"cannot enumerate {current}: {exc}")
        for child in children:
            path = Path(child.path)
            entries.append(path)
            try:
                is_dir = child.is_dir(follow_symlinks=False)
            except OSError as exc:
                fail(f"cannot inspect {path}: {exc}")
            if is_dir:
                pending.append(path)
    return entries


def resolved_within_bundle(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root)
        return True
    except (OSError, ValueError):
        return False


def check_symlink(path: Path, root: Path) -> None:
    try:
        target = os.readlink(path)
    except OSError as exc:
        fail(f"cannot read symlink {path}: {exc}")
    if os.path.isabs(target):
        fail(f"absolute symlink is not allowed: {path} -> {target}")
    if "\x00" in target:
        fail(f"symlink has an invalid target: {path}")
    lexical = os.path.normpath(os.path.join(os.path.dirname(path), target))
    if lexical == os.pardir or lexical.startswith(os.pardir + os.sep):
        fail(f"symlink escapes the bundle: {path} -> {target}")
    if not resolved_within_bundle(path, root):
        fail(f"symlink resolves outside the bundle: {path} -> {target}")
    normalised = path.resolve(strict=False)
    try:
        resolved = normalised.resolve(strict=True)
    except OSError:
        fail(f"dangling symlink inside the bundle: {path} -> {target}")
    try:
        resolved.relative_to(root)
    except ValueError:
        fail(f"symlink resolves outside the bundle: {path} -> {resolved}")
    if not os.access(path, os.R_OK) and not resolved.is_file():
        fail(f"cannot read symlink target: {path} -> {resolved}")


def read_bytes(path: Path, label: str) -> bytes:
    ensure_regular_file(path, label)
    try:
        return path.read_bytes()
    except OSError as exc:
        fail(f"cannot read {label} at {path}: {exc}")


def is_macho(data: bytes) -> bool:
    return len(data) >= 4 and data[:4] in MACHO_MAGICS


def thin_macho_filetype(data: bytes, label: str) -> int:
    if len(data) < 4:
        fail(f"truncated Mach-O header at {label}")
    header = THIN_MACHO_HEADERS.get(data[:4])
    if header is None:
        fail(f"invalid thin Mach-O magic at {label}")
    endian, header_size = header
    if len(data) < header_size:
        fail(f"truncated Mach-O header at {label}")
    filetype = int.from_bytes(data[12:16], endian)
    sizeofcmds = int.from_bytes(data[20:24], endian)
    if header_size + sizeofcmds > len(data):
        fail(f"truncated Mach-O load commands at {label}")
    return filetype


def macho_file_types(path: Path) -> tuple[int, ...]:
    data = read_bytes(path, f"Mach-O {path}")
    if len(data) < 4:
        fail(f"truncated Mach-O header at {path}")
    if data[:4] in THIN_MACHO_HEADERS:
        return (thin_macho_filetype(data, str(path)),)

    fat_header = FAT_MACHO_HEADERS.get(data[:4])
    if fat_header is None:
        fail(f"unrecognized Mach-O header at {path}")
    endian, is_64_bit, arch_size = fat_header
    if len(data) < 8:
        fail(f"truncated universal Mach-O header at {path}")
    architectures = int.from_bytes(data[4:8], endian)
    if architectures == 0 or architectures > MAX_FAT_ARCHES:
        fail(f"invalid universal Mach-O architecture count at {path}: {architectures}")
    table_end = 8 + architectures * arch_size
    if table_end > len(data):
        fail(f"truncated universal Mach-O architecture table at {path}")

    filetypes: list[int] = []
    for index in range(architectures):
        record = 8 + index * arch_size
        if is_64_bit:
            offset = int.from_bytes(data[record + 8:record + 16], endian)
            size = int.from_bytes(data[record + 16:record + 24], endian)
        else:
            offset = int.from_bytes(data[record + 8:record + 12], endian)
            size = int.from_bytes(data[record + 12:record + 16], endian)
        if size < 28:
            fail(f"universal Mach-O slice {index} is too small at {path}")
        if offset < table_end or offset + size > len(data):
            fail(f"universal Mach-O slice {index} is truncated at {path}")
        slice_data = data[offset:offset + size]
        filetypes.append(thin_macho_filetype(slice_data, f"{path} slice {index}"))
    return tuple(filetypes)


def classify_file(path: Path) -> bytes:
    output = run_tool(["file", "-b", "--", str(path)])
    if b"Mach-O" in output:
        with path.open("rb") as handle:
            if not is_macho(handle.read(4)):
                fail(f"file reported Mach-O but the header does not match: {path}")
    return output


def is_macho_file(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            data = handle.read(4)
    except OSError as exc:
        fail(f"cannot inspect Mach-O header at {path}: {exc}")
    classify_file(path)
    return is_macho(data)


def validate_plist(path: Path, label: str) -> object:
    data = read_bytes(path, label)
    try:
        return plistlib.loads(data)
    except Exception as exc:
        fail(f"invalid plist at {path}: {exc}")


def validate_info(path: Path) -> tuple[str, str]:
    payload = validate_plist(path, "Info.plist")
    if not isinstance(payload, dict):
        fail("Info.plist root is not a dictionary")
    bundle_id = payload.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or not any(
        pattern.fullmatch(bundle_id) for pattern in STORE_IDS
    ):
        fail(
            "Info.plist CFBundleIdentifier is not the App Store identity or its "
            f"development identity: {bundle_id!r}"
        )
    executable = payload.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable:
        fail("Info.plist CFBundleExecutable is missing")
    if "/" in executable or executable in (".", ".."):
        fail(f"Info.plist CFBundleExecutable is not a safe basename: {executable!r}")
    if payload.get("CFBundlePackageType") != "APPL":
        fail("Info.plist CFBundlePackageType must be APPL")
    for key in payload:
        if isinstance(key, str) and SU_KEY_PATTERN.match(key):
            fail(f"forbidden Sparkle/updater key {key} is present in Info.plist")
    return bundle_id, executable


def validate_entitlements(path: Path, require_sandbox: bool) -> None:
    try:
        result = subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        fail(f"could not read entitlements from {path}: {exc}")
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        fail(
            f"codesign could not read entitlements for {path} "
            f"({result.returncode}): {detail}"
        )
    output = result.stdout
    start = output.find(b"<?xml")
    if start < 0:
        start = output.find(b"<plist")
    if start < 0:
        if b"code object is not signed at all" in result.stderr:
            fail(f"code item is not signed: {path}")
        if require_sandbox:
            fail(f"main app returned no entitlement property list: {path}")
        return
    try:
        payload = plistlib.loads(output[start:])
    except Exception as exc:
        fail(f"codesign returned an invalid entitlement property list for {path}: {exc}")
    if not isinstance(payload, dict):
        fail(f"signed entitlements root is not a dictionary for {path}")
    sandbox = payload.get("com.apple.security.app-sandbox")
    if sandbox is not None and sandbox is not True:
        fail(f"app-sandbox must be absent or true for {path}")
    if require_sandbox and sandbox is not True:
        fail(
            "executable code item entitlements must set "
            f"com.apple.security.app-sandbox=true: {path}"
        )
    if payload.get("com.apple.security.get-task-allow") not in (None, False):
        fail(f"signed entitlements must not enable get-task-allow: {path}")
    for key in payload:
        if not isinstance(key, str):
            fail(f"signed entitlement key is not a string: {path}")
        value = payload[key]
        if key == "com.apple.security.app-sandbox":
            continue
        if key == "com.apple.security.get-task-allow" and value is not False:
            fail(f"get-task-allow must be absent or false: {path}")
        if key.startswith(FORBIDDEN_ENTITLEMENT_PREFIXES):
            fail(f"forbidden sandbox escape entitlement {key}: {path}")
        if key in FORBIDDEN_ENTITLEMENTS or key in FORBIDDEN_ENTITLEMENT_KEYS:
            fail(f"forbidden debug/JIT entitlement {key}: {path}")


def check_component_name(path: Path, app: Path) -> None:
    name = path.name
    for forbidden in FORBIDDEN_COMPONENT_NAMES:
        if name == forbidden:
            fail(f"forbidden component {forbidden} at {normalized_relative(path, app)}")
    for pattern in FORBIDDEN_NAME_PATTERNS:
        if pattern.search(name):
            fail(f"forbidden helper or launch registration at {normalized_relative(path, app)}")


def code_items_to_verify(app: Path, machos: list[Path]) -> list[Path]:
    items: dict[str, Path] = {str(app): app}
    for path in machos:
        try:
            info = path.lstat()
        except OSError as exc:
            fail(f"cannot inspect code item {path}: {exc}")
        if not stat.S_ISREG(info.st_mode):
            fail(f"code item is not a regular file: {path}")
        items[str(path)] = path

        current = path.parent
        while True:
            suffix = current.name.rsplit(".", 1)[-1] if "." in current.name else ""
            if suffix in {"framework", "app", "appex", "xpc", "bundle", "plugin"}:
                items[str(current)] = current
            if current == app:
                break
            parent = current.parent
            if parent == current:
                break
            current = parent
    return [items[key] for key in sorted(items)]


def code_bundle_suffix(path: Path) -> Optional[str]:
    if "." not in path.name:
        return None
    return path.name.rsplit(".", 1)[-1].lower()


def requires_sandbox_entitlement(
    path: Path,
    app: Path,
    main: Path,
    macho_types: dict[str, tuple[int, ...]],
) -> bool:
    """Require sandbox on executable containers and actual MH_EXECUTE code."""
    resolved = path.resolve()
    if resolved in {app.resolve(), main.resolve()}:
        return True
    if path.is_dir() and code_bundle_suffix(path) in EXECUTABLE_CODE_BUNDLE_SUFFIXES:
        return True
    return MH_EXECUTE in macho_types.get(str(resolved), ())


def verify_signed_code(
    app: Path,
    main_executable: Path,
    machos: list[Path],
    macho_types: dict[str, tuple[int, ...]],
) -> int:
    items = code_items_to_verify(app, machos)
    if not any(path.resolve() == main_executable.resolve() for path in items):
        fail(f"main executable is not a signed code item: {main_executable}")
    for path in items:
        run_tool(["codesign", "--verify", "--strict", "--verbose=2", str(path)])
        validate_entitlements(
            path,
            require_sandbox=requires_sandbox_entitlement(
                path,
                app,
                main_executable,
                macho_types,
            ),
        )
    return len(items)


def scan_plist(payload: object, where: str) -> None:
    if isinstance(payload, dict):
        for key, value in payload.items():
            if isinstance(key, str) and SU_KEY_PATTERN.match(key):
                fail(f"forbidden updater key {key} in {where}")
            scan_plist(value, where)
    elif isinstance(payload, list):
        for value in payload:
            scan_plist(value, where)
    elif isinstance(payload, str):
        for pattern in FORBIDDEN_TEXT_PATTERNS:
            if pattern.search(payload):
                fail(
                    f"forbidden runtime component reference {pattern.pattern} "
                    f"in {where}"
                )
    elif isinstance(payload, bytes):
        text = payload.decode("latin-1", errors="replace")
        for pattern in FORBIDDEN_TEXT_PATTERNS:
            if pattern.search(text):
                fail(
                    f"forbidden runtime component reference {pattern.pattern} "
                    f"in data value of {where}"
                )


def scan_macho(path: Path, app: Path) -> None:
    relative = normalized_relative(path, app)
    print(f"Mach-O: {relative}")

    otool_output = run_tool(["otool", "-L", str(path)])
    decoded_otool = otool_output.decode("utf-8", errors="replace")
    if str(path) not in decoded_otool:
        fail(f"otool output did not identify {relative}")
    for line in decoded_otool.splitlines():
        for pattern in FORBIDDEN_PATH_PATTERNS:
            if pattern.search(line):
                fail(f"forbidden dependency {pattern.pattern} in {relative}")

    undefined_output = run_tool(["nm", "-u", str(path)])
    undefined_text = undefined_output.decode("utf-8", errors="replace")
    for pattern in FORBIDDEN_SYMBOL_PATTERNS:
        if pattern.search(undefined_text):
            fail(f"forbidden symbol {pattern.pattern} in undefined symbols of {relative}")

    all_output = run_tool(["nm", "-a", str(path)])
    all_text = all_output.decode("utf-8", errors="replace")
    for pattern in FORBIDDEN_SYMBOL_PATTERNS:
        if pattern.search(all_text):
            fail(f"forbidden symbol {pattern.pattern} in all symbols of {relative}")

    try:
        binary_text = path.read_bytes().decode("latin-1", errors="replace")
    except OSError as exc:
        fail(f"cannot read Mach-O bytes at {path}: {exc}")
    for pattern in FORBIDDEN_TEXT_PATTERNS:
        if pattern.search(binary_text):
            fail(f"forbidden string {pattern.pattern} in Mach-O bytes of {relative}")


def scan_objc_symbols(path: Path, app: Path) -> None:
    try:
        result = subprocess.run(
            ["nm", "-gj", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        fail(f"could not inspect Objective-C symbols at {path}: {exc}")
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        fail(
            f"could not inspect Objective-C symbols at {path} "
            f"({result.returncode}): {detail}"
        )
    text = result.stdout.decode("utf-8", errors="replace")
    for pattern in FORBIDDEN_SYMBOL_PATTERNS:
        if pattern.search(text):
            fail(
                f"forbidden symbol {pattern.pattern} in Objective-C symbols "
                f"of {normalized_relative(path, app)}"
            )


def audit_layout(app: Path, executable: str) -> None:
    contents = app / "Contents"
    if not contents.is_dir():
        fail(f"missing Contents directory at {app}")
    for required in ("Info.plist", "MacOS"):
        if not (contents / required).exists():
            fail(f"missing Contents/{required} at {app}")
    main = contents / "MacOS" / executable
    if not main.is_file():
        fail(f"missing main executable at {main}")
    ensure_regular_file(main, "main executable")
    if not is_macho_file(main):
        fail(f"main executable is not Mach-O: {main}")


def audit_bundle(app: Path, unsigned: bool) -> None:
    try:
        app = app.resolve(strict=True)
    except OSError as exc:
        fail(f"bundle does not exist or cannot be resolved: {app}: {exc}")
    if not app.is_dir():
        fail(f"bundle is not a directory: {app}")

    info_path = app / "Contents" / "Info.plist"
    bundle_id, executable = validate_info(info_path)
    audit_layout(app, executable)

    machos: list[Path] = []
    macho_types: dict[str, tuple[int, ...]] = {}
    symlinks = 0
    for path in safe_walk(app):
        check_component_name(path, app)
        relative = normalized_relative(path, app)
        for pattern in FORBIDDEN_PATH_PATTERNS:
            if pattern.search(relative):
                fail(f"forbidden component path {relative}")
        try:
            info = path.lstat()
        except OSError as exc:
            fail(f"cannot inspect {path}: {exc}")
        if stat.S_ISLNK(info.st_mode):
            check_symlink(path, app)
            symlinks += 1
            continue
        if stat.S_ISDIR(info.st_mode):
            continue
        if not stat.S_ISREG(info.st_mode):
            fail(f"unsupported non-regular bundle entry: {relative}")
        read_bytes(path, relative)
        classify_file(path)
        if is_macho_file(path):
            machos.append(path)
            macho_types[str(path.resolve())] = macho_file_types(path)
        elif path.suffix.lower() == ".plist":
            payload = validate_plist(path, normalized_relative(path, app))
            scan_plist(payload, normalized_relative(path, app))

    main_path = (app / "Contents" / "MacOS" / executable).resolve()
    if not any(path.resolve() == main_path for path in machos):
        fail(f"main executable was not enumerated as Mach-O: {main_path.relative_to(app)}")

    for path in machos:
        scan_macho(path, app)
        scan_objc_symbols(path, app)

    main_executable = app / "Contents" / "MacOS" / executable
    signed_code_items = 0
    if unsigned:
        print("Scope: unsigned compile/static only")
        print("Sandbox runtime: NOT RUN")
    else:
        signed_code_items = verify_signed_code(
            app,
            main_executable,
            machos,
            macho_types,
        )
        print(
            "Scope: signed static audit with recursive nested-code verification; "
            "sandbox runtime remains NOT RUN"
        )

    print(f"Bundle ID: {bundle_id}")
    print(f"Mach-O files audited: {len(machos)}")
    print(f"Signed code items verified: {signed_code_items}")
    print(f"Symlinks audited: {symlinks}")
    print("Known limitation: numeric private HAL selectors need source closure audit.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fail-closed static App Store bundle audit",
    )
    parser.add_argument("app", type=Path)
    parser.add_argument(
        "--unsigned",
        action="store_true",
        help="skip signature evidence; this is static-only, not sandbox runtime proof",
    )
    args = parser.parse_args()
    try:
        audit_bundle(args.app, args.unsigned)
    except AuditFailure as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
