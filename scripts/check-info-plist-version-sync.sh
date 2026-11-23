#!/usr/bin/env bash
# Guards release housekeeping: Support/Info.plist must carry the same version
# and build as the latest published appcast item.
#
# Info.plist is the fallback version source when a build does not pass an
# explicit version/build, so a stale Info.plist silently mislabels default
# builds (e.g. shipping 1.10.4 while Info.plist still says 1.9.5). Every release
# must update Info.plist together with appcast.xml.
set -euo pipefail

ROOT="${STATUS_TRIO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
INFO_PLIST="$ROOT/Support/Info.plist"
APPCAST="$ROOT/appcast.xml"

die() {
    echo "info-plist version sync error: $*" >&2
    exit 1
}

[[ -f "$INFO_PLIST" ]] || die "missing $INFO_PLIST"
[[ -f "$APPCAST" ]] || die "missing $APPCAST"

python3 - "$INFO_PLIST" "$APPCAST" <<'PY'
import plistlib
import sys
import xml.etree.ElementTree as ET

plist_path, appcast_path = sys.argv[1], sys.argv[2]

with open(plist_path, "rb") as fh:
    info = plistlib.load(fh)
plist_version = str(info.get("CFBundleShortVersionString", "")).strip()
plist_build = str(info.get("CFBundleVersion", "")).strip()

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

errors = []
if plist_version != appcast_version:
    errors.append(
        f"CFBundleShortVersionString {plist_version!r} != latest appcast shortVersionString {appcast_version!r}"
    )
if plist_build != appcast_build:
    errors.append(
        f"CFBundleVersion {plist_build!r} != latest appcast build {appcast_build!r}"
    )
if errors:
    sys.exit(
        "info-plist version sync error: "
        + "; ".join(errors)
        + ". Update Support/Info.plist whenever you publish a new appcast version."
    )

print(f"info-plist version sync OK: {plist_version} (build {plist_build})")
PY
