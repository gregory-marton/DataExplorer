"""Shared fixtures and helpers for DataExplorer tests."""
import subprocess
from pathlib import Path

MATLAB = "/Applications/MATLAB_R2025b.app/bin/matlab"
ROOT = Path(__file__).parent.parent


def run_matlab(script: str, timeout: int = 120) -> subprocess.CompletedProcess:
    """Run a MATLAB -batch command from the repo root and return the result."""
    return subprocess.run(
        [MATLAB, "-batch", script],
        capture_output=True,
        text=True,
        cwd=ROOT,
        timeout=timeout,
    )
