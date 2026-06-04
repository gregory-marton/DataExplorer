"""Syntax and lint checks for all .m files via MATLAB checkcode."""
import pytest
from conftest import ROOT, run_matlab


# Lint every .m at the repo root AND the MATLAB test files themselves — a syntax
# slip in tests/*.m otherwise only surfaces in the slow tier, where it breaks the
# whole test class.
M_FILES = sorted(
    f for f in [*ROOT.glob("*.m"), *ROOT.glob("tests/*.m")]
    if not f.name.startswith(".")
)


@pytest.mark.parametrize("mfile", M_FILES, ids=[f.name for f in M_FILES])
def test_checkcode_clean(mfile, matlab_bin):
    """checkcode must report zero messages for every .m file at the repo root."""
    rel = mfile.relative_to(ROOT)
    result = run_matlab(f"checkcode('{rel}', '-id')", matlab=matlab_bin)
    assert result.returncode == 0, (
        f"MATLAB exited {result.returncode}:\n{result.stderr.strip()}"
    )
    output = result.stdout.strip()
    assert not output, f"checkcode issues in {rel}:\n{output}"
