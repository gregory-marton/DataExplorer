"""Shared fixtures and helpers for DataExplorer tests."""
import subprocess
import uuid
from pathlib import Path

MATLAB = "/Applications/MATLAB_R2025b.app/bin/matlab"
ROOT = Path(__file__).parent.parent
CACHE = ROOT / ".cache"
SENTINEL = CACHE / "integration_sentinel.txt"
LAST_RUN = CACHE / "last_full_run.txt"


def run_matlab(script: str, timeout: int = 120) -> subprocess.CompletedProcess:
    """Run a MATLAB -batch command from the repo root and return the result."""
    return subprocess.run(
        [MATLAB, "-batch", script],
        capture_output=True,
        text=True,
        cwd=ROOT,
        timeout=timeout,
    )


def pytest_sessionstart(session):
    CACHE.mkdir(exist_ok=True)
    SENTINEL.write_text(str(uuid.uuid4()))


def pytest_sessionfinish(session, exitstatus):
    slow_ran = any(item.get_closest_marker("slow") for item in session.items)

    if exitstatus == 0 and slow_ran:
        # We just ran the full integration suite — nothing deferred; clear sentinel.
        SENTINEL.unlink(missing_ok=True)
        LAST_RUN.unlink(missing_ok=True)
    elif exitstatus == 0 and not slow_ran:
        uid = SENTINEL.read_text().strip() if SENTINEL.exists() else None
        if uid:
            script = ROOT / "scripts" / "run_integration_deferred.sh"
            subprocess.Popen(
                ["bash", str(script), uid],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            print(f"\n[deferred-integration] scheduled (id {uid[:8]}…)")

    if LAST_RUN.exists():
        lines = LAST_RUN.read_text().splitlines()
        tail = "\n".join(lines[-15:])
        print(f"\n[deferred-integration] last full run had failures:\n{tail}\n")
