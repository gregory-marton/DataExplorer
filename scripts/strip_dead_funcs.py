#!/usr/bin/env python3
"""Remove zero-reference local functions from a .m file, cascading.

A local function is "dead" if its name appears nowhere outside its own
definition line (ignoring comments). Removing one can make its callees dead, so
we iterate to a fixed point. Each removed function's span runs from its
`function` line (plus any immediately preceding comment-banner/blank lines) up to
the next `function` line (or EOF).

Local function names referenced only inside recipe strings would be a hazard, but
this codebase's recipes call standalone de_* files, never se_*/plot_* locals — so
code-line reference counting is accurate.

Usage: python3 scripts/strip_dead_funcs.py DataExplorer.m
Prints every function it removes.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
target = ROOT / (sys.argv[1] if len(sys.argv) > 1 else "DataExplorer.m")


def func_defs(lines):
    """Return list of (line_idx, name) for each top-level function definition."""
    out = []
    for i, line in enumerate(lines):
        m = re.match(r"^\s*function\b(.*)", line)
        if not m:
            continue
        sig = m.group(1)
        head = sig.split("(", 1)[0]
        sig = sig.split("=", 1)[1] if "=" in head else sig
        nm = re.match(r"\s*([A-Za-z]\w*)", sig)
        if nm:
            out.append((i, nm.group(1)))
    return out


def strip_comment(line):
    if line.lstrip().startswith("%"):
        return ""
    return re.sub(r"%.*$", "", line)


def dead_names(lines, defs):
    dead = []
    for di, name in defs:
        pat = re.compile(rf"\b{re.escape(name)}\b")
        refs = sum(len(pat.findall(strip_comment(l))) for j, l in enumerate(lines) if j != di)
        if refs == 0:
            dead.append((di, name))
    return dead


def span(lines, defs, di):
    """[start, end) line range to delete for the function defined at line di."""
    # extend start upward over a comment-banner / blank lines
    start = di
    while start - 1 >= 0 and (lines[start - 1].lstrip().startswith("%") or lines[start - 1].strip() == ""):
        start -= 1
    # end = next function def line, or EOF
    nexts = [d for d, _ in defs if d > di]
    end = nexts[0] if nexts else len(lines)
    return start, end


def main():
    lines = target.read_text().splitlines(keepends=True)
    removed = []
    while True:
        defs = func_defs(lines)
        dead = dead_names(lines, defs)
        if not dead:
            break
        di, name = dead[0]              # remove one at a time; recompute spans after
        s, e = span(lines, defs, di)
        del lines[s:e]
        removed.append(name)
    target.write_text("".join(lines))
    print(f"Removed {len(removed)} dead local function(s):")
    for n in removed:
        print(f"  - {n}")


if __name__ == "__main__":
    main()
