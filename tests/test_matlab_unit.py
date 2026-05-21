"""Run the MATLAB matlab.unittest test class and report results to pytest."""
import re
import pytest
from conftest import ROOT, run_matlab

# ---------------------------------------------------------------------------
# Discover test names by running runtests in 'dry-run' mode (list only).
# We do this at collection time so pytest can show individual test IDs.
# ---------------------------------------------------------------------------

def _collect_test_names() -> list[str]:
    result = run_matlab(
        "results = runtests('tests/test_DataExplorer.m');"
        "for k = 1:numel(results), disp(results(k).Name); end"
    )
    if result.returncode != 0:
        return []
    names = [ln.strip() for ln in result.stdout.splitlines() if ln.strip()]
    return [n for n in names if "/" in n or "test_" in n.lower()]


_TEST_NAMES = _collect_test_names()


@pytest.mark.parametrize("test_name", _TEST_NAMES)
def test_matlab_unit(test_name):
    """Run a single MATLAB unittest method and assert it passed."""
    # Run just this one test by name filter
    script = (
        f"results = runtests('tests/test_DataExplorer.m', 'Name', '{test_name}');"
        "if isempty(results), error('Test not found: ' + string(results)); end;"
        "r = results(1);"
        "if r.Failed, error('FAILED: %s\\n%s', r.Name, r.Details.DiagnosticRecord.Report); end;"
        "if r.Incomplete, error('INCOMPLETE (skipped assumption not met): %s', r.Name); end;"
    )
    result = run_matlab(script, timeout=180)
    assert result.returncode == 0, (
        f"MATLAB error running {test_name}:\n{result.stderr.strip()}\n{result.stdout.strip()}"
    )
