"""Fast recipe-generation smoke tests (gating tier, NOT marked slow).

Recipe generation is cheap (load + profile + assemble — no figure rendering to
inspect), so behavioral checks on the generated recipe belong here, not in the
deferred slow MATLAB suite.  These use real-world CamelCase column names (what
readtable actually produces) — the form that the earlier snake_case unit tests
missed.
"""
import os
import tempfile
import textwrap
from pathlib import Path

from conftest import ROOT, run_matlab


def _gen_recipe(csv_text: str, matlab_bin: str) -> str:
    """Write csv_text to a temp file, run DataExplorer headless, return recipe text."""
    tmp = Path(tempfile.mkdtemp())
    csv = tmp / "smoke.csv"
    csv.write_text(csv_text)
    out = tmp / "recipe_out.m"
    # Copy this csv's specific recipe (dataexplorer_<stem>.m), NOT the newest
    # dataexplorer_*.m — the deferred integration run writes its own recipes to
    # the same tempdir concurrently, so "newest" can grab the wrong one.
    script = (
        "set(0,'DefaultFigureVisible','off');"
        f"DataExplorer('{csv}');"
        f"copyfile(fullfile(tempdir,'dataexplorer_{csv.stem}.m'), '{out}');"
    )
    res = run_matlab(script, timeout=240, matlab=matlab_bin)
    assert res.returncode == 0, f"MATLAB failed:\n{res.stderr}\n{res.stdout}"
    assert out.exists(), f"No recipe produced:\n{res.stdout}"
    return out.read_text()


def _camelcase_csv(n=120):
    """A table with CamelCase id columns, a geo name column, and a correlated family."""
    import math
    import random

    random.seed(7)
    states = ["Alabama", "California", "Texas", "NewYork", "Florida", "Ohio"]
    rows = ["StateName,StateCode,SiteNum,ParameterCode,Year,MeasureA,MeasureB,MeasureC,Indep"]
    for i in range(n):
        s = i % len(states)
        latent = abs(random.gauss(5, 2)) + 1
        a = latent + random.gauss(0, 0.1)
        b = latent * 1.5 + random.gauss(0, 0.1)
        c = latent * 0.8 + random.gauss(0, 0.1)
        indep = random.gauss(0, 1)
        rows.append(
            f"{states[s]},{s+1},{100+(i%40)},{44201+(i%5)},{2020+(i%3)},"
            f"{a:.4f},{b:.4f},{c:.4f},{indep:.4f}"
        )
    return "\n".join(rows) + "\n"


def _latlon_csv(n=40):
    """A table with Latitude/Longitude and two numeric measures."""
    import random

    random.seed(13)
    rows = ["Latitude,Longitude,Value,Spread"]
    for _ in range(n):
        lat = 25 + random.random() * 23
        lon = -123 + random.random() * 58
        rows.append(f"{lat:.3f},{lon:.3f},{random.random()*10:.3f},{random.random()*3:.3f}")
    return "\n".join(rows) + "\n"


def _wide_family_csv(n=120, members=12):
    """A state column plus many (>MaxVars) strongly-correlated numeric columns,
    mimicking wide year columns that collapse into one large family."""
    import random

    random.seed(11)
    states = ["Alabama", "California", "Texas", "Florida", "Ohio", "NewYork"]
    cols = [f"M{j:02d}" for j in range(members)]
    rows = ["StateName," + ",".join(cols)]
    for i in range(n):
        latent = abs(random.gauss(5, 2)) + 1
        vals = [f"{latent * (1 + 0.3 * j) + random.gauss(0, 0.05):.4f}" for j in range(members)]
        rows.append(f"{states[i % len(states)]}," + ",".join(vals))
    return "\n".join(rows) + "\n"


def _fam_cols_lists(recipe):
    import re

    return [re.findall(r"'([^']*)'", body) for body in re.findall(r"fam_cols = \{([^}]*)\}", recipe)]


def test_recipe_caps_family_members(matlab_bin):
    # A large correlated family (12 members) must not emit a 12-wide pairplot /
    # 12-bar ladder — that is the regression that timed out Prod_dataset/FIADB.
    # The emitted fam_cols is capped to MaxVars (8); the (+N correlated) comment
    # still records the full size so nothing is hidden.
    recipe = _gen_recipe(_wide_family_csv(), matlab_bin)
    fams = _fam_cols_lists(recipe)
    assert fams, f"expected at least one correlated family.\n{recipe}"
    for names in fams:
        assert len(names) <= 8, (
            f"fam_cols must be capped to <=8 members; got {len(names)}: {names}\n{recipe}"
        )
    # Prove the cap was actually exercised: the source family exceeded the cap.
    import re

    plus_counts = [int(x) for x in re.findall(r"\(\+(\d+) correlated\)", recipe)]
    assert any(c >= 8 for c in plus_counts), (
        f"test should exercise an over-cap family (+>=8 correlated); saw {plus_counts}\n{recipe}"
    )


def test_recipe_uses_de_timeseries(matlab_bin):
    # The multi-series time-series block must be expressed as a de_timeseries call,
    # not inlined.
    recipe = _gen_recipe(_camelcase_csv(), matlab_bin)
    assert "de_timeseries" in recipe, (
        f"recipe should call de_timeseries for the time-series block.\nRecipe:\n{recipe}"
    )


def test_recipe_includes_geoscatter_for_latlon(matlab_bin):
    # Tabular lat/lon data must get a geo-scatter map *through the recipe*
    # (regression: this used to exist only on the retired se_plot path).
    recipe = _gen_recipe(_latlon_csv(), matlab_bin)
    assert "de_geoscatter" in recipe, (
        f"recipe must emit de_geoscatter for lat/lon data.\nRecipe:\n{recipe}"
    )


def _skewed_state_csv(n=150):
    """A state column plus a heavily right-skewed numeric measure."""
    import random

    random.seed(5)
    states = ["Alabama", "California", "Texas", "Florida", "Ohio", "NewYork"]
    rows = ["StateName,Skewed"]
    for i in range(n):
        val = random.expovariate(1.0) ** 2  # very right-skewed (skewness >> 2)
        rows.append(f"{states[i % len(states)]},{val:.5f}")
    return "\n".join(rows) + "\n"


def test_recipe_logscale_for_skewed_choropleth(matlab_bin):
    # A strongly right-skewed choropleth column must get a log color scale,
    # decided from prof.skewness by the recipe. Color and bar axes share one
    # vocabulary word: Scale (not a separate LogColor parameter).
    recipe = _gen_recipe(_skewed_state_csv(), matlab_bin)
    assert "de_statebins" in recipe, f"expected a state choropleth.\n{recipe}"
    assert "'Scale','log'" in recipe, (
        f"skewed choropleth column should get Scale log.\n{recipe}"
    )
    assert "LogColor" not in recipe, (
        f"LogColor was folded into Scale; it must not appear.\n{recipe}"
    )


def test_recipe_excludes_camelcase_id_choropleths(matlab_bin):
    recipe = _gen_recipe(_camelcase_csv(), matlab_bin)
    for idname in ("StateCode", "SiteNum", "ParameterCode"):
        assert f"'ColorCol','{idname}'" not in recipe, (
            f"CamelCase id column {idname} must not be a choropleth color.\n"
            f"Recipe:\n{recipe}"
        )


def test_recipe_collapses_correlated_family(matlab_bin):
    recipe = _gen_recipe(_camelcase_csv(), matlab_bin)
    assert "de_corr_families" in recipe, "recipe must compute families"
    # Per-family plots are emitted as flat, editable calls driven by fam_cols
    # (not the old de_plot_corr_family wrapper).
    assert "fam_cols" in recipe, "recipe must emit per-family fam_cols plots"
    assert "de_plot_corr_family" not in recipe, "de_plot_corr_family was removed"
    # MeasureA/B/C are a correlated family: at most one may be a choropleth color.
    n_family_choro = sum(
        f"'ColorCol','{m}'" in recipe for m in ("MeasureA", "MeasureB", "MeasureC")
    )
    assert n_family_choro <= 1, (
        f"At most one family member may get its own choropleth; got {n_family_choro}.\n{recipe}"
    )
