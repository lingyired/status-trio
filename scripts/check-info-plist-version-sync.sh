#!/usr/bin/env bash
# Guards release housekeeping: Support/Info.plist must never describe a version
# older than the latest published appcast item.
#
# Info.plist is the fallback version source when a build does not pass an
# explicit version/build, so a stale Info.plist silently mislabels default
# builds (e.g. shipping 1.10.4 while Info.plist still says 1.9.5). Ordinary
# local verification runs before the appcast is updated, so it must accept a
# *pending* version that runs ahead of the published feed; it only rejects a
# regression. Publishing passes `--exact` because the shipped metadata must then
# match the published item exactly.
#
# Usage:
#   check-info-plist-version-sync.sh             # local verification: ahead OK
#   check-info-plist-version-sync.sh --exact     # publish gate: must match
#   check-info-plist-version-sync.sh --allow-ahead
set -euo pipefail

MODE="allow-ahead"
for arg in "$@"; do
    case "$arg" in
        --exact|--require-published|--release)
            MODE="exact"
            ;;
        --allow-ahead|--local)
            MODE="allow-ahead"
            ;;
        -h|--help)
            sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "info-plist version sync error: unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

ROOT="${STATUS_TRIO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
INFO_PLIST="$ROOT/Support/Info.plist"
APPCAST="$ROOT/appcast.xml"

die() {
    echo "info-plist version sync error: $*" >&2
    exit 1
}

[[ -f "$INFO_PLIST" ]] || die "missing $INFO_PLIST"
[[ -f "$APPCAST" ]] || die "missing $APPCAST"

python3 - "$INFO_PLIST" "$APPCAST" "$MODE" <<'PY'
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

plist_path, appcast_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]

with open(plist_path, "rb") as fh:
    info = plistlib.load(fh)
plist_version = str(info.get("CFBundleShortVersionString", "")).strip()
plist_build = str(info.get("CFBundleVersion", "")).strip()

if not plist_version:
    sys.exit("info-plist version sync error: Support/Info.plist has no CFBundleShortVersionString")
if not plist_build.isdigit():
    sys.exit(f"info-plist version sync error: CFBundleVersion {plist_build!r} is not numeric")

NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(appcast_path).getroot()

best = None
for item in root.findall("./channel/item"):
    version = item.findtext("sparkle:version", default="", namespaces=NS).strip()
    if not version.isdigit():
        continue
    short = item.findtext("sparkle:shortVersionString", default="", namespaces=NS).strip()
    if best is None or int(version) > best[0]:
        best = (int(version), version, short)

if best is None:
    sys.exit("info-plist version sync error: appcast.xml has no numeric sparkle:version item")

_, appcast_build, appcast_version = best


def version_key(value):
    """Compare dotted marketing versions numerically, ignoring any suffix."""
    parts = []
    for chunk in value.split("."):
        match = re.match(r"\d+", chunk.strip())
        parts.append(int(match.group(0)) if match else 0)
    while parts and parts[-1] == 0:
        parts.pop()
    return tuple(parts) or (0,)


plist_key = version_key(plist_version)
appcast_key = version_key(appcast_version)
plist_build_number = int(plist_build)
appcast_build_number = int(appcast_build)

errors = []
if mode == "exact":
    if plist_version != appcast_version:
        errors.append(
            f"CFBundleShortVersionString {plist_version!r} != latest appcast "
            f"shortVersionString {appcast_version!r}"
        )
    if plist_build_number != appcast_build_number:
        errors.append(
            f"CFBundleVersion {plist_build!r} != latest appcast build {appcast_build!r}"
        )
else:
    # A pending release may lead the feed, but must never trail it.
    if plist_build_number < appcast_build_number:
        errors.append(
            f"CFBundleVersion {plist_build!r} is behind latest appcast build "
            f"{appcast_build!r}"
        )
    elif plist_build_number == appcast_build_number and plist_version != appcast_version:
        # Same build, different marketing version: the two metadata sources
        # disagree about what that build is.
        errors.append(
            f"CFBundleVersion {plist_build!r} is already published as "
            f"{appcast_version!r}, but Support/Info.plist says {plist_version!r}"
        )
    if plist_key < appcast_key:
        errors.append(
            f"CFBundleShortVersionString {plist_version!r} is behind latest "
            f"appcast shortVersionString {appcast_version!r}"
        )

if errors:
    hint = (
        "Update Support/Info.plist together with appcast.xml before publishing."
        if mode == "exact"
        else "A pending release may be ahead of appcast.xml, but never behind it."
    )
    sys.exit("info-plist version sync error: " + "; ".join(errors) + ". " + hint)

if mode == "exact":
    print(f"info-plist version sync OK (exact): {plist_version} (build {plist_build})")
else:
    relation = "matches" if plist_build_number == appcast_build_number else "is ahead of"
    print(
        f"info-plist version sync OK: {plist_version} (build {plist_build}) "
        f"{relation} published {appcast_version} (build {appcast_build})"
    )
PY
