#!/usr/bin/env python3
"""
inspect_functions.py — list all functions in DataExplorer.m with their line
numbers, prefix category, and (for de_* functions) their public signature.

Usage:
    python scripts/inspect_functions.py
    python scripts/inspect_functions.py --grep de_histogram
    python scripts/inspect_functions.py --prefix de
    python scripts/inspect_functions.py --warnings   # show checkcode-style issues
"""

import re
import sys
import argparse
from pathlib import Path

ROOT = Path(__file__).parent.parent
MAIN = ROOT / "DataExplorer.m"

PREFIX_LABELS = {
    "de_": "library  (public)",
    "cg_": "codegen  (recipe)",
    "se_": "internal (private)",
    "load_": "loader",
    "plot_": "plot helper",
    "nc_": "NetCDF helper",
}


def parse_functions(path: Path) -> list[dict]:
    lines = path.read_text().splitlines()
    funcs = []
    for i, line in enumerate(lines, start=1):
        m = re.match(r"^function\s+(?:[^=]+=\s*)?(\w+)\s*\(([^)]*)\)", line.strip())
        if m:
            name = m.group(1)
            args = m.group(2).strip()
            prefix = next((p for p in PREFIX_LABELS if name.startswith(p)), "other")
            funcs.append({"line": i, "name": name, "args": args, "prefix": prefix})
    return funcs


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--grep", metavar="PATTERN", help="filter by name substring")
    parser.add_argument("--prefix", metavar="PREFIX", help="filter by prefix (de, cg, se, ...)")
    parser.add_argument("--warnings", action="store_true", help="flag stale docstrings (name mismatch)")
    args = parser.parse_args()

    funcs = parse_functions(MAIN)

    if args.prefix:
        funcs = [f for f in funcs if f["prefix"].startswith(args.prefix)]
    if args.grep:
        funcs = [f for f in funcs if args.grep.lower() in f["name"].lower()]

    # Group by prefix
    by_prefix: dict[str, list] = {}
    for f in funcs:
        by_prefix.setdefault(f["prefix"], []).append(f)

    for prefix, group in sorted(by_prefix.items()):
        label = PREFIX_LABELS.get(prefix + "_", PREFIX_LABELS.get(prefix, prefix))
        print(f"\n── {label} ({''.join(prefix)} prefix) ──")
        for f in group:
            sig = f"function {f['name']}({f['args']})"
            print(f"  L{f['line']:>4}  {sig}")

            if args.warnings:
                # Check if docstring first word matches function name
                lines = MAIN.read_text().splitlines()
                doc_line = lines[f["line"]]  # line after function def
                m = re.match(r"^%(\w+)", doc_line.strip())
                if m and m.group(1).upper() != f["name"].upper():
                    print(f"           ⚠ docstring says {m.group(1)}, function is {f['name']}")

    print(f"\nTotal: {len(funcs)} function(s) in {MAIN.name}")


if __name__ == "__main__":
    main()
