#!/usr/bin/env python3
"""Fail-closed audit of the App Store source closure.

The source-membership manifest is a claim. This auditor verifies that claim
against the repository's Direct-only manifest, the actual SwiftFileList output
from Xcode, and a limited lexical scan of every compiled Swift source.

This is static evidence only. It does not prove sandbox runtime behavior,
framework availability on macOS 13, or that no private API remains in a binary.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 2
CHANNEL = "appStore"
STORE_DEFINE = "STATUS_TRIO_APP_STORE"
DIRECT_ONLY_MANIFEST = "AppStore/direct-only-sources.txt"
FILE_LIST_NAME = "StatusTrioCore.SwiftFileList"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SOURCE_TREE_SHA_RE = re.compile(r"^[0-9a-f]{64}$")

REQUIRED_FIELDS = (
    "schema_version",
    "channel",
    "repository_root",
    "included_sources",
    "excluded_sources",
    "source_sha",
    "source_tree_sha256",
    "linked_frameworks",
    "swift_defines",
    "compiled_sources",
    "derived_sources",
    "swift_file_lists",
)

ALLOWED_FRAMEWORKS = {
    "AppKit",
    "AudioToolbox",
    "Carbon",
    "Combine",
    "CoreBluetooth",
    "CoreFoundation",
    "CoreGraphics",
    "CoreLocation",
    "CoreAudio",
    "CoreText",
    "CoreWLAN",
    "CryptoKit",
    "Darwin",
    "Dispatch",
    "Foundation",
    "ImageIO",
    "IOBluetooth",
    "IOKit",
    "Network",
    "OSLog",
    "QuartzCore",
    "Security",
    "ServiceManagement",
    "SwiftUI",
    "SystemConfiguration",
    "notify",
    "os",
}

FORBIDDEN_FRAMEWORKS = {
    "Sparkle",
    "DDCPrivateAPI",
    "PowerHelperProtocol",
    "CoreDisplay",
    "DirectPlatform",
}

FORBIDDEN_IMPORTS = {
    "Sparkle",
    "DDCPrivateAPI",
    "PowerHelperProtocol",
    "CoreDisplay",
    "DirectPlatform",
}

# These are forbidden wherever they occur outside Swift comments. Keeping the
# patterns token-shaped avoids treating prose such as "shared DDC model" as an
# implementation reference.
FORBIDDEN_TOKENS = (
    ("IOAVService", re.compile(r"\bIOAVService[A-Za-z0-9_]*\b")),
    ("IOBluetoothPreference", re.compile(r"\bIOBluetoothPreference[A-Za-z0-9_]*\b")),
    (
        "IOBluetoothLocalDeviceSetPowerState",
        re.compile(r"\bIOBluetoothLocalDeviceSetPowerState\b"),
    ),
    (
        "IOBluetoothLocalDeviceSupportsPowerOff",
        re.compile(r"\bIOBluetoothLocalDeviceSupportsPowerOff\b"),
    ),
    ("Sparkle/SPUUpdater", re.compile(r"\b(?:Sparkle|SPUUpdater)\b")),
    ("PowerHelperProtocol", re.compile(r"\bPowerHelperProtocol\b")),
    ("DDCPrivateAPI", re.compile(r"\bDDCPrivateAPI\b")),
    ("CoreDisplay", re.compile(r"\bCoreDisplay\b")),
    ("DirectPlatform", re.compile(r"\bDirectPlatform\b")),
    ("AppleSMC", re.compile(r"\bAppleSMC\b")),
    (
        "powerd charging plist",
        re.compile(r"(?:/Library/Preferences/)?com\.apple\.powerd\.charging\.plist"),
    ),
    ("com.apple.nat", re.compile(r"\bcom\.apple\.nat(?:\.[A-Za-z0-9_]+)*\b")),
    (
        "root helper Mach service label",
        re.compile(
            r"(?<![A-Za-z0-9_.-])com\.lingsmbp\.StatusTrio\.PowerHelper"
            r"(?![A-Za-z0-9_.-])"
        ),
    ),
    (
        "mobile helper Mach service label",
        re.compile(
            r"(?<![A-Za-z0-9_.-])com\.lingsmbp\.StatusTrio\.MobileBatteryHelper"
            r"(?![A-Za-z0-9_.-])"
        ),
    ),
    ("root helper component", re.compile(r"\bStatusTrioPowerHelper\b")),
    (
        "mobile helper component",
        re.compile(r"\bStatusTrioMobileBatteryHelper\b"),
    ),
)

SWIFT_INTEGER_LITERAL_RE = re.compile(
    r"(?<![A-Za-z0-9_])(?P<literal>"
    r"0[bB][01](?:_?[01])*|"
    r"0[oO][0-7](?:_?[0-7])*|"
    r"0[xX][0-9A-Fa-f](?:_?[0-9A-Fa-f])*|"
    r"[0-9](?:_?[0-9])*"
    r")(?![A-Za-z0-9_.])"
)
PRIVATE_HAL_VALUES = {0x69616170, 0x6C73746D, 0x6C736D73}

PRIVILEGED_XPC_RE = re.compile(
    r"\bNSXPCConnection\s*\([^)]*?\boptions\s*:\s*\.privileged\b",
    re.DOTALL,
)
ROOT_HELPER_RE = re.compile(
    r"\bSMAppService\s*\.\s*(?:daemon|agent)\s*\([^)]*"
    r"(?:StatusTrio)?PowerHelper[^)]*\)",
    re.DOTALL,
)
FORBIDDEN_PRIVILEGED_API_RE = re.compile(
    r"\b(?:SMJobBless|SMJobSubmit|SMJobRemove|"
    r"AuthorizationExecuteWithPrivileges)\b"
)


class AuditFailure(Exception):
    """A deterministic contract failure with a stable diagnostic."""


def fail(message: str) -> None:
    raise AuditFailure(message)


@dataclass(frozen=True)
class SourceToken:
    kind: str
    text: str
    line: int
    column: int


def display(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def source_location(path: Path, root: Path, line: int, column: int | None = None) -> str:
    location = f"{display(path, root)}:{line}"
    if column is not None:
        location += f":{column}"
    return location


def read_text(path: Path, label: str, root: Path) -> str:
    ensure_regular_readable(path, label, root)
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        fail(f"{display(path, root)}: {label} is not valid UTF-8: {exc}")
    except OSError as exc:
        fail(f"{display(path, root)}: cannot read {label}: {exc}")


def ensure_regular_readable(path: Path, label: str, root: Path) -> None:
    try:
        info = path.lstat()
    except OSError as exc:
        fail(f"{display(path, root)}: cannot stat {label}: {exc}")
    if stat.S_ISLNK(info.st_mode):
        fail(f"{display(path, root)}: {label} is a symlink, expected a regular file")
    if not stat.S_ISREG(info.st_mode):
        fail(f"{display(path, root)}: {label} is not a regular file")
    if not os.access(path, os.R_OK):
        fail(f"{display(path, root)}: {label} is not readable")
    try:
        with path.open("rb"):
            pass
    except OSError as exc:
        fail(f"{display(path, root)}: {label} is not readable: {exc}")


def ensure_within(path: Path, container: Path, label: str, root: Path) -> None:
    try:
        path.resolve(strict=True).relative_to(container.resolve(strict=True))
    except (OSError, ValueError):
        fail(f"{display(path, root)}: {label} escapes {display(container, root)}")


def git_output(root: Path, arguments: list[str], label: str) -> str:
    environment = os.environ.copy()
    for variable in (
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_COMMON_DIR",
        "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    ):
        environment.pop(variable, None)
    environment["LC_ALL"] = "C"
    command = ["git", "-C", str(root), *arguments]
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=15,
            env=environment,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(f"cannot verify Git {label} for repository_root: {exc}")
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        fail(
            f"cannot verify Git {label} for repository_root "
            f"(git exit {result.returncode}): {detail or 'no diagnostic'}"
        )
    output = result.stdout.decode("utf-8", errors="replace").strip()
    if not output or "\n" in output or "\r" in output:
        fail(f"Git {label} did not return exactly one value")
    return output


def repository_head(root: Path) -> str:
    toplevel = git_output(root, ["rev-parse", "--show-toplevel"], "worktree root")
    try:
        actual_root = Path(toplevel).resolve(strict=True)
    except OSError as exc:
        fail(f"cannot resolve Git worktree root {toplevel!r}: {exc}")
    if actual_root != root.resolve():
        fail(
            "repository_root is not the Git worktree root: "
            f"{root} (Git root: {actual_root})"
        )
    head = git_output(root, ["rev-parse", "--verify", "HEAD^{commit}"], "HEAD")
    if not SHA_RE.fullmatch(head):
        fail(f"repository HEAD is not a lowercase 40-character commit SHA: {head!r}")
    return head


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"manifest field {field} must be a non-empty string")
    return value


def require_string_list(value: Any, field: str) -> list[str]:
    if not isinstance(value, list):
        fail(f"manifest field {field} must be an array")
    for index, item in enumerate(value):
        if not isinstance(item, str) or not item:
            fail(f"manifest field {field}[{index}] must be a non-empty string")
    return value


def require_relative_path(path: str, field: str) -> str:
    if "\x00" in path:
        fail(f"manifest field {field} contains a NUL byte")
    candidate = Path(path)
    if candidate.is_absolute():
        fail(f"manifest field {field} must be repository-relative: {path}")
    parts = candidate.parts
    if not parts or any(part in ("", ".", "..") for part in parts):
        fail(f"manifest field {field} contains a non-canonical path: {path}")
    if candidate.as_posix() != path:
        fail(f"manifest field {field} must use canonical POSIX syntax: {path}")
    if candidate.suffix != ".swift":
        fail(f"manifest field {field} is not a Swift file: {path}")
    return path


def require_unique(paths: list[str], field: str) -> None:
    seen: set[str] = set()
    for path in paths:
        if path in seen:
            fail(f"manifest field {field} contains duplicate path: {path}")
        seen.add(path)


def source_tree_sha256(root: Path, entries: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for relative in sorted(set(entries)):
        path = root / relative
        ensure_regular_readable(path, "source tree entry", root)
        try:
            data = path.read_bytes()
        except OSError as exc:
            fail(f"{display(path, root)}: cannot hash source tree entry: {exc}")
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(len(data)).encode("ascii"))
        digest.update(b"\0")
        digest.update(data)
        digest.update(b"\0")
    return digest.hexdigest()


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
    except OSError as exc:
        fail(f"cannot read manifest {path}: {exc}")
    except json.JSONDecodeError as exc:
        fail(f"manifest {path} is not valid JSON: {exc}")
    if not isinstance(value, dict):
        fail("manifest root must be a JSON object")
    missing = [field for field in REQUIRED_FIELDS if field not in value]
    if missing:
        fail("manifest is missing required field(s): " + ", ".join(missing))
    if type(value["schema_version"]) is not int or value["schema_version"] != SCHEMA_VERSION:
        fail(f"manifest schema_version must be integer {SCHEMA_VERSION}")
    if value["channel"] != CHANNEL:
        fail(f"manifest channel must be {CHANNEL!r}")
    sha = require_string(value["source_sha"], "source_sha")
    if not SHA_RE.fullmatch(sha):
        fail("manifest source_sha must be a lowercase 40-character hexadecimal SHA")
    tree_sha = require_string(value["source_tree_sha256"], "source_tree_sha256")
    if not SOURCE_TREE_SHA_RE.fullmatch(tree_sha):
        fail(
            "manifest source_tree_sha256 must be a lowercase "
            "64-character SHA-256"
        )
    root_value = require_string(value["repository_root"], "repository_root")
    repository_root = Path(root_value)
    if not repository_root.is_absolute() or repository_root.resolve().as_posix() != root_value:
        fail("manifest repository_root must be a canonical absolute path")
    if not repository_root.is_dir():
        fail(f"manifest repository_root is not a directory: {root_value}")
    for field in (
        "included_sources",
        "excluded_sources",
        "linked_frameworks",
        "swift_defines",
        "compiled_sources",
        "derived_sources",
        "swift_file_lists",
    ):
        require_string_list(value[field], field)
    for field in ("included_sources", "excluded_sources", "compiled_sources"):
        for path_value in value[field]:
            require_relative_path(path_value, field)
    for path_value in value["derived_sources"]:
        if "\x00" in path_value or Path(path_value).suffix != ".swift":
            fail(f"manifest field derived_sources has invalid Swift path: {path_value}")
    for path_value in value["swift_file_lists"]:
        candidate = Path(path_value)
        if (
            "\x00" in path_value
            or not candidate.parts
            or candidate.suffix != ".SwiftFileList"
            or any(part == ".." for part in candidate.parts)
        ):
            fail(f"manifest field swift_file_lists has invalid path: {path_value}")
    require_unique(value["included_sources"], "included_sources")
    require_unique(value["excluded_sources"], "excluded_sources")
    require_unique(value["compiled_sources"], "compiled_sources")
    require_unique(value["derived_sources"], "derived_sources")
    # Absolute and relative spellings of the same file list are compared after
    # resolution in parse_file_lists, so uniqueness is enforced there.
    if STORE_DEFINE not in value["swift_defines"]:
        fail(
            "manifest swift_defines must contain the App Store compilation "
            f"condition {STORE_DEFINE}"
        )
    included = set(value["included_sources"])
    excluded = set(value["excluded_sources"])
    overlap = sorted(included & excluded)
    if overlap:
        fail("included_sources and excluded_sources overlap: " + ", ".join(overlap))
    if set(value["compiled_sources"]) != included:
        fail(
            "manifest compiled_sources must equal included_sources "
            "(set equality with no duplicates)"
        )
    return value


def parse_direct_only_manifest(root: Path) -> list[str]:
    path = root / DIRECT_ONLY_MANIFEST
    ensure_regular_readable(path, "Direct-only source manifest", root)
    entries: list[str] = []
    seen: set[str] = set()
    for line_number, raw_line in enumerate(
        read_text(path, "Direct-only source manifest", root).splitlines(), 1
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if any(part == ".." for part in Path(line).parts):
            fail(f"{display(path, root)}:{line_number}: path escape is not allowed: {line}")
        if Path(line).is_absolute():
            fail(f"{display(path, root)}:{line_number}: path must be repository-relative: {line}")
        relative = require_relative_path(line, f"{DIRECT_ONLY_MANIFEST}:{line_number}")
        if relative in seen:
            fail(
                f"{display(path, root)}:{line_number}: duplicate Direct-only entry: {relative}"
            )
        source = root / relative
        if not source.exists():
            fail(
                f"{display(path, root)}:{line_number}: Direct-only source does not exist: {relative}"
            )
        ensure_within(source, root, "Direct-only source", root)
        seen.add(relative)
        entries.append(relative)
    return sorted(entries)


def validate_sources_exist(
    root: Path, sources: Iterable[str], label: str
) -> None:
    for relative in sources:
        path = root / relative
        ensure_regular_readable(path, label, root)
        ensure_within(path, root, label, root)


def read_swift_file_list(path: Path, root: Path) -> list[str]:
    ensure_regular_readable(path, "SwiftFileList", root)
    if path.name != FILE_LIST_NAME:
        fail(
            f"{display(path, root)}: expected Store Core file list named {FILE_LIST_NAME}"
        )
    if ".build" not in path.parts:
        fail(f"{display(path, root)}: SwiftFileList must live under .build")
    lines = read_text(path, "SwiftFileList", root).splitlines()
    entries: list[str] = []
    seen: set[str] = set()
    for line_number, raw_line in enumerate(lines, 1):
        if "\x00" in raw_line:
            fail(f"{display(path, root)}:{line_number}: NUL byte in SwiftFileList")
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        candidate = Path(line)
        if not candidate.is_absolute() and Path(line).parts and Path(line).parts[0] == "~":
            fail(f"{display(path, root)}:{line_number}: home-relative file list entry")
        if not candidate.is_absolute():
            candidate = path.parent / candidate
        try:
            candidate = candidate.resolve(strict=True)
        except OSError as exc:
            fail(f"{display(path, root)}:{line_number}: missing file-list entry: {line}: {exc}")
        if not candidate.is_file():
            fail(f"{display(path, root)}:{line_number}: file-list entry is not a file: {line}")
        source_value = candidate.as_posix()
        if source_value in seen:
            fail(
                f"{display(path, root)}:{line_number}: duplicate file-list entry: {line}"
            )
        seen.add(source_value)
        try:
            candidate.relative_to(root)
            entries.append(candidate.relative_to(root).as_posix())
            continue
        except ValueError:
            pass
        derived_root = (root / ".build" / "app-store" / "DerivedData").resolve()
        try:
            candidate.relative_to(derived_root)
        except ValueError:
            fail(
                f"{display(path, root)}:{line_number}: file-list entry is outside "
                "the repository and controlled DerivedData: "
                + line
            )
    if not entries:
        fail(f"{display(path, root)}: SwiftFileList contains no source entries")
    return entries


def parse_file_lists(
    root: Path, manifest: dict[str, Any]
) -> tuple[list[str], list[str]]:
    compiled: list[str] = []
    derived: list[str] = []
    seen_file_lists: set[Path] = set()
    per_list_sets: list[tuple[str, set[str], set[str]]] = []
    for value in manifest["swift_file_lists"]:
        path = Path(value)
        if not path.is_absolute():
            path = root / path
        lexical_path = path.resolve(strict=False)
        if lexical_path in seen_file_lists:
            fail(f"manifest swift_file_lists duplicates {value}")
        seen_file_lists.add(lexical_path)
        try:
            path.resolve(strict=True).relative_to((root / ".build").resolve())
        except (OSError, ValueError):
            fail(f"{display(path, root)}: SwiftFileList resolves outside .build")
        ensure_regular_readable(path, "SwiftFileList", root)
        ensure_within(path, root, "SwiftFileList", root)
        # This rejects a symlink escaping .build before the stricter file check.
        try:
            path.resolve(strict=True).relative_to((root / ".build").resolve())
        except (OSError, ValueError):
            fail(f"{display(path, root)}: SwiftFileList resolves outside .build")
        resolved_path = path.resolve()
        entries = read_swift_file_list(resolved_path, root)
        derived_root = (root / ".build" / "app-store" / "DerivedData").resolve()
        list_compiled: list[str] = []
        list_derived: list[str] = []
        for entry in entries:
            resolved = (root / entry).resolve()
            try:
                resolved.relative_to(derived_root)
                list_derived.append(entry)
            except ValueError:
                list_compiled.append(entry)
        per_list_sets.append(
            (
                display(resolved_path, root),
                set(list_compiled),
                set(list_derived),
            )
        )
        compiled.extend(list_compiled)
        derived.extend(list_derived)
    if not manifest["swift_file_lists"]:
        fail("manifest swift_file_lists is empty; real compiled evidence is required")
    if not compiled:
        fail("manifest SwiftFileList evidence contains no repository source files")
    # Xcode emits one file list per architecture for the same target. Their
    # sets must agree; a duplicate within one file list is rejected above.
    first_name, first_compiled, first_derived = per_list_sets[0]
    for name, list_compiled, list_derived in per_list_sets[1:]:
        if list_compiled != first_compiled or list_derived != first_derived:
            fail(
                "SwiftFileList evidence differs between architecture slices: "
                f"{first_name} vs {name}"
            )
    return sorted(set(compiled)), sorted(set(derived))


def classify_swift_tokens(text: str) -> list[SourceToken]:
    """Return tokens outside comments while retaining all string forms.

    Swift comments are removed with a small lexer rather than a regex. Strings,
    including raw and multiline literals, are deliberately retained because
    dlsym/NSSelectorFromString can name a private symbol only in a string.
    """
    tokens: list[SourceToken] = []
    i = 0
    line = 1
    column = 1
    length = len(text)

    def advance(fragment: str) -> None:
        nonlocal line, column
        newlines = fragment.count("\n")
        if newlines:
            line += newlines
            column = len(fragment) - fragment.rfind("\n")
        else:
            column += len(fragment)

    def consume_string(
        content_i: int,
        hashes: int,
        triple: bool,
        token_line: int,
        token_column: int,
    ) -> int:
        nonlocal line, column
        delimiter = '"""' if triple else '"'
        closing = delimiter + ("#" * hashes)
        raw_escape = "\\" + ("#" * hashes) if hashes else ""
        i = content_i
        while i < length:
            if hashes and text.startswith(raw_escape, i):
                if i + len(raw_escape) >= length:
                    fail(
                        f"unterminated raw Swift string at "
                        f"line {token_line}, column {token_column}"
                    )
                fragment = text[i : i + len(raw_escape) + 1]
                advance(fragment)
                i += len(fragment)
                continue
            if not hashes and text[i] == "\\":
                if i + 1 >= length:
                    fail(
                        f"unterminated Swift string at "
                        f"line {token_line}, column {token_column}"
                    )
                advance(text[i : i + 2])
                i += 2
                continue
            if text.startswith(closing, i):
                advance(closing)
                return i + len(closing)
            if not triple and text[i] in "\r\n":
                fail(
                    f"newline in single-line Swift string at "
                    f"line {token_line}, column {token_column}"
                )
            advance(text[i])
            i += 1
        fail(
            f"unterminated Swift string at "
            f"line {token_line}, column {token_column}"
        )

    while i < length:
        char = text[i]
        if char == "/" and i + 1 < length and text[i + 1] == "/":
            end = text.find("\n", i + 2)
            if end < 0:
                break
            advance(text[i:end])
            i = end
            continue
        if char == "/" and i + 1 < length and text[i + 1] == "*":
            start_line, start_column = line, column
            depth = 1
            i += 2
            advance("/*")
            while i < length and depth:
                if text.startswith("/*", i):
                    depth += 1
                    advance("/*")
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    advance("*/")
                    i += 2
                else:
                    advance(text[i])
                    i += 1
            if depth:
                fail(
                    f"unterminated Swift block comment at "
                    f"line {start_line}, column {start_column}"
                )
            continue
        if char.isspace():
            advance(char)
            i += 1
            continue
        if char == "#":
            marker_i = i
            while marker_i < length and text[marker_i] == "#":
                marker_i += 1
            if marker_i < length and text[marker_i] == '"':
                hashes = marker_i - i
                triple = text.startswith('"""', marker_i)
                content_i = marker_i + (3 if triple else 1)
                token_line, token_column = line, column
                advance(text[i:content_i])
                i = consume_string(
                    content_i,
                    hashes,
                    triple,
                    token_line,
                    token_column,
                )
                tokens.append(
                    SourceToken("string", text[marker_i - hashes : i], token_line, token_column)
                )
                continue
        if char == '"':
            start_i = i
            token_line, token_column = line, column
            triple = text.startswith('"""', i)
            content_i = i + (3 if triple else 1)
            advance(text[i:content_i])
            i = consume_string(
                content_i,
                0,
                triple,
                token_line,
                token_column,
            )
            tokens.append(SourceToken("string", text[start_i:i], token_line, token_column))
            continue
        if char.isalpha() or char == "_":
            start_i = i
            token_line, token_column = line, column
            while i < length and (text[i].isalnum() or text[i] == "_"):
                advance(text[i])
                i += 1
            tokens.append(SourceToken("identifier", text[start_i:i], token_line, token_column))
            continue
        if char.isdigit():
            start_i = i
            token_line, token_column = line, column
            while i < length and (
                text[i].isalnum() or text[i] in "_+-." or text[i] == "'"
            ):
                advance(text[i])
                i += 1
            tokens.append(SourceToken("number", text[start_i:i], token_line, token_column))
            continue
        tokens.append(SourceToken("punct", char, line, column))
        advance(char)
        i += 1
    return tokens


def token_text(tokens: list[SourceToken]) -> str:
    return "".join(token.text for token in tokens)


def token_match_location(token: SourceToken, match: re.Match[str]) -> tuple[int, int]:
    prefix = token.text[: match.start()]
    if "\n" not in prefix:
        return token.line, token.column + match.start()
    return (
        token.line + prefix.count("\n"),
        len(prefix.rsplit("\n", 1)[-1]) + 1,
    )


def parse_swift_integer(literal: str) -> int:
    compact = literal.replace("_", "")
    if compact.startswith(("0b", "0B")):
        return int(compact[2:], 2)
    if compact.startswith(("0o", "0O")):
        return int(compact[2:], 8)
    if compact.startswith(("0x", "0X")):
        return int(compact[2:], 16)
    return int(compact, 10)


def scan_swift_source(path: Path, root: Path) -> None:
    text = read_text(path, "Swift source", root)
    try:
        tokens = classify_swift_tokens(text)
    except AuditFailure as exc:
        fail(f"{display(path, root)}: {exc}")

    for token in tokens:
        for label, pattern in FORBIDDEN_TOKENS:
            match = pattern.search(token.text)
            if match:
                line, column = token_match_location(token, match)
                fail(
                    f"{source_location(path, root, line, column)}: forbidden {label} "
                    f"reference: {match.group(0)}"
                )
        for match in SWIFT_INTEGER_LITERAL_RE.finditer(token.text):
            if parse_swift_integer(match.group("literal")) not in PRIVATE_HAL_VALUES:
                continue
            line, column = token_match_location(token, match)
            fail(
                f"{source_location(path, root, line, column)}: "
                f"forbidden private HAL selector: {match.group('literal')}"
            )

    for index, token in enumerate(tokens):
        if token.kind != "identifier" or token.text != "import":
            continue
        # `@preconcurrency import Sparkle` is still an import of Sparkle.
        # Do not skip it merely because an attribute precedes `import`.
        next_index = index + 1
        if next_index >= len(tokens) or tokens[next_index].kind != "identifier":
            continue
        module = tokens[next_index].text
        if module in FORBIDDEN_IMPORTS:
            fail(
                f"{source_location(path, root, tokens[next_index].line, tokens[next_index].column)}: "
                f"forbidden Store import: {module}"
            )

    outside_comments = token_text(tokens)
    for label, pattern in (
        ("privileged NSXPC connection", PRIVILEGED_XPC_RE),
        ("root-helper registration", ROOT_HELPER_RE),
        ("privileged helper API", FORBIDDEN_PRIVILEGED_API_RE),
    ):
        match = pattern.search(outside_comments)
        if not match:
            continue
        consumed = 0
        for token in tokens:
            if consumed + len(token.text) > match.start():
                fail(
                    f"{source_location(path, root, token.line, token.column)}: "
                    f"forbidden {label}"
                )
            consumed += len(token.text)


def check_frameworks(manifest: dict[str, Any], root: Path) -> None:
    frameworks = manifest["linked_frameworks"]
    require_unique(frameworks, "linked_frameworks")
    forbidden = sorted(set(frameworks) & FORBIDDEN_FRAMEWORKS)
    if forbidden:
        fail("forbidden Store linked framework(s): " + ", ".join(forbidden))
    unknown = sorted(set(frameworks) - ALLOWED_FRAMEWORKS)
    if unknown:
        fail("unreviewed Store linked framework(s): " + ", ".join(unknown))
    # Framework names are matched against imports in scan_swift_source. A
    # public framework in this list is allowed, but an import of Sparkle or a
    # protected module is still rejected by the token scan.


def validate_manifest(
    root: Path, manifest_path: Path, manifest: dict[str, Any]
) -> None:
    if not manifest_path.is_file():
        fail(f"manifest is missing: {display(manifest_path, root)}")
    if manifest_path.is_symlink():
        fail(f"manifest must be a regular file, not a symlink: {display(manifest_path, root)}")
    if manifest["repository_root"] != root.as_posix():
        fail(
            "manifest repository_root does not match the audited repository: "
            f"{manifest['repository_root']} != {root.as_posix()}"
        )
    if root not in manifest_path.resolve().parents:
        fail(f"manifest path escapes repository_root: {manifest_path}")
    head = repository_head(root)
    if manifest["source_sha"] != head:
        fail(
            "manifest source_sha is stale or does not match repository HEAD: "
            f"{manifest['source_sha']} != {head}"
        )
    expected_tree_sha = source_tree_sha256(
        root,
        manifest["included_sources"] + manifest["excluded_sources"],
    )
    if manifest["source_tree_sha256"] != expected_tree_sha:
        fail(
            "manifest source_tree_sha256 does not match current source contents: "
            f"{manifest['source_tree_sha256']} != {expected_tree_sha}"
        )

    direct_only = parse_direct_only_manifest(root)
    if direct_only != sorted(manifest["excluded_sources"]):
        missing = sorted(set(direct_only) - set(manifest["excluded_sources"]))
        extra = sorted(set(manifest["excluded_sources"]) - set(direct_only))
        detail = []
        if missing:
            detail.append("missing: " + ", ".join(missing))
        if extra:
            detail.append("unlisted: " + ", ".join(extra))
        fail(
            "excluded_sources must exactly match "
            f"{DIRECT_ONLY_MANIFEST}; " + "; ".join(detail)
        )
    if not manifest["included_sources"]:
        fail("included_sources must not be empty")
    validate_sources_exist(root, manifest["included_sources"], "included source")
    for excluded in manifest["excluded_sources"]:
        path = root / excluded
        if not path.exists():
            fail(f"excluded source does not exist: {excluded}")
        ensure_within(path, root, "excluded source", root)


def audit(root: Path, manifest_path: Path) -> None:
    try:
        manifest = load_manifest(manifest_path)
    except AuditFailure:
        raise
    validate_manifest(root, manifest_path, manifest)
    check_frameworks(manifest, root)
    compiled, derived = parse_file_lists(root, manifest)
    included = sorted(manifest["included_sources"])
    if compiled != included:
        missing = sorted(set(included) - set(compiled))
        extra = sorted(set(compiled) - set(included))
        detail = []
        if missing:
            detail.append("missing from compiled evidence: " + ", ".join(missing))
        if extra:
            detail.append("unexpected compiled sources: " + ", ".join(extra))
        fail(
            "included_sources and compiled_sources do not match real SwiftFileList "
            "evidence; " + "; ".join(detail)
        )
    if compiled != sorted(set(manifest["compiled_sources"])):
        fail("manifest compiled_sources does not match parsed SwiftFileList evidence")
    if derived != sorted(set(manifest["derived_sources"])):
        fail("manifest derived_sources does not match parsed SwiftFileList evidence")
    overlap = sorted(set(compiled) & set(manifest["excluded_sources"]))
    if overlap:
        fail("excluded source appears in compiled evidence: " + ", ".join(overlap))
    for relative in compiled:
        path = root / relative
        ensure_regular_readable(path, "compiled source", root)
        ensure_within(path, root, "compiled source", root)
        scan_swift_source(path, root)
    for relative in derived:
        path = root / relative
        ensure_regular_readable(path, "derived source", root)
        ensure_within(path, root, "derived source", root)
        if not path.resolve().is_relative_to((root / ".build").resolve()):
            fail(f"{display(path, root)}: derived source is outside .build")
        scan_swift_source(path, root)
    print(f"Source closure audit passed: {len(compiled)} compiled, {len(derived)} derived")


def find_repository_root(script: Path) -> Path:
    return script.resolve().parent.parent


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=None,
        help="Repository root; defaults to this script's parent repository.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = (args.repository_root or find_repository_root(Path(__file__))).resolve()
    manifest_path = args.manifest
    if not manifest_path.is_absolute():
        manifest_path = (Path.cwd() / manifest_path).resolve()
    try:
        audit(root, manifest_path)
    except AuditFailure as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
