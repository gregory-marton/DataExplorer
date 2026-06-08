# Signal-aware interestingness ranker — Plan

> **Status:** captured 2026-06-08 (moved out of CLAUDE.md "Task 6"); **not yet prioritized / not
> started.** Design-level; per-task `- [ ]` checkboxes to be added when picked up.
> **Related:** [2026-06-08-gmm-outlier-detection.md] (shares `de_select_columns`); the ranker also
> feeds the geo/drilldown figure-prioritization (CLAUDE.md Task 3).
> **Note on names:** original text said `se_select_columns` (line 1832); current code is
> `de_select_columns` — verify the current location at implementation time.

**Goal:** Replace the column interestingness ranker so it measures whether a column carries *signal*
(stratifies the data) rather than mere marginal spread/diversity.

## Context (from CLAUDE.md Task 6)
Current ranker: numeric score = `std/range`; categorical score = Shannon entropy.

**Known issues:**
- `std/range` is outlier-sensitive (one extreme inflates range, suppressing the score) and misses
  bimodality and heavy tails.
- Shannon entropy measures marginal diversity, not signal — high entropy can be noise (free-text or
  high-cardinality code columns). What matters is whether grouping by the column *explains* something.
- Correlation pruning threshold (0.92) is high and Pearson-only (misses monotone-nonlinear relations).

## Approach (sketch — design before implementing)
- **Categorical → ANOVA F-statistic** (`f_oneway` equivalent): how much grouping by this column
  explains variance in the numeric columns. Fall back to **normalized entropy**
  (`entropy / log2(cardinality)`) when there are no numeric columns. (Compute F without the Stats
  toolbox if needed.)
- **Numeric → an outlier-robust, shape-aware measure** instead of `std/range`: e.g. a robust
  dispersion (MAD/IQR-based) plus sensitivity to bimodality/heavy tails (e.g. a dip-test or
  kurtosis signal). Exact metric TBD.
- **Correlation pruning:** lower the 0.92 threshold and add a rank/monotone correlation (Spearman)
  alongside Pearson to catch monotone-nonlinear families.
- **Drive by concrete bad examples**, not theory — collect columns the current ranker mis-ranks
  (from real example datasets) and use them as the test cases.

## File map (tentative)
| Action | File | Purpose |
|--------|------|---------|
| Modify | `de_select_columns.m` (or wherever the ranker now lives) | replace numeric + categorical scores; correlation pruning |
| Modify | `tests/test_DataExplorer.m` | synthetic stratifying-vs-noise columns rank as expected; the gathered bad examples |

## Open questions
Exact numeric replacement metric (robust spread vs explicit bimodality test); ANOVA F without the
Stats toolbox; new correlation threshold + Spearman addition; needs a concrete bad-example corpus first.

## Verification
On the gathered mis-ranked examples, the new ranker puts genuinely stratifying/structured columns
above noisy high-entropy or single-outlier columns; unit tests with synthetic "stratifies a numeric"
vs "pure noise" columns; existing column-selection tests still pass; recipe-smoke green.
