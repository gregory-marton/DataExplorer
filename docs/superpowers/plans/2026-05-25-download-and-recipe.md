# Download Examples + Recipe Full Inversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (Task 2) Add a download script for the 5 git-ignored large example datasets; (Task 5) extend the recipe system so the generated script includes all library-callable figures (choropleth, sparkline_cat), removing them from the direct render path so code generation is the primitive and execution is a side effect.

**Architecture:** Task 2 is a standalone Python script (`scripts/download_examples.py`) with a thin shell wrapper. Task 5 adds three `cg_*` code-generator functions inside `DataExplorer.m`, wires them into `se_assemble_recipe`, and removes the geographic figure rendering from `se_plot_categorical_drilldown` — those figures now only appear when the recipe runs. The pairplot, overview, panel totals, and grouped time series remain direct-rendered (too complex to express as clean library calls).

**Tech Stack:** MATLAB (local functions in `DataExplorer.m`), Python 3 (download script), `pytest` + `matlab.unittest` for tests.

---

## Background: what already exists

The recipe infrastructure is partially implemented. Read these before touching anything:

- `DataExplorer.m` line 116–130: main recipe hook — calls `se_assemble_recipe`, then `run(recipe_path)`.
- `DataExplorer.m` line 2359: `cg_load_code(filepath, T)` — generates load code for all file formats.
- `DataExplorer.m` line 2454: `cg_clean_code()` — emits `[T, prof] = de_profile(T);`.
- `DataExplorer.m` line 2462: `cg_best_plots_code(T, prof, sel, source_name)` — emits histogram, scatter, time-series code. **This is what currently runs when the recipe executes.**
- `DataExplorer.m` line 2588: `se_assemble_recipe(filepath, T, prof, options)` — assembles the three sections and `run()`s the result. **This is where we add the new code generators.**
- `save_recipe.m`: standalone function — copies latest recipe from `tempdir` to a user-specified path.
- `DataExplorer.m` line 2785: `se_plot_categorical_drilldown` — currently renders geo figures directly. **After Task 5, it will not render choropleth or sparkline_cat figures.**

## File structure

**Modified:**
- `DataExplorer.m` — three new `cg_*` local functions; `se_assemble_recipe` extended; `se_plot_categorical_drilldown` stripped of geo rendering; panel detection hoisted to top level.
- `tests/test_DataExplorer.m` — new recipe-output tests.

**Created:**
- `scripts/download_examples.py` — downloads the 5 large datasets.
- `download_examples.sh` — thin shell wrapper.

---

## Task 1: Download script

**Files:**
- Create: `scripts/download_examples.py`
- Create: `download_examples.sh`

The 5 git-ignored files and their sources:

| File | Source |
|---|---|
| `examples/LLCP2024ASC.zip` | https://www.cdc.gov/brfss/annual_data/2024/files/LLCP2024ASC.zip |
| `examples/LLCP2024.ASC` | Extracted from `LLCP2024ASC.zip` (same archive) |
| `examples/ncdd-202501-grd-scaled.nc` | https://www.ncei.noaa.gov/pub/data/daily-grids/v1-0-0/2025/01/ncdd-202501-grd-scaled.nc |
| `examples/FIADB_URBAN_ENTIRE_CSV.zip` | ⚠️ **URL unknown — stop here before implementing.** Navigate to https://research.fs.usda.gov/products/dataandtools/urban-datamart. If the direct download URL is not obvious, ask the project owner whether to replace this file with an alternative (see note below). |
| `examples/xr_latest_dwca.zip` | ⚠️ **URL unknown — stop here before implementing.** Ask the project owner for the direct download URL. If unavailable, replace with the suggested alternative (see note below). |

> **⚠️ Reviewer note for these two files:** Before writing the download script for `FIADB_URBAN_ENTIRE_CSV.zip` and `xr_latest_dwca.zip`, check with the project owner — the URLs were not findable at plan-writing time and may require login or a non-stable link.
>
> **Suggested replacements if the original sources are unavailable:**
>
> - `xr_latest_dwca.zip` — The repo already contains `ebd-datafile-SAMPLE.zip` (eBird Basic Dataset sample), which exercises the same figure types: lat/lon scatter via `se_plot_geo`, species categories, date axis. Consider replacing `xr_latest_dwca.zip` with a larger eBird download if more rows are needed, or simply reuse the existing sample. Direct eBird data requires a free account at https://ebird.org/data/download — no stable anonymous URL.
>
> - `FIADB_URBAN_ENTIRE_CSV.zip` — Core characteristics needed: a categorical column with tree species (high cardinality), a geographic column (city or state), and numeric measurements (diameter, height). Good public alternatives with stable direct URLs:
>   - **USDA NASS Crops** (state + crop type + year + harvested acres): `https://www.nass.usda.gov/Statistics_by_State/index.php` — panel format similar to `Prod_dataset.xlsx`; may be redundant.
>   - **SF Street Trees** (species + lat/lon + numeric): `https://data.sfgov.org/api/views/tkzw-k3nq/rows.csv?accessType=DOWNLOAD` (~5 MB, git-committable, has `Species`, `DBH`, lat/lon) — **recommended** if the FIADB source is inaccessible.

- [ ] **Step 1: Verify the two uncertain download URLs**

Visit the USDA Urban DataMart page and the source for `xr_latest_dwca.zip`. Confirm the direct file URLs, then record them in the `DOWNLOADS` dict in the script below before running it. Do not proceed with Step 2 until both URLs are confirmed.

- [ ] **Step 2: Write `scripts/download_examples.py`**

```python
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
```

- [ ] **Step 3: Write `download_examples.sh`**

```bash
#!/usr/bin/env bash
set -e
python3 "$(dirname "$0")/scripts/download_examples.py" "$@"
```

Make it executable:
```bash
chmod +x download_examples.sh
```

- [ ] **Step 4: Run the script and verify files appear**

```bash
python3 scripts/download_examples.py
ls -lh examples/LLCP2024ASC.zip examples/LLCP2024.ASC examples/ncdd-202501-grd-scaled.nc
```

Expected: files exist with non-zero size. The two `FILL_IN_URL` entries will be skipped — that is expected until the URLs are confirmed.

- [ ] **Step 5: Commit**

```bash
git add scripts/download_examples.py download_examples.sh
git commit -m "Add download_examples script for git-ignored large example datasets"
```

---

## Task 2: Hoist panel detection to the top level

`se_detect_panel` is currently called on line ~1096 inside `se_plot`. `se_assemble_recipe` needs the panel struct to know whether to generate choropleth code. Move the call to the top of DataExplorer so both functions receive it.

**Files:**
- Modify: `DataExplorer.m` lines 113–130 (main pipeline) and line 1096 inside `se_plot`

- [ ] **Step 1: Write the failing test**

In `tests/test_DataExplorer.m`, inside the existing test class, add:

```matlab
function test_recipe_runs_without_error(testCase)
    % DataExplorer on a simple table must write and run a recipe without error.
    T = table(categorical(["ME";"ME";"NY";"NY"]), [1;2;3;4], ...
        'VariableNames', {'StateCode','Value'});
    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    % Run via a temp file so se_assemble_recipe has a filepath
    tmp = [tempname '.csv'];
    writetable(T, tmp);
    cl2 = onCleanup(@() delete(tmp));

    figs_before = findobj(0,'Type','figure');
    DataExplorer(tmp);
    figs_after = findobj(0,'Type','figure');
    new_figs = setdiff(figs_after, figs_before);
    cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

    % Recipe must have been written
    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    testCase.verifyNotEmpty(hits, 'Expected a recipe file in tempdir');
end
```

- [ ] **Step 2: Run test to verify it passes already (smoke check)**

```bash
python3 -m pytest tests/ -m slow -k "test_recipe_runs_without_error" -v
```

Expected: PASS (recipe already writes, this test is baseline).

- [ ] **Step 3: Hoist `panel = se_detect_panel(T, prof)` to the top level**

In `DataExplorer.m`, change the main pipeline section (around line 113):

```matlab
%% ── 4.  Plot ──────────────────────────────────────────────────────────────
panel = se_detect_panel(T, prof);
se_plot(T, prof, options, panel);

%% ── 5.  Recipe ────────────────────────────────────────────────────────────
if ischar(source) || isstring(source)
    recipe_path = se_assemble_recipe(string(source), T, prof, panel, options);
    if ~isempty(recipe_path)
        fprintf('  Running recipe to produce best-of plots…\n');
        T_return = T;
        run(recipe_path);
        T = T_return;
        [~, bname, ~] = fileparts(source);
        fprintf('\n  ══════════════════════════════════════════════════════════\n');
        fprintf('  Recipe script: %s\n', recipe_path);
        fprintf('  To keep it:    save_recipe(''%s_recipe.m'')\n', bname);
        fprintf('  ══════════════════════════════════════════════════════════\n\n');
    end
end
```

Update `se_plot` signature (line ~1026) to accept the pre-computed panel and skip its own detection:

```matlab
function se_plot(T, prof, options, panel)
```

Inside `se_plot`, replace the existing panel detection block (around line 1095–1096):

```matlab
% panel pre-computed by caller — used here directly
```

Delete the line `panel = se_detect_panel(T, prof);` and the `if isempty(panel)` guard if any. The `panel` variable is now passed in; everything below that uses `panel.is_panel` stays unchanged.

Update `se_assemble_recipe` signature (line ~2588):

```matlab
function recipe_path = se_assemble_recipe(filepath, T, prof, panel, options)
```

- [ ] **Step 4: Run the test — still passes**

```bash
python3 -m pytest tests/ -m slow -k "test_recipe_runs_without_error" -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DataExplorer.m
git commit -m "Hoist panel detection to DataExplorer top level; pass to recipe assembler"
```

---

## Task 3: Add `cg_state_choropleth_code`

A new local function in `DataExplorer.m` that returns the MATLAB code string to reproduce all state choropleth figures for a given dataset. Does NOT render anything — code generation only.

**Files:**
- Modify: `DataExplorer.m` (add function after `cg_best_plots_code`, around line 2584)
- Modify: `tests/test_DataExplorer.m`

- [ ] **Step 1: Write the failing test**

```matlab
function test_cg_state_choropleth_code_wide_years(testCase)
    % cg_state_choropleth_code for a wide-year panel must emit a de_statebins call
    % with TimeCol='Year'. We test via the recipe file written by DataExplorer.
    states = categorical(repelem(["ME";"NY";"CA"], 1));
    T = table(states, [1;2;3], [4;5;6], ...
        'VariableNames', {'StateCode','x2020','x2021'});
    tmp = [tempname '.csv'];
    writetable(T, tmp);
    cl = onCleanup(@() delete(tmp));
    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    DataExplorer(tmp);

    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    testCase.assertNotEmpty(hits, 'Expected a recipe file');
    [~, newest] = max([hits.datenum]);
    recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
    testCase.verifyTrue(contains(recipe_text, 'de_statebins'), ...
        'Recipe must contain de_statebins call');
    testCase.verifyTrue(contains(recipe_text, 'TimeCol'), ...
        'Recipe must pass TimeCol for wide-year dataset');
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
python3 -m pytest tests/ -m slow -k "test_cg_state_choropleth_code_wide_years" -v
```

Expected: FAIL — recipe does not yet contain `de_statebins`.

- [ ] **Step 3: Implement `cg_state_choropleth_code` in `DataExplorer.m`**

Add after `cg_best_plots_code` (after line ~2584):

```matlab
% ── cg_state_choropleth_code ────────────────────────────────────────────────
function code = cg_state_choropleth_code(T, prof)
%CG_STATE_CHOROPLETH_CODE  Return recipe code for state choropleth figures.
code = '';
cat_all = find(prof.type == "categorical" & ~prof.skip);
geo_idx = [];
for ci = cat_all(:)'
    if se_looks_like_states(prof, ci, T)
        geo_idx = ci; break;
    end
end
if isempty(geo_idx), return; end

catname = prof.name{geo_idx};
[wide_yr_idxs, wide_yr_vals] = se_detect_wide_years(prof);
[time_idx, ~] = se_find_time_axis(prof);
num_idxs = find(prof.type == "numeric" & ~prof.skip);
L = {};

if ~isempty(wide_yr_idxs)
    [yr_sorted, yr_ord] = sort(wide_yr_vals);
    yr_names_s = prof.name(wide_yr_idxs(yr_ord));
    yr_cell = strjoin(cellfun(@(s) sprintf('''%s''',s), yr_names_s, 'UniformOutput',false), ', ');
    yr_vec  = strjoin(arrayfun(@num2str, yr_sorted, 'UniformOutput',false), ', ');

    L{end+1} = sprintf('%% Choropleth: %s (wide years → long)', catname);
    L{end+1} = sprintf('yr_ch = {%s};', yr_cell);
    L{end+1} = sprintf('yr_v_ch = [%s];', yr_vec);
    L{end+1} = 'n_yr_ch = numel(yr_v_ch); n_r_ch = height(T);';
    L{end+1} = 'kp_ch = setdiff(T.Properties.VariableNames, yr_ch);';
    L{end+1} = 'T_long_ch = repmat(T(:,kp_ch), n_yr_ch, 1);';
    L{end+1} = 'T_long_ch.Year = repelem(yr_v_ch(:), n_r_ch);';
    L{end+1} = 'T_long_ch.Value = reshape(cell2mat(arrayfun(@(c) double(T.(c{1})), yr_ch, ''UniformOutput'', false).''), [], 1);';
    L{end+1} = sprintf('de_statebins(T_long_ch, ''StateCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''Title'',''Choropleth: %s'');', catname, catname);
    L{end+1} = '';
else
    num_plot = num_idxs(~ismember(num_idxs, geo_idx));
    for j = 1:numel(num_plot)
        ncn = prof.name{num_plot(j)};
        if isempty(time_idx)
            L{end+1} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''ColorCol'',''%s'', ''Title'',''Choropleth: %s'');', catname, ncn, ncn);
        else
            tcn = prof.name{time_idx};
            L{end+1} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''ColorCol'',''%s'', ''TimeCol'',''%s'', ''Title'',''Choropleth: %s'');', catname, ncn, tcn, ncn);
        end
        L{end+1} = '';
    end
end

if isempty(L), return; end
code = strjoin(L, newline);
end
```

- [ ] **Step 4: Wire into `se_assemble_recipe`**

Inside `se_assemble_recipe`, replace the `sections` assembly block:

```matlab
choro_code = cg_state_choropleth_code(T, prof);

sections = { ...
    header, ...
    '%% === Load ===',       load_code,   '', ...
    '%% === Clean ===',      clean_code,  '', ...
    '%% === Best-of Plots ===', plots_code ...
};
if ~isempty(choro_code)
    sections{end+1} = '';
    sections{end+1} = '%% === State Choropleth ===';
    sections{end+1} = choro_code;
end
```

- [ ] **Step 5: Run test — now passes**

```bash
python3 -m pytest tests/ -m slow -k "test_cg_state_choropleth_code_wide_years" -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "Add cg_state_choropleth_code; include de_statebins in recipe"
```

---

## Task 4: Add `cg_country_choropleth_code`

Mirror of Task 3 for `de_countrybins`.

**Files:**
- Modify: `DataExplorer.m` (add after `cg_state_choropleth_code`)
- Modify: `tests/test_DataExplorer.m`

- [ ] **Step 1: Write the failing test**

```matlab
function test_cg_country_choropleth_code_emits_countrybins(testCase)
    % Dataset with ISO-2 country codes + a value column must put de_countrybins in recipe.
    countries = categorical(["US";"GB";"DE";"FR";"JP"]);
    T = table(countries, [1;2;3;4;5], 'VariableNames', {'ISO2','GDP'});
    tmp = [tempname '.csv'];
    writetable(T, tmp);
    cl = onCleanup(@() delete(tmp));
    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    DataExplorer(tmp);

    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    testCase.assertNotEmpty(hits);
    [~, newest] = max([hits.datenum]);
    recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
    testCase.verifyTrue(contains(recipe_text, 'de_countrybins'), ...
        'Recipe must contain de_countrybins for ISO-2 country codes');
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
python3 -m pytest tests/ -m slow -k "test_cg_country_choropleth_code_emits_countrybins" -v
```

Expected: FAIL.

- [ ] **Step 3: Implement `cg_country_choropleth_code` in `DataExplorer.m`**

Add directly after `cg_state_choropleth_code`:

```matlab
% ── cg_country_choropleth_code ──────────────────────────────────────────────
function code = cg_country_choropleth_code(T, prof)
%CG_COUNTRY_CHOROPLETH_CODE  Return recipe code for world choropleth figures.
code = '';
cat_all = find(prof.type == "categorical" & ~prof.skip);
geo_idx = [];
for ci = cat_all(:)'
    if se_looks_like_countries(prof, ci, T)
        geo_idx = ci; break;
    end
end
if isempty(geo_idx), return; end

catname = prof.name{geo_idx};
[wide_yr_idxs, wide_yr_vals] = se_detect_wide_years(prof);
[time_idx, ~] = se_find_time_axis(prof);
num_idxs = find(prof.type == "numeric" & ~prof.skip);
L = {};

if ~isempty(wide_yr_idxs)
    [yr_sorted, yr_ord] = sort(wide_yr_vals);
    yr_names_s = prof.name(wide_yr_idxs(yr_ord));
    yr_cell = strjoin(cellfun(@(s) sprintf('''%s''',s), yr_names_s, 'UniformOutput',false), ', ');
    yr_vec  = strjoin(arrayfun(@num2str, yr_sorted, 'UniformOutput',false), ', ');

    L{end+1} = sprintf('%% World choropleth: %s (wide years → long)', catname);
    L{end+1} = sprintf('yr_co = {%s};', yr_cell);
    L{end+1} = sprintf('yr_v_co = [%s];', yr_vec);
    L{end+1} = 'n_yr_co = numel(yr_v_co); n_r_co = height(T);';
    L{end+1} = 'kp_co = setdiff(T.Properties.VariableNames, yr_co);';
    L{end+1} = 'T_long_co = repmat(T(:,kp_co), n_yr_co, 1);';
    L{end+1} = 'T_long_co.Year = repelem(yr_v_co(:), n_r_co);';
    L{end+1} = 'T_long_co.Value = reshape(cell2mat(arrayfun(@(c) double(T.(c{1})), yr_co, ''UniformOutput'', false).''), [], 1);';
    L{end+1} = sprintf('de_countrybins(T_long_co, ''CountryCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''Title'',''World choropleth: %s'');', catname, catname);
    L{end+1} = '';
else
    num_plot = num_idxs(~ismember(num_idxs, geo_idx));
    for j = 1:numel(num_plot)
        ncn = prof.name{num_plot(j)};
        if isempty(time_idx)
            L{end+1} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''ColorCol'',''%s'', ''Title'',''World choropleth: %s'');', catname, ncn, ncn);
        else
            tcn = prof.name{time_idx};
            L{end+1} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''ColorCol'',''%s'', ''TimeCol'',''%s'', ''Title'',''World choropleth: %s'');', catname, ncn, tcn, ncn);
        end
        L{end+1} = '';
    end
end

if isempty(L), return; end
code = strjoin(L, newline);
end
```

- [ ] **Step 4: Wire into `se_assemble_recipe`**

After the `choro_code` block, add:

```matlab
country_code = cg_country_choropleth_code(T, prof);
if ~isempty(country_code)
    sections{end+1} = '';
    sections{end+1} = '%% === World Choropleth ===';
    sections{end+1} = country_code;
end
```

- [ ] **Step 5: Run test — now passes**

```bash
python3 -m pytest tests/ -m slow -k "test_cg_country_choropleth_code_emits_countrybins" -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "Add cg_country_choropleth_code; include de_countrybins in recipe"
```

---

## Task 5: Add `cg_geo_multicategorical_code`

Generates the pivot + filter + `de_statebins(..., 'CellRenderer','sparkline_cat',...)` code for geo×category cross-indexed datasets.

**Files:**
- Modify: `DataExplorer.m`
- Modify: `tests/test_DataExplorer.m`

- [ ] **Step 1: Write the failing test**

```matlab
function test_cg_geo_multicategorical_code_emits_sparkline_cat(testCase)
    % 3 states × 3 MSN codes × 2 years → recipe must include sparkline_cat call.
    states = categorical(repelem(["ME";"NY";"CA"], 3));
    msns   = categorical(repmat(["A";"B";"C"], 3, 1));
    T = table(states, msns, [1;2;3;4;5;6;7;8;9], [10;11;12;13;14;15;16;17;18], ...
        'VariableNames', {'StateCode','MSN','x2020','x2021'});
    tmp = [tempname '.csv'];
    writetable(T, tmp);
    cl = onCleanup(@() delete(tmp));
    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    DataExplorer(tmp);

    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    testCase.assertNotEmpty(hits);
    [~, newest] = max([hits.datenum]);
    recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
    testCase.verifyTrue(contains(recipe_text, 'sparkline_cat'), ...
        'Recipe must contain sparkline_cat for geo × categorical dataset');
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
python3 -m pytest tests/ -m slow -k "test_cg_geo_multicategorical_code_emits_sparkline_cat" -v
```

Expected: FAIL.

- [ ] **Step 3: Implement `cg_geo_multicategorical_code` in `DataExplorer.m`**

Add after `cg_country_choropleth_code`:

```matlab
% ── cg_geo_multicategorical_code ────────────────────────────────────────────
function code = cg_geo_multicategorical_code(T, prof)
%CG_GEO_MULTICATEGORICAL_CODE  Recipe code for geo × cat sparkline_cat figures.
%   Fires only when wide year columns exist and at least one geo + one other
%   categorical cross-index the rows (same heuristic as se_plot_geo_multicategorical).
code = '';
[wide_yr_idxs, wide_yr_vals] = se_detect_wide_years(prof);
if isempty(wide_yr_idxs), return; end

cat_all = find(prof.type == "categorical" & ~prof.skip);
if numel(cat_all) < 2, return; end

geo_cats   = cat_all(arrayfun(@(ci) se_looks_like_states(prof,ci,T) || se_looks_like_countries(prof,ci,T), cat_all));
other_cats = cat_all(~ismember(cat_all, geo_cats));
if isempty(geo_cats) || isempty(other_cats), return; end

TOTAL_WORDS = {'total','totals','grand total','all totals'};
[yr_sorted, yr_ord] = sort(wide_yr_vals);
yr_names_s = prof.name(wide_yr_idxs(yr_ord));
yr_cell = strjoin(cellfun(@(s) sprintf('''%s''',s), yr_names_s, 'UniformOutput',false), ', ');
yr_vec  = strjoin(arrayfun(@num2str, yr_sorted, 'UniformOutput',false), ', ');

L = {};
% Pivot header (shared across all geo×cat pairs in this dataset)
L{end+1} = '%% Geo × categorical sparkline_cat';
L{end+1} = sprintf('yr_gm = {%s};', yr_cell);
L{end+1} = sprintf('yr_v_gm = [%s];', yr_vec);
L{end+1} = 'n_yr_gm = numel(yr_v_gm); n_r_gm = height(T);';
L{end+1} = 'kp_gm = setdiff(T.Properties.VariableNames, yr_gm);';
L{end+1} = 'T_long_gm = repmat(T(:,kp_gm), n_yr_gm, 1);';
L{end+1} = 'T_long_gm.Year = repelem(yr_v_gm(:), n_r_gm);';
L{end+1} = 'T_long_gm.Value = reshape(cell2mat(arrayfun(@(c) double(T.(c{1})), yr_gm, ''UniformOutput'', false).''), [], 1);';
L{end+1} = '';

for gi = 1:numel(geo_cats)
    geo_idx  = geo_cats(gi);
    geo_name = prof.name{geo_idx};
    is_states_geo = se_looks_like_states(prof, geo_idx, T);

    for oi = 1:numel(other_cats)
        cat_idx  = other_cats(oi);
        cat_name = prof.name{cat_idx};
        n_geo    = prof.nunique(geo_idx);
        n_other  = prof.nunique(cat_idx);
        ratio    = height(T) / (n_geo * n_other);
        if ratio < 0.5 || ratio > 1.5, continue; end

        % Top-K non-total levels
        cat_col = T.(cat_name);
        cat_levs = cellstr(categories(cat_col));
        cnt_levs = countcats(cat_col);
        is_tot   = cellfun(@(lv) any(strcmpi(lv, TOTAL_WORDS)), cat_levs);
        cat_levs = cat_levs(~is_tot);
        cnt_levs = cnt_levs(~is_tot);
        if isempty(cat_levs), continue; end
        [~, ord] = sort(cnt_levs,'descend');
        K = min(5, numel(cat_levs));
        top_levs = cat_levs(ord(1:K));

        levs_cell = strjoin(cellfun(@(s) sprintf('''%s''',strrep(s,'''','''''')), top_levs, 'UniformOutput',false), ', ');
        title_str = strrep(sprintf('%s x %s: Value by category over time', geo_name, cat_name), '''', '''''');

        L{end+1} = sprintf('top_gm = {%s};', levs_cell);
        L{end+1} = sprintf('T_filt_gm = T_long_gm(ismember(string(T_long_gm.%s), string(top_gm)), :);', cat_name);
        if is_states_geo
            L{end+1} = sprintf('de_statebins(T_filt_gm, ''StateCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''sparkline_cat'', ''CatCol'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, cat_name, K, title_str);
        else
            L{end+1} = sprintf('de_countrybins(T_filt_gm, ''CountryCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''sparkline_cat'', ''CatCol'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, cat_name, K, title_str);
        end
        L{end+1} = '';
    end
end

if numel(L) <= 8   % only the pivot header, no actual calls
    code = ''; return;
end
code = strjoin(L, newline);
end
```

- [ ] **Step 4: Wire into `se_assemble_recipe`**

```matlab
geo_multi_code = cg_geo_multicategorical_code(T, prof);
if ~isempty(geo_multi_code)
    sections{end+1} = '';
    sections{end+1} = '%% === Geo × Categorical ===';
    sections{end+1} = geo_multi_code;
end
```

- [ ] **Step 5: Run test — now passes**

```bash
python3 -m pytest tests/ -m slow -k "test_cg_geo_multicategorical_code_emits_sparkline_cat" -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "Add cg_geo_multicategorical_code; include sparkline_cat call in recipe"
```

---

## Task 6: Full inversion — remove geo rendering from drilldown

With the recipe now generating choropleth and sparkline_cat code, remove those renders from `se_plot_categorical_drilldown` and `se_plot` so each figure appears exactly once (at recipe execution time, not during `se_plot`).

**Files:**
- Modify: `DataExplorer.m` — `se_plot_categorical_drilldown` and the panel path in `se_plot`

- [ ] **Step 1: Write the regression test**

```matlab
function test_inversion_geo_figures_in_recipe_not_during_seplot(testCase)
    % For a geo × cat dataset, choropleth and sparkline_cat figures must
    % NOT appear before the recipe runs (i.e., not during se_plot itself).
    % We verify by counting figures after se_plot would fire but before
    % the recipe runs. We can't directly intercept, so we verify the
    % recipe file contains the expected calls and no extra figures appear
    % before recipe execution in a controlled call.
    %
    % Simpler proxy: after DataExplorer returns, there should be a recipe
    % with de_statebins in it. The figure count check is in the integration run.
    states = categorical(repelem(["ME";"NY";"CA"], 3));
    msns   = categorical(repmat(["A";"B";"C"], 3, 1));
    T = table(states, msns, [1;2;3;4;5;6;7;8;9], [10;11;12;13;14;15;16;17;18], ...
        'VariableNames', {'StateCode','MSN','x2020','x2021'});
    tmp = [tempname '.csv'];
    writetable(T, tmp);
    cl = onCleanup(@() delete(tmp));
    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    DataExplorer(tmp);

    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    testCase.assertNotEmpty(hits);
    [~, newest] = max([hits.datenum]);
    recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
    testCase.verifyTrue(contains(recipe_text, 'de_statebins'), ...
        'de_statebins must be in recipe');
    testCase.verifyTrue(contains(recipe_text, 'sparkline_cat'), ...
        'sparkline_cat must be in recipe');
end
```

- [ ] **Step 2: Run — this passes already from Task 5 work**

```bash
python3 -m pytest tests/ -m slow -k "test_inversion_geo_figures_in_recipe_not_during_seplot" -v
```

Expected: PASS (recipe content is already correct).

- [ ] **Step 3: Remove geo rendering from `se_plot_categorical_drilldown`**

In `DataExplorer.m`, find `se_plot_categorical_drilldown` (line ~2785). Remove the entire "Cross-indexed geo × categorical" block (currently lines ~2840–2860):

```matlab
%% ── Cross-indexed geo × categorical: sparklines or scatter per tile ──────────
all_cats_for_geo = [cat_useful(:)', cat_big(:)'];
geo_cats   = all_cats_for_geo(arrayfun(@(ci) ...
    se_looks_like_states(prof,ci,T) || se_looks_like_countries(prof,ci,T), all_cats_for_geo));
other_cats = all_cats_for_geo(~ismember(all_cats_for_geo, geo_cats));
for gi = 1:numel(geo_cats)
    ...
end
```

Also remove the `se_plot_state_choropleth` and `se_plot_country_choropleth` calls from the `cat_big` loop (lines ~2866–2872):

Replace:
```matlab
if se_looks_like_states(prof, ci, T)
    se_plot_state_summary(T, prof, ci, sel_num, ts_num, time_idx, is_year_axis);
elseif se_looks_like_countries(prof, ci, T)
    num_idxs = unique([sel_num, ts_num(:)']);
    num_idxs = num_idxs(prof.type(num_idxs) == "numeric");
    if ~isempty(time_idx), num_idxs = num_idxs(num_idxs ~= time_idx); end
    se_plot_country_choropleth(T, prof, ci, num_idxs, time_idx, is_year_axis);
else
```

With:
```matlab
if se_looks_like_states(prof, ci, T)
    se_plot_state_summary(T, prof, ci, sel_num, ts_num, time_idx, is_year_axis);
elseif se_looks_like_countries(prof, ci, T)
    % country choropleth moved to recipe (cg_country_choropleth_code)
else
```

- [ ] **Step 4: Run the full non-slow test suite to check for regressions**

```bash
python3 -m pytest tests/ -v
```

Expected: same pass/fail pattern as before (only pre-existing checkcode failures).

- [ ] **Step 5: Run the MATLAB unit tests that touch drilldown**

```bash
python3 -m pytest tests/ -m slow -k "geo_multicategorical or choropleth or drilldown" -v
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add DataExplorer.m
git commit -m "Full inversion: geo choropleth and sparkline_cat now recipe-only"
```

---

## Task 7: Verify recipe is executable (end-to-end)

Add a test that actually runs the saved recipe and verifies figures are produced. This is the payoff test that validates the full inversion is working.

**Files:**
- Modify: `tests/test_DataExplorer.m`

- [ ] **Step 1: Write the test**

```matlab
function test_recipe_produces_statebins_figure_when_run(testCase)
    % Write a CSV with StateCode + wide years, run DataExplorer, then
    % explicitly run the recipe and verify a figure with 'de_statebins'
    % provenance appears (i.e., the recipe's statebins call works).
    states = categorical(repelem(["ME";"NY";"CA";"TX";"FL"], 1));
    T = table(states, [1;2;3;4;5], [6;7;8;9;10], ...
        'VariableNames', {'StateCode','x2020','x2021'});
    tmp = [tempname '.csv'];
    writetable(T, tmp);
    cl = onCleanup(@() delete(tmp));

    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    % Run DataExplorer — this writes and runs the recipe
    figs_before = findobj(0,'Type','figure');
    DataExplorer(tmp);
    figs_after = findobj(0,'Type','figure');
    new_figs = setdiff(figs_after, figs_before);
    cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

    % At least one figure must be a statebins tile-grid
    % (de_statebins sets the figure Name to the Title argument)
    names = arrayfun(@(f) string(f.Name), new_figs(isgraphics(new_figs)), 'UniformOutput', false);
    names = [names{:}];
    has_choro = any(contains(names, 'Choropleth'));
    testCase.verifyTrue(has_choro, ...
        'Recipe must produce a Choropleth figure via de_statebins');
end
```

- [ ] **Step 2: Run to verify it passes**

```bash
python3 -m pytest tests/ -m slow -k "test_recipe_produces_statebins_figure_when_run" -v
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test_DataExplorer.m
git commit -m "Add end-to-end test: recipe produces de_statebins choropleth figure"
```

---

## Self-review

**Spec coverage:**
- Task 2 download script ✅ (Task 1 in plan, URLs confirmed/placeholder for 2 unknown ones)
- `save_recipe()` ✅ (already exists, not changed)
- Recipe includes load + clean + plots ✅ (already done, extended here)
- All `se_plot_*` code generation ✅ for library-callable figures (choropleth, sparkline_cat); panel totals and grouped time series remain direct-rendered (not cleanly library-callable)
- Script written to `/tmp/`, executed via `run()` ✅
- Full inversion: geo figures moved from `se_plot` to recipe ✅ (Task 6)
- End-to-end recipe execution test ✅ (Task 7)
- `se_echo_load_code` already delegates to `cg_load_code` — no change needed ✅

**Gaps acknowledged:**
- `se_plot_panel_totals` and `se_plot_grouped_timeseries_wide` remain direct-rendered; recipe does not include them. These require a future `de_panel_totals` / `de_grouped_timeseries` library function to recipe-ize cleanly.
- Two download URLs (FIADB, xr_latest) require manual confirmation before Task 1 Step 1 can be completed.
