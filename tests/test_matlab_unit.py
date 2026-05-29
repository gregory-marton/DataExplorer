"""Run the MATLAB matlab.unittest test class and report results to pytest."""
import re
import pytest
from pathlib import Path
from conftest import ROOT, run_matlab

# ---------------------------------------------------------------------------
# Discover test names by parsing the .m file — no MATLAB startup at collection
# time, which would time out running the full integration suite.
# ---------------------------------------------------------------------------

_TEST_FILE = ROOT / "tests" / "test_DataExplorer.m"


def _collect_test_names() -> list[str]:
    source = _TEST_FILE.read_text(encoding="utf-8")
    # Match public test methods: "function test_<name>(testCase)"
    methods = re.findall(r"^\s*function\s+(test_\w+)\s*\(testCase\)", source, re.MULTILINE)
    class_name = "test_DataExplorer"
    return [f"{class_name}/{m}" for m in methods]


_TEST_NAMES = _collect_test_names()


@pytest.mark.slow
@pytest.mark.parametrize("test_name", _TEST_NAMES)
def test_matlab_unit(test_name, matlab_bin):
    """Run a single MATLAB unittest method and assert it passed."""
    script = (
        f"results = runtests('tests/test_DataExplorer.m', 'Name', '{test_name}');"
        "if isempty(results), error('Test not found: ' + string(results)); end;"
        "r = results(1);"
        "if r.Failed, error('FAILED: %s\\n%s', r.Name, r.Details.DiagnosticRecord.Report); end;"
        "if r.Incomplete, error('INCOMPLETE (skipped assumption not met): %s', r.Name); end;"
    )
    result = run_matlab(script, timeout=360, matlab=matlab_bin)
    assert result.returncode == 0, (
        f"MATLAB error running {test_name}:\n{result.stderr.strip()}\n{result.stdout.strip()}"
    )
