# DataExplorer

A MATLAB utility for rapid, forgiving exploration of mixed-type tabular datasets.
Point it at a file and it loads, profiles, and visualises — no
configuration required. It also encourages and attempts to support low-code
tinkering from there by showing the recipes that it uses and providing
a toolbox of quick visualization functions.

## Quick start

```matlab
Just open DataExplorer and click Run. Navigate to your file, and
examine the results. Make sure to examine the recipe that got printed
to console for how to reproduce those results yourself.

% Add the folder to your path, then:
T = DataExplorer('mydata.csv')
T = DataExplorer('survey.xlsx')  % prompts to pick a sheet.
T = DataExplorer('climate.nc')
T = DataExplorer('archive.zip')   % prompts to pick a file.

% Or explore a table you already have:
T = DataExplorer(T_existing)

% Limit rows / columns for speed:
T = DataExplorer('bigfile.csv', MaxRows=10000, MaxVars=8)
T = DataExplorer('data.xlsx', Columns={'State','Year','Value'})

% Outputs are [T, prof, recipe].  Asking for the recipe (the 3rd output) hands
% you the generated code WITHOUT running it — no figures.  Plain calls still plot:
T                 = DataExplorer('mydata.csv');   % loads, profiles, and plots
[T, prof]         = DataExplorer('mydata.csv');   % …plus the profile struct
[T, prof, recipe] = DataExplorer('mydata.csv');   % the code only — no plots
% recipe is a string array (one line per element):
disp(recipe(1:5))                                  % peek at the first lines
```

After the run, the console shows a copy-pasteable MATLAB script that reproduces
everything DataExplorer just did — the same code returned as `recipe` above.
Save it with `save_recipe` — pass the returned `recipe` (preferred), or call it
bare to grab the most recent run's recipe from the temp directory:

```matlab
[T, prof, recipe] = DataExplorer('mydata.csv');
save_recipe('my_analysis.m', recipe);   % preferred — writes exactly this recipe
save_recipe('my_analysis.m')            % fallback — most recent run's recipe
```

## What it does

DataExplorer runs a four-step pipeline:

| Step | What happens |
|------|-------------|
| **Load** | Auto-detects CSV/TSV/TXT, Excel (multi-sheet), ZIP, NetCDF, ASC fixed-width |
| **Profile** | Classifies columns, converts strings to numbers where ≥ 70% parse, flags IDs and mostly-missing columns |
| **Echo** | Prints a self-contained MATLAB script to the console |
| **Show** | Overview tiles, time series, geographic maps, pairplot / scatter matrix |

Plots produced include:

- **Overview** — paginated 4 × 2 grid of per-variable diagnostic tiles
- **Time series** — overlaid lines and stacked-area views; detects year-columns and datetime columns automatically
- **Geographic** — US state / world tile choropleths (`de_statebins`, `de_countrybins`) and lat/lon scatter maps. A single-variable map is shown *stratified* by a categorical (a state × level heatmap) when one explains the values — a bare per-region mean mixes sub-populations — and a small red caveat flags any mean that stays confounded
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
| `de_load(file, ...)` | Load CSV/TSV/TXT/Excel/ZIP and profile it → `[T, prof]`; the shared loader |
| `de_profile(T)` | Profile a table: classify columns, recode missing values, convert types |
| `de_overview(T, prof)` | Paginated per-variable diagnostic tile grid |
| `de_pairplot(T, prof, sel)` | Type-aware scatter matrix for the selected columns |
| `de_histogram(x, name)` | Publication-quality histogram with KDE and summary stats |
| `de_statebins(T, ...)` | US state tile choropleth (no Mapping Toolbox required) |
| `de_countrybins(T, ...)` | World tile choropleth |
| `de_geobins(T, ...)` | Tile choropleth for any region/grid (the engine behind the two above) |
| `de_geoscatter(lon, lat, color, size, ...)` | Lat/lon scatter map (color + size encode values) |
| `de_variance_explained(x, g)` | One-way ANOVA η²: how strongly categorical `g` stratifies numeric `x` |
| `de_pick_stratifier(T, prof, ...)` | Weighted-random pick of a categorical to stratify a numeric by |
| `de_pivot_wide_years(T, yr_cols)` | Pivot wide year-columns to long format |
| `de_reservoir_sample(file, n)` | Random reservoir sample from a large file |
| `de_stride_sample(file, ...)` | Deterministic stride sample; supports NetCDF |

## Design principles

DataExplorer makes a lot of automatic choices. These are the rules behind them —
useful when extending it or interpreting its output.

- **Forgiving by default.** Heuristics are deliberately lenient: a string column
  becomes numeric if ≥ 70 % of values parse; ~20 missing-value sentinels (`N/A`,
  `NULL`, `-`, …) are recognised; delimiters and header rows are sniffed. Preserve
  this tolerance when changing the profiler.
- **Classify by meaning, not just storage type.** Beyond numeric / categorical /
  datetime, columns get a semantic *role* — `measure`, `identifier`, `temporal`, or
  `geographic` — and the role, not the storage type, drives what gets plotted. See
  *How types and roles are identified* below.
- **Group related variables by correlation, not by name.** Families of related
  measures (e.g. mean, standard deviation, and a ladder of percentiles) are found
  with rank (Spearman) correlation and complete-linkage clustering — language-
  agnostic, so it works regardless of naming. A family collapses to a single
  representative in the pairplot and choropleths, plus one combined figure.
- **Choose scales from the data.** Strongly right-skewed positive variables switch
  to log automatically (semi-log vs log-log decided from the count spread); mixed-
  sign skewed variables use a symmetric-log transform. Log usage is always made
  visually obvious (distinct bar colour + a corner badge), never silent.
- **No interactive widgets in plots.** Time is encoded as a visual axis — a heatmap
  x-axis or a per-tile sparkline — never a slider. Everything renders to a static
  figure a recipe can reproduce.
- **Geographic detection validates values, not just names.** A column is treated as
  a map key only when its values actually match a known grid's vocabulary.
- **Information-dense but readable.** Axes carry units where known; central
  tendencies carry bootstrapped confidence bands; axis limits are shared across
  small multiples so patches are comparable; cardinalities are shown.
- **Prompts are rare and intentional.** Only genuinely ambiguous cases (multi-file
  ZIP, multi-sheet Excel) ask. Don't add prompts without a clear need.
- **Fast by default; signal when slow.** The core pipeline should produce something
  useful within a minute or two. Anything slower prints a message first and shows a
  single-line progress indicator — never block silently.

## How types and roles are identified

Classification is the heart of DataExplorer, and it rests on a few principles
rather than any single rule.

- **Prefer several converging signals over one brittle test.** No lone heuristic
  decides a column. Language-dependent signals (matching English keywords in a name)
  are used only as a *fallback* to language-agnostic ones (the shape of the values,
  their statistics) — names are the least reliable evidence.
- **Resolve storage type first, meaning second.** A column is first settled into a
  storage type (numeric, categorical, datetime, logical), then given a semantic
  *role* on top — `measure`, `identifier`, `temporal`, or `geographic`. The role is
  what steers the visualisations.

**Numbers vs. codes.** A text column that mostly parses as numbers is *usually* a
measure — but not always. Leading zeros (`01`, `003`) betray a code that merely
looks numeric; that value-shape signal is language-agnostic and wins. A name whose
final token is *code*, *id*, *num*, or *number* also marks an identifier
(tokenization is CamelCase-aware, because `readtable` turns `State Code` into
`StateCode`). All-unique values are a third identifier tell. Identifiers are kept
out of correlation plots and choropleths, where they would only add noise.

**Temporal.** Time arrives in three guises, all recognised: a real
`datetime`/`duration` column; a text column whose values *look* like dates (date
separators or month names) and parse cleanly, which is converted to `datetime`; and
a numeric or wide-layout column named for a time unit. Real datetime objects are
preferred so plots get proper time axes.

**Geographic.** Geography, too, comes in more than one form, treated as one family
of signals: **latitude/longitude pairs** — recognised by name, kept together, and
fed to the scatter map — and **place columns** (state or country codes/names),
recognised by matching the column's *actual values* against a known place
vocabulary, not the name alone. (A consequence and current soft spot: a `StateCode`
of FIPS numbers a grid can't resolve should fall back to a sibling name column —
value-matching is the right principle, the vocabularies just need to grow.)

**Relationships between columns.** Beyond single-column roles, DataExplorer looks
for *families* of related measures — say a mean, a standard deviation, and a ladder
of percentiles all describing one quantity. These are found by **rank correlation**,
which is language-agnostic and robust to monotone nonlinearity, so it never depends
on the columns being named alike. A family collapses to one representative across
the analysis, plus a single combined figure, instead of a dozen near-duplicates.

**Forgiving, but never silent.** Where DataExplorer auto-corrects — recoding a
missing sentinel, choosing a log scale, collapsing a family — it does so to give a
useful first result with minimal input, but it *reports every such choice* (in the
console profile and on the figures) so you can see it and override it.

## Architecture & implementation principles

- **Everything is reachable through the recipe (top-level design choice).** Every
  visualisation DataExplorer can produce must appear in the generated recipe — there
  are no direct-render-only paths. This does double duty: the recipe is how a user
  *discovers* what was done and edits it, and it cleanly separates two things that
  should be tested apart — the *policy* of when a plot is appropriate (decided by the
  recipe assembler) from whether the *plot tool itself* draws correctly (the `de_*`
  function). Add a plot by wiring it into the assembler **and** writing its `de_*`
  function; never by adding a side path that bypasses the recipe.
- **Code generation is the primitive; execution is a side effect.** DataExplorer
  assembles a complete, self-contained MATLAB *recipe* (load + clean + every plot)
  and runs it with `eval`. The recipe — not a hidden render path — is the source of
  truth, which is why `save_recipe` produces something that runs standalone with
  only the `de_*` library on the path. When adding or changing a visualisation,
  wire it into the recipe assembler (`se_assemble_recipe` and the `cg_*` code
  generators) and the standalone `de_*` function it calls.
- **The `de_*` files are the library; `DataExplorer.m` orchestrates.** Reusable
  capability lives in standalone `de_*.m` files so both the recipe and a human can
  call them directly.
- **The recipe is a teaching scaffold, and it speaks the library.** Recipes call the
  `de_*` functions rather than emitting verbose vanilla MATLAB. The trade is a small
  dependency in exchange for code a student can actually read, learn a reusable
  vocabulary from, and edit — with sensible defaults (alpha blending, shared axis
  limits, confidence bands) baked into the calls instead of forgotten.
- **Complexity belongs in the generator; the recipe stays flat and editable.** The
  `cg_*` code generators may do arbitrarily clever analysis to *decide* what to emit,
  but what they emit should be a handful of plain library calls plus the *structure*
  exposed as editable variables — e.g. a correlated family becomes
  `fam_cols = {...}; de_pairplot(T, prof, fam_cols); de_statebins(..., 'ValueCols',fam_cols)`,
  not a single opaque call that hides the column list. A new single-purpose wrapper
  that exists only to shorten the recipe is a smell: it moves the decision out of the
  student's reach. Prefer composing existing `de_*` calls
  around a named variable the student can see and change. Add a library function only
  when it is genuinely reusable capability, not recipe sugar.
- **Toolbox-free core.** Every `de_*` function must run on base MATLAB. The
  Statistics and Mapping toolboxes are optional enhancements; degrade gracefully
  (e.g. compute Spearman via manual ranking + `corrcoef`, not `corr`).
- **Strings, not chars.** Use the MATLAB `string` type throughout; convert to `char`
  only at an API boundary that requires it.
- **No silent shims.** No version-compatibility guards or empty `catch` blocks that
  swallow errors. A `try/catch` for a genuine edge case must still surface what
  happened.
- **Parse names robustly.** Column names arrive in many forms; `readtable` turns
  `"State Code"` into CamelCase `StateCode`. MATLAB's `regexp(…, 'split')` does
  **not** split on zero-width boundaries, so CamelCase won't tokenize that way — use
  `de_name_tokens` for any name-based heuristic.

## Testing discipline

Hard-won, in roughly the order they bit us:

- **Test-first, red-green.** Write the failing test, watch it fail for the right
  reason, then implement. No batching fixes ahead of tests.
- **`checkcode`-green is not "working."** The fast lint tier catches syntax, not
  behaviour. Behavioural checks — does the recipe exclude id columns? does it run
  without crashing? — belong in a **gating smoke test**
  (`tests/test_recipe_smoke.py`), which generates *and executes* a recipe from a
  tiny synthetic dataset. Recipe generation is cheap, so there is no excuse to
  defer it to the slow tier.
- **Tests must use real input forms.** A regression test for id-column handling
  that uses `State_Code` (snake_case) misses the bug that only appears with
  `StateCode` (what `readtable` actually produces). Reproduce the real shape of the
  data.
- **Run the behavioural test before claiming done**, not just the linter.
- **Prefer scripts to shell one-liners.** Recurring analysis or search goes in
  `scripts/` (e.g. `inspect_corr.py`, `list_funcs.py`) so it is reusable and a
  human can run it too.
- **Chesterton's fence.** When extracting or refactoring `de_*` behaviour, match the
  original exactly unless you understand why a decision was made.
- **No student PII, ever.** This is a teaching tool that handles student data. Never
  put real student names — or any student-identifying information — in code, tests,
  comments, docstrings, or examples. Use clearly fictional names (Alice Apple,
  Beatrice Beachball).

## Roadmap / vision

- **A browser variant.** A JavaScript port deployable to GitHub Pages — zero
  install, runs entirely client-side (file reading in the browser, no server). The
  same load → profile → echo → show pipeline, with the recipe becoming a
  self-contained HTML file the student edits. The leaning is toward [Observable Plot](https://observablehq.com/plot/)
  (a lighter spiritual successor to D3) for the generated charts.
- **One mental model across languages.** Whatever the host (MATLAB today, JS and
  potentially Python later), the contract stays the same: load → profile → echo a
  readable recipe → show. The recipe is the portable, editable artifact in every
  variant.
- **Deeper automated analysis** (concrete plans in `docs/superpowers/plans/`):
  - *Multi-dimensional outlier detection + sentinel surfacing* — fit a small GMM over the
    densest numeric columns, rank rows by likelihood, attribute each surprise to specific
    variables, and flag likely numeric sentinel values (far + repeated) with a printed,
    reversible recode.
  - *A signal-aware interestingness ranker* — rank columns by whether they actually
    *stratify* the data (ANOVA F for categoricals; outlier-robust, bimodality-aware spread
    for numerics) rather than by raw spread or entropy.

## Requirements

- **MATLAB R2025b (25.2) or later**
- **Statistics and Machine Learning Toolbox** — optional; enables violin plots
- **Mapping Toolbox** — optional; used only by `de_usamap` (teaching demo)

All core functionality runs without optional toolboxes.

## File formats supported

| Format | Notes |
|--------|-------|
| CSV / TSV / TXT | Delimiter auto-detected; header sniffed |
| Excel (`.xlsx`, `.xls`, `.xlsm`) | Multi-sheet detection; prompts when ambiguous |
| ZIP | Extracts and loads the relevant file inside |
| NetCDF (`.nc`, `.nc4`) | Variables sharing a grid load together as columns of one table; otherwise pick one (see below) |
| ASC fixed-width | BRFSS-style fixed-width text |

### NetCDF: conformable or ask

Data variables that share a coordinate grid (e.g. `temp` and `prcp`, both on
`lon × lat × time`) are **conformable**: they are stride-sampled identically and
combined into a single table — coordinate columns plus one column per variable.
This keeps cross-variable analysis (pairplots, correlations, gridded mean/std
maps) working across all of them.

When a file mixes differently-shaped variables, it is treated exactly like a
multi-sheet workbook or a multi-file ZIP — **pick one**:

- `NCVariable='name'` loads that variable's conformable group;
- `AutoSelect=true` picks the largest group;
- otherwise DataExplorer lists the variables (with their dimensions) and asks.

> **Future work — multi-table sources.** Loading *several* Excel sheets / ZIP
> CSVs / non-conformable NetCDF variables *together* (as an array of tables,
> exploring each) is a deliberate future direction, not yet supported. Today every
> source resolves to a single table ("conformable or ask").
