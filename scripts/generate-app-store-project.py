#!/usr/bin/env python3
"""Generate the App Store Xcode project and its audited source membership."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


SHARED_SOURCE_ROOT = "Sources/StatusTrioCore"
STORE_PLATFORM_ROOT = "AppStore/Platform"
DIRECT_ONLY_MANIFEST = "AppStore/direct-only-sources.txt"
APP_ENTRYPOINT = "Sources/StatusTrio/main.swift"
SHARED_RESOURCE_ROOT = "Sources/StatusTrioCore/Resources"
APP_ICON_SOURCE = "Support/AppIcon.png"
APP_LOCALIZATION_DIRECTORIES = (
    "ar.lproj",
    "de.lproj",
    "en.lproj",
    "es.lproj",
    "fr.lproj",
    "it.lproj",
    "ja.lproj",
    "ko.lproj",
    "pt-BR.lproj",
    "ru.lproj",
    "zh-Hans.lproj",
    "zh-Hant.lproj",
)
DEFAULT_PROJECT_SPEC = "AppStore/project.json"
DEFAULT_GENERATED_ROOT = ".build/app-store"
DEFAULT_INFO_PLIST = "Support/Info.plist"
STORE_BUNDLE_ID = "com.lingsmbp.StatusTrio.AppStore"
STORE_DISPLAY_NAME = "Status Trio (App Store)"
STORE_EXECUTABLE = "StatusTrio"
STORE_MODULE = "StatusTrioCore"
STORE_APP_CATEGORY = "public.app-category.utilities"
STORE_RESOURCE_ACCESSOR = "AppStore/Platform/StoreResourceBundle.swift"
STORE_VERSION_XCCONFIG = "AppStore/Version.xcconfig"
STORE_ENTITLEMENTS = "Distribution/AppStore.entitlements"
STORE_ENTITLEMENTS_TEMPLATE = "Distribution/AppStore.entitlements"
STORE_PRIVACY_MANIFEST = "AppStore/PrivacyInfo.xcprivacy"
SHARED_RESOURCE_GROUP = "SharedStoreResources"
SWIFT_VERSION = "6.0"
MACOS_DEPLOYMENT_TARGET = "13.0"
XCODEGEN_REQUIRED_VERSION = (2, 46, 0)
XCODEGEN_REQUIRED_VERSION_TEXT = ".".join(
    str(part) for part in XCODEGEN_REQUIRED_VERSION
)
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")
BUILD_RE = re.compile(r"^[0-9]+$")
SWIFT_IMPORT_RE = re.compile(
    r"^\s*(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)\n]*\))?)\s+)*"
    r"(?:public\s+|package\s+|internal\s+|"
    r"private\s+|fileprivate\s+)?import\s+"
    r"(?:(?:typealias|struct|class|enum|protocol|actor|let|var|func)\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*$",
    re.MULTILINE,
)
SWIFT_MODULE_FRAMEWORKS = {
    "AppKit": "AppKit",
    "AudioToolbox": "AudioToolbox",
    "Carbon": "Carbon",
    "Combine": "Combine",
    "CoreAudio": "CoreAudio",
    "CoreBluetooth": "CoreBluetooth",
    "CoreFoundation": "CoreFoundation",
    "CoreGraphics": "CoreGraphics",
    "CoreLocation": "CoreLocation",
    "CoreText": "CoreText",
    "CoreWLAN": "CoreWLAN",
    "CryptoKit": "CryptoKit",
    "Foundation": "Foundation",
    "ImageIO": "ImageIO",
    "IOBluetooth": "IOBluetooth",
    "IOKit": "IOKit",
    "Network": "Network",
    "OSLog": "OSLog",
    "QuartzCore": "QuartzCore",
    "Security": "Security",
    "ServiceManagement": "ServiceManagement",
    "SwiftUI": "SwiftUI",
    "SystemConfiguration": "SystemConfiguration",
}
FORBIDDEN_SWIFT_IMPORTS = {
    "CoreDisplay",
    "DDCPrivateAPI",
    "PowerHelperProtocol",
    "Sparkle",
    "DirectPlatform",
    "StatusTrioDirectPlatform",
}
SWIFT_DEFINES = ["STATUS_TRIO_APP_STORE"]
SOURCE_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SOURCE_TREE_SHA_RE = re.compile(r"^[0-9a-f]{64}$")
FILE_LIST_RELATIVE_PATH_RE = re.compile(
    r"^Build/Intermediates\.noindex/(?:ArchiveIntermediates/[^/]+/IntermediateBuildFilesPath/)?StatusTrioAppStore\.build/(?P<configuration>Debug|Release)/StatusTrioCore\.build/Objects-normal/(?P<architecture>arm64|x86_64)/StatusTrioCore\.SwiftFileList$"
)
# Strong markers identify a Status Trio checkout. Optional source and platform
# markers are checked by build_membership so a missing deployment input still
# reports as that input, rather than as an unrelated "wrong root" error.
REPO_ROOT_MARKERS = (
    "Support/Info.plist",
    "Sources/StatusTrio/main.swift",
    SHARED_SOURCE_ROOT,
)


class GenerationError(RuntimeError):
    """A fail-closed project-generation error."""


def repo_path(root: Path, relative: str) -> Path:
    return root / relative


def validate_repository_root(root: Path) -> None:
    if not root.is_dir():
        raise GenerationError(f"repository root is not a directory: {root}")
    for marker in REPO_ROOT_MARKERS:
        if not (root / marker).exists():
            raise GenerationError(
                f"repository root is missing required marker {marker}: {root}"
            )


def repo_relative(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise GenerationError(f"path escapes repository: {path}") from exc


def project_setting_path(root: Path, project_dir: Path, relative: str) -> str:
    """Return a build-setting path relative to the generated xcodeproj."""

    target = repo_path(root, relative).resolve(strict=False)
    project = project_dir.resolve(strict=False)
    return Path(os.path.relpath(target, project)).as_posix()


def read_manifest(root: Path, manifest_path: Path) -> list[str]:
    if not manifest_path.is_file():
        try:
            relative = manifest_path.relative_to(root).as_posix()
        except ValueError:
            relative = manifest_path.as_posix()
        raise GenerationError(f"missing Direct-only source manifest: {relative}")

    entries: list[str] = []
    seen: set[str] = set()
    for line_number, raw_line in enumerate(manifest_path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if os.path.isabs(line) or any(part == ".." for part in Path(line).parts):
            raise GenerationError(
                f"Direct-only source manifest line {line_number} must be repo-relative and cannot escape: {line}"
            )
        normalized = Path(line).as_posix()
        if not normalized.endswith(".swift"):
            raise GenerationError(
                f"Direct-only source manifest line {line_number} is not a Swift source: {line}"
            )
        if normalized in seen:
            raise GenerationError(
                f"Direct-only source manifest line {line_number} duplicates an earlier entry: {line}"
            )
        seen.add(normalized)
        entries.append(normalized)
    return entries


def swift_sources_under(root: Path, relative_root: str) -> list[Path]:
    directory = repo_path(root, relative_root)
    if not directory.is_dir():
        raise GenerationError(f"missing source directory: {relative_root}")
    return sorted(
        (path for path in directory.rglob("*.swift") if path.is_file()),
        key=lambda path: repo_relative(root, path),
    )


def read_version_source(root: Path, info_plist: Path) -> tuple[str, str]:
    try:
        with info_plist.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise GenerationError(f"cannot read version source {repo_relative(root, info_plist)}: {exc}") from exc

    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
        raise GenerationError(
            f"{repo_relative(root, info_plist)} has invalid CFBundleShortVersionString: {version!r}"
        )
    if not isinstance(build, str) or not BUILD_RE.fullmatch(build):
        raise GenerationError(f"{repo_relative(root, info_plist)} has invalid CFBundleVersion: {build!r}")
    return version, build


def validate_override(value: str, label: str, pattern: re.Pattern[str]) -> str:
    if not pattern.fullmatch(value):
        raise GenerationError(f"{label} is invalid: {value!r}")
    return value


def app_info_plist_resources(root: Path) -> list[str]:
    """Return the existing localized InfoPlist.strings files for the app."""

    expected = [
        f"{SHARED_RESOURCE_ROOT}/{directory}/InfoPlist.strings"
        for directory in APP_LOCALIZATION_DIRECTORIES
    ]
    missing = [path for path in expected if not repo_path(root, path).is_file()]
    if missing:
        raise GenerationError(
            "missing localized app InfoPlist.strings files:\n  "
            + "\n  ".join(missing)
        )
    discovered = sorted(
        repo_relative(root, path)
        for path in repo_path(root, SHARED_RESOURCE_ROOT).glob("*.lproj/InfoPlist.strings")
        if path.is_file()
    )
    unexpected = sorted(set(discovered) - set(expected))
    if unexpected:
        raise GenerationError(
            "unexpected localized app InfoPlist.strings files:\n  "
            + "\n  ".join(unexpected)
        )
    return expected


def validate_app_resource_inputs(root: Path) -> list[str]:
    if not repo_path(root, APP_ICON_SOURCE).is_file():
        raise GenerationError(f"missing Store app icon source: {APP_ICON_SOURCE}")
    validate_privacy_manifest(root, repo_path(root, STORE_PRIVACY_MANIFEST))
    return app_info_plist_resources(root)


def shared_resource_files(root: Path) -> list[str]:
    """Enumerate the existing shared resources without copying or renaming."""

    directory = repo_path(root, SHARED_RESOURCE_ROOT)
    if not directory.is_dir():
        raise GenerationError(f"missing shared resource directory: {SHARED_RESOURCE_ROOT}")
    resources = []
    for path in directory.rglob("*"):
        if not path.is_file() or path.name == ".DS_Store":
            continue
        resources.append(repo_relative(root, path))
    resources.sort()
    required = app_info_plist_resources(root)
    missing = sorted(set(required) - set(resources))
    if missing:
        raise GenerationError(
            "shared resource enumeration omitted app InfoPlist.strings files:\n  "
            + "\n  ".join(missing)
        )
    if not resources:
        raise GenerationError(f"no resources found under {SHARED_RESOURCE_ROOT}")
    return resources


def path_label(root: Path, path: Path) -> str:
    try:
        return repo_relative(root, path)
    except GenerationError:
        return path.as_posix()


def validate_privacy_manifest(root: Path, manifest: Path) -> None:
    """Require the Store privacy manifest without owning its reason entries."""

    if not manifest.is_file():
        raise GenerationError(
            f"missing Store privacy manifest: {path_label(root, manifest)}"
        )
    try:
        with manifest.open("rb") as handle:
            payload = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise GenerationError(
            f"cannot read Store privacy manifest {path_label(root, manifest)}: {exc}"
        ) from exc
    if not isinstance(payload, dict):
        raise GenerationError(
            f"Store privacy manifest must be a dictionary: {path_label(root, manifest)}"
        )
    if payload.get("NSPrivacyTracking") is not False:
        raise GenerationError(
            "Store privacy manifest must set NSPrivacyTracking=false: "
            f"{path_label(root, manifest)}"
        )
    collected = payload.get("NSPrivacyCollectedDataTypes")
    if not isinstance(collected, list):
        raise GenerationError(
            "Store privacy manifest must declare NSPrivacyCollectedDataTypes as an "
            f"array: {path_label(root, manifest)}"
        )
    if collected:
        raise GenerationError(
            "Store privacy manifest must not collect data: "
            f"{path_label(root, manifest)}"
        )
    tracking_domains = payload.get("NSPrivacyTrackingDomains")
    if tracking_domains is not None:
        if not isinstance(tracking_domains, list):
            raise GenerationError(
                "Store privacy manifest NSPrivacyTrackingDomains must be an array: "
                f"{path_label(root, manifest)}"
            )
        if tracking_domains:
            raise GenerationError(
                "Store privacy manifest must not declare tracking domains: "
                f"{path_label(root, manifest)}"
            )


def prepare_store_icon(root: Path) -> str:
    """Build the generated ICNS from the existing Direct artwork.

    XcodeGen resources must exist while generating the project, so generation
    owns the icon build. The build script rebuilds it before signing as an
    independent bundle check.
    """

    source = repo_path(root, APP_ICON_SOURCE)
    validate_app_resource_inputs(root)
    output = repo_path(root, store_icon_path(root))
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_root = Path(
        subprocess.check_output(
            ["mktemp", "-d", f"{os.environ.get('TMPDIR', '/tmp')}/StatusTrioAppStoreIcon.XXXXXX"],
            text=True,
        ).strip()
    )
    try:
        base_png = temporary_root / "AppIcon.png"
        iconset = temporary_root / "AppIcon.iconset"
        iconset.mkdir()
        result = subprocess.run(
            ["sips", "-s", "format", "png", "-z", "1024", "1024", str(source), "--out", str(base_png)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        if result.returncode != 0:
            raise GenerationError(
                "sips rejected the Store icon source: "
                + result.stderr.decode("utf-8", errors="replace").strip()
            )
        sizes = (
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png"),
        )
        for pixels, filename in sizes:
            result = subprocess.run(
                ["sips", "-z", str(pixels), str(pixels), str(base_png), "--out", str(iconset / filename)],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            if result.returncode != 0:
                raise GenerationError(
                    f"sips could not create {filename}: "
                    + result.stderr.decode("utf-8", errors="replace").strip()
                )
        temporary_icns = temporary_root / "StatusTrioAppStore.icns"
        result = subprocess.run(
            ["iconutil", "--convert", "icns", "--output", str(temporary_icns), str(iconset)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        if result.returncode != 0:
            raise GenerationError(
                "iconutil rejected the generated iconset: "
                + result.stderr.decode("utf-8", errors="replace").strip()
            )
        if not temporary_icns.is_file() or temporary_icns.stat().st_size == 0:
            raise GenerationError("generated Store app icon is empty")
        output_tmp = output.with_name(output.name + ".tmp")
        temporary_icns.replace(output_tmp)
        output_tmp.replace(output)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise GenerationError(f"cannot generate Store app icon: {exc}") from exc
    finally:
        subprocess.run(["/bin/rm", "-rf", str(temporary_root)], check=False)
    return repo_relative(root, output)


def read_direct_exclusions(root: Path, entries: list[str]) -> list[str]:
    shared_paths = {
        repo_relative(root, path)
        for path in swift_sources_under(root, SHARED_SOURCE_ROOT)
    }
    for entry in entries:
        if entry not in shared_paths:
            raise GenerationError(
                f"Direct-only source manifest lists a file outside {SHARED_SOURCE_ROOT} or does not exist: {entry}"
            )

    platform_root = repo_path(root, STORE_PLATFORM_ROOT)
    if not platform_root.is_dir():
        raise GenerationError(f"missing Store platform source directory: {STORE_PLATFORM_ROOT}")
    for path in sorted(platform_root.rglob("*.swift")):
        if path.is_file() and repo_relative(root, path) in set(entries):
            raise GenerationError(
                f"Direct-only source manifest must not list Store platform source: {repo_relative(root, path)}"
            )
    return sorted(entries)


def validate_manifest_covers_direct_imports(root: Path, entries: list[str]) -> None:
    """Require every shared source importing a Direct module to be excluded."""

    excluded = set(entries)
    offenders: list[str] = []
    for path in swift_sources_under(root, SHARED_SOURCE_ROOT):
        relative = repo_relative(root, path)
        imports = swift_imports([path])
        forbidden = imports & FORBIDDEN_SWIFT_IMPORTS
        if forbidden and relative not in excluded:
            offenders.append(f"{relative} imports {', '.join(sorted(forbidden))}")
    if offenders:
        raise GenerationError(
            "Direct-only source manifest omits shared sources with Direct imports:\n  "
            + "\n  ".join(offenders)
        )


def validate_platform_sources(root: Path, platform: list[str]) -> None:
    offenders: list[str] = []
    for relative in platform:
        imports = swift_imports([repo_path(root, relative)])
        forbidden = imports & FORBIDDEN_SWIFT_IMPORTS
        if forbidden:
            offenders.append(f"{relative} imports {', '.join(sorted(forbidden))}")
    if offenders:
        raise GenerationError(
            "Store platform sources must not import Direct-only modules:\n  "
            + "\n  ".join(offenders)
        )


def build_membership(root: Path) -> tuple[list[str], list[str], list[str], list[str]]:
    entries = read_manifest(root, repo_path(root, DIRECT_ONLY_MANIFEST))
    excluded = read_direct_exclusions(root, entries)
    excluded_set = set(excluded)
    shared_sources = swift_sources_under(root, SHARED_SOURCE_ROOT)
    included = [
        repo_relative(root, path)
        for path in shared_sources
        if repo_relative(root, path) not in excluded_set
    ]

    platform_sources = swift_sources_under(root, STORE_PLATFORM_ROOT)
    platform = [repo_relative(root, path) for path in platform_sources]
    if not platform:
        raise GenerationError(f"missing Swift sources under {STORE_PLATFORM_ROOT}")
    if STORE_RESOURCE_ACCESSOR not in platform:
        raise GenerationError(
            f"missing Store resource accessor: {STORE_RESOURCE_ACCESSOR}"
        )
    validate_manifest_covers_direct_imports(root, entries)
    validate_platform_sources(root, platform)
    if path_is_under(root, STORE_PLATFORM_ROOT, APP_ENTRYPOINT):
        raise GenerationError(
            f"Store app entrypoint must not live under {STORE_PLATFORM_ROOT}: {APP_ENTRYPOINT}"
        )
    return included, excluded, platform, entries


def path_is_under(root: Path, relative_root: str, relative_path: str) -> bool:
    return repo_relative(root, repo_path(root, relative_path)).startswith(
        relative_root.rstrip("/") + "/"
    )


def swift_imports(paths: list[Path]) -> set[str]:
    modules: set[str] = set()
    for path in paths:
        text = path.read_text(encoding="utf-8")
        modules.update(SWIFT_IMPORT_RE.findall(text))
    return modules


def linked_frameworks_for(paths: list[Path]) -> list[str]:
    modules = swift_imports(paths)
    forbidden = sorted(modules & FORBIDDEN_SWIFT_IMPORTS)
    if forbidden:
        raise GenerationError(
            "Store source closure imports Direct-only modules: "
            + ", ".join(forbidden)
        )
    unknown = sorted(modules - set(SWIFT_MODULE_FRAMEWORKS))
    # Swift standard-library and runtime-only modules do not need a framework
    # link edge. Never silently discard a third-party or private module.
    harmless_standard_modules = {
        "Darwin",
        "Dispatch",
        "Combine",
        "Foundation",
        "Observation",
        "OSLog",
        "notify",
        "os",
    }
    unsupported = sorted(set(unknown) - harmless_standard_modules)
    if unsupported:
        raise GenerationError(
            "unclassified Store Swift imports: " + ", ".join(unsupported)
        )
    return sorted(
        {
            SWIFT_MODULE_FRAMEWORKS[module]
            for module in modules
            if module in SWIFT_MODULE_FRAMEWORKS
        }
    )


def source_tree_sha256(root: Path, entries: list[str]) -> str:
    digest = hashlib.sha256()
    for relative in sorted(set(entries)):
        path = repo_path(root, relative)
        try:
            data = path.read_bytes()
        except OSError as exc:
            raise GenerationError(f"cannot hash source tree entry {relative}: {exc}") from exc
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(len(data)).encode("ascii"))
        digest.update(b"\0")
        digest.update(data)
        digest.update(b"\0")
    return digest.hexdigest()


def source_sha(root: Path) -> str:
    override = os.environ.get("STATUS_TRIO_SOURCE_SHA", "")
    if override:
        if not SOURCE_SHA_RE.fullmatch(override):
            raise GenerationError(
                "STATUS_TRIO_SOURCE_SHA must be a lowercase 40-character Git SHA."
            )
        return override
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise GenerationError(f"cannot resolve repository source SHA: {exc}") from exc


def check_no_forbidden_configuration(root: Path) -> None:
    forbidden_markers = ("Sparkle", "DDCPrivateAPI", "PowerHelperProtocol", "CoreDisplay")
    candidates = [
        repo_path(root, STORE_VERSION_XCCONFIG),
        repo_path(root, "AppStore/project.json"),
        repo_path(root, "AppStore/Info.plist"),
        repo_path(root, STORE_ENTITLEMENTS),
    ]
    for candidate in candidates:
        if not candidate.exists():
            continue
        text = candidate.read_text(encoding="utf-8")
        for marker in forbidden_markers:
            if marker in text:
                raise GenerationError(
                    f"{repo_relative(root, candidate)} must not reference {marker}"
                )


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def write_json(path: Path, payload: Any) -> None:
    write_text(path, json.dumps(payload, indent=2, sort_keys=True) + "\n")


def xcconfig_text(version: str, build: str) -> str:
    return (
        "// Generated by scripts/generate-app-store-project.py. Do not edit.\n"
        "// Source: Support/Info.plist\n"
        f"MARKETING_VERSION = {version}\n"
        f"CURRENT_PROJECT_VERSION = {build}\n"
        f"ST_MARKETING_VERSION = {version}\n"
        f"ST_BUILD_NUMBER = {build}\n"
    )


def info_plist_payload(version: str, build: str) -> dict[str, Any]:
    candidate_descriptions = {
        "NSLocationUsageDescription": (
            "Shows the current Wi-Fi network name and network details when "
            "you open them in Status Trio."
        ),
        "NSLocationWhenInUseUsageDescription": (
            "Shows the current Wi-Fi network name and network details when "
            "you open them in Status Trio."
        ),
        "NSBluetoothAlwaysUsageDescription": (
            "Shows Bluetooth connection status and reads battery/model "
            "metadata for devices you explicitly authorize."
        ),
    }
    return {
        "CFBundleDisplayName": STORE_DISPLAY_NAME,
        "CFBundleExecutable": STORE_EXECUTABLE,
        "CFBundleIconFile": "StatusTrioAppStore",
        "CFBundleIdentifier": STORE_BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": STORE_DISPLAY_NAME,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "CFBundleDevelopmentRegion": "en",
        "LSMinimumSystemVersion": MACOS_DEPLOYMENT_TARGET,
        "LSApplicationCategoryType": STORE_APP_CATEGORY,
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "STIncludesPrivilegedHelper": False,
        "STTelemetryProduction": False,
        **candidate_descriptions,
    }


def store_icon_path(root: Path) -> str:
    return ".build/app-store/generated/StatusTrioAppStore.icns"


def entitlements_payload(
    fallback_when_missing: bool = True,
    root: Path | None = None,
) -> dict[str, Any]:
    template_root = root or Path(__file__).resolve().parent.parent
    template = repo_path(template_root, STORE_ENTITLEMENTS_TEMPLATE)
    if template.is_file():
        try:
            with template.open("rb") as handle:
                payload = plistlib.load(handle)
        except (OSError, plistlib.InvalidFileException) as exc:
            raise GenerationError(f"cannot read Store entitlements template {STORE_ENTITLEMENTS_TEMPLATE}: {exc}") from exc
        if not isinstance(payload, dict):
            raise GenerationError(f"Store entitlements template is not a dictionary: {STORE_ENTITLEMENTS_TEMPLATE}")
        if payload.get("com.apple.security.app-sandbox") is not True:
            raise GenerationError(
                f"Store entitlements template must set com.apple.security.app-sandbox=true: {STORE_ENTITLEMENTS_TEMPLATE}"
            )
        if payload.get("com.apple.security.device.bluetooth") is not True:
            raise GenerationError(
                f"Store entitlements template must set com.apple.security.device.bluetooth=true: {STORE_ENTITLEMENTS_TEMPLATE}"
            )
        if payload.get("com.apple.security.personal-information.location") is not True:
            raise GenerationError(
                "Store entitlements template must set "
                "com.apple.security.personal-information.location=true: "
                f"{STORE_ENTITLEMENTS_TEMPLATE}"
            )
        return payload
    if not fallback_when_missing:
        raise GenerationError(
            f"missing Store entitlements template: {STORE_ENTITLEMENTS_TEMPLATE}"
        )
    return {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
        # These are the minimum public capabilities used by the Store
        # Bluetooth/IOBluetooth and CoreLocation provider paths.
        "com.apple.security.device.bluetooth": True,
        "com.apple.security.personal-information.location": True,
    }


def project_spec(
    root: Path,
    version: str,
    build: str,
    included: list[str],
    platform: list[str],
    linked_frameworks: list[str],
    xcode_project_dir: Path,
) -> dict[str, Any]:
    for path in included + platform:
        if not repo_path(root, path).is_file():
            raise GenerationError(f"source does not exist: {path}")

    # Keep this explicit. XcodeGen's target source membership is the boundary
    # that prevents Direct implementation files from entering Store Core.
    store_core_sources = included + platform
    app_localizations = validate_app_resource_inputs(root)
    core_resources = shared_resource_files(root)
    privacy_manifest = STORE_PRIVACY_MANIFEST
    store_icon = store_icon_path(root)
    swift_defines = " ".join(SWIFT_DEFINES)
    entitlements_setting = project_setting_path(
        root, xcode_project_dir, STORE_ENTITLEMENTS
    )
    info_plist_setting = project_setting_path(
        root, xcode_project_dir, "AppStore/Info.plist"
    )
    return {
        "name": "StatusTrioAppStore",
        "configFiles": {
            "Debug": STORE_VERSION_XCCONFIG,
            "Release": STORE_VERSION_XCCONFIG,
        },
        "options": {
            "bundleIdPrefix": "com.lingsmbp.StatusTrio",
            "deploymentTarget": {"macOS": MACOS_DEPLOYMENT_TARGET},
            "developmentLanguage": "en",
            "minimumXcodeGenVersion": XCODEGEN_REQUIRED_VERSION_TEXT,
            "xcodeVersion": "27.0",
        },
        "configs": {
            "Debug": {
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": f"DEBUG {swift_defines}",
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            },
            "Release": {
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": swift_defines,
                "SWIFT_OPTIMIZATION_LEVEL": "-O",
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                "COPY_PHASE_STRIP": False,
            },
        },
        "settings": {
            "base": {
                "CODE_SIGNING_ALLOWED": False,
                "CODE_SIGNING_REQUIRED": False,
                "DEVELOPMENT_TEAM": "",
                "GCC_C_LANGUAGE_STANDARD": "gnu17",
                "MACOSX_DEPLOYMENT_TARGET": MACOS_DEPLOYMENT_TARGET,
                "SDKROOT": "macosx",
                "SWIFT_STRICT_CONCURRENCY": "complete",
                "SWIFT_VERSION": SWIFT_VERSION,
            }
        },
        "targets": {
            "StatusTrioCore": {
                "type": "framework",
                "platform": "macOS",
                "deploymentTarget": MACOS_DEPLOYMENT_TARGET,
                "productName": STORE_MODULE,
                "productType": "com.apple.product-type.framework",
                "sources": [
                    {"path": path, "group": "StatusTrioCore"}
                    for path in store_core_sources
                ]
                + [
                    {
                        "path": path,
                        "group": SHARED_RESOURCE_GROUP,
                        "buildPhase": "resources",
                    }
                    for path in core_resources
                ],
                "settings": {
                    "base": {
                        "CLANG_ENABLE_MODULES": True,
                        "DEFINES_MODULE": True,
                        "GENERATE_INFOPLIST_FILE": True,
                        "DYLIB_INSTALL_NAME_BASE": "@rpath",
                        "LD_DYLIB_INSTALL_NAME": "@rpath/StatusTrioCore.framework/Versions/A/StatusTrioCore",
                        "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
                        "MACH_O_TYPE": "mh_dylib",
                        "MODULEMAP_FILE": "",
                        "PRODUCT_BUNDLE_IDENTIFIER": f"{STORE_BUNDLE_ID}.Core",
                        "PRODUCT_MODULE_NAME": STORE_MODULE,
                        "PRODUCT_NAME": "$(TARGET_NAME)",
                        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks @loader_path/Frameworks",
                        "SKIP_INSTALL": True,
                        "SUPPORTED_PLATFORMS": "macosx",
                        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": f"$(inherited) {swift_defines}",
                        "SWIFT_EMIT_LOC_STRINGS": False,
                    }
                },
                "dependencies": [
                    {"sdk": f"{framework}.framework"}
                    for framework in linked_frameworks
                ],
                "preBuildScripts": [
                    {
                        "name": "Verify Store Source Membership",
                        "script": (
                            "set -euo pipefail\n"
                            "repo_root=\"$SRCROOT\"\n"
                            "while [ \"$repo_root\" != \"/\" ] && "
                            "[ ! -f \"$repo_root/scripts/generate-app-store-project.py\" ]; do\n"
                            "  repo_root=\"$(dirname \"$repo_root\")\"\n"
                            "done\n"
                            "if [ ! -f \"$repo_root/scripts/generate-app-store-project.py\" ]; then\n"
                            "  echo \"Store source-membership script not found above $SRCROOT\" >&2\n"
                            "  exit 1\n"
                            "fi\n"
                            "python3 \"$repo_root/scripts/generate-app-store-project.py\" "
                            "--check-membership-only --repo-root \"$repo_root\"\n"
                        ),
                        "basedOnDependencyAnalysis": False,
                    }
                ],
            },
            "StatusTrio": {
                "type": "application",
                "platform": "macOS",
                "deploymentTarget": MACOS_DEPLOYMENT_TARGET,
                "productName": STORE_EXECUTABLE,
                "sources": [
                    {"path": APP_ENTRYPOINT, "group": "AppEntrypoint"},
                ]
                + [
                    {
                        "path": path,
                        "group": SHARED_RESOURCE_GROUP,
                        "buildPhase": "resources",
                    }
                    for path in app_localizations
                ]
                + [
                    {
                        "path": privacy_manifest,
                        "group": "Privacy",
                        "buildPhase": "resources",
                    }
                ]
                + [
                    {
                        "path": store_icon,
                        "group": "AppIcon",
                        "buildPhase": "resources",
                    }
                ],
                "dependencies": [
                    {
                        "target": "StatusTrioCore",
                        "embed": True,
                        "codeSign": True,
                    }
                ],
                "settings": {
                    "base": {
                        "ASSETCATALOG_COMPILER_APPICON_NAME": "",
                        "CODE_SIGN_ENTITLEMENTS": entitlements_setting,
                        "GENERATE_INFOPLIST_FILE": False,
                        "INFOPLIST_FILE": info_plist_setting,
                        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
                        "PRODUCT_BUNDLE_IDENTIFIER": STORE_BUNDLE_ID,
                        "PRODUCT_NAME": STORE_EXECUTABLE,
                        "SKIP_INSTALL": False,
                        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) STATUS_TRIO_APP_STORE",
                        "SWIFT_EMIT_LOC_STRINGS": False,
                    }
                },
            },
        },
        "schemes": {
            "StatusTrio (App Store)": {
                "build": {
                    "targets": {
                        "StatusTrio": "all",
                        "StatusTrioCore": "all",
                    }
                },
                "run": {
                    "config": "Debug",
                    "commandLineArguments": {},
                    "environmentVariables": {},
                },
                "archive": {"config": "Release"},
            }
        },
    }


def resolve_xcode_object_path(
    object_id: str,
    objects: dict[str, Any],
    parents: dict[str, list[str]],
    project_dir: Path,
    main_group_id: str,
    cache: dict[str, Path],
    visiting: set[str] | None = None,
) -> Path:
    if object_id in cache:
        return cache[object_id]
    if object_id not in objects:
        raise GenerationError(f"Xcode project references unknown object: {object_id}")
    visiting = set() if visiting is None else visiting
    if object_id in visiting:
        raise GenerationError(f"cycle in Xcode group path for object: {object_id}")
    visiting.add(object_id)

    obj = objects[object_id]
    source_tree = obj.get("sourceTree", "<group>")
    if object_id == main_group_id:
        parent_path = project_dir
    else:
        candidates = parents.get(object_id, [])
        if len(candidates) != 1:
            label = obj.get("name") or obj.get("path") or object_id
            groups = ", ".join(
                (objects[parent_id].get("name") or objects[parent_id].get("path") or parent_id)
                for parent_id in candidates
            )
            raise GenerationError(
                "Xcode project object is a member of multiple or no PBXGroups "
                f"({label}): {groups or '<none>'}"
            )
        parent_path = resolve_xcode_object_path(
            candidates[0],
            objects,
            parents,
            project_dir,
            main_group_id,
            cache,
            visiting,
        )

    if source_tree != "<group>":
        label = obj.get("name") or obj.get("path") or object_id
        raise GenerationError(
            f"resource object uses unsupported sourceTree {source_tree!r}: {label}"
        )
    relative = obj.get("path")
    if relative is not None:
        if not isinstance(relative, str):
            raise GenerationError(f"Xcode project object has non-string path: {object_id}")
        resolved = (parent_path / relative).resolve(strict=False)
    else:
        resolved = parent_path.resolve(strict=False)
    visiting.remove(object_id)
    cache[object_id] = resolved
    return resolved


def validate_generated_xcode_project(root: Path, project: Path) -> None:
    """Resolve real PBX resource paths and reject malformed group membership."""

    xcode_project = project
    if xcode_project.suffix != ".xcodeproj":
        xcode_project = xcode_project / "StatusTrioAppStore.xcodeproj"
    pbxproj = xcode_project / "project.pbxproj"
    if not pbxproj.is_file():
        raise GenerationError(f"missing generated Xcode project: {xcode_project}")
    try:
        converted = subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(pbxproj)],
            text=True,
            stderr=subprocess.PIPE,
        )
        payload = json.loads(converted)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        raise GenerationError(f"cannot parse generated Xcode project {pbxproj}: {exc}") from exc
    objects = payload.get("objects")
    if not isinstance(objects, dict):
        raise GenerationError("generated Xcode project has no object dictionary")
    project_objects = [
        obj for obj in objects.values() if obj.get("isa") == "PBXProject"
    ]
    if len(project_objects) != 1:
        raise GenerationError("generated Xcode project must contain exactly one PBXProject")
    main_group_id = project_objects[0].get("mainGroup")
    if not isinstance(main_group_id, str):
        raise GenerationError("generated Xcode project has no main PBXGroup")

    parents: dict[str, list[str]] = {}
    for object_id, obj in objects.items():
        if obj.get("isa") not in {"PBXGroup", "PBXVariantGroup"}:
            continue
        for child_id in obj.get("children", []):
            if not isinstance(child_id, str):
                raise GenerationError(
                    f"Xcode group {object_id} contains a non-string child ID"
                )
            parents.setdefault(child_id, []).append(object_id)

    duplicates = {
        object_id: parent_ids
        for object_id, parent_ids in parents.items()
        if len(parent_ids) > 1
    }
    if duplicates:
        details = []
        for object_id, parent_ids in sorted(duplicates.items()):
            obj = objects.get(object_id, {})
            label = obj.get("name") or obj.get("path") or object_id
            details.append(f"{label} ({', '.join(parent_ids)})")
        raise GenerationError(
            "malformed Xcode project: objects belong to multiple PBXGroups: "
            + "; ".join(details)
        )

    project_dir = xcode_project.parent.resolve()
    cache: dict[str, Path] = {}
    resource_paths: list[Path] = []
    for phase_id, phase in objects.items():
        if phase.get("isa") != "PBXResourcesBuildPhase":
            continue
        for build_file_id in phase.get("files", []):
            build_file = objects.get(build_file_id)
            if not isinstance(build_file, dict):
                raise GenerationError(
                    f"resources phase contains unknown build file: {build_file_id}"
                )
            file_ref_id = build_file.get("fileRef")
            if not isinstance(file_ref_id, str):
                raise GenerationError(
                    f"resource build file has no fileRef: {build_file_id}"
                )
            file_ref = objects.get(file_ref_id)
            if not isinstance(file_ref, dict):
                raise GenerationError(
                    f"resource build file references unknown object: {file_ref_id}"
                )
            if file_ref.get("isa") != "PBXFileReference":
                raise GenerationError(
                    "Store resource must use an explicit PBXFileReference, found "
                    f"{file_ref.get('isa')}: {file_ref_id}"
                )
            resolved = resolve_xcode_object_path(
                file_ref_id,
                objects,
                parents,
                project_dir,
                main_group_id,
                cache,
            )
            if not resolved.exists():
                raise GenerationError(
                    f"generated Xcode resource path does not exist: {resolved}"
                )
            try:
                repo_relative(root, resolved)
            except GenerationError as exc:
                raise GenerationError(
                    f"generated Xcode resource escapes repository: {resolved}"
                ) from exc
            resource_paths.append(resolved)
    for object_id, obj in objects.items():
        if obj.get("isa") != "XCBuildConfiguration":
            continue
        settings = obj.get("buildSettings", {})
        if not isinstance(settings, dict):
            raise GenerationError(
                f"Xcode build configuration has invalid settings: {object_id}"
            )
        for key in ("CODE_SIGN_ENTITLEMENTS", "INFOPLIST_FILE"):
            value = settings.get(key)
            if value is None:
                continue
            if not isinstance(value, str) or not value:
                raise GenerationError(
                    f"Xcode build setting {key} is not a nonempty string: {object_id}"
                )
            expanded = value.replace("$(SRCROOT)", str(project_dir)).replace(
                "$(PROJECT_DIR)", str(project_dir)
            )
            candidate = Path(expanded)
            resolved = (
                candidate.resolve(strict=False)
                if candidate.is_absolute()
                else (project_dir / candidate).resolve(strict=False)
            )
            if not resolved.exists():
                raise GenerationError(
                    f"generated Xcode {key} path does not exist: {resolved}"
                )
            try:
                repo_relative(root, resolved)
            except GenerationError as exc:
                raise GenerationError(
                    f"generated Xcode {key} escapes repository: {resolved}"
                ) from exc
    if not resource_paths:
        raise GenerationError("generated Xcode project contains no resource inputs")
    shared_paths = sorted(
        {
            str(path)
            for path in resource_paths
            if resource_paths.count(path) > 1
        }
    )
    # The same localized file is intentionally in both the app and Core
    # resource phases, so duplicate phase membership is valid. The malformed
    # case rejected above is one object hanging from multiple PBXGroups.
    print(
        "Generated Xcode resource paths validated: "
        f"{len(resource_paths)} build entries ({len(set(resource_paths))} files; "
        f"{len(shared_paths)} shared across phases)"
    )


def check_xcodegen_version(executable: str) -> None:
    try:
        output = subprocess.check_output([executable, "--version"], text=True, stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise GenerationError(f"xcodegen is unavailable: {exc}") from exc
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", output)
    if not match:
        raise GenerationError(f"cannot parse xcodegen version: {output.strip()}")
    actual = tuple(int(part) for part in match.groups())
    if actual != XCODEGEN_REQUIRED_VERSION:
        found = ".".join(str(part) for part in actual)
        raise GenerationError(
            f"xcodegen {XCODEGEN_REQUIRED_VERSION_TEXT} is required exactly; "
            f"found {found}"
        )


def write_generated_inputs(
    root: Path,
    version: str,
    build: str,
) -> None:
    write_text(repo_path(root, STORE_VERSION_XCCONFIG), xcconfig_text(version, build))
    plist_bytes = plistlib.dumps(info_plist_payload(version, build), fmt=plistlib.FMT_XML, sort_keys=True)
    write_text(repo_path(root, "AppStore/Info.plist"), plist_bytes.decode("utf-8"))
    if repo_path(root, STORE_ENTITLEMENTS_TEMPLATE).is_file():
        entitlements_payload(fallback_when_missing=False, root=root)
    else:
        entitlements_bytes = plistlib.dumps(
            entitlements_payload(fallback_when_missing=True, root=root),
            fmt=plistlib.FMT_XML,
            sort_keys=True,
        )
        write_text(repo_path(root, STORE_ENTITLEMENTS), entitlements_bytes.decode("utf-8"))


def write_membership_audit(
    output_root: Path,
    root: Path,
    included: list[str],
    excluded: list[str],
    platform: list[str],
    linked_frameworks: list[str],
    sha: str,
    tree_sha256: str,
) -> None:
    audit = {
        "schema_version": 2,
        "channel": "appStore",
        "repository_root": str(root),
        "included_sources": sorted(set(included + platform)),
        "excluded_sources": excluded,
        "source_sha": sha,
        "source_tree_sha256": tree_sha256,
        "linked_frameworks": linked_frameworks,
        "swift_defines": SWIFT_DEFINES,
        "compiled_sources": None,
        "derived_sources": [],
        "swift_file_lists": [],
    }
    write_json(output_root / "source-membership.json", audit)


def load_audit(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as handle:
            audit = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise GenerationError(f"cannot read source membership audit {path}: {exc}") from exc
    if not isinstance(audit, dict):
        raise GenerationError(f"source membership audit is not an object: {path}")
    return audit


def parse_swift_file_list(path: Path) -> list[str]:
    entries: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise GenerationError(f"cannot read SwiftFileList {path}: {exc}") from exc
    for line_number, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if not stripped:
            continue
        if "\0" in line:
            raise GenerationError(f"{path}:{line_number}: NUL byte in SwiftFileList")
        entries.append(line)
    return entries


def normalize_file_list_entry(
    root: Path,
    derived_data: Path,
    swift_file_list: Path,
    entry: str,
) -> tuple[str | None, str | None]:
    # Xcode normally writes absolute paths, but relative paths are resolved
    # against the list's directory. Unsupported output is an error, not a skip.
    candidate = Path(entry)
    if not candidate.is_absolute():
        candidate = swift_file_list.parent / candidate
    resolved = candidate.resolve()
    if resolved.suffix != ".swift":
        raise GenerationError(f"non-Swift entry in {swift_file_list}: {entry}")
    # A generated file below DerivedData is derived even when DerivedData also
    # happens to live inside the repository.
    try:
        derived_relative = resolved.relative_to(derived_data.resolve())
    except ValueError:
        derived_relative = None
    if derived_relative is not None:
        return None, derived_relative.as_posix()
    try:
        relative = resolved.relative_to(root.resolve())
    except ValueError:
        relative = None
    if relative is not None:
        return relative.as_posix(), None
    try:
        derived_relative = resolved.relative_to(derived_data.resolve())
    except ValueError as exc:
        raise GenerationError(
            f"SwiftFileList source is outside repository and DerivedData: {entry}"
        ) from exc
    return None, derived_relative.as_posix()


def store_file_list_parts(
    path: Path,
    derived_data: Path,
) -> tuple[str, str, str, bool]:
    try:
        relative = path.resolve(strict=False).relative_to(derived_data.resolve(strict=False)).as_posix()
    except ValueError as exc:
        raise GenerationError(f"SwiftFileList is outside DerivedData: {path}") from exc
    match = FILE_LIST_RELATIVE_PATH_RE.fullmatch(relative)
    if match is None:
        raise GenerationError(f"unexpected StoreCore SwiftFileList layout: {relative}")
    is_archive = relative.startswith("Build/Intermediates.noindex/ArchiveIntermediates/")
    return (
        match.group("configuration"),
        match.group("architecture"),
        relative,
        is_archive,
    )


def find_swift_file_lists(
    derived_data: Path,
    configuration: str,
    build_action: str,
) -> list[Path]:
    if not derived_data.is_dir():
        raise GenerationError(f"missing derived data directory: {derived_data}")
    candidates = sorted(
        (
            path
            for path in derived_data.rglob("StatusTrioCore.SwiftFileList")
            if path.is_file()
            and any(
                part.startswith("StatusTrioCore") and part.endswith(".build")
                for part in path.parts
            )
        ),
        key=lambda path: path.as_posix(),
    )
    if not candidates:
        raise GenerationError(
            "no StoreCore StatusTrioCore.SwiftFileList found under "
            f"{derived_data}; Xcode output shape changed or target did not compile"
        )
    selected: dict[str, Path] = {}
    for candidate in candidates:
        candidate_configuration, architecture, _, is_archive = (
            store_file_list_parts(candidate, derived_data)
        )
        # A reused DerivedData can retain evidence from the other build action
        # or configuration. Only the current invocation's exact pairs count.
        if candidate_configuration != configuration:
            continue
        if build_action == "build" and is_archive:
            continue
        if build_action == "archive" and not is_archive:
            continue
        if architecture in selected:
            raise GenerationError(
                "duplicate StoreCore SwiftFileList for current "
                f"{build_action}/{configuration}/{architecture}: "
                f"{selected[architecture]} and {candidate}"
            )
        selected[architecture] = candidate
    for architecture in ("arm64", "x86_64"):
        if architecture not in selected:
            raise GenerationError(
                f"missing StoreCore SwiftFileList for {build_action}/{configuration}/{architecture}; "
                f"found {sorted(selected)}"
            )
    lists = [selected["arm64"], selected["x86_64"]]
    normalized: list[list[str]] = []
    for path in lists:
        entries: list[str] = []
        for entry in parse_swift_file_list(path):
            candidate = Path(entry)
            if not candidate.is_absolute():
                candidate = path.parent / candidate
            entries.append(candidate.resolve().as_posix())
        normalized.append(entries)
    if normalized[0] != normalized[1]:
        raise GenerationError(
            "StoreCore SwiftFileList differs across architecture slices: "
            + ", ".join(path.as_posix() for path in lists)
        )
    return lists

def record_compiled_sources(
    root: Path,
    derived_data: Path,
    audit_path: Path,
    configuration: str,
    build_action: str,
) -> None:
    derived_data_relative = repo_relative(root, derived_data)
    audit = load_audit(audit_path)
    if audit.get("schema_version") != 2:
        raise GenerationError("source membership schema_version must be 2")
    if audit.get("channel") != "appStore":
        raise GenerationError("source membership channel must be appStore")

    file_lists = find_swift_file_lists(derived_data, configuration, build_action)
    compiled: set[str] = set()
    derived: set[str] = set()
    for file_list in file_lists:
        for entry in parse_swift_file_list(file_list):
            source, derived_source = normalize_file_list_entry(
                root, derived_data, file_list, entry
            )
            if source is not None:
                compiled.add(source)
            elif derived_source is not None:
                derived.add(derived_source)

    included = audit.get("included_sources")
    if not isinstance(included, list) or not all(
        isinstance(path, str) for path in included
    ):
        raise GenerationError("included_sources must be a repo-relative string array")
    expected = set(included)
    if compiled != expected:
        missing = sorted(expected - compiled)
        unexpected = sorted(compiled - expected)
        details = []
        if missing:
            details.append("missing from compile list: " + ", ".join(missing))
        if unexpected:
            details.append("unexpected compiled sources: " + ", ".join(unexpected))
        raise GenerationError("source closure mismatch; " + "; ".join(details))

    audit["compiled_sources"] = sorted(compiled)
    audit["derived_sources"] = sorted(
        (Path(derived_data_relative) / path).as_posix()
        for path in derived
    )
    audit["swift_file_lists"] = [
        repo_relative(root, path) for path in file_lists
    ]
    write_json(audit_path, audit)
    print(f"Recorded {len(compiled)} compiled Store sources from {len(file_lists)} SwiftFileList file(s)")


def verify_closure_audit(audit_path: Path) -> None:
    audit = load_audit(audit_path)
    required = {
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
    }
    missing = sorted(required - set(audit))
    if missing:
        raise GenerationError("audit is missing fields: " + ", ".join(missing))
    if audit["schema_version"] != 2:
        raise GenerationError("audit schema_version must be 2")
    if audit["channel"] != "appStore":
        raise GenerationError("audit channel must be appStore")
    if not Path(audit["repository_root"]).is_absolute():
        raise GenerationError("audit repository_root must be absolute")
    if not isinstance(audit["source_sha"], str) or not SOURCE_SHA_RE.fullmatch(
        audit["source_sha"]
    ):
        raise GenerationError("audit source_sha must be a lowercase 40-character SHA")
    if not isinstance(audit["source_tree_sha256"], str) or not SOURCE_TREE_SHA_RE.fullmatch(
        audit["source_tree_sha256"]
    ):
        raise GenerationError("audit source_tree_sha256 must be a lowercase 64-character SHA-256")
    for field in ("included_sources", "excluded_sources", "compiled_sources"):
        value = audit[field]
        if not isinstance(value, list) or not all(
            isinstance(path, str) and not Path(path).is_absolute()
            for path in value
        ):
            raise GenerationError(f"audit {field} must be repo-relative paths")
    if audit["included_sources"] != audit["compiled_sources"]:
        raise GenerationError(
            "audit included_sources does not equal compiled_sources; run a real Store build"
        )
    if audit["compiled_sources"] is None or not audit["swift_file_lists"]:
        raise GenerationError("audit has no compiled_sources/swift_file_lists evidence")
    frameworks = audit["linked_frameworks"]
    if not isinstance(frameworks, list) or not all(
        isinstance(item, str) for item in frameworks
    ):
        raise GenerationError("audit linked_frameworks must be strings")
    defines = audit["swift_defines"]
    if not isinstance(defines, list) or not all(
        isinstance(item, str) for item in defines
    ):
        raise GenerationError("audit swift_defines must be strings")
    for path in audit["included_sources"]:
        if not (Path(audit["repository_root"]) / path).is_file():
            raise GenerationError(f"audit source does not exist: {path}")
    if audit["excluded_sources"] and set(audit["excluded_sources"]) & set(
        audit["compiled_sources"]
    ):
        raise GenerationError("excluded source appears in compiled_sources")
    for path in audit["swift_file_lists"]:
        if Path(path).is_absolute() or not (
            Path(audit["repository_root"]) / path
        ).is_file():
            raise GenerationError(f"missing SwiftFileList evidence: {path}")
    print("Store source closure audit passed")


def verify_only_contract(root: Path) -> None:
    included, excluded, platform, entries = build_membership(root)
    validate_app_resource_inputs(root)
    if not included:
        raise GenerationError("Store source membership unexpectedly contains no shared sources")
    for path in included + excluded + platform + [APP_ENTRYPOINT]:
        if not repo_path(root, path).is_file():
            raise GenerationError(f"source does not exist: {path}")
    if set(included) & set(excluded):
        raise GenerationError("included and excluded source sets overlap")
    if not set(entries).issubset(set(excluded)):
        raise GenerationError("excluded source set does not cover the Direct-only manifest")
    check_no_forbidden_configuration(root)


def check_privacy_manifest_only(root: Path, manifest: Path) -> None:
    validate_privacy_manifest(root, manifest)
    print(
        "Store privacy manifest contract passed: "
        + path_label(root, manifest)
    )


def generate(
    root: Path,
    output_root: Path,
    project_path: Path,
    record_derived_data: Path | None,
    args_configuration: str = "Release",
    args_build_action: str = "build",
    expected_source_tree_sha256: str | None = None,
) -> None:
    version, build = read_version_source(root, repo_path(root, DEFAULT_INFO_PLIST))
    version = validate_override(
        os.environ.get("APP_VERSION", version), "APP_VERSION", VERSION_RE
    )
    build = validate_override(
        os.environ.get("BUILD_NUMBER", build), "BUILD_NUMBER", BUILD_RE
    )
    included, excluded, platform, entries = build_membership(root)
    for path in included + platform + [APP_ENTRYPOINT]:
        if not repo_path(root, path).is_file():
            raise GenerationError(f"source does not exist: {path}")
    validate_app_resource_inputs(root)
    check_no_forbidden_configuration(root)
    entitlements_payload(fallback_when_missing=False, root=root)
    linked_frameworks = linked_frameworks_for(
        [repo_path(root, path) for path in included + platform]
    )
    sha = source_sha(root)
    tree_sha256 = source_tree_sha256(root, included + excluded + platform)
    if expected_source_tree_sha256 is not None:
        if not SOURCE_TREE_SHA_RE.fullmatch(expected_source_tree_sha256):
            raise GenerationError(
                "--expected-source-tree-sha256 must be a lowercase "
                "64-character SHA-256"
            )
        if tree_sha256 != expected_source_tree_sha256:
            raise GenerationError(
                "Store source tree changed during the build; expected "
                f"{expected_source_tree_sha256}, found {tree_sha256}"
            )

    write_generated_inputs(root, version, build)
    prepare_store_icon(root)
    write_membership_audit(
        output_root,
        root,
        included,
        excluded,
        platform,
        linked_frameworks,
        sha,
        tree_sha256,
    )
    spec = project_spec(
        root,
        version,
        build,
        included,
        platform,
        linked_frameworks,
        output_root / "XcodeProject",
    )
    write_json(project_path, spec)

    audit_path = output_root / "source-membership.json"
    if record_derived_data is not None:
        record_compiled_sources(
            root,
            record_derived_data,
            audit_path,
            args_configuration,
            args_build_action,
        )
    print(f"Generated {repo_relative(root, project_path)}")
    print(f"Generated {repo_relative(root, audit_path)}")
    print(f"Store source membership: {len(included)} shared, {len(excluded)} excluded, {len(platform)} Store platform")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Repository root. Defaults to the parent of this script.",
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=None,
        help=f"Project spec output path (default: {DEFAULT_PROJECT_SPEC}).",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=None,
        help=f"Generated audit directory (default: {DEFAULT_GENERATED_ROOT}).",
    )
    parser.add_argument(
        "--check-membership-only",
        action="store_true",
        help="Validate source membership without writing generated project files.",
    )
    parser.add_argument(
        "--require-xcodegen",
        action="store_true",
        help="Fail unless xcodegen is exactly 2.46.0.",
    )
    parser.add_argument(
        "--record-compiled-sources",
        type=Path,
        default=None,
        metavar="DERIVED_DATA",
        help="Record StoreCore *.SwiftFileList evidence under this DerivedData path.",
    )
    parser.add_argument(
        "--record-configuration",
        choices=("Debug", "Release"),
        default="Release",
        help="Configuration whose exact SwiftFileList must be selected.",
    )
    parser.add_argument(
        "--record-build-action",
        choices=("build", "archive"),
        default="build",
        help="Build action whose exact SwiftFileList must be selected.",
    )
    parser.add_argument(
        "--verify-closure-audit",
        action="store_true",
        help="Require included_sources to equal compiled_sources in the audit.",
    )
    parser.add_argument(
        "--expected-source-tree-sha256",
        default=None,
        help=(
            "Fail unless the source membership tree still matches the digest "
            "recorded before the build."
        ),
    )
    parser.add_argument(
        "--check-privacy-manifest",
        type=Path,
        default=None,
        metavar="PATH",
        help="Validate one Store privacy manifest without generating the project.",
    )
    parser.add_argument(
        "--validate-xcode-project",
        type=Path,
        default=None,
        metavar="PATH",
        help="Validate PBX resource paths and PBXGroup membership after XcodeGen.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    script_root = Path(__file__).resolve().parent.parent
    root = (args.repo_root or script_root).resolve()
    project_path = (args.project or repo_path(root, DEFAULT_PROJECT_SPEC)).resolve()
    output_root = (args.output_root or repo_path(root, DEFAULT_GENERATED_ROOT)).resolve()

    try:
        validate_repository_root(root)
        if args.check_privacy_manifest is not None:
            manifest = args.check_privacy_manifest
            if not manifest.is_absolute():
                manifest = (Path.cwd() / manifest).resolve()
            check_privacy_manifest_only(root, manifest)
            return 0
        if args.require_xcodegen:
            check_xcodegen_version(os.environ.get("XCODEGEN", "xcodegen"))
        if args.validate_xcode_project is not None:
            validate_generated_xcode_project(root, args.validate_xcode_project.resolve())
            return 0
        if args.check_membership_only:
            verify_only_contract(root)
            print("Store source membership contract passed")
            return 0
        output_root.mkdir(parents=True, exist_ok=True)
        if args.record_compiled_sources is not None:
            generate(
                root,
                output_root,
                project_path,
                args.record_compiled_sources,
                args.record_configuration,
                args.record_build_action,
                args.expected_source_tree_sha256,
            )
        elif not args.verify_closure_audit:
            generate(
                root,
                output_root,
                project_path,
                None,
                expected_source_tree_sha256=args.expected_source_tree_sha256,
            )
        if args.verify_closure_audit:
            verify_closure_audit(output_root / "source-membership.json")
        return 0
    except GenerationError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
