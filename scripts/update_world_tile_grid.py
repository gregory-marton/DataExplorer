#!/usr/bin/env python3
"""Keep data/world_tile_grid.json in sync with the canonical upstream source.

Source: github.com/mustafasaifee42/Tile-Grid-Map (Tile-Grid-Map-Cleaned.json)
Based on the Maarten Lambrechts / BBC World Tile Grid standard.

Usage:
    python scripts/update_world_tile_grid.py

Prints a diff of added / removed country codes and updates the file if changed.
Coordinates format: [col, row], 1-indexed (origin = top-left).
"""

import json
import urllib.request
from pathlib import Path

UPSTREAM = (
    "https://raw.githubusercontent.com/mustafasaifee42/Tile-Grid-Map"
    "/master/Tile-Grid-Map-Cleaned.json"
)
DATA_FILE = Path(__file__).resolve().parent.parent / "data" / "world_tile_grid.json"


def fetch(url: str) -> list:
    with urllib.request.urlopen(url) as r:
        return json.loads(r.read().decode("utf-8"))


def code_index(data: list) -> dict:
    return {e["alpha-2"]: e for e in data}


def main() -> None:
    print(f"Fetching {UPSTREAM} …")
    upstream = fetch(UPSTREAM)
    current = (
        json.loads(DATA_FILE.read_text(encoding="utf-8")) if DATA_FILE.exists() else []
    )

    up_idx  = code_index(upstream)
    cur_idx = code_index(current)

    added   = sorted(set(up_idx) - set(cur_idx))
    removed = sorted(set(cur_idx) - set(up_idx))
    moved   = sorted(
        c for c in set(up_idx) & set(cur_idx)
        if up_idx[c].get("coordinates") != cur_idx[c].get("coordinates")
    )

    if added:
        print("  + Added:   " + ", ".join(
            f"{c} ({up_idx[c]['name']})" for c in added))
    if removed:
        print("  - Removed: " + ", ".join(
            f"{c} ({cur_idx[c]['name']})" for c in removed))
    if moved:
        print("  ~ Moved:   " + ", ".join(
            f"{c} {cur_idx[c]['coordinates']} → {up_idx[c]['coordinates']}"
            for c in moved))
    if not added and not removed and not moved:
        print("  No changes.")

    if upstream == current:
        print(f"  {DATA_FILE.name} is already up to date.")
        return

    DATA_FILE.parent.mkdir(exist_ok=True)
    DATA_FILE.write_text(
        json.dumps(upstream, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"  Updated {DATA_FILE}")


if __name__ == "__main__":
    main()
