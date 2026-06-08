# Filter during read (predicate sampling) — Plan

> **Status:** captured 2026-06-08 from a design session; **not yet prioritized / not started.**
> Design-level; per-task `- [ ]` checkboxes to be added when picked up.
> **Related:** [2026-06-08-native-grouping-api.md] (the predicate is the same `rowfilter`/logical-indexing
> idiom), [2026-06-08-complain-ignored-options.md] (the NetCDF range filters it touches are a silent-ignore site).

**Goal:** Support filtering to a subpopulation *during* the streaming read, so the sample is drawn from
matching rows — not a sample of everything that's mostly irrelevant.

## Context
For a big file like the EPA AQI data, a user often wants one subpopulation
(`T.ParameterName == "PM2.5 - Local Conditions"`). Doing it student-side *after* load is
sample-then-filter: a 50k reservoir sample of an 8M-row file, then filtered to a ~5% parameter, leaves
~2.5k usable rows. **Filter-then-sample** (apply the predicate during the read, sample only matching rows)
yields ~50k *matching* rows. The same issue already bites the NetCDF range filters, applied post-sample
(`de_stride_sample` lines 282-301), which shrink the result below `MaxRows`.

## File map
| Action | File | Purpose |
|--------|------|---------|
| Modify | `de_reservoir_sample.m` | `Where`/`RowFilter` predicate; filter each chunk right after `chunk = read(ds)` (line ~98) so only matching rows enter the reservoir |
| Modify | `de_stride_sample.m` | predicate for the tabular path (rethink the stride estimate — see below); for NetCDF, apply Lat/Lon ranges at READ via `start`/`count` instead of post-sample |
| Modify | `de_load.m` | accept the predicate and forward to the sampler (or apply after a full read for small files); profile the filtered sample |
| Modify | `DataExplorer.m` | expose `Where=`; emit the filter in the recipe |
| Modify | `tests/test_DataExplorer.m` | predicate cuts a synthetic CSV to the subpopulation; sample size reflects matches |

## Approach (sketch — design before implementing)
- **Reservoir** is the natural fit: filter the chunk before the reservoir loop → uniform sample of the
  subpopulation.
- **Stride (tabular):** the file-size stride estimate (line ~100-101) assumes all rows match; with a
  predicate the match count is unknown, so the stride must be rethought (stride over matches, first-N
  matches, or a count pass). Prefer reservoir for filtered sampling.
- **NetCDF:** a general value predicate doesn't map to a grid; the analog is coordinate ranges (already
  present but post-sample) — apply them at read via `start`/`count`.

## Open questions
- **Predicate form:** function handle on a chunk table (`@(C) C.ParameterName=="…"`, mirrors logical
  indexing — transferable) vs a `rowfilter` object (most native, but tabulartext datastores may not accept
  `rowfilter` directly) vs a `col=value` spec. Likely: accept a function handle, maybe also `rowfilter`.
- **Read-time typing:** chunks arrive as `%q` strings, so string-column predicates work directly but
  numeric predicates need `str2double` inside the predicate (or convert the chunk first — costlier). Decide/document.
- **Recipe:** emit the filter explicitly (`de_reservoir_sample(file, 50000, Where=@(C) …)` or a post-load
  `T = T(T.ParameterName=="…",:)`) so it's self-teaching.

## Verification
Predicate cuts a synthetic CSV to the matching subpopulation and the sample size reflects matches (not the
whole file); reservoir uniformity over matches; recipe-smoke green; the emitted recipe contains the filter step.
