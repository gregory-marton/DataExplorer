#!/usr/bin/env python3
"""Inspect the correlation structure of numeric columns in a CSV (inside a zip).

Computes pairwise Pearson and Spearman |correlation| among numeric columns and
reports complete-linkage clusters at a threshold, for both metrics. Pure stdlib.

Usage: python3 scripts/inspect_corr.py examples/annual_conc_by_monitor_2025.zip
"""
import csv
import io
import sys
import zipfile
from math import sqrt

THRESH = 0.80
MIN_VALID = 30


def read_csv_from_zip(zpath):
    with zipfile.ZipFile(zpath) as z:
        name = [n for n in z.namelist() if n.lower().endswith((".csv", ".txt"))][0]
        with z.open(name) as f:
            text = io.TextIOWrapper(f, encoding="utf-8", errors="replace")
            reader = csv.reader(text)
            header = next(reader)
            cols = [[] for _ in header]
            for row in reader:
                for i, v in enumerate(row):
                    if i < len(cols):
                        cols[i].append(v)
    return header, cols


def to_float(v):
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def numeric_columns(header, cols, frac=0.7):
    """Return {name: [floats-or-None]} for columns >=frac numeric, skipping id/coord."""
    out = {}
    for name, col in zip(header, cols):
        vals = [to_float(v) for v in col]
        n_ok = sum(1 for x in vals if x is not None)
        if n_ok < frac * len(vals):
            continue
        nm = name.lower()
        if any(k in nm for k in ("lat", "lon", "code", "site num", "poc")):
            # keep POC actually; only drop ids/coords for clarity of the family question
            if "poc" not in nm:
                continue
        # drop near-constant
        distinct = {x for x in vals if x is not None}
        if len(distinct) <= 1:
            continue
        out[name] = vals
    return out


def pearson(a, b):
    pairs = [(x, y) for x, y in zip(a, b) if x is not None and y is not None]
    if len(pairs) < MIN_VALID:
        return None
    xs, ys = zip(*pairs)
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    if sxx == 0 or syy == 0:
        return None
    return sxy / sqrt(sxx * syy)


def rankdata(vals):
    """Average ranks for a list (ignoring None handled by caller via paired filtering)."""
    idx = sorted(range(len(vals)), key=lambda i: vals[i])
    ranks = [0.0] * len(vals)
    i = 0
    while i < len(idx):
        j = i
        while j + 1 < len(idx) and vals[idx[j + 1]] == vals[idx[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[idx[k]] = avg
        i = j + 1
    return ranks


def spearman(a, b):
    pairs = [(x, y) for x, y in zip(a, b) if x is not None and y is not None]
    if len(pairs) < MIN_VALID:
        return None
    xs, ys = zip(*pairs)
    rx, ry = rankdata(list(xs)), rankdata(list(ys))
    return pearson(rx, ry)


def complete_linkage(names, absR, thr):
    """Greedy complete-linkage clusters (size>=3), seeded in given order."""
    m = len(names)
    assigned = [False] * m
    fams = []
    for seed in range(m):
        if assigned[seed]:
            continue
        cluster = [seed]
        for j in range(m):
            if j == seed or assigned[j]:
                continue
            if all(absR[j][c] is not None and absR[j][c] >= thr for c in cluster):
                cluster.append(j)
        if len(cluster) >= 3:
            for c in cluster:
                assigned[c] = True
            fams.append([names[c] for c in cluster])
    return fams


def main():
    zpath = sys.argv[1] if len(sys.argv) > 1 else "examples/annual_conc_by_monitor_2025.zip"
    header, cols = read_csv_from_zip(zpath)
    num = numeric_columns(header, cols)
    names = list(num.keys())
    print(f"{len(names)} numeric columns considered (rows={len(cols[0])}):")
    for nm in names:
        print(f"  - {nm}")
    print()

    for metric_name, fn in (("Pearson", pearson), ("Spearman", spearman)):
        m = len(names)
        absR = [[None] * m for _ in range(m)]
        for i in range(m):
            absR[i][i] = 1.0
            for j in range(i + 1, m):
                r = fn(num[names[i]], num[names[j]])
                v = abs(r) if r is not None else None
                absR[i][j] = absR[j][i] = v
        fams = complete_linkage(names, absR, THRESH)
        print(f"=== {metric_name} |r|, complete-linkage @ {THRESH} ===")
        if not fams:
            print("  (no families of size >= 3)")
        for fi, fam in enumerate(fams, 1):
            print(f"  family {fi} ({len(fam)}): {fam}")
        # Also show min pairwise within the percentile-ish set for insight
        print()


if __name__ == "__main__":
    main()
