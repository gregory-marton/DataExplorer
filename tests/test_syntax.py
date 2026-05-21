"""Syntax and lint checks for all .m files via MATLAB checkcode."""
import pytest
from conftest import ROOT, run_matlab


M_FILES = sorted(ROOT.glob("*.m"))


@pytest.mark.parametrize("mfile", M_FILES, ids=[f.name for f in M_FILES])
def test_checkcode_clean(mfile):
    """checkcode must report zero messages for every .m file at the repo root."""
    rel = mfile.relative_to(ROOT)
    result = run_matlab(f"checkcode('{rel}', '-id')")
    assert result.returncode == 0, (
        f"MATLAB exited {result.returncode}:\n{result.stderr.strip()}"
    )
    output = result.stdout.strip()
    assert not output, f"checkcode issues in {rel}:\n{output}"
