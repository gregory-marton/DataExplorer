# Multi-dimensional outlier detection + sentinel surfacing — Plan

> **Status:** captured 2026-06-08 (moved out of CLAUDE.md "Task 4"); **not yet prioritized / not
> started.** Design-level; per-task `- [ ]` checkboxes to be added when picked up.
> **Related:** [2026-06-08-interestingness-ranker.md] (shares `de_select_columns` column selection),
> [2026-06-08-validate-argument-bounds.md] / [2026-06-08-complain-ignored-options.md] ("never silent").
> **Note on names:** the original text referenced `se_profile`/`se_select_columns` and "Phase 6 in
> DataExplorer"; current code uses `de_profile`/`de_select_columns` and the recipe-as-primitive
> pipeline (no `se_plot`). Verify current names/locations at implementation time.

**Goal:** Surface the rows that are *jointly* unusual across several numeric columns (not just
extreme in one), attribute each surprise to specific variables, and flag likely numeric **sentinel**
values — always with a printed, reversible recode (never silent).

## Context (from CLAUDE.md Task 4)
`de_profile` deliberately does **not** do numeric sentinel replacement (the -999/-9999 heuristic was
removed); text sentinels ("N/A", "NULL", …) are handled by `MissingStrings` before numeric
conversion. The outlier-detection pass is the right place to surface candidate *numeric* sentinels:
values that are far AND repeated should be auto-recoded to missing — but the recode **must be
printed** so the user can review/undo. Safety net rationale: some legitimate extremes are
indistinguishable from sentinels by value alone (e.g. 0 or -1 as satellite dry mass at launch), so
the printout, not silent removal, is the contract.

## Approach (sketch — design before implementing)
1. **GMM outliers.** Fit a small GMM (k=3–5, `fitgmdist`) on the densest numeric columns (cap ~10,
   reuse `de_select_columns`). Pre-filter rows already flagged mostly-missing by `de_profile`. Rank
   rows by log-likelihood; lowest = multi-dimensional outliers. **Attribution:** per-variable
   distance from the nearest cluster centroid → name which variables drive each row's surprise.
   Output: ranked top ~20 surprising rows with variable-level attribution (printed table).
2. **Sentinel surfacing.** Detect values that are **far AND repeated** as univariate outliers →
   candidate sentinels; auto-recode to missing, **print** each recode (value, column, count) for
   review/undo. Never silent.
3. **Integration.** Fires when ≥3 numeric columns and ≥50 non-missing rows exist; skip silently
   otherwise. In the current architecture, expose as a `de_*` library function and emit it in the
   recipe (so it's reproducible/teachable), rather than the old "Phase 6 in se_plot."
4. **Toolbox.** `fitgmdist` needs the Statistics & ML Toolbox — degrade gracefully when absent
   (skip, or a toolbox-free Mahalanobis-distance fallback), consistent with the rest of the codebase.

## File map (tentative)
| Action | File | Purpose |
|--------|------|---------|
| Create | `de_outliers.m` | GMM fit + log-likelihood ranking + per-variable attribution (graceful degrade) |
| Create | `de_sentinel_scan.m` | far+repeated univariate sentinel candidates; returns recodes to print |
| Modify | `DataExplorer.m` | `cg_outliers_code` generator; wire into `se_assemble_recipe`; gate (≥3 num, ≥50 rows) |
| Modify | `tests/test_DataExplorer.m` | planted-outlier / planted-sentinel tests |

## Open questions
Stats-toolbox dependency vs a base-MATLAB fallback; exact "far AND repeated" sentinel thresholds;
console table vs recipe-emitted code (or both); how aggressive the auto-recode should be; print format.

## Verification
Synthetic data with planted multi-dim outliers and planted sentinels: top-N includes the planted
rows; attribution names the right variable(s); each sentinel recode is printed; recipe-smoke stays
green; the pass skips cleanly with <3 numeric columns and without the Stats toolbox.
