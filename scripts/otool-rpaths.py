#!/usr/bin/env python3
"""Extract LC_RPATH paths from `otool -l`, including universal binaries."""

import re
import sys


PATH = re.compile(r"^\s*path\s+(.+?)\s+\(offset \d+\)\s*$")
in_rpath = False

for line in sys.stdin:
    stripped = line.strip()
    if stripped == "cmd LC_RPATH":
        in_rpath = True
        continue
    if not in_rpath:
        continue
    match = PATH.match(line)
    if match:
        print(match.group(1))
        in_rpath = False
    elif stripped.startswith("cmd "):
        in_rpath = False
