# DataExplorer

A MATLAB utility for rapid, forgiving exploration of mixed-type tabular datasets.
Point it at a file and it loads, profiles, and visualises — no configuration required.

## Quick start

```matlab
% Add the folder to your path, then:
T = DataExplorer('mydata.csv')
T = DataExplorer('survey.xlsx')
T = DataExplorer('climate.nc')
T = DataExplorer('archive.zip')   % picks the right file inside automatically

% Or explore a table you already have:
T = DataExplorer(T_existing)

% Limit rows / columns for speed:
T = DataExplorer('bigfile.csv', MaxRows=10000, MaxVars=8)
T = DataExplorer('data.xlsx', Columns={'State','Year','Value'})
```

After the run, the console shows a copy-pasteable MATLAB script that reproduces
everything DataExplorer just did.  Save it with:

```matlab
save_recipe('my_analysis.m')
```

## What it does

DataExplorer runs a five-step pipeline:

| Step | What happens |
|------|-------------|
| **Load** | Auto-detects CSV/TSV/TXT, Excel (multi-sheet), ZIP, NetCDF, ASC fixed-width |
| **Profile** | Classifies columns, converts strings to numbers where ≥ 70% parse, flags IDs and mostly-missing columns |
| **Echo** | Prints a self-contained MATLAB script to the console |
| **Report** | Compact variable-summary table |
| **Plot** | Overview tiles, time series, geographic maps, pairplot / scatter matrix |

Plots produced include:

- **Overview** — paginated 5 × 3 grid of per-variable diagnostic tiles
- **Time series** — overlaid lines and stacked-area views; detects year-columns and datetime columns automatically
- **Geographic** — US state choropleth (`de_statebins`), world choropleth (`de_countrybins`), lat/lon scatter map
- **Pairplot** — type-aware scatter matrix (scatter, boxplot, violin, histogram, heatmap) for selected columns
- **Categorical drill-down** — grouped time series and scatter-by-category for each categorical grouping column

## Sampling helpers

For files too large to load in full:

```matlab
% Random reservoir sample — equal probability, any row order
T = de_reservoir_sample('bigfile.csv', 50000)

% Deterministic stride sample — reproducible, works on NetCDF grids too
T = de_stride_sample('bigfile.csv', MaxRows=50000)
T = de_stride_sample('climate.nc', Variable='prcp', MaxRows=10000)
```

## Library functions

The standalone `de_*` functions can be used independently of DataExplorer:

| Function | Purpose |
|----------|---------|
| `de_profile(T)` | Profile a table: classify columns, recode missing values, convert types |
| `de_overview(T, prof)` | Paginated per-variable diagnostic tile grid |
| `de_histogram(x, name)` | Publication-quality histogram with KDE and summary stats |
| `de_statebins(T, ...)` | US state tile choropleth (no Mapping Toolbox required) |
| `de_countrybins(T, ...)` | World tile choropleth |
| `de_geoscatter(T, ...)` | Lat/lon scatter map |
| `de_pivot_wide_years(T, yr_cols)` | Pivot wide year-columns to long format |
| `de_reservoir_sample(file, n)` | Random reservoir sample from a large file |
| `de_stride_sample(file, ...)` | Deterministic stride sample; supports NetCDF |

## Requirements

- **MATLAB R2025a or later**
- **Statistics and Machine Learning Toolbox** — optional; enables violin plots
- **Mapping Toolbox** — optional; used only by `de_usamap` (teaching demo)

All core functionality runs without optional toolboxes.

## File formats supported

| Format | Notes |
|--------|-------|
| CSV / TSV / TXT | Delimiter auto-detected; header sniffed |
| Excel (`.xlsx`, `.xls`, `.xlsm`) | Multi-sheet detection; prompts when ambiguous |
| ZIP | Extracts and loads the relevant file inside |
| NetCDF (`.nc`, `.nc4`) | Auto-iterates data variables; handles 2-D and 3-D grids |
| ASC fixed-width | BRFSS-style fixed-width text |
