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

### Task 3 — Fix Excel header detection when header row is mostly numeric
`detectImportOptions` mistakes a row of year values (`1960, 1961, …`) for a data row and generates `Var1, Var2, …` names. Fix: after detection, if variable names are all auto-generated, peek at the raw first row; if it contains a mix of text and year-like integers (4-digit, ~1900–2100), re-run with explicit `VariableNamesRange='A1'`, `DataRange='A2'`.

### Task 4 — Detect wide-format year columns and pivot to long for timeline plots
When column headers are 4-digit years, pivot wide-to-long into `(grouping_keys, Year, Value)` before passing to `se_plot_timeseries`. Grouping keys are non-year non-numeric columns (e.g., `StateCode`, `MSN`).

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

### Task 9 — Create and maintain a Python version
Full Python port with the same five-phase pipeline. Natural equivalents: pandas (load/profile), matplotlib/seaborn (plots), xarray/netCDF4 (NetCDF), scikit-learn `GaussianMixture` (task 6), scipy `f_oneway` (task 8 ANOVA ranker). Recipe output should be a Jupyter notebook (`.ipynb`) — the native Python exploration format — rather than a `.m` file. This is a meaningful divergence from the MATLAB version (not a strict translation) and gives a better Python-native experience.

**Maintenance:** every feature added to the MATLAB version needs a parallel Python implementation. Manage with a shared test matrix (same example datasets, same expected behaviors) and a feature parity checklist updated whenever either version changes. Resolve early: strict parity vs. Python-idiomatic reimagining (the latter is recommended but makes "in sync" harder to define precisely).
