#!/usr/bin/env python3
"""Download large example datasets that are too big for git.

Usage:
    python scripts/download_examples.py
    python scripts/download_examples.py --force   # re-download even if present
"""
import argparse
import os
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).parent.parent
EXAMPLES = ROOT / "examples"

DOWNLOADS = {
    "LLCP2024ASC.zip": (
        "https://www.cdc.gov/brfss/annual_data/2024/files/LLCP2024ASC.zip",
        None,   # no extraction needed — DataExplorer reads the zip directly
    ),
    "LLCP2024.ASC": (
        "https://www.cdc.gov/brfss/annual_data/2024/files/LLCP2024ASC.zip",
        "LLCP2024.ASC",   # extract this entry from the zip
    ),
    "ncdd-202501-grd-scaled.nc": (
        "https://www.ncei.noaa.gov/pub/data/daily-grids/v1-0-0/2025/01/ncdd-202501-grd-scaled.nc",
        None,
    ),
    "FIADB_URBAN_ENTIRE_CSV.zip": (
        "FILL_IN_URL",   # replace with confirmed URL from USDA Urban DataMart
        None,
    ),
    "xr_latest_dwca.zip": (
        "FILL_IN_URL",   # replace with confirmed URL from project owner
        None,
    ),
}


def _progress(count, block, total):
    if total > 0:
        pct = min(count * block / total * 100, 100)
        print(f"\r  {pct:5.1f}%", end="", flush=True)


def download_file(dest: Path, url: str, force: bool = False) -> bool:
    """Download url to dest. Returns True if downloaded, False if skipped."""
    if dest.exists() and not force:
        print(f"  skip  {dest.name} (already present)")
        return False
    print(f"  fetch {dest.name}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, dest, reporthook=_progress)
    print()   # newline after progress
    return True


def extract_entry(zip_path: Path, entry: str, dest: Path, force: bool = False):
    """Extract a single entry from a zip to dest."""
    if dest.exists() and not force:
        print(f"  skip  {dest.name} (already present)")
        return
    print(f"  extract {entry} → {dest.name}")
    with zipfile.ZipFile(zip_path) as zf:
        with zf.open(entry) as src, open(dest, "wb") as out:
            out.write(src.read())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true",
                        help="Re-download even if file already present")
    args = parser.parse_args()

    for filename, (url, extract) in DOWNLOADS.items():
        if "FILL_IN_URL" in url:
            print(f"  SKIP  {filename} — URL not configured (edit DOWNLOADS in this script)")
            continue
        dest = EXAMPLES / filename
        if extract is None:
            download_file(dest, url, force=args.force)
        else:
            # Download the zip to a temp name, then extract
            zip_dest = EXAMPLES / Path(url).name
            download_file(zip_dest, url, force=args.force)
            if zip_dest.exists():
                extract_entry(zip_dest, extract, dest, force=args.force)

    print("\nDone.")


if __name__ == "__main__":
    main()
