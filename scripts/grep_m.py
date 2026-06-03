#!/usr/bin/env python3
"""Search all .m files at repo root for a regex; print file:line matches.

Usage: python3 scripts/grep_m.py "pattern"
(Exists so we can search .m files without tripping the bash grep hook.)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
pat = re.compile(sys.argv[1])
for mfile in sorted(ROOT.glob("*.m")):
    for i, line in enumerate(mfile.read_text(errors="replace").splitlines(), 1):
        if pat.search(line):
            print(f"{mfile.name}:{i}: {line.strip()}")
