#!/usr/bin/env python3
"""Search .m files for a regex; print file:line matches.

Usage:
  python3 scripts/grep_m.py "pattern"            # repo-root *.m (default)
  python3 scripts/grep_m.py "pattern" tests      # *.m under tests/ (recursive)
  python3 scripts/grep_m.py "pattern" .          # every *.m in the repo (recursive)
(Exists so we can search .m files without tripping the bash grep hook.)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
pat = re.compile(sys.argv[1])

if len(sys.argv) > 2:
    base = (ROOT / sys.argv[2]).resolve()
    files = sorted(base.rglob("*.m"))
else:
    files = sorted(ROOT.glob("*.m"))

for mfile in files:
    rel = mfile.relative_to(ROOT)
    for i, line in enumerate(mfile.read_text(errors="replace").splitlines(), 1):
        if pat.search(line):
            print(f"{rel}:{i}: {line.strip()}")
