# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`DataExplorer` is a standalone MATLAB utility for interactive, forgiving exploration of mixed-type tabular datasets. It is a demo/tool project — no build system, CI/CD, or test suite. The main deliverable is `DataExplorer.m` (2,023 lines) plus `SampleData.m` (168 lines).

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

% Efficient uniform random sampling for large files (reservoir sampling)
T = SampleData('bigfile.csv', 50000)
```

## Architecture: Five Phases in DataExplorer.m

The function executes a linear pipeline:

1. **Load** (`se_load` + format dispatchers)
   - `load_from_zip`: interactive file selection from ZIP archives
   - `load_netcdf`: interactive variable/dimension selection for `.nc` files
   - `load_excel`: multi-sheet detection with size-based selection prompt
   - `load_text`: delimiter auto-detection, header sniffing, UTF-8/ASCII fallback

2. **Profile & Clean** (`se_profile`)
   - Classifies columns as: numeric, categorical, datetime, duration, logical, unknown
   - Recognizes 20+ sentinel missing values ("N/A", "NULL", "-999", etc.) — configurable via `MissingStrings`
   - String→numeric conversion if ≥70% of values parse successfully
   - Flags columns >80% missing or with all-unique values (IDs) as skippable

3. **Echo Load Code** (`se_echo_load_code`)
   - Prints copy-pasteable MATLAB code to the console to reproduce the load step programmatically

4. **Report** (`se_report`)
   - Prints compact variable summary table to console

5. **Plot** (`se_plot` + specialized sub-functions)
   - **Overview figure** (`se_plot_overview`): paginated 5×3 grid of diagnostic tiles for every column
   - **Geo figure** (`se_plot_geo`): auto-detects lat/lon columns (case-insensitive) and renders an interactive map
   - **Time series** (`se_plot_timeseries`): activated when datetime or "year" columns are found
   - **Pairplot/scatter matrix** (`se_plot`): np×np grid for selected columns with type-aware dispatch per cell (scatter, boxplot, violin, heatmap, histogram, bar)

## Key Design Principles

**Type-aware plotting dispatch:** Off-diagonal pairplot cells call different sub-functions (`plot_num_num`, `plot_num_cat`, `plot_cat_cat`, etc.) based on the type pair of the two variables. Diagonal cells call `plot_num_diag` or `plot_cat_diag`.

**Forgiving data handling:** Heuristics are intentionally lenient (70% numeric threshold, 20+ missing sentinels, delimiter auto-detection). When modifying the profiler, preserve this tolerance.

**Smart column selection** (`se_select_columns`): Prefers numeric columns for the pairplot, avoids ID-like columns (all-unique values). `MaxVars` (default 8) caps the pairplot size; `Columns` overrides the selection entirely.

**Interactive prompts are sparse and intentional:** Only triggered for ambiguous cases (multi-file ZIP, multi-sheet Excel, NetCDF variable selection). Don't add new interactive prompts without a clear need.

**Performance: fast by default, signaled when slow.** The core pipeline (load, profile, overview plots) should produce something useful within a minute or two on a regular laptop. More involved analyses (ANOVA-based interestingness ranking, GMM outlier detection) are acceptable but must be clearly signaled — print a message before starting and use a `fprintf`-based progress indicator (updating a single console line, tqdm-style) for anything expected to take more than a few seconds. Never silently block.

## Optional Toolbox Dependencies

- **Statistics and Machine Learning Toolbox:** Checked at runtime via `ver('stats')`. Enables violin plots and advanced distribution features. Code must degrade gracefully when absent.
- **Mapping Toolbox:** Used for geo figure rendering.

`SampleData.m` uses only base MATLAB (implements Algorithm R reservoir sampling directly).

## Example Datasets

`examples/` contains 13 datasets covering the full format range used for manual testing and (eventually) regression testing: Excel (multi-sheet), ZIP (CSV inside), NetCDF, ASC. Notable:
- `Prod_dataset.xlsx` — US State Energy Data System (EIA/SEDS). 4 sheets; the **Data** sheet is `A1:BO1780` with `(Data_Status, StateCode, MSN, 1960, 1961, …, 2023)` — year columns across the top, ~50 states × ~35 MSN energy-type codes per row. Drives tasks 3, 4, and 5.
- `ncdd-202501-grd-scaled.nc` — NetCDF; triggers interactive variable/dimension selector.
- `LLCP2024.ASC` and `LLCP2024ASC.zip` — same dataset in raw and zipped form; pick one.
- ZIP files containing multiple files trigger the interactive file picker.

## Planned Work (as of 2026-05-05)

These tasks were designed in conversation and not yet implemented. Read them before adding features — several are architecturally load-bearing.

### Task 1 — Automated regression testing
Interactive baseline session: load each dataset in `examples/`, show resulting PNGs one page at a time, discuss what to assert for each before moving on. Then build a MATLAB (`matlab.unittest`) test harness around the agreed expectations. Pre-sampled small fixtures for large datasets. Visual correctness requires human sign-off; automated checks verify: syntactic validity (`checkcode`), headless execution without errors, expected figure count.

### ~~Task 3~~ — DONE (Excel header detection)
`se_fix_names` detects all-`Var1/Var2/…` column names, peeks at the raw first row, and re-assigns names when it finds a mix of text labels and year-like integers (≥3 values in 1900–2100 range). Verified by `test_excel_prod_dataset` against `Prod_dataset.xlsx`.

### ~~Task 4~~ — DONE (Wide-format year columns)
`se_detect_wide_years` finds `x####` columns; `se_plot_grouped_timeseries_wide` renders trend lines per category level directly from the wide columns (no long-format materialisation needed). The choropleth path pivots via `se_pivot_wide_to_long` to pass `TimeCol='Year'` to `de_statebins`. Both paths verified by `test_excel_prod_dataset` and `test_dataexplorer_wide_year_state_choropleth_has_slider`.

### Task 5 — Detect→summarize→drill-down for high-dimensional grouped datasets
When a dataset has multiple categorical grouping dimensions + a time axis + numeric values, replace the flat pairplot with:
1. Infer grouping keys, time axis, value columns.
2. Stats pass (variance or trend slope per group) to rank interestingness.
3. Show 2–3 curated aggregate views: a "totals" view (aggregate over all groups, full time range) and a "best single group" view (highest-variance group, full time range). Optional choropleth when a geographic key is detected (e.g., 2-letter `StateCode`) and Mapping Toolbox is available.
4. Surface faceting/restriction options with those examples as context.

Generalizes beyond `Prod_dataset.xlsx` to any high-dimensional tabular data. The interestingness ranker here is shared with task 7 (recipe example selection) and task 8 — write it as a reusable utility.

### Task 6 — Multi-dimensional outlier detection with per-variable surprise attribution
Fit a small GMM (k=3–5, `fitgmdist`) to the densest numeric columns (cap ~10, using same column selection as `se_select_columns`). Rank rows by log-likelihood; lowest = multi-dimensional outliers. Attribute surprise to specific variables via per-variable distance from nearest cluster centroid. Pre-filter rows that are mostly missing (already flagged by `se_profile`) — those are uninteresting. Output: ranked list of top ~20 surprising rows with variable-level attribution. Integrate as Phase 6 in DataExplorer when ≥3 numeric columns and ≥50 non-missing rows exist; skip silently otherwise.

### Task 7 — save_recipe() / code-generation-as-primitive architecture
**Architectural inversion:** code generation is the primitive; execution is a side effect.
- All `se_plot_*` functions return MATLAB code strings as their primary output.
- DataExplorer assembles a complete self-contained script (load + clean + plots) and writes it to `/tmp/dataexplorer_<basename>.m`, then executes via `run()`.
- At the end, prints: `% To save this script: save_recipe('mydata.m')`
- `save_recipe(dest)` copies the tmp file to `dest`; fails if `dest` exists.

**Two-tier plot strategy:** Many-plot overviews (5×3 grids, pairplots) are for exploration and excluded from the recipe. Before each overview, generate 1–2 full-page example plots chosen by the interestingness ranker (highest-variance variable → clean histogram; most-correlated pair → clean scatter; best time series → clean line chart). These full-page examples go in the recipe. The user gets something immediately runnable and editable without reconstructing anything from the overview.

The generated script must be self-contained — includes full load + clean code, runs without DataExplorer installed.

Also: fix and test the existing `se_echo_load_code` — it gets subsumed into the new load section.

### Task 8 — Improve se_select_columns interestingness ranker
Current ranker (line 1832): numeric score = `std/range`; categorical score = Shannon entropy.

**Known issues:**
- `std/range`: sensitive to outliers (one extreme value inflates range, suppresses score); misses bimodality and heavy tails.
- Shannon entropy: measures marginal diversity, not signal. High entropy can be noise (free-text field, high-cardinality code column). What matters is whether the variable *stratifies* something — a categorical column where all groups have similar numeric distributions is low-information regardless of entropy.
- Candidate replacement for categorical: ANOVA F-statistic (`f_oneway` equivalent) measuring how much grouping by this column explains variance in numeric columns. Fall back to normalized entropy (`entropy / log2(cardinality)`) when no numeric columns exist.
- Correlation pruning threshold 0.92 is high; Pearson only (misses monotone nonlinear relationships).

Fix should be driven by concrete bad examples from the baseline session (task 1), not theory alone.

### Task 6 amendment — Sentinel detection via outlier detection
`se_profile` does **not** attempt numeric sentinel replacement (the -999/-9999 heuristic was removed). Missing text sentinels ("N/A", "NULL", etc.) are handled by `MissingStrings` before numeric conversion; that is sufficient for now. Task 6's outlier detection pass is the right place to surface candidate sentinel values: far AND repeated univariate outliers should be recoded automatically (the goal is a useful first pass with minimal input), but the recode must be printed so the user can review and undo post-hoc. Never silent. Constraint: some legitimate extremes are indistinguishable from sentinels by value alone (e.g., 0 or -1 as satellite dry mass at launch) — the printout is the safety net.

### Task 7 amendment — Decide library vs. vanilla code in recipes
Recipe output is currently vanilla MATLAB (portable, no dependency). The alternative: expose DataExplorer internals as a named library (`de_profile`, `de_histogram`, etc.) and use those in recipe code. This produces cleaner, more readable output and gives students reusable vocabulary, but adds a dependency. Decide this question before finalizing Task 7 recipe format — the baseline session (Task 1) is the right moment to look at actual recipe output and judge readability. Candidate library functions to brainstorm: `se_select_columns`/interestingness ranker, `se_profile`, best-plot generators, outlier/sentinel detection.

### Task 10 — Categorical drill-down figures
After the pairplot, add a "categorical drill-down" phase that fires when at least one useful categorical exists. Heuristic filter: skip categoricals where `nunique == 1` (constant); for coloring/grouping, also skip those with cardinality > ~15 unless they are a known geo key (e.g., 2-letter `StateCode`).

Three new figure types, in priority order:

1. **Grouped time series** — for each qualifying categorical, one figure showing the numeric variables over time (or year axis) with one line per category level. This is the most immediately useful: for cigarette data, this would show prevalence trends by state, focus group, etc.

2. **Scatter matrix × categorical** — for each qualifying categorical, one page of np×np scatters where points are colored by that categorical's levels. Expands the existing correlation heatmap cells into grouped scatter views. Cap at `MaxVars` columns for the scatter grid.

3. **Choropleth maps** — when a categorical matches a known geographic key pattern (2-letter state codes → `de_statebins`; ISO country codes → `de_countrybins`), produce one map per numeric variable. No Mapping Toolbox required. For lat/lon point data, `se_plot_geo` continues to handle that path. `de_countrybins` is not yet wired into DataExplorer — needs a `se_looks_like_countries` detector analogous to `se_looks_like_states`.

   **Statebin display mode (TODO):** The current state choropleth pops up as a separate interactive figure with a year slider. Preferred alternative: embed it as a static tile in the main overview page (alongside the pairplot, etc.), with each tile showing richer per-cell content — a 1D or 2D heatmap encoding, or a sparkline for the time dimension, or a small bar. Goals: more data density on one page, no separate window, works for non-year continuous dimensions as well as time. `de_tilegrid` is the right place to add a `TileContent` or `CellRenderer` option. The slider-based separate-window mode can remain as an explicit call option.

All three figure types can generate many figures quickly. Apply the interestingness ranker from Task 8 to select which categoricals and numerics to prioritize if the total would exceed a reasonable cap (e.g., 5 figures per type).

**Stacked vs. line heuristic (already fixed 2026-05-20):** `se_plot_timeseries` now uses a compositional test — stacked area only when row-wise sums have CV < 0.2. Otherwise overlaid lines. Compositional data now generates both a stacked area figure AND an overlaid-lines figure with a dashed Total line.

**Choropleth refactored (2026-05-21→2026-05-24):** `se_plot_state_choropleth` calls `de_statebins` (no Mapping Toolbox required). Wide-format year columns (x1960..x2023) are detected and pivoted to long format so the TimeCol slider appears.

**Tile-grid library (2026-05-24):** Three standalone files form a layered tile-grid system:
- `de_tilegrid.m` — shared rendering engine (grid struct + pre-normalised codes → choropleth figure with optional slider).
- `de_statebins.m` — US state choropleth by default; accepts a `Grid` argument (string preset, struct array, or path to `{code,row,col}` JSON) for any region (provinces, counties, etc.).  Built-in name→code normaliser for US states.  Custom grids: place JSON in `data/grids/<name>.json` and pass `Grid='<name>'`.
- `de_countrybins.m` — world tile choropleth using `data/world_tile_grid.json` (Maarten Lambrechts / BBC standard, 195 countries). 4-tier normaliser (alpha-2 > alpha-3 > full name > historical alias). Overflow row for unrecognised codes. Update script: `python scripts/update_world_tile_grid.py`.
- `de_usamap.m` — **teaching demo only**. Single `usamap('conus')` axes; AK and HI placed via affine transform in projected coordinates. Requires Mapping Toolbox. `AKScale`, `AKOffset`, `HIOffset` exposed so students can explore the transform.

**Internal title prefix (2026-05-21):** `se_src_prefix(source_name, rest)` helper suppresses the "source —" prefix from axes titles when the source is "table input" (i.e., when T was passed directly rather than loaded from a file). Heatmap title format changed to "Time × CatName".

### Task 9 — Create and maintain a Python version
Full Python port with the same five-phase pipeline. Natural equivalents: pandas (load/profile), matplotlib/seaborn (plots), xarray/netCDF4 (NetCDF), scikit-learn `GaussianMixture` (task 6), scipy `f_oneway` (task 8 ANOVA ranker). Recipe output should be a Jupyter notebook (`.ipynb`) — the native Python exploration format — rather than a `.m` file. This is a meaningful divergence from the MATLAB version (not a strict translation) and gives a better Python-native experience.

**Maintenance:** every feature added to the MATLAB version needs a parallel Python implementation. Manage with a shared test matrix (same example datasets, same expected behaviors) and a feature parity checklist updated whenever either version changes. Resolve early: strict parity vs. Python-idiomatic reimagining (the latter is recommended but makes "in sync" harder to define precisely).

### Task 11 — Create a JS/D3 browser variant
Zero-install version deployable to GitHub Pages or any static host. Same five-phase pipeline adapted for the browser: `FileReader` API for load, D3 for plots, no server required.

Recipe output format: a self-contained HTML file that is the *minimum code a student needs* to reproduce or extend the analysis — analogous to the MATLAB recipe using `de_histogram` as vocabulary. Not a no-code tool; the student is expected to edit the code.

**Library candidates for recipe output:** Observable Plot (Jeremy Ashkenas, spiritual successor to D3, much less boilerplate than raw D3) or Plotly.js. Crossfilter is more suited to linked dashboards and is probably overkill for a starting recipe. D3 raw is too verbose for a recipe that students will edit. Recommend Observable Plot as default.

**Design questions to resolve before starting:**
- Do the three target variants (MATLAB, Python, JS) share a recipe spec, or does each do the idiomatic thing? Recommended: idiomatic per language (`.m`, `.ipynb`, standalone `.html`), with a shared test matrix verifying pipeline equivalence.
- Subset of features for v1: load (CSV/TSV/Excel via SheetJS), profile, overview plots, pairplot, time series. NetCDF and ZIP deferred (harder in browser).
- `de_geomap` equivalent: Leaflet or D3-geo with TopoJSON (natural fit for browser; no Mapping Toolbox dependency).

**Relationship to Task 9:** Decide the feature parity checklist scope once Task 9 is underway — the JS variant follows the same checklist but may lag behind.
