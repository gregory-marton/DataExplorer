#!/usr/bin/env python3
"""One-shot: rename tile-grid option names to MATLAB-native vocabulary (Plan B3).

Renames, in this order so the CatCol-substring-of-CatColors collision is safe
(longest superset first):
    CatColors -> GroupColors
    CatCol    -> GroupVariable
    ColorCol  -> ColorVariable
    ValueCols -> DataVariables

Applies to repo-root *.m (except the off-limits student_examples.m), the test file,
README.md, and the recipe-smoke test. Idempotent. Prints a per-file change summary.

Usage:
    python3 scripts/rename_options.py            # apply
    python3 scripts/rename_options.py --dry-run  # preview counts only
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RENAMES = [
    ("CatColors", "GroupColors"),
    ("CatCol",    "GroupVariable"),
    ("ColorCol",  "ColorVariable"),
    ("ValueCols", "DataVariables"),
]
SKIP = {"student_examples.m"}   # off-limits scratch file


def target_files():
    files = [p for p in sorted(ROOT.glob("*.m")) if p.name not in SKIP]
    files += [ROOT / "tests" / "test_DataExplorer.m",
              ROOT / "README.md",
              ROOT / "tests" / "test_recipe_smoke.py"]
    return [f for f in files if f.exists()]


def main():
    dry = "--dry-run" in sys.argv
    changed = 0
    for f in target_files():
        text = f.read_text()
        orig = text
        counts = []
        for old, new in RENAMES:
            c = text.count(old)
            if c:
                counts.append(f"{old}->{new} x{c}")
                text = text.replace(old, new)
        if text != orig:
            changed += 1
            print(f"{f.relative_to(ROOT)}: " + ", ".join(counts))
            if not dry:
                f.write_text(text)
    print(f"{'DRY-RUN, ' if dry else ''}{changed} file(s) {'would change' if dry else 'changed'}")


if __name__ == "__main__":
    main()
