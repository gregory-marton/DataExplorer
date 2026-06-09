# Validate argument bounds (MaxRows and beyond) — Plan

> **Status:** **CORE DONE 2026-06-08.** Implemented on the user-facing surface: `MaxRows`/`nrows`
> budget (`de__must_be_row_budget`, `Inf`=no limit); ranges (`de__must_be_range`) on
> CLim/SharedXLim/SharedYLim (de_tilegrid), ColorLim/SizeLim (de_geoscatter),
> Lat/Lon/TimeRange (de_stride_sample); enums (`mustBeMember`) on CellRenderer/Scale
> (de_tilegrid + de_geobins); positive counts (`mustBePositive`) on MaxVars (DataExplorer),
> TopK (de_tilegrid + de_geobins), MinSize/MaxSize (de_geoscatter). 10 unit tests + checkcode +
> recipe-smoke green.
> **Internal bounds DONE 2026-06-09:** ChunkSize>0; de_corr_families (Threshold∈[0,1], MinSize>0,
> Method∈{spearman,pearson}); de_pick_stratifier (Floor∈[0,1], MaxCard>0); de_plot_cat_association
> (MaxPairs>0, VThresh∈[0,1], Figure∈{all,pair,vmatrix}). Used
> `mustBeGreaterThanOrEqual`+`mustBeLessThanOrEqual` for ranges — **`mustBeInRange` is deprecated in
> R2026a** (checkcode flags it; the recommended `mustBeBetween` has inclusive/exclusive ambiguity, so
> the two-bound chain is cleaner). ForcePlot enum left alone (accepted set not obvious). The clearer
> `GeoCol`-not-found message landed in the complain-ignored-options plan. **Plan D complete.**
> **Related:** [2026-06-08-complain-ignored-options.md] — complementary: that plan *warns* when a
> **valid** option is ignored by the active mode; this plan *errors* when an option's **value** is
> out of bounds. Enum validation here overlaps the CellRenderer silent-typo-fallback noted there.

**Goal:** Validate option bounds at the boundary (in the `arguments` blocks) so misuse fails fast with
a clear message, instead of crashing deep inside (e.g. `MaxRows=0` → `Row index exceeds table
dimensions`) or silently mis-routing (e.g. a typo'd `CellRenderer` falling back to `color`).

## Context
`de_load(file, MaxRows=0)` crashes with an opaque `Row index exceeds table dimensions`: `0` is read
as "keep 0 rows," routes into the sampler, and the row-indexing falls over. The right sentinel for
"no limit" is **`Inf`** (already `de_load`'s default; `DataExplorer`/samplers default to `10000`).
More broadly, most numeric/range/enum options across the codebase are unvalidated. MATLAB idiom: use
`Inf` for unbounded and **validate inputs** via `arguments`-block validators (`mustBePositive`,
`mustBeMember`, `mustBeInRange`) — not silent reinterpretation. Precedent already in repo:
`de_overview` (`MaxVars (1,1) double {mustBePositive} = Inf`, `FontSize {mustBePositive}`),
`de_pairplot` (`FontSize {mustBePositive}`).

## Distinction from the "complain" plan
- **This plan:** invalid *value* for an option → **error** at the boundary (`CellRenderer="heatmp"`,
  `MaxRows=0`, `CLim=[10 1]`).
- **Complain plan:** valid option not *used* by the active mode → **warn** (`ValueCols` to `heatmap_cat`).
Together: "if you can't use an option, refuse it or complain — never silently crash or ignore."

## File map
| Action | File | Purpose |
|--------|------|---------|
| Create | `de__must_be_row_budget.m` | validator: positive count or `Inf`, with an "use Inf for no limit" message |
| Create | `de__must_be_range.m` | validator: `[lo hi]` with `lo<=hi`, or `[NaN NaN]` (auto/unset) |
| Modify | `DataExplorer.m`, `de_load.m`, `de_stride_sample.m`, `de_reservoir_sample.m` | `MaxRows`/`nrows` budget validator; `ChunkSize`, `MaxVars` positivity |
| Modify | `de_tilegrid.m`, `de_geobins.m`, `de_statebins.m`, `de_countrybins.m` | `TopK` positivity; `CLim`/`SharedXLim`/`SharedYLim` range; `CellRenderer`/`Scale` enums |
| Modify | `de_geoscatter.m` | `MinSize`/`MaxSize` positivity + ordering; `ColorLim`/`SizeLim` range |
| Modify | `de_corr_families.m`, `de_pick_stratifier.m`, `de_plot_cat_association.m` | fraction bounds + enums (below) |
| Modify | `tests/test_DataExplorer.m` | red-green for representative cases |

## Review — argument-bounds gaps by category (from a codebase scan; verify each)

### 1. Positive counts (should be `> 0`; `Inf` where unbounded) — currently unvalidated
- `DataExplorer.MaxRows` (10000), `DataExplorer.MaxVars` (8) — note `de_overview.MaxVars` IS validated; `DataExplorer`'s is not.
- `de_load.MaxRows` (Inf), `de_stride_sample.MaxRows` (10000; the divide-by-zero stride crash), `de_reservoir_sample` `nrows` (10000) + `ChunkSize` (50000).
- `TopK` (5) in `de_geobins`/`de_statebins`/`de_countrybins` (TopK≤0 → `K=0` → empty render).
- `de_geobins.FontSize` (7) — unvalidated, unlike `de_pairplot`/`de_overview`.
- `de_corr_families.MinSize` (3), `de_pick_stratifier.MaxCard` (15), `de_plot_cat_association.MaxPairs` (3).
→ `{mustBePositive}` (allows `Inf`); for `MaxRows`/`nrows` use `de__must_be_row_budget` (adds the `Inf` hint).

### 2. Ordered ranges `[lo hi]` (lo ≤ hi, or `[NaN NaN]` = auto) — currently unchecked
- `CLim`, `SharedXLim`, `SharedYLim` (de_tilegrid/geobins/statebins/countrybins);
  `de_geoscatter.ColorLim`, `SizeLim`; `de_stride_sample.LatRange`/`LonRange`/`TimeRange`.
→ `{de__must_be_range}`. A reversed pair currently yields empty/garbage silently.

### 3. String enums (validate against the allowed set; a typo currently mis-routes silently)
- `CellRenderer` ∈ {color, heatmap_cat, scatter_cat, value_ladder} — **typo silently falls back to `color`** (the exact silent-fallback the complain plan flags; `mustBeMember` turns it into an error).
- `Scale` ∈ {auto, log, linear}.
- `de_corr_families.Method` ∈ {spearman, pearson, …}; `de_plot_cat_association.Figure` ∈ {all, …}, `ForcePlot` ∈ {auto, …}.
→ inline `{mustBeMember(options.X, ["…","…"])}` (the matlabby enum idiom; no helper needed).

### 4. Fractions / probabilities (should be in `[0,1]`) — currently unchecked
- `de_corr_families.Threshold` (0.80), `de_pick_stratifier.Floor` (0.05), `de_plot_cat_association.VThresh` (0.10).
→ `{mustBeInRange(x,0,1)}` (R2020b+) or `{mustBeNonnegative}` + a `<=1` check.

## Validators (sketch)
```matlab
function de__must_be_row_budget(x)   % positive count, or Inf for no limit
    if ~(isscalar(x) && (x == Inf || x > 0))
        error('DataExplorer:badMaxRows', ...
            'MaxRows must be a positive row count, or Inf for no limit (got %g).', x);
    end
end
function de__must_be_range(x)         % [lo hi] with lo<=hi, or [NaN NaN] for auto
    if numel(x) ~= 2 || (all(~isnan(x)) && x(1) > x(2))
        error('DataExplorer:badRange', ...
            'Range must be [lo hi] with lo<=hi (or [NaN NaN] for auto); got [%g %g].', x(1), x(2));
    end
end
```
Enum: `options.CellRenderer (1,1) string {mustBeMember(options.CellRenderer, ["color","heatmap_cat","scatter_cat","value_ladder"])} = "color"`.

## Verification
Strict-superset change — every currently-valid call still passes. Red-green tests: `MaxRows=0` →
`DataExplorer:badMaxRows`; `MaxRows=Inf` loads everything; `TopK=0` errors; `CellRenderer="heatmp"` →
`mustBeMember` error; reversed `CLim=[10 1]` → `DataExplorer:badRange`. Plus checkcode and
**`tests/test_recipe_smoke.py` stays green** (the generated recipe only emits valid values).
