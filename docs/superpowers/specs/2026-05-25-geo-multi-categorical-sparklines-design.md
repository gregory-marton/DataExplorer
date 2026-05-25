# Design: Geo × Categorical × Numeric — Multi-Dimensional Tile Figures

**Date:** 2026-05-25
**Status:** Approved for implementation planning

---

## Problem

When a dataset has two high-cardinality categoricals (one geographic, one domain) plus a time axis or multiple numeric dimensions, DataExplorer currently treats each categorical independently. There is no view that crosses them simultaneously. For example, with `Prod_dataset.xlsx` (StateCode × MSN × year columns × energy value), the tool produces a state choropleth (per numeric) and a grouped time series (per categorical), but never a view that shows all four dimensions at once.

The design principle: show as many dimensions simultaneously as is readable. A geographic tile grid with rich per-cell content is the natural structure for data that has geo + one other categorical + time or multiple numerics.

No sliders. No animations. Static figures only.

---

## Scope

This spec covers the **geo case only**. The non-geo case (two non-geographic categoricals + time/numerics) is deferred until a concrete dataset example motivates it.

---

## Detection Logic

Fire this figure type when **all** of the following hold:

1. One categorical is geographic (`se_looks_like_states` or `se_looks_like_countries` returns true).
2. At least one other non-geographic categorical exists in `cat_useful` or `cat_big`.
3. The two categoricals together approximately uniquely index the rows:
   `0.5 ≤ nrows / (nunique(geo_cat) × nunique(other_cat)) ≤ 1.5`.
   This allows for some missing combinations while excluding datasets where the two categoricals are genuinely independent (e.g., both vary freely across all rows).
4. Either:
   - **a)** Wide year columns exist (`wide_yr_idxs` non-empty), **or**
   - **b)** At least two non-skip numeric columns exist (excluding the time axis if present).

Condition 3 is the key cross-indexing test. It distinguishes a dataset like `StateCode × MSN` (which truly cross-indexes rows) from one where both categoricals happen to coexist but don't form a joint index.

---

## Figure Structure

One figure per qualifying numeric variable (capped at ~3, ranked by interestingness ranker from Task 6). Each figure:

- Uses the `de_statebins` (or `de_countrybins`) geographic tile grid layout.
- Each state/country cell contains a **mini chart** rendered by the chosen `CellRenderer`.
- Shared legend for the faceting categorical (top-k levels, colored consistently).
- Figure title: `"[GeoVar] × [CatVar]: [NumericVar]"` or `"[GeoVar] × [CatVar]: [Num1] vs [Num2]"`.
- Figure size: large enough for cells to be readable (e.g., `[100 100 1600 1000]`).

---

## Cell Renderers

The renderer is chosen by which dimensions are available. Two renderers for v1:

### Renderer A — Sparklines (time available)

**Condition:** Wide year columns or explicit time axis exists.

**Cell content:** Mini line chart.
- x = year (or time values), spanning the full data range.
- y = numeric value (shared y-limits across all cells within the same figure, for geographic comparability).
- One colored line per top-k level of the faceting categorical, ranked by interestingness.
- k = 4–5 (enough to distinguish by color; more becomes unreadable at cell size).
- "Other" line (dashed gray) if levels beyond top-k exist, matching the existing `se_level_colors` / `plot_cat_big` pattern.

**Aggregation:** For each (geo level, cat level, time point), take the mean of the numeric. Missing combinations: skip (no imputation).

### Renderer B — Scatter (no time, multiple numerics)

**Condition:** No time axis; at least two non-skip numeric columns available.

**Cell content:** Mini scatter plot.
- x = numeric variable 1 (highest interestingness score).
- y = numeric variable 2 (second highest).
- Points colored by the faceting categorical's levels (top-k, same color scheme).
- One point per row within that geo cell's subset.
- Shared axis limits across all cells (for comparability).

---

## de_tilegrid Extension

`de_tilegrid` currently renders each tile as a filled rectangle (scalar color from a shared colormap). It needs a new `CellRenderer` parameter.

### Interface change

Actual signature: `de_tilegrid(T, grid, normed, options)` where `T` is a table, `grid` is the layout struct, and `normed` is a string array of normalized tile codes (same height as `T`).

New name-value options:
- `CellRenderer`: `'color'` (existing default) | `'sparkline'` | `'scatter'`
- `CatCol`: column name of the faceting categorical (used for line grouping in sparklines; point color in scatter)
- `YCol`: column name of the numeric value (y-axis for sparklines; y-axis for scatter — distinct from `ColorCol` which drives tile fill in `'color'` mode)
- `XCol`: column name for scatter x-axis (not needed for sparklines, which use `TimeCol`)
- `TopK`: max category levels to show per cell (default 5)
- `SharedYLim`: `[lo hi]` — if supplied, all cells use this y-range (caller computes it from the full dataset for comparability)

For `'sparkline'`: T must contain `TimeCol`, `YCol`, `CatCol`, and the geo code column. One row per (geo, time, cat level) combination. `de_tilegrid` groups by geo code, then within each cell groups by cat level and draws one line per level (top-k by row count or caller-supplied order).

For `'scatter'`: T must contain `XCol`, `YCol`, `CatCol`, and the geo code column. One row per observation. `de_tilegrid` groups by geo code and draws a scatter per cell, coloring points by `CatCol`.

### Rendering approach

Use MATLAB axes within each tile's bounding box. For each non-empty cell:
1. Compute the tile's pixel/data bounding box from its `[row, col]` grid position.
2. Create a small `axes` object positioned at that bounding box using normalized figure units.
3. Draw the mini chart in that axes (line objects for sparklines; scatter for scatter).
4. Suppress tick labels, box on, no axis labels — only the content.
5. A thin border rectangle distinguishes the cell from background.

Overflow tiles (unrecognised codes) remain as plain colored rectangles (existing behavior).

### Backward compatibility

`CellRenderer` defaults to `'color'`, preserving all existing `de_tilegrid` / `de_statebins` / `de_countrybins` call sites.

---

## New DataExplorer Function

`se_plot_geo_multicategorical(T, prof, geo_idx, cat_idx, num_idxs, yr_idxs, yr_vals)`

Called from the categorical drill-down phase after the existing per-categorical handling, when the detection conditions are met.

Responsibilities:
1. Select top-k levels of `cat_idx` by interestingness score.
2. For each qualifying numeric (up to cap):
   a. Choose renderer (A if time available, B if multiple numerics and no time).
   b. Aggregate data per (geo level, cat level, time/numeric).
   c. Build `renderer_struct`.
   d. Call `de_statebins` or `de_countrybins` with `CellRenderer` set.
3. Print progress message before starting (figure generation may take a few seconds).

---

## Deferred / Out of Scope

- **Non-geo case:** Two non-geographic categoricals + time. Deferred until a concrete dataset motivates it.
- **Heatmap cell renderer** (x=time, y=category, color=value): noted as a future option, but sparklines are more readable at tile cell scale and sufficient for v1.
- **Animations / sliders:** Explicitly excluded.
- **More than two categoricals:** Not handled in v1.
- **Renderer C and beyond:** Additional cell renderers (histogram, boxplot per cell) are natural extensions but out of scope here.

---

## Integration Points

- `de_tilegrid.m`: new `CellRenderer` parameter and per-cell axes rendering.
- `de_statebins.m`, `de_countrybins.m`: pass through `CellRenderer` to `de_tilegrid`.
- `DataExplorer.m`: add detection + dispatch in the categorical drill-down section (`se_plot_categorical_drilldown` or equivalent call site around line 2820).
- `se_level_colors`: already handles top-k + Other pattern; reused here.
- Interestingness ranker (`se_select_columns`, current implementation around line 1832): used for both categorical level selection and numeric variable selection. Task 6 will improve the ranker; this feature uses whatever is current.
