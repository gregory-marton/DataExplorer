"""Shared fixtures and helpers for DataExplorer tests."""
import subprocess
import uuid
from pathlib import Path
import pytest

ROOT = Path(__file__).parent.parent
CACHE = ROOT / ".cache"
SENTINEL = CACHE / "integration_sentinel.txt"
LAST_RUN = CACHE / "last_full_run.txt"


def _discover_matlab() -> list[str]:
    """Return paths to all installed MATLAB binaries, newest version first."""
    apps = sorted(Path("/Applications").glob("MATLAB_R*.app"), reverse=True)
    return [str(p / "bin" / "matlab") for p in apps if (p / "bin" / "matlab").exists()]


def _default_matlab() -> str:
    found = _discover_matlab()
    if not found:
        raise RuntimeError("No MATLAB installation found under /Applications/MATLAB_R*.app")
    return found[0]


def pytest_addoption(parser):
    parser.addoption(
        "--matlab", default=None,
        help="Path to matlab binary (default: newest discovered under /Applications)",
    )
    parser.addoption(
        "--all-matlab", action="store_true", default=False,
        help="Run the suite against every MATLAB version found under /Applications",
    )


def pytest_configure(config):
    config._matlab_binaries = None   # resolved lazily in generate/fixture


def _get_matlab_binaries(config) -> list[str]:
    if config._matlab_binaries is not None:
        return config._matlab_binaries
    if config.getoption("--all-matlab"):
        bins = _discover_matlab()
    elif config.getoption("--matlab"):
        bins = [config.getoption("--matlab")]
    else:
        bins = [_default_matlab()]
    config._matlab_binaries = bins
    return bins


def pytest_generate_tests(metafunc):
    if "matlab_bin" in metafunc.fixturenames:
        bins = _get_matlab_binaries(metafunc.config)
        ids = [Path(b).parents[1].name for b in bins]   # e.g. "MATLAB_R2025b.app"
        metafunc.parametrize("matlab_bin", bins, ids=ids, scope="session")


@pytest.fixture(scope="session")
def matlab_bin(request):
    return request.param


def run_matlab(script: str, timeout: int = 120,
               matlab: str | None = None) -> subprocess.CompletedProcess:
    """Run a MATLAB -batch command from the repo root and return the result."""
    binary = matlab or _default_matlab()
    return subprocess.run(
        [binary, "-batch", script],
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
