#!/usr/bin/env python3
"""Render the MobileBattery dependency table from its JSON manifest.

`Support/mobile-battery-dependencies.json` is the single source of truth for the
pinned versions, commits, repositories, and licenses of the libraries the mobile
battery helper links. Generating the docs table from that manifest keeps
`docs/legal/third-party-licenses.md` from drifting when a dependency is bumped.

Usage:
    python3 scripts/render-mobile-battery-license-table.py [manifest]

The optional argument overrides the default manifest path (used by tests).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = ROOT / "Support" / "mobile-battery-dependencies.json"

HEADER = "| Component | License | Version | Upstream repository | Commit |"
SEPARATOR = "| --- | --- | --- | --- | --- |"


def render(manifest: Path) -> str:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    by_name = {dependency["name"]: dependency for dependency in data["dependencies"]}
    order = data.get("sourceBuildOrder") or [dep["name"] for dep in data["dependencies"]]
    rows = [HEADER, SEPARATOR]
    for name in order:
        dependency = by_name[name]
        rows.append(
            "| {name} | {license} | {version} | {repository} | {commit} |".format(
                name=dependency["name"],
                license=dependency["license"],
                version=dependency["version"],
                repository=dependency["repository"],
                commit=dependency["commit"],
            )
        )
    return "\n".join(rows) + "\n"


def main(argv: list[str]) -> int:
    manifest = Path(argv[1]) if len(argv) > 1 else DEFAULT_MANIFEST
    sys.stdout.write(render(manifest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
