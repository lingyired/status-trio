#!/usr/bin/env python3
"""Extract load-command paths from `otool -L`, excluding universal file headers."""

import re
import sys


DEPENDENCY = re.compile(r"^\s+(.+?)\s+\(compatibility version [^)]*\)")

for line in sys.stdin:
    match = DEPENDENCY.match(line)
    if match:
        print(match.group(1))
