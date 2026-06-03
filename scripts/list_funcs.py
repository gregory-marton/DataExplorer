#!/usr/bin/env python3
"""List MATLAB function definitions (line number + signature) in a .m file.

Usage: python3 scripts/list_funcs.py [file.m] [name-substring-filter]
Defaults to DataExplorer.m, no filter.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
target = sys.argv[1] if len(sys.argv) > 1 else "DataExplorer.m"
needle = sys.argv[2].lower() if len(sys.argv) > 2 else ""

path = ROOT / target
pat = re.compile(r"^\s*function\b.*")
for i, line in enumerate(path.read_text().splitlines(), 1):
    if pat.match(line):
        if not needle or needle in line.lower():
            print(f"{i}: {line.strip()}")
