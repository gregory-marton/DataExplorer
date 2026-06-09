# Align the plot/group API with MATLAB-native vocabulary — Plan

> **Status:** **B1 DONE 2026-06-08.** `ColorMethod` (mean/count/median/sum, default mean) added to
> `de_tilegrid` and plumbed through `de_geobins`/`de_statebins`/`de_countrybins`; threaded through the
> choropleth/heatmap_cat/value_ladder aggregation (`tg_agg`) with method-aware labels (colorbar,
> title, heatmap colorbar, sparkline key). 2 unit tests + checkcode + recipe-smoke green; recipes
> unaffected (default mean). Directly enables the PM25 insight: `ColorMethod="count"` shows coverage.
> **B2 DONE 2026-06-08:** value_ladder no longer forces `has_choro=false` — with a `ColorCol` set it
> fills the tiles (colorbar) while drawing member bars on top (value_ladder excluded from sparklines;
> `ColorCol` added to its consumed-set so Plan A no longer flags it). The original "ladder also colored
> by something" is delivered. 2 tests + checkcode + recipe-smoke green (recipe value_ladder has no
> ColorCol → unchanged).
> **REMAINING: B3** the rename `ColorCol`→`ColorVariable`, `ValueCols`→`DataVariables`,
> `CatCol`→`GroupVariable` (cosmetic, high-churn; rewrites recipe text + tests + docs). Do it WHOLE
> (a partial rename leaves mixed vocabulary, worse than none). **De-risked order** (longest-superset
> first, per file via replace_all): (1) `CatColors`→`GroupColors`, (2) `CatCol`→`GroupVariable`,
> (3) `ColorCol`→`ColorVariable`, (4) `ValueCols`→`DataVariables` — across DataExplorer.m, de_tilegrid/
> geobins/statebins/countrybins/usamap/geoscatter, tests, README, CLAUDE.md. Then full re-gate
> (checkcode + recipe-smoke + the recipe-content slow tests, several of which assert option-name
> tokens in the emitted recipe).
> **Related:** [2026-06-08-complain-ignored-options.md] (renamed options change its consumed-sets —
> do together or sequence carefully), [2026-06-08-filter-during-read.md] (shares the `rowfilter` idiom).

**Goal:** Make the tile-grid/plot API mirror MATLAB's native grouped-analysis grammar (group keys,
value vars, aggregation method) so it's idiomatic AND teaches students transferable base-MATLAB.

## Context
Our tile-grid API uses idiosyncratic names (`ColorCol`, `CatCol`, `TimeCol`, `ValueCols`) and a
**hardcoded `mean`** aggregation. MATLAB's grouped-analysis family shares one grammar across
`groupsummary(T,groupvars,method,datavars)`, `varfun(...,'GroupingVariables',...,'InputVariables',...)`,
`grpstats`, `pivot(Rows,Columns,Method,DataVariable)`, `heatmap(T,xvar,yvar,'ColorVariable','ColorMethod')`,
`geobubble(...,'SizeVariable','ColorVariable')`.

## Key observations
- `heatmap_cat` per tile *is* `heatmap(T, xvar=time, yvar=cat, ColorVariable, ColorMethod)` faceted over
  a geo grid; `de_geoscatter` ≈ `geobubble(...,SizeVariable,ColorVariable)`.
- **Biggest divergence: no `Method`/`ColorMethod`** — we always aggregate by `mean`, silently. Exposing
  it (count/mean/median/sum/…) is the most useful + most matlabby change; it also directly helps the PM25
  case (`ColorMethod="count"` shows the four standards differ in *coverage* even though their means match).
- Naming: this subsumes the earlier `ColorCol`→`ValueCol` question — the native answer is `ColorVariable`
  for the colored value and `DataVars`/`DataVariables` for the ladder set (what `groupsummary` calls them);
  `CatCol`→a grouping/`GroupVariable` role.

## File map
| Action | File | Purpose |
|--------|------|---------|
| Modify | `de_tilegrid.m` | add `Method`/`ColorMethod` (default `mean`); thread through Heat/multi_heat; rename value/group options |
| Modify | `de_statebins.m`, `de_countrybins.m`, `de_geobins.m`, `de_usamap.m` | forward the new option names/method |
| Modify | `DataExplorer.m` | `cg_*` generators emit native-vocabulary calls + a literal `groupsummary`/`pivot` step before plotting |
| Modify | `tests/test_DataExplorer.m`, `README.md`, `CLAUDE.md` | option renames, method coverage, docs |

## Approach (sketch — design before implementing)
1. Add `Method`/`ColorMethod` (default `mean`); thread through the aggregation instead of the hardcoded mean.
2. Rename value/group options to native vocabulary (`ColorVariable`, `DataVariables`, group role).
3. Make recipes self-teaching: emit the literal `groupsummary`/`pivot`/`heatmap` step that produces the
   per-group summary, then hand it to the plotter (already done in the NetCDF geoscatter recipe:
   `groupsummary(T,{lon,lat},{'mean','std'},vars)`).

## Combined fill + bars (value_ladder + ColorVariable) — added 2026-06-08
Today `value_ladder` forces `has_choro=false` (de_tilegrid.m:156), so it drops `ColorCol`
entirely — you can't draw a ladder whose tiles are *also* tinted by a separate variable. Let the
renderer accept BOTH a `ColorVariable` (tile-fill choropleth, e.g. mean MedianAQI per state) AND
`DataVariables` (the per-member bars drawn on top). Implementation: stop zeroing `has_choro` for
the ladder; keep bar colors as member identity (`lines`) but re-check bar/label contrast against a
colored (parula) tile instead of gray; the legend then carries two encodings (colorbar = fill mean;
bar colors = members) — label which is which, without over-claiming. Surfaced from a real attempt:
`de_statebins(AQI, StateCol="State", CellRenderer="value_ladder", ValueCols=cols, ColorCol="MedianAQI")`
— the `ColorCol` was silently dropped.

## Open questions
- Clean rename vs deprecation aliases for the old option names (recipe text + test churn).
- How far: just value+method, or full `heatmap`-signature parity.
- Interaction with the "complain" plan — renamed options change its consumed-sets; do them together or
  sequence B-before-A to avoid reworking A's option lists.

## Verification
Method coverage tests (mean/count/median/sum produce expected aggregates); rename tests; recipe-smoke
green; recipes contain the native `groupsummary`/`pivot` step; checkcode; README/CLAUDE updated.
