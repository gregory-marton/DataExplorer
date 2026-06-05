# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`DataExplorer` is a standalone MATLAB utility for interactive, forgiving exploration of mixed-type tabular datasets. It is a demo/tool project — no build system, CI/CD, or test suite. The main deliverable is `DataExplorer.m` plus two sampling helpers: `de_reservoir_sample.m` (random, tabular) and `de_stride_sample.m` (deterministic, tabular + 3-D NetCDF).

## Usage

```matlab
% Open file picker dialog
T = DataExplorer()

% Load a specific file (CSV, TSV, TXT, XLSX, ZIP, NetCDF)
T = DataExplorer('mydata.csv')

% Explore an existing table
T = DataExplorer(T_in)

% Key optional arguments
T = DataExplorer('bigfile.csv', MaxRows=10000, MaxVars=8, Columns={'col1','col2'})

% Outputs: [T, prof, recipe].  recipe is the generated recipe as a string array
% (one line per element).  IMPORTANT: requesting the recipe (3rd output) returns
% the code WITHOUT running it — no figures.  T = DataExplorer(...) and
% [T, prof] = DataExplorer(...) render as usual.
[T, prof, recipe] = DataExplorer('mydata.csv');   % code only, no plots

% Random reservoir sample for large files (equal probability, any order)
T = de_reservoir_sample('bigfile.csv', 50000)

% Deterministic stride sample for large files or 3-D NetCDF grids
T = de_stride_sample('bigfile.csv', MaxRows=50000)
T = de_stride_sample('climate.nc', Variable='prcp', MaxRows=10000)
```

## Architecture: Five Phases in DataExplorer.m

The function executes a linear pipeline:

1. **Load**
   - Tabular formats (ZIP / Excel / text) go through the shared **`de_load`** library
     (the single loader; also usable standalone — `T = de_load('file.csv')`).
     `de_load` loads + profiles and returns `[T, prof]`. Ambiguity (multi-file ZIP,
     multi-sheet workbook) resolves by `Interactive`: DataExplorer passes
     `Interactive=true` (prompt); the default is an error listing the candidates +
     the `InnerFile=`/`Sheet=` option to add and re-run; `AutoSelect=true` picks the
     default. ZIP entry selection, Excel multi-sheet detection, delimiter sniffing,
     and header re-sniffing all live in `de_load`'s local functions.
   - NetCDF stays in DataExplorer (`se_load` → `load_netcdf` + the `nc_*` family):
     auto-iterates all data variables (skipping coordinates); heuristic for >2D
     reduction (flatten if small, mean over time dim otherwise); interactive only
     when neither `NCVariable` nor `AutoSelect` is set. This is the multi-variable
     orchestration that produces several explorations, so it sits above `de_load`.

2. **Profile & Clean** (`se_profile`)
   - Classifies columns as: numeric, categorical, datetime, duration, logical, unknown
   - Recognizes 20+ sentinel missing values ("N/A", "NULL", "-999", etc.) — configurable via `MissingStrings`
   - String→numeric conversion if ≥70% of values parse successfully
   - Flags columns >80% missing or with all-unique values (IDs) as skippable

3. **Assemble recipe** (`se_assemble_recipe` + `cg_*` code generators)
   - Builds a complete, self-contained MATLAB script (load + clean + every plot) as a string, writes it to `tempdir/dataexplorer_<name>.m`, and echoes it to the console. This is the canonical code path (see "Code generation is the primitive").
   - Returned as DataExplorer's 3rd output (`[T, prof, recipe]`); **requesting the recipe skips execution** (no figures).

4. **Execute** (eval the recipe's plot sections)
   - When the recipe is *not* requested, DataExplorer `eval`s the plot sections to render figures (T and prof are already loaded, so the load/clean sections are skipped).

5. **Plots** (standalone `de_*` functions, invoked by the recipe — there is no `se_plot`)
   - **Overview** (`de_overview`): paginated 4×2 grid of per-column diagnostic tiles
   - **Pairplot** (`de_pairplot`): np×np scatter matrix, type-aware per cell (scatter, boxplot, violin, heatmap, histogram, bar); capped at `MaxVars`
   - **Choropleths** (`de_statebins`/`de_countrybins`/`de_geobins` → `de_tilegrid`): plain color, state×level `heatmap_cat`, or `value_ladder`; single-numeric maps are stratified by a weighted-random categorical, and a small red `ConfoundNote` flags a mean that mixes sub-populations
   - **Time series** (`de_timeseries`): overlaid lines and/or stacked area
   - **Geo scatter** (`de_geoscatter`): lat/lon point map
   - **Categorical associations / drill-down** (`de_plot_cat_association`, grouped time series)

## Key Design Principles

**Type-aware plotting dispatch:** `de_pairplot` chooses each cell's plot from the type pair of its two variables — numeric×numeric scatter, numeric×categorical box/violin or ranked-median dot plot, categorical×categorical co-occurrence heatmap, datetime×numeric time-ordered scatter; diagonal cells are histograms or bar charts (via its `pp_*` local helpers). Beyond the pairplot there is awareness of temporal and geographic axes, so the recipe also emits timelines, statebins/choropleths, and geo scatters, colored by categoricals and tracking numeric values. Totals are often detected and treated specially.

**Forgiving data handling:** Heuristics are intentionally lenient (70% numeric threshold, 20+ missing sentinels, delimiter auto-detection). When modifying the profiler, preserve this tolerance.

**Smart column selection** (`de_select_columns`): Prefers numeric columns for the pairplot, avoids ID-like columns (all-unique values), and collapses correlated families to one representative. `MaxVars` (default 8) caps the pairplot size; `Columns` overrides the selection entirely.

**Emphasis on information density with readability:** Axes are labelled, titles and legends provided, units shown where available, tooltips show categories as well as values, central tendencies are accompanied by bootstrapped confidence regions, labels show data cardinality and group cardinality. Axis limits are consistent across patches in larger visualizations to allow for comparisons, and other good visualization practices.

**Interactive prompts are sparse and intentional:** Only triggered for ambiguous cases (multi-file ZIP, multi-sheet Excel, NetCDF variable selection). Don't add new interactive prompts without a clear need.

**Performance: fast by default, signaled when slow.** The core pipeline (load, profile, overview plots) should produce something useful within a minute or two on a regular laptop. More involved analyses (ANOVA-based interestingness ranking, GMM outlier detection) are acceptable but must be clearly signaled — print a message before starting and use a `fprintf`-based progress indicator (updating a single console line, tqdm-style) for anything expected to take more than a few seconds. Never silently block.

## Optional Toolbox Dependencies

- **Statistics and Machine Learning Toolbox:** Checked at runtime via `ver('stats')`. Enables violin plots and advanced distribution features. Code must degrade gracefully when absent.
- **Mapping Toolbox:** Used only by `de_usamap` (a teaching demo). The production geo plots — `de_statebins`/`de_countrybins`/`de_geobins`/`de_geoscatter` — need no toolbox.

`de_reservoir_sample.m` and `de_stride_sample.m` use only base MATLAB.

## Working Conventions

**File inspection:** Use the `Read` tool to read files and inspect code. Reserve `Bash` for running commands (tests, git, MATLAB). Do not use `grep`/`cat`/`head`/`tail` via Bash when `Read` will do.

**Test harness:** Run `python3 -m pytest tests/ -v` (fast, smoke) to gate commits. Slow MATLAB tests (`-m slow`) are integration tests — run them as a background pass after all tasks complete, not in per-step TDD loops.

## Example Datasets

`examples/` contains 13 datasets covering the full format range used for manual testing and (eventually) regression testing: Excel (multi-sheet), ZIP (CSV inside), NetCDF, ASC. Notable:
- `Prod_dataset.xlsx` — US State Energy Data System (EIA/SEDS). 4 sheets; the **Data** sheet is `A1:BO1780` with `(Data_Status, StateCode, MSN, 1960, 1961, …, 2023)` — year columns across the top, ~50 states × ~35 MSN energy-type codes per row. Drives tasks 3, 4, and 5.
- `ncdd-202501-grd-scaled.nc` — NetCDF gridded climate data; auto-iterates data variables, averaging over the time dimension (too large to flatten).
- `LLCP2024.ASC` and `LLCP2024ASC.zip` — same dataset in raw and zipped form; pick one.
- ZIP files containing multiple files trigger the interactive file picker.

## Planned Work (as of 2026-05-05)

These tasks were designed in conversation and not yet implemented. Read them before adding features — several are architecturally load-bearing.

### Task 1 — Automated regression testing
Interactive baseline session: load each dataset in `examples/`, show resulting PNGs one page at a time, discuss what to assert for each before moving on. Then build a MATLAB (`matlab.unittest`) test harness around the agreed expectations. Pre-sampled small fixtures for large datasets. Visual correctness requires human sign-off; automated checks verify: syntactic validity (`checkcode`), headless execution without errors, expected figure count.

### Task 2 — Auto-download large datasets from original sources during setup.
Only small exampes are currently committed to version control, so for the full test suite, we need the larger ones, and these should be fetched automatically.

### Task 3 — Even better high-dimensional grouping
When a dataset has multiple categorical grouping dimensions, a time axis, geo dimensions, etc. add visualizations to dig into each such dimension, separating out the others.
1. Infer grouping keys, time axis, value columns.
2. Stats pass (variance or trend slope per group) to rank interestingness.
3. Improve the statebin style choropeths to show more data when practical, e.g. top-k categories as heatmap patches with a time x axis or one numeric variable in the x direction, another in the y direction as heatmap patches, and a third numeric variable in a sparkline, or multiple sparklines by category, or multiple sparklines by numeric variable, etc.

After the pairplot, add a "categorical drill-down" phase that fires when at least one useful categorical exists. Heuristic filter: skip categoricals where `nunique == 1` (constant); for coloring/grouping, also skip those with cardinality > ~15 unless they are a known geo key (e.g., 2-letter `StateCode`).

Three new figure types, in priority order:

1. **Grouped time series** — for each qualifying categorical, one figure showing the numeric variables over time (or year axis) with one line per category level. This is the most immediately useful: for cigarette data, this would show prevalence trends by state, focus group, etc.

2. **Scatter matrix × categorical** — for each qualifying categorical, one page of np×np scatters where points are colored by that categorical's levels. Expands the existing correlation heatmap cells into grouped scatter views. Cap at `MaxVars` columns for the scatter grid.

3. **Choropleth maps** — when a categorical matches a known geographic key pattern (2-letter state codes → `de_statebins`; ISO country codes → `de_countrybins`), produce one map per numeric variable. No Mapping Toolbox required. For lat/lon point data, `se_plot_geo` continues to handle that path. `de_countrybins` is not yet wired into DataExplorer — needs a `se_looks_like_countries` detector analogous to `se_looks_like_states`.

All three figure types can generate many figures quickly. Apply the interestingness ranker from Task 6 to select which categoricals and numerics to prioritize if the total would exceed a reasonable cap (e.g., 5 figures per type).

**Stacked vs. line heuristic (already fixed 2026-05-20):** `se_plot_timeseries` now uses a compositional test — stacked area only when row-wise sums have CV < 0.2. Otherwise overlaid lines. Compositional data now generates both a stacked area figure AND an overlaid-lines figure with a dashed Total line.

**Choropleth refactored (2026-05-21→2026-05-24):** `se_plot_state_choropleth` calls `de_statebins` (no Mapping Toolbox required). Wide-format year columns (x1960..x2023) are detected and pivoted to long format so the TimeCol slider appears.

**Tile-grid library (2026-05-24):** Three standalone files form a layered tile-grid system:
- `de_tilegrid.m` — shared rendering engine (grid struct + pre-normalised codes → choropleth figure with optional slider). Colorbar label includes time range when sparklines active: `mean(col, yr1 – yrN)`. Legend key text box in top-left margin explains color = mean, spark = time range.
- `de_statebins.m` — US state choropleth by default; accepts a `Grid` argument (string preset, struct array, or path to `{code,row,col}` JSON) for any region (provinces, counties, etc.).  Built-in name→code normaliser for US states.  Custom grids: place JSON in `data/grids/<name>.json` and pass `Grid='<name>'`.  Overflow row: unrecognised codes (e.g. EIA region codes X3, X5) get amber-bordered tiles below the main grid.
- `de_countrybins.m` — world tile choropleth using `data/world_tile_grid.json` (Maarten Lambrechts / BBC standard, 195 countries). 4-tier normaliser (alpha-2 > alpha-3 > full name > historical alias). Overflow row for unrecognised codes. Update script: `python scripts/update_world_tile_grid.py`.
- `de_usamap.m` — **teaching demo only**. Single `usamap('conus')` axes; AK and HI placed via affine transform in projected coordinates. Requires Mapping Toolbox. `AKScale`, `AKOffset`, `HIOffset` exposed so students can explore the transform.

**"Other" + CI in grouped time series (2026-05-24):** `se_plot_grouped_timeseries_wide` shows top-(K-1) named levels + an "Other (N classes, n=M)" aggregate line (dashed gray). Bootstrap 95% CI shading (B=500) on all lines. Level labels include `(n=M)` row counts. `se_level_colors` detects Other bucket via `strncmp(…,'Other (',7)` and assigns neutral gray.

**"Other" in bar charts (2026-05-24):** `plot_cat_diag` collapses levels beyond MAX_K=8 into "Other (N, n=M)" bar. Category tick labels show `(n=count)`. `cat_big` path in the main loop uses same "Other (N classes, n=M)" format.

**Internal title prefix (2026-05-21):** `se_src_prefix(source_name, rest)` helper suppresses the "source —" prefix from axes titles when the source is "table input" (i.e., when T was passed directly rather than loaded from a file). Heatmap title format changed to "Time × CatName".


### Task 4 — Multi-dimensional outlier detection with per-variable surprise attribution
Fit a small GMM (k=3–5, `fitgmdist`) to the densest numeric columns (cap ~10, using same column selection as `se_select_columns`). Rank rows by log-likelihood; lowest = multi-dimensional outliers. Attribute surprise to specific variables via per-variable distance from nearest cluster centroid. Pre-filter rows that are mostly missing (already flagged by `se_profile`) — those are uninteresting. Output: ranked list of top ~20 surprising rows with variable-level attribution. Integrate as Phase 6 in DataExplorer when ≥3 numeric columns and ≥50 non-missing rows exist; skip silently otherwise.

amendment: `se_profile` does **not** attempt numeric sentinel replacement (the -999/-9999 heuristic was removed). Missing text sentinels ("N/A", "NULL", etc.) are handled by `MissingStrings` before numeric conversion; that is sufficient for now. Task 6's outlier detection pass is the right place to surface candidate sentinel values: far AND repeated univariate outliers should be recoded automatically (the goal is a useful first pass with minimal input), but the recode must be printed so the user can review and undo post-hoc. Never silent. Constraint: some legitimate extremes are indistinguishable from sentinels by value alone (e.g., 0 or -1 as satellite dry mass at launch) — the printout is the safety net.

### Task 5 — save_recipe() / code-generation-as-primitive architecture
**Architectural inversion:** code generation is the primitive; execution is a side effect.
- All `se_plot_*` functions return MATLAB code strings as their primary output.
- DataExplorer assembles a complete self-contained script (load + clean + plots) and writes it to `/tmp/dataexplorer_<basename>.m`, then executes via `run()`.
- At the end, prints: `% To save this script: save_recipe('mydata.m')`
- `save_recipe(dest)` copies the tmp file to `dest`; fails if `dest` exists.

The generated script must be self-contained — includes full load + clean code, runs without DataExplorer installed.

Also: fix and test the existing `se_echo_load_code` — it gets subsumed into the new load section.

amendment — Decide library vs. vanilla code in recipes
Recipe output is currently vanilla MATLAB (portable, no dependency). The alternative: expose DataExplorer internals as a named library (`de_profile`, `de_histogram`, etc.) and use those in recipe code. This produces cleaner, more readable output and gives students reusable vocabulary, but adds a dependency. Decide this question before finalizing Task 7 recipe format — the baseline session (Task 1) is the right moment to look at actual recipe output and judge readability. Candidate library functions to brainstorm: `se_select_columns`/interestingness ranker, `se_profile`, best-plot generators, outlier/sentinel detection.

**Recipe abstraction audit (2026-05-26):** Typical recipe length for a Prod_dataset-style file is ~80–90 lines — just under the 100-line threshold. Two clear abstraction candidates:
1. **Wide-year pivot** (highest priority): the 7-line `repmat`/`repelem`/`reshape+cell2mat` block appears in all three geo `cg_*` generators (`cg_state_choropleth_code`, `cg_country_choropleth_code`, `cg_geo_multicategorical_code`). Each uses a different variable suffix (`_ch`, `_co`, `_gm`) to avoid collisions. A `de_pivot_wide_years(T, yr_cols)` library function returning `T_long` would reduce each to one line and save ~14 lines per recipe.
2. **Time-series block** (lower priority): the overlaid+stacked block in `cg_best_plots_code` (~30 lines for compositional datasets) could become `de_timeseries(T, time_col, value_cols)` but that function doesn't yet exist.
The NetCDF spatial recipe is already short (9 lines) thanks to `de_stride_sample` + `de_geoscatter`.

### Task 6 — Improve se_select_columns interestingness ranker
Current ranker (line 1832): numeric score = `std/range`; categorical score = Shannon entropy.

**Known issues:**
- `std/range`: sensitive to outliers (one extreme value inflates range, suppresses score); misses bimodality and heavy tails.
- Shannon entropy: measures marginal diversity, not signal. High entropy can be noise (free-text field, high-cardinality code column). What matters is whether the variable *stratifies* something — a categorical column where all groups have similar numeric distributions is low-information regardless of entropy.
- Candidate replacement for categorical: ANOVA F-statistic (`f_oneway` equivalent) measuring how much grouping by this column explains variance in numeric columns. Fall back to normalized entropy (`entropy / log2(cardinality)`) when no numeric columns exist.
- Correlation pruning threshold 0.92 is high; Pearson only (misses monotone nonlinear relationships).

Fix should be driven by concrete bad examples from the baseline session (task 1), not theory alone.

