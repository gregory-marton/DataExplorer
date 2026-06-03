#!/usr/bin/env python3
"""Report local functions in a .m file that have zero references (dead code).

A function is "dead" if its name appears only on its own definition line and
nowhere else (no caller, in code or comment). Run iteratively: deleting dead
functions can make their callees dead too.

Usage: python3 scripts/find_dead_funcs.py [file.m]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
target = sys.argv[1] if len(sys.argv) > 1 else "DataExplorer.m"
text = (ROOT / target).read_text()
lines = text.splitlines()

defs = {}  # name -> def line number (1-based)
for i, line in enumerate(lines, 1):
    m = re.match(r"^\s*function\b(.*)", line)
    if not m:
        continue
    # name is the token after '=' (if any) before '('
    sig = m.group(1)
    sig = sig.split("=", 1)[1] if "=" in sig.split("(", 1)[0] else sig
    nm = re.match(r"\s*([A-Za-z]\w*)", sig)
    if nm:
        defs[nm.group(1)] = i

def strip_comment(line):
    # Drop full-line comments and trailing comments (approx: % not preceded by ').
    if line.lstrip().startswith("%"):
        return ""
    return re.sub(r"%.*$", "", line)

dead = []
for name, defline in defs.items():
    # count word-boundary occurrences anywhere except the def line, ignoring comments
    pat = re.compile(rf"\b{re.escape(name)}\b")
    refs = sum(
        len(pat.findall(strip_comment(line)))
        for i, line in enumerate(lines, 1)
        if i != defline
    )
    if refs == 0:
        dead.append((defline, name))

dead.sort()
if not dead:
    print("No dead local functions found.")
for defline, name in dead:
    print(f"{defline}: {name}")
