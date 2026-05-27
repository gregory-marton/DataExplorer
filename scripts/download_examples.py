#!/usr/bin/env python3
"""Download large example datasets that are too big for git.

Usage:
    python scripts/download_examples.py
    python scripts/download_examples.py --force   # re-download even if present

Source pages:
    CDC BRFSS:   https://www.cdc.gov/brfss/annual_data/annual_2024.html
    NOAA NCEI:   https://www.ncei.noaa.gov/data/nclimgrid-daily/access/grids/
    USDA FIA:    https://apps.fs.usda.gov/fia/datamart/
    CASdatasets: https://dutangc.github.io/CASdatasets/reference/usautoBI.html
"""
import argparse
import shutil
import subprocess
import urllib.request
import urllib.error
import zipfile
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).parent.parent
EXAMPLES = ROOT / "examples"

# (url, extract_entry_or_None)
DOWNLOADS = {
    "LLCP2024ASC.zip": (
        "https://www.cdc.gov/brfss/annual_data/2024/files/LLCP2024ASC.zip",
        None,
    ),
    "LLCP2024.ASC": (
        "https://www.cdc.gov/brfss/annual_data/2024/files/LLCP2024ASC.zip",
        "LLCP2024.ASC",
    ),
    "ncdd-202501-grd-scaled.nc": (
        "https://www.ncei.noaa.gov/data/nclimgrid-daily/access/grids/2025/ncdd-202501-grd-scaled.nc",
        None,
    ),
    "FIADB_URBAN_ENTIRE_CSV.zip": (
        "https://apps.fs.usda.gov/fia/datamart/urban/FIADB_URBAN_ENTIRE_CSV.zip",
        None,
    ),
}

USAUTOBI_URL = "https://raw.githubusercontent.com/dutangc/CASdatasets/master/data/usautoBI.rda"


def _progress(count, block, total):
    if total > 0:
        pct = min(count * block / total * 100, 100)
        print(f"\r  {pct:5.1f}%", end="", flush=True)


def _check_http(url: str) -> None:
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, method="HEAD")
        ) as resp:
            if resp.status >= 300:
                raise RuntimeError(f"HTTP {resp.status} fetching {url!r}")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code} fetching {url!r}") from exc


def download_file(dest: Path, url: str, force: bool = False) -> bool:
    """Download url to dest. Returns True if downloaded, False if skipped."""
    if dest.exists() and not force:
        print(f"  skip  {dest.name} (already present)")
        return False
    _check_http(url)
    print(f"  fetch {dest.name}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    try:
        urllib.request.urlretrieve(url, tmp, reporthook=_progress)
        tmp.rename(dest)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise
    finally:
        print()
    return True


def extract_entry(zip_path: Path, entry: str, dest: Path, force: bool = False):
    """Extract a single named entry from a zip to dest."""
    resolved = Path(dest).resolve()
    if not resolved.is_relative_to(EXAMPLES.resolve()):
        raise ValueError(f"Path traversal detected in entry {entry!r}")
    if dest.exists() and not force:
        print(f"  skip  {dest.name} (already present)")
        return
    print(f"  extract {entry} → {dest.name}")
    with zipfile.ZipFile(zip_path) as zf:
        with zf.open(entry) as src, open(dest, "wb") as out:
            shutil.copyfileobj(src, out)


def download_usautobi(force: bool = False):
    """Download usautoBI.rda and convert to CSV via Rscript or pyreadr."""
    csv_path = EXAMPLES / "usautoBI.csv"
    rda_path = EXAMPLES / "usautoBI.rda"

    if csv_path.exists() and not force:
        print(f"  skip  {csv_path.name} (already present)")
        return

    download_file(rda_path, USAUTOBI_URL, force=force)

    print(f"  convert {rda_path.name} → {csv_path.name}")
    converted = False

    rscript = shutil.which("Rscript")
    if rscript:
        result = subprocess.run(
            [rscript, "-e",
             f"load('{rda_path}'); write.csv(usautoBI, '{csv_path}', row.names=FALSE)"],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            rda_path.unlink(missing_ok=True)
            print(f"  ✓ {csv_path.name} (via Rscript)")
            converted = True

    if not converted:
        try:
            import pyreadr
            r = pyreadr.read_r(str(rda_path))
            list(r.values())[0].to_csv(str(csv_path), index=False)
            rda_path.unlink(missing_ok=True)
            print(f"  ✓ {csv_path.name} (via pyreadr)")
            converted = True
        except ImportError:
            pass

    if not converted:
        print(f"  ⚠ could not convert — R and pyreadr both unavailable")
        print(f"    {rda_path.name} saved; to convert manually:")
        print(f"    Rscript -e \"load('{rda_path}'); write.csv(usautoBI, '{csv_path}', row.names=FALSE)\"")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true",
                        help="Re-download even if file already present")
    args = parser.parse_args()

    EXAMPLES.mkdir(parents=True, exist_ok=True)
    print()

    for filename, (url, extract) in DOWNLOADS.items():
        dest = EXAMPLES / filename
        if extract is None:
            download_file(dest, url, force=args.force)
        else:
            zip_dest = EXAMPLES / Path(urlparse(url).path).name
            download_file(zip_dest, url, force=args.force)
            if zip_dest.exists():
                extract_entry(zip_dest, extract, dest, force=args.force)

    download_usautobi(force=args.force)

    print("\nDone. Full test suite: python3 -m pytest tests/ -m slow -v\n")


if __name__ == "__main__":
    main()
