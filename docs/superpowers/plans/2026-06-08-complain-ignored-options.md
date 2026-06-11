# Complain, don't silently ignore options — Plan

> **Status:** **CORE DONE 2026-06-08.** Implemented in `de_tilegrid`: (1) `de_tilegrid:ignoredOptions`
> warns when a non-default discriminating option (ColorCol/TimeCol/CatCol/ValueCols/XCol/YCol/
> SharedXLim/SharedYLim/CatColors) isn't used by the active renderer — e.g. `ColorCol` passed to
> `value_ladder`; (2) `de_tilegrid:valueLadderNeeds2` warns on the silent <2-ValueCols fallback.
> Helper `tg_ignored_options` + per-renderer consumed-sets. 4 unit tests (incl. verifyWarningFree)
> + checkcode + recipe-smoke green (no over-warning on real recipes).
> **flat-stratification DONE 2026-06-09:** `de_tilegrid:flatStratification` warns when heatmap_cat
> category levels barely change the value (the PM25-by-PollutantStandard case) or there is only one
> level — recipe-safe, since the recipe only emits non-flat stratifiers (de_pick_stratifier chooses
> one with signal). **GeoCol-not-found message DONE:** de_geobins names the missing column + suggests
> the closest real one (`gb_closest`). **degenerate-TimeCol SKIPPED (on purpose):** a single distinct
> time value is indistinguishable from legitimate single-period data (the cad3bda single-year recipe),
> so warning would over-fire and break the warning-free recipe gate — not worth the false positives.
> **Instead, single-period LABELING (DONE 2026-06-09):** when TimeCol collapses to one value, the
> title and colorbar state the period (e.g. `mean(MedianAQI), 2025`) and the axis is skipped — time is
> shown as a label, signalling it's supported, rather than faked as an axis or flagged as an error.
> **REMAINING (low value):** de_countrybins FontSize/GridFile override notices, de_overview
> MaxVars-truncation notice, de_plot_categorical_drilldown truncation notice.
>
> **Loader-option audit (REDONE 2026-06-11):** the original scan only audited `de_tilegrid`
> *renderer* options and MISSED `de_load` entirely — format-specific loader options were silently
> ignored when passed to the wrong format (the reported case: `VariableNamesRange="A8:L8"` on a CSV
> did nothing). Fixed: `de_load` now warns `DataExplorer:ignoredLoadOptions` when a format-specific
> option can't be used (VariableNamesRange/DataRange/Sheet → non-Excel; InnerFile → non-zip;
> NCVariable → non-nc; VariableNamesLine/DataLines → non-text), with a hint pointing text users at
> VariableNamesLine/DataLines. AND the text path now actually *supports* a non-row-1 header
> (VariableNamesLine/DataLines + auto-guess past preamble — separate commit). Lesson: option-support
> audits must cover the LOADER surface, not just renderers.
> **Related:** [2026-06-08-native-grouping-api.md] (renames the very options this plan
> warns about — coordinate the consumed-sets), [2026-06-08-filter-during-read.md].

**Goal:** Make DataExplorer's plot/load functions *warn* when a user-set option can't be
honored or isn't used by the active mode, instead of silently ignoring it. User directive:
**"if you can't use an option, complain."**

## Context
`de_tilegrid` (via `de_statebins`/`de_countrybins`/`de_geobins`) accepts a broad option set,
but each `CellRenderer` consumes only a subset and **silently ignores the rest**, and several
degenerate cases silently fall back. Motivating episode: a `heatmap_cat` call on the EPA
annual-conc data rendered as a plain choropleth with no explanation — verified cause: the 4
`PollutantStandard` levels all share the same `ArithmeticMean` (the "standard" is a regulatory
threshold, not a distinct measurement), so the bands are identical ("flat stratification"). A
codebase scan found ~15 silent-ignore/fallback sites; `de_tilegrid` is the worst (~7).

## Approach
Warn (not error — the tool is forgiving) only about *explicitly user-set (non-default)* options
the active mode/data can't honor; stay quiet for defaults and documented `auto`/threshold
behavior. New helper `de__warn_ignored.m` →
`warning('<fn>:ignoredOptions','CellRenderer="%s" ignores: %s', mode, strjoin(ignored,', '))`.
Non-default detection: string `~=""`; `ValueCols` `~isempty`; `SharedX/YLim` `~all(isnan)`; etc.
Use stable warning ids so they're suppressible/greppable.

## File map
| Action | File | Purpose |
|--------|------|---------|
| Create | `de__warn_ignored.m` | shared "these options were ignored" warning helper |
| Modify | `de_tilegrid.m` | per-renderer consumed-sets + the 4 warnings below |
| Modify | `de_countrybins.m`, `de_overview.m`, `de_plot_categorical_drilldown.m`, `de_stride_sample.m` | secondary sweep (verify each first) |
| Modify | `tests/test_DataExplorer.m` | `verifyWarning` / `verifyWarningFree` |

## Primary target — de_tilegrid.m (verified, ~7 cases)
1. **Ignored-option warning** per renderer. Consumed sets:
   - `color`: ColorCol, TimeCol, Scale, CLim, Colormap
   - `heatmap_cat`: CatCol, ColorCol, TimeCol, TopK, SharedYLim, Colormap, CLim
   - `scatter_cat`: CatCol, XCol, YCol, TopK, SharedXLim, SharedYLim, CatColors
   - `value_ladder`: ValueCols, SharedYLim, Scale
2. **`value_ladder` with <2 `ValueCols`** (gate ~line 101-102) → `de_tilegrid:valueLadderNeeds2` + fallback note.
3. **`heatmap_cat`/sparkline with a collapsing TimeCol** (`has_time` true but `n_t<=1`) → `de_tilegrid:degenerateTime`.
4. **Flat stratification** — reuse `multi_heat` to detect per-tile spread ≈ 0 across category levels (or `K==1`) → `de_tilegrid:flatStratification` (the PM25 case).

## Secondary — verified sweep (confirm each against current code; the scan agent is NOT authoritative)
- `de_countrybins.m` — hardcoded `FontSize` override; legacy `GridFile=""` fallback.
- `de_overview.m` — silent `MaxVars` truncation (mirror `de_pairplot`'s existing warning).
- `de_plot_categorical_drilldown.m` — silent column truncation / geo fallback.
- `de_stride_sample.m` — **confirmed**: `LatRange`/`LonRange`/`TimeRange` are NetCDF-only and silently ignored for tabular files (lines ~25-27, 282-301).
- `de_usamap.m` — TimeCol-collapse → no slider (teaching demo; low priority).
- **OUT** (intended behavior, not silent-ignore): `de_timeseries Compositional="auto"`,
  `de_pick_stratifier` empty return, `de_plot_cat_association V_Thresh`, `de_pairplot` all-missing tile.

## Verification
`verifyWarning`/`verifyWarningFree` red-green for each case; **`tests/test_recipe_smoke.py` must stay
warning-free** (proves the consumed-sets are right and we don't over-warn). Plus checkcode + the new
unit tests via the pytest harness.
