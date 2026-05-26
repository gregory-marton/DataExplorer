# NetCDF Spatial Grid Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hanging `mean(ncread(...))` path for large NetCDF spatial grids with stride sampling (`SampleNetCDF`) and a dedicated geo scatter visualization (`de_geoscatter`), while fixing fast-path control flow bugs.

**Architecture:** A new `nc_is_spatial_grid` heuristic in DataExplorer.m routes variables whose dimensions include a lat-like and a lon-like name to a dedicated path: `SampleNetCDF` reads the data using `ncread`'s native stride argument (never loading the full array), and `de_geoscatter` plots it with color encoding time and point size encoding the variable's value. The existing tabular path handles all other NetCDF variables unchanged. A compact recipe is written to `/tmp/` via a new `cg_netcdf_spatial_recipe` local function, calling the same public `SampleNetCDF` and `de_geoscatter` functions so students can re-use them with different inputs.

**Tech Stack:** MATLAB, `ncread`/`ncinfo`/`nccreate`/`ncwrite`, `scatter`, `matlab.unittest`, pytest harness

**Out of scope (future plan):** Spatial/temporal pairplot decomposition for variable pairs (collapse-one/overlay-other). Categorical drill-down enhancements that generalise the same pattern.

---

## Background: Codebase orientation

- **`DataExplorer.m`** — 4110-line monolith. All local functions at the bottom. NetCDF fast-path at lines 70–110; `load_netcdf` at ~line 580; `nc_list_data_vars` at ~line 821.
- **`de_*.m` files** — standalone library functions exposed in recipes: `de_statebins.m`, `de_tilegrid.m`, `de_histogram.m`, `de_profile.m`, `de_geoscatter.m` (new).
- **`SampleData.m`** — reservoir sampling for text files. `SampleNetCDF.m` follows its API pattern.
- **`tests/test_DataExplorer.m`** — `matlab.unittest.TestCase` subclass. Tests tagged `@TestTags({'slow'})` run via `pytest tests/ -m slow -k <name>`. Fast smoke tests (no tag) run via `python3 -m pytest tests/ -v`.
- **Synthetic NetCDF fixtures:** use `nccreate`/`ncwrite` to build temp files in tests. See `test_load_netcdf_with_ncvariable_no_prompt` (line 1519) for the established pattern.
- **Test discipline:** add all new tests permanently to `tests/test_DataExplorer.m`. Never delete them.
- **String vs char:** prefer MATLAB `string` type throughout; convert to `char` only where an API requires it.

---

## File structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `de_geoscatter.m` | Library: geo scatter, color=any variable, size=any variable |
| Create | `SampleNetCDF.m` | Stride-sampled table from a 3D gridded NetCDF variable |
| Modify | `DataExplorer.m` | Fast-path routing, `nc_is_spatial_grid`, `cg_netcdf_spatial_recipe`, raw='2' fix |
| Modify | `tests/test_DataExplorer.m` | Tests for all of the above |

---

## Task 1: Fix fast-path control flow and raw='1' fallback

**Files:**
- Modify: `DataExplorer.m` lines ~85–90 (catch block) and ~711–726 (heuristic raw choice) and ~782–792 (ival resolution)

**The bugs:**
1. `catch ME_` at line 87 catches `MATLAB:interrupt` (Ctrl+C) and silently loops — so every stop creates another hang.
2. The heuristic at line 724 sets `raw='1'` (mean, reads entire array) for large variables — hangs for multi-GB files. Fix: use `raw='2'` (single middle slice), which reads only `lon × lat × 1` elements.
3. The ival-resolution `while true` loop at line 782 lacks a branch for the NCVariable case — falls through to interactive `input()`.

- [ ] **Step 1: Write failing test**

Add inside the `methods (Test, TestTags={'slow'})` block of `tests/test_DataExplorer.m`:

```matlab
function test_load_netcdf_large_3d_uses_slice_not_mean(testCase)
    % A 3D variable larger than MaxRows×10 must load without hanging.
    % raw='1' (mean over full array) hangs; raw='2' (middle slice) reads lon×lat only.
    tmp = [tempname '.nc'];
    cl  = onCleanup(@() delete(tmp));
    nlon = 50; nlat = 40; ntime = 8;   % 16 000 elements, MaxRows=10 → 16000 >> 100
    nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
    nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
    nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
    nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
    ncwrite(tmp,'longitude', linspace(-180,180,nlon)');
    ncwrite(tmp,'latitude',  linspace(-90,90,nlat)');
    ncwrite(tmp,'time',      (1:ntime)');
    ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    % NCVariable bypasses fast-path, goes through load_netcdf heuristic.
    % MaxRows=10 forces total_elems (16000) >> MaxRows*10 (100) → heuristic fires.
    T = DataExplorer(tmp, NCVariable='prcp', MaxRows=10);
    testCase.verifyClass(T, 'table');
    testCase.verifyGreaterThan(height(T), 0);
end
```

- [ ] **Step 2: Run to verify it fails (or times out)**

```
python3 -m pytest tests/ -m slow -k test_load_netcdf_large_3d_uses_slice_not_mean -v
```
Expected: FAIL or timeout (hangs on `mean(ncread(...))`).

- [ ] **Step 3: Add auto_ival initialisation before the heuristic block**

In `DataExplorer.m`, in `load_netcdf`, just before the reduction-choice block (around line 688 where the `total_elems` fprintf is), add:

```matlab
auto_ival = 1;   % middle slice index, set by NCVariable heuristic below
```

- [ ] **Step 4: Change raw='1' to raw='2' in the heuristic block**

Find lines 724–726 (the `else` branch of the `strlength(options.NCVariable) > 0` block):

```matlab
                raw = '1';
                fprintf('  Auto: mean over "%s" (%d elements > MaxRows×10)\n', ...
                    dim_names{dim_choice}, total_elems);
```

Replace with:

```matlab
                raw = '2';
                auto_ival = ceil(sz(dim_choice) / 2);
                fprintf('  Auto: middle slice of "%s" (index %d/%d, %d elements > MaxRows×10)\n', ...
                    dim_names{dim_choice}, auto_ival, sz(dim_choice), total_elems);
```

- [ ] **Step 5: Add NCVariable branch in the ival-resolution loop (case '2' block)**

Find the `while true` loop that resolves `ival` for `case '2'` (around line 782). It currently reads:

```matlab
            while true
                if options.NCSliceIndex >= 1 && options.NCSliceIndex <= sz(dim_choice) && ...
                        (strlength(options.NCReduction) > 0 || options.AutoSelect)
                    ival = options.NCSliceIndex;
                    fprintf('  Using NCSliceIndex=%d\n', ival);
                    break;
                end
                raw2 = input('  Which index? ', 's');
```

Replace with:

```matlab
            while true
                if options.NCSliceIndex >= 1 && options.NCSliceIndex <= sz(dim_choice) && ...
                        (strlength(options.NCReduction) > 0 || options.AutoSelect)
                    ival = options.NCSliceIndex;
                    fprintf('  Using NCSliceIndex=%d\n', ival);
                    break;
                elseif strlength(options.NCVariable) > 0
                    ival = auto_ival;
                    fprintf('  Auto slice: index %d of %d\n', ival, sz(dim_choice));
                    break;
                end
                raw2 = input('  Which index? ', 's');
```

- [ ] **Step 6: Fix Ctrl+C re-throw in the fast-path catch block**

Find lines 87–90:

```matlab
                catch ME_
                    fprintf('  ⚠ Skipping "%s": %s\n', data_vars_{nc_vi_}, ME_.message);
                    continue
                end
```

Replace with:

```matlab
                catch ME_
                    if strcmp(ME_.identifier, 'MATLAB:interrupt')
                        rethrow(ME_);
                    end
                    fprintf('  ⚠ Skipping "%s": %s\n', data_vars_{nc_vi_}, ME_.message);
                    continue
                end
```

- [ ] **Step 7: Run the test to verify it passes**

```
python3 -m pytest tests/ -m slow -k test_load_netcdf_large_3d_uses_slice_not_mean -v
```
Expected: PASS.

- [ ] **Step 8: Run full fast suite**

```
python3 -m pytest tests/ -v
```
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "fix: NetCDF heuristic uses middle slice (raw='2'), re-throw Ctrl+C in fast-path"
```

---

## Task 2: de_geoscatter.m — standalone geo scatter library function

**Files:**
- Create: `de_geoscatter.m`
- Modify: `tests/test_DataExplorer.m`

Geographic scatter with no Mapping Toolbox. `color_data` → colormap + colorbar. `size_data` → marker area mapped to `[MinSize, MaxSize]` pt², with a small inset size legend. Both mappings are linear over the full data range (including negative values).

- [ ] **Step 1: Write failing fast smoke test**

Add inside `methods (Test)` (no tag — runs without MATLAB):

```matlab
function test_de_geoscatter_checkcode_clean(testCase)
    f = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'de_geoscatter.m');
    testCase.assertNotEmpty(dir(f), 'de_geoscatter.m not found');
    info = checkcode(f, '-string');
    n = numel(regexp(info, 'L \d+', 'match'));
    testCase.verifyEqual(n, 0, sprintf('checkcode found %d issue(s):\n%s', n, info));
end
```

- [ ] **Step 2: Run to verify it fails**

```
python3 -m pytest tests/ -v -k test_de_geoscatter_checkcode_clean
```
Expected: FAIL with "de_geoscatter.m not found".

- [ ] **Step 3: Write failing integration test**

Add inside `methods (Test, TestTags={'slow'})`:

```matlab
function test_de_geoscatter_produces_figure_with_colorbar_and_scatter(testCase)
    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    rng(42);
    n     = 60;
    lon_v = linspace(-120,-70,n)';
    lat_v = linspace(25,50,n)';
    t_v   = sort(randi(12,n,1));   % time index 1..12
    val_v = randn(n,1);            % signed values — size mapping must handle negatives

    [fig, ax] = de_geoscatter(lon_v, lat_v, double(t_v), val_v, ...
        ColorLabel="Month", SizeLabel="Anomaly");

    cl2 = onCleanup(@() close(fig));
    testCase.verifyTrue(isgraphics(fig, 'figure'), 'Expected a figure');
    testCase.verifyTrue(isgraphics(ax,  'axes'),   'Expected main axes');
    cb = findobj(fig, 'Type', 'colorbar');
    testCase.verifyNotEmpty(cb, 'Expected a colorbar');
    sc = findobj(fig, 'Type', 'scatter');
    testCase.verifyNotEmpty(sc, 'Expected at least one scatter object');
    % Verify colorbar label was applied
    testCase.verifyEqual(string(cb(1).Label.String), "Month");
end
```

- [ ] **Step 4: Run to verify it fails**

```
python3 -m pytest tests/ -m slow -k test_de_geoscatter_produces_figure_with_colorbar_and_scatter -v
```
Expected: FAIL with "de_geoscatter not found".

- [ ] **Step 5: Create de_geoscatter.m**

```matlab
function [fig, ax] = de_geoscatter(lon, lat, color_data, size_data, options)
%DE_GEOSCATTER  Geographic scatter: color encodes one numeric variable, size another.
%   No Mapping Toolbox required.
%
%   Usage
%   ─────
%   de_geoscatter(lon, lat, time_vals, prcp_vals)
%   de_geoscatter(lon, lat, time_vals, prcp_vals, ColorLabel="Time", SizeLabel="prcp")
%   [fig, ax] = de_geoscatter(...)
%
%   All four vector arguments must have the same length.
%   color_data is mapped linearly to parula(256).
%   size_data  is mapped linearly to marker area [MinSize, MaxSize] pt².
%   Negative values in size_data are fine — the full range is normalised.
%   A size legend is drawn in the lower-right corner showing min / mid / max values.
%
%   Optional arguments
%   ──────────────────
%   ColorLabel  ("Color")   Colorbar label.
%   SizeLabel   ("Size")    Size-legend title.
%   Title       ("")        Figure/axes title string.
%   MinSize     (20)        Minimum marker area (pt²).
%   MaxSize     (200)       Maximum marker area (pt²).

arguments
    lon        (:,1) double
    lat        (:,1) double
    color_data (:,1) double
    size_data  (:,1) double
    options.ColorLabel (1,1) string = "Color"
    options.SizeLabel  (1,1) string = "Size"
    options.Title      (1,1) string = ""
    options.MinSize    (1,1) double = 20
    options.MaxSize    (1,1) double = 200
end

%% ── Normalise size_data to [MinSize, MaxSize] ─────────────────────────────────
s_lo = min(size_data, [], 'omitnan');
s_hi = max(size_data, [], 'omitnan');
if s_hi > s_lo
    sz_norm = (size_data - s_lo) ./ (s_hi - s_lo);
else
    sz_norm = repmat(0.5, size(size_data));
end
sz_pts = options.MinSize + sz_norm .* (options.MaxSize - options.MinSize);

%% ── Main scatter ──────────────────────────────────────────────────────────────
fig = figure('Color', 'w', 'Name', 'Geo Scatter');
ax  = axes(fig, 'Position', [0.08 0.08 0.70 0.85]);

scatter(ax, lon, lat, sz_pts, color_data, 'filled', 'MarkerFaceAlpha', 0.5);
colormap(ax, parula(256));
cb              = colorbar(ax);
cb.Label.String = char(options.ColorLabel);
xlabel(ax, 'Longitude');
ylabel(ax, 'Latitude');
if strlength(options.Title) > 0
    title(ax, char(options.Title), 'Interpreter', 'none');
end
box(ax, 'on');
grid(ax, 'on');

%% ── Size legend (inset axes, lower-right corner) ─────────────────────────────
leg_ax = axes(fig, 'Position', [0.80 0.05 0.18 0.32]);
axis(leg_ax, 'off');
hold(leg_ax, 'on');

rep_vals = [s_lo, (s_lo + s_hi) / 2, s_hi];
rep_sz   = [options.MinSize, (options.MinSize + options.MaxSize) / 2, options.MaxSize];
y_pos    = [2.6, 1.6, 0.6];
for ki = 1:3
    scatter(leg_ax, 0.35, y_pos(ki), rep_sz(ki), [0.45 0.45 0.45], ...
        'filled', 'MarkerFaceAlpha', 0.6);
    text(leg_ax, 0.70, y_pos(ki), sprintf('%.3g', rep_vals(ki)), ...
        'VerticalAlignment', 'middle', 'FontSize', 7);
end
text(leg_ax, 0.35, 3.4, char(options.SizeLabel), ...
    'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 8, ...
    'Interpreter', 'none');
xlim(leg_ax, [0 1.3]);
ylim(leg_ax, [0 3.8]);
end
```

- [ ] **Step 6: Run fast smoke test**

```
python3 -m pytest tests/ -v -k test_de_geoscatter_checkcode_clean
```
Expected: PASS.

- [ ] **Step 7: Run integration test**

```
python3 -m pytest tests/ -m slow -k test_de_geoscatter_produces_figure_with_colorbar_and_scatter -v
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add de_geoscatter.m tests/test_DataExplorer.m
git commit -m "feat: add de_geoscatter library function (color + size geo scatter, no Mapping Toolbox)"
```

---

## Task 3: SampleNetCDF.m — stride-sampled table from a gridded NetCDF variable

**Files:**
- Create: `SampleNetCDF.m`
- Modify: `tests/test_DataExplorer.m`

`ncread(filepath, varname, start, count, stride)` reads only every `stride(k)`-th element along dimension k — never loads the full array. The uniform stride `s` is found by incrementing until `prod(ceil(sz/s)) ≤ MaxRows`. Output is a long-format table with columns named after the coordinate and data variables; lat-like and lon-like dim names are normalised to `latitude` / `longitude`.

- [ ] **Step 1: Write failing fast smoke test**

Add inside `methods (Test)`:

```matlab
function test_samplenetcdf_checkcode_clean(testCase)
    f = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'SampleNetCDF.m');
    testCase.assertNotEmpty(dir(f), 'SampleNetCDF.m not found');
    info = checkcode(f, '-string');
    n = numel(regexp(info, 'L \d+', 'match'));
    testCase.verifyEqual(n, 0, sprintf('checkcode found %d issue(s):\n%s', n, info));
end
```

- [ ] **Step 2: Run to verify it fails**

```
python3 -m pytest tests/ -v -k test_samplenetcdf_checkcode_clean
```
Expected: FAIL.

- [ ] **Step 3: Write failing integration tests**

Add inside `methods (Test, TestTags={'slow'})`:

```matlab
function test_samplenetcdf_returns_table_within_maxrows(testCase)
    tmp = [tempname '.nc'];
    cl  = onCleanup(@() delete(tmp));
    nlon = 30; nlat = 20; ntime = 5;
    nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
    nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
    nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
    nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
    ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
    ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
    ncwrite(tmp,'time',      (1:ntime)');
    ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

    T = SampleNetCDF(tmp, Variable='prcp', MaxRows=100, Verbose=false);
    testCase.verifyClass(T, 'table');
    % Allow slight overshoot from ceiling arithmetic
    testCase.verifyLessThanOrEqual(height(T), 120, ...
        'SampleNetCDF should not exceed MaxRows significantly');
    expected_cols = {'longitude','latitude','time','prcp'};
    for k = 1:numel(expected_cols)
        testCase.verifyTrue(ismember(expected_cols{k}, T.Properties.VariableNames), ...
            sprintf('Expected column "%s"', expected_cols{k}));
    end
end

function test_samplenetcdf_latrange_filters_rows(testCase)
    tmp = [tempname '.nc'];
    cl  = onCleanup(@() delete(tmp));
    nlon = 10; nlat = 10; ntime = 3;
    nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
    nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
    nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
    nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
    ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
    ncwrite(tmp,'latitude',  linspace(0,90,nlat)');   % 0,10,20,...,90
    ncwrite(tmp,'time',      (1:ntime)');
    ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

    T = SampleNetCDF(tmp, Variable='prcp', LatRange=[30 60], Verbose=false);
    testCase.verifyTrue(all(T.latitude >= 30 & T.latitude <= 60), ...
        'All returned rows must satisfy LatRange');
    testCase.verifyGreaterThan(height(T), 0, 'Expected some rows in LatRange [30,60]');
end

function test_samplenetcdf_auto_selects_first_data_variable(testCase)
    % When Variable is not specified, SampleNetCDF picks the first data variable.
    tmp = [tempname '.nc'];
    cl  = onCleanup(@() delete(tmp));
    nccreate(tmp,'longitude','Dimensions',{'longitude',4},'Format','classic');
    nccreate(tmp,'latitude', 'Dimensions',{'latitude', 3},'Format','classic');
    nccreate(tmp,'time',     'Dimensions',{'time',     2},'Format','classic');
    nccreate(tmp,'prcp','Dimensions',{'longitude',4,'latitude',3,'time',2},'Format','classic');
    ncwrite(tmp,'longitude', [-120;-110;-100;-90]);
    ncwrite(tmp,'latitude',  [30;40;50]);
    ncwrite(tmp,'time',      [1;2]);
    ncwrite(tmp,'prcp',      rand(4,3,2));

    T = SampleNetCDF(tmp, Verbose=false);
    testCase.verifyTrue(ismember('prcp', T.Properties.VariableNames), ...
        'Expected data variable "prcp" in output table');
end
```

- [ ] **Step 4: Run to verify they fail**

```
python3 -m pytest tests/ -m slow -k "test_samplenetcdf" -v
```
Expected: all FAIL (SampleNetCDF not found).

- [ ] **Step 5: Create SampleNetCDF.m**

```matlab
function T = SampleNetCDF(filepath, options)
%SAMPLENETCDF  Stride-sampled table from a 3D gridded NetCDF variable.
%
%   T = SampleNetCDF('climate.nc')
%   T = SampleNetCDF('climate.nc', Variable='prcp', MaxRows=5000)
%   T = SampleNetCDF('climate.nc', Variable='prcp', LatRange=[30 60], LonRange=[-100 -70])
%
%   Uses ncread's native stride argument — never loads the full array.
%   Output: long-format table with columns named after coordinate variables.
%   Lat-like and lon-like dimension names are normalised to "latitude"/"longitude".
%   Suitable for de_geoscatter or DataExplorer(T).
%
%   Variable must have exactly 3 dimensions (lon, lat, time order assumed).
%
%   Optional arguments
%   ──────────────────
%   Variable   ("")          Variable name. Empty = first data variable found.
%   MaxRows    (10000)       Target row count. Stride adjusted to stay at or below.
%   LatRange   ([-Inf Inf])  [min max] latitude filter (post-sampling, inclusive).
%   LonRange   ([-Inf Inf])  [min max] longitude filter (post-sampling, inclusive).
%   TimeRange  ([1 Inf])     [first last] time-coordinate index range (1-based).
%   Verbose    (true)        Print progress.

arguments
    filepath            (1,1) string
    options.Variable    (1,1) string  = ""
    options.MaxRows     (1,1) double  = 10000
    options.LatRange    (1,2) double  = [-Inf Inf]
    options.LonRange    (1,2) double  = [-Inf Inf]
    options.TimeRange   (1,2) double  = [1 Inf]
    options.Verbose     (1,1) logical = true
end

if ~isfile(filepath)
    error('SampleNetCDF:notFound', 'File not found: %s', filepath);
end

%% ── Discover variable ─────────────────────────────────────────────────────────
info = ncinfo(filepath);
all_var_names = {info.Variables.Name};

% Collect all dimension names used anywhere in the file
all_dim_names = {};
for k = 1:numel(info.Variables)
    if ~isempty(info.Variables(k).Dimensions)
        all_dim_names = [all_dim_names, {info.Variables(k).Dimensions.Name}]; %#ok<AGROW>
    end
end
all_dim_names = unique(all_dim_names);

if strlength(options.Variable) > 0
    varname = char(options.Variable);
    var_idx = find(strcmp(all_var_names, varname), 1);
    if isempty(var_idx)
        error('SampleNetCDF:noVar', 'Variable "%s" not found in %s', varname, filepath);
    end
else
    % First data variable: not a coordinate variable, has at least one element
    var_idx = [];
    for k = 1:numel(info.Variables)
        v = info.Variables(k);
        if ~ismember(v.Name, all_dim_names) && ~isempty(v.Size) && prod(v.Size) > 0
            var_idx = k;
            break;
        end
    end
    if isempty(var_idx)
        error('SampleNetCDF:noVar', 'No data variable found in %s', filepath);
    end
    varname = info.Variables(var_idx).Name;
end

v    = info.Variables(var_idx);
sz   = double(v.Size);
ndim = numel(sz);
if ndim ~= 3
    error('SampleNetCDF:unsupported', ...
        'Variable "%s" has %d dimensions; SampleNetCDF requires exactly 3.', varname, ndim);
end
dim_names = {v.Dimensions.Name};

if options.Verbose
    [~, fname, ext] = fileparts(filepath);
    fprintf('\n  SampleNetCDF: %s%s  —  "%s"  [%s]\n', fname, ext, varname, ...
        strjoin(arrayfun(@num2str, sz, 'UniformOutput', false), '×'));
    fprintf('  Target rows: %d\n\n', options.MaxRows);
end

%% ── Read coordinate variables ─────────────────────────────────────────────────
coords = cell(1, ndim);
for k = 1:ndim
    dn = dim_names{k};
    if ismember(dn, all_var_names)
        coords{k} = double(ncread(filepath, dn));
    else
        coords{k} = (1:sz(k))';
    end
end

%% ── Compute uniform stride ────────────────────────────────────────────────────
total_elems = prod(sz);
if total_elems <= options.MaxRows
    strides = ones(1, ndim);
else
    s = max(1, floor((total_elems / options.MaxRows) ^ (1/ndim)));
    while prod(ceil(sz / s)) > options.MaxRows
        s = s + 1;
    end
    strides = repmat(s, 1, ndim);
end

n_sampled = prod(ceil(sz ./ strides));
if options.Verbose
    fprintf('  Strides: [%s]  →  %d rows\n', ...
        strjoin(arrayfun(@num2str, strides, 'UniformOutput', false), ', '), n_sampled);
end

%% ── Read with stride ──────────────────────────────────────────────────────────
start_idx = ones(1, ndim);
count_idx = ceil(sz ./ strides);
data = double(ncread(filepath, varname, start_idx, count_idx, strides));

%% ── Build strided coordinate vectors ─────────────────────────────────────────
strided_coords = cell(1, ndim);
for k = 1:ndim
    c = coords{k}(1:strides(k):end);
    strided_coords{k} = c(1:count_idx(k));
end

%% ── Flatten to long-format table ─────────────────────────────────────────────
[G1, G2, G3] = ndgrid(strided_coords{1}, strided_coords{2}, strided_coords{3});
vname_safe = matlab.lang.makeValidName(varname);
T = table(G1(:), G2(:), G3(:), data(:), ...
    'VariableNames', {dim_names{1}, dim_names{2}, dim_names{3}, vname_safe});

%% ── Normalise lat/lon/time column names ──────────────────────────────────────
lat_pat  = 'lat|latitude|^y$';
lon_pat  = 'lon|longitude|^x$';
time_pat = 'time|^t$|day|month|year';
rename_map = {lat_pat, 'latitude'; lon_pat, 'longitude'; time_pat, 'time'};
for k = 1:ndim
    dn = dim_names{k};
    for r = 1:size(rename_map, 1)
        target = rename_map{r, 2};
        if ~isempty(regexpi(dn, rename_map{r, 1}, 'once')) && ~strcmp(dn, target)
            T.Properties.VariableNames{k} = target;
            break;
        end
    end
end

%% ── Apply range filters ───────────────────────────────────────────────────────
keep = true(height(T), 1);
cols = T.Properties.VariableNames;

if ismember('latitude', cols)
    keep = keep & T.latitude  >= options.LatRange(1) & T.latitude  <= options.LatRange(2);
end
if ismember('longitude', cols)
    keep = keep & T.longitude >= options.LonRange(1) & T.longitude <= options.LonRange(2);
end
if ismember('time', cols)
    t_uniq = unique(T.time);
    t_lo   = options.TimeRange(1);
    t_hi   = min(options.TimeRange(2), numel(t_uniq));
    if t_lo <= t_hi
        valid_t = t_uniq(t_lo : t_hi);
        keep = keep & ismember(T.time, valid_t);
    end
end
T = T(keep, :);

if options.Verbose
    fprintf('  ✓ %d rows after range filter.\n\n', height(T));
end
end
```

- [ ] **Step 6: Run fast smoke test**

```
python3 -m pytest tests/ -v -k test_samplenetcdf_checkcode_clean
```
Expected: PASS.

- [ ] **Step 7: Run integration tests**

```
python3 -m pytest tests/ -m slow -k "test_samplenetcdf" -v
```
Expected: all three PASS.

- [ ] **Step 8: Commit**

```bash
git add SampleNetCDF.m tests/test_DataExplorer.m
git commit -m "feat: add SampleNetCDF stride-sampled table from 3D gridded NetCDF"
```

---

## Task 4: Route spatial grids in the DataExplorer fast-path

**Files:**
- Modify: `DataExplorer.m` (fast-path loop body, add `nc_is_spatial_grid` and `cg_netcdf_spatial_recipe` local functions)

Spatial grids (lat-like + lon-like + one other dimension) get `SampleNetCDF` + `de_geoscatter` instead of `se_load` + `se_plot`. This fixes both the hang (stride sampling never reads the full array) and the figure explosion (one geo scatter per variable instead of five tabular figures).

- [ ] **Step 1: Write failing test**

Add inside `methods (Test, TestTags={'slow'})`:

```matlab
function test_netcdf_spatial_grid_produces_geoscatter_figure(testCase)
    % DataExplorer on a lon×lat×time NetCDF must produce a "Geo Scatter" figure.
    tmp = [tempname '.nc'];
    cl  = onCleanup(@() delete(tmp));
    nlon = 8; nlat = 6; ntime = 3;
    nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
    nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
    nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
    nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
    ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
    ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
    ncwrite(tmp,'time',      (1:ntime)');
    ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
    figs_before = findobj(0,'Type','figure');

    DataExplorer(tmp);

    figs_after = findobj(0,'Type','figure');
    new_figs   = setdiff(figs_after, figs_before);
    cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

    fig_names = arrayfun(@(f) get(f,'Name'), new_figs, 'UniformOutput', false);
    has_geo   = any(cellfun(@(n) contains(lower(n),'geo scatter'), fig_names));
    testCase.verifyTrue(has_geo, ...
        'Expected a "Geo Scatter" figure for a spatial grid NetCDF variable');
end
```

- [ ] **Step 2: Run to verify it fails**

```
python3 -m pytest tests/ -m slow -k test_netcdf_spatial_grid_produces_geoscatter_figure -v
```
Expected: FAIL (no "Geo Scatter" figure, tabular pipeline runs instead).

- [ ] **Step 3: Add nc_is_spatial_grid local function to DataExplorer.m**

Insert just after the closing `end` of `nc_list_data_vars` (around line 841):

```matlab
function tf = nc_is_spatial_grid(info, varname)
%NC_IS_SPATIAL_GRID  True when varname is a 3D variable with lat-like and lon-like dims.
    var_idx = find(strcmp({info.Variables.Name}, varname), 1);
    if isempty(var_idx), tf = false; return; end
    v = info.Variables(var_idx);
    if isempty(v.Dimensions) || numel(v.Dimensions) ~= 3
        tf = false; return;
    end
    dim_names = {v.Dimensions.Name};
    has_lat = any(~cellfun('isempty', regexpi(dim_names, 'lat|latitude|^y$', 'once')));
    has_lon = any(~cellfun('isempty', regexpi(dim_names, 'lon|longitude|^x$', 'once')));
    tf = has_lat && has_lon;
end
```

- [ ] **Step 4: Add cg_netcdf_spatial_recipe local function to DataExplorer.m**

Insert just after `nc_is_spatial_grid`:

```matlab
function recipe_path = cg_netcdf_spatial_recipe(filepath, varname)
%CG_NETCDF_SPATIAL_RECIPE  Write a recipe for a spatial NetCDF grid variable.
%   Recipe calls SampleNetCDF + de_geoscatter — both are public library functions
%   the student can re-use with different arguments.
    vname_safe = matlab.lang.makeValidName(varname);
    L = {};
    L{end+1} = sprintf('%% DataExplorer recipe — %s [%s]', filepath, varname);
    L{end+1} = '';
    L{end+1} = 'addpath(fileparts(which(''DataExplorer'')));';
    L{end+1} = '';
    L{end+1} = '% Load with stride sampling (never reads the full array)';
    L{end+1} = sprintf('T = SampleNetCDF(''%s'', Variable=''%s'');', filepath, varname);
    L{end+1} = '';
    L{end+1} = '% Geo scatter: color = time, size = value';
    L{end+1} = sprintf('de_geoscatter(T.longitude, T.latitude, double(T.time), T.%s, ...', ...
        vname_safe);
    L{end+1} = sprintf('    ColorLabel="time", SizeLabel="%s");', varname);
    code = strjoin(L, newline);

    [~, basename] = fileparts(filepath);
    recipe_path = fullfile(tempdir, sprintf('dataexplorer_%s_%s.m', ...
        matlab.lang.makeValidName(basename), vname_safe));
    fid = fopen(recipe_path, 'w');
    fprintf(fid, '%s\n', code);
    fclose(fid);
end
```

- [ ] **Step 5: Replace the fast-path for loop body in DataExplorer.m**

The current loop body (lines 82–104) runs the full tabular pipeline for every variable. Replace the entire `for` loop body (keeping the `for` and outer `end`) with:

```matlab
            for nc_vi_ = 1:n_plot_
                vname_vi_  = data_vars_{nc_vi_};
                T_vi_      = table();
                recipe_vi_ = '';
                if nc_is_spatial_grid(nc_info_, vname_vi_)
                    % ── Spatial grid: stride sample + geo scatter ─────────────
                    fprintf('  [%d/%d] Spatial grid "%s" — stride sampling…\n', ...
                        nc_vi_, n_plot_, vname_vi_);
                    try
                        T_vi_ = SampleNetCDF(string(source), ...
                            Variable=string(vname_vi_), ...
                            MaxRows=options.MaxRows, Verbose=false);
                    catch ME_
                        if strcmp(ME_.identifier, 'MATLAB:interrupt'), rethrow(ME_); end
                        fprintf('  ⚠ Skipping "%s": %s\n', vname_vi_, ME_.message);
                        continue
                    end
                    [~, fn_, fe_] = fileparts(string(source));
                    vname_safe_   = matlab.lang.makeValidName(vname_vi_);
                    time_col_     = 'time';
                    if ~ismember(time_col_, T_vi_.Properties.VariableNames)
                        time_col_ = T_vi_.Properties.VariableNames{3};
                    end
                    de_geoscatter(T_vi_.longitude, T_vi_.latitude, ...
                        double(T_vi_.(time_col_)), T_vi_.(vname_safe_), ...
                        ColorLabel="time", SizeLabel=string(vname_vi_), ...
                        Title=string(sprintf('%s%s — %s', fn_, fe_, vname_vi_)));
                    recipe_vi_ = cg_netcdf_spatial_recipe(string(source), vname_vi_);
                else
                    % ── Tabular path: existing pipeline ───────────────────────
                    opts_vi_            = options;
                    opts_vi_.NCVariable = string(vname_vi_);
                    try
                        T_vi_ = se_load(string(source), opts_vi_);
                    catch ME_
                        if strcmp(ME_.identifier, 'MATLAB:interrupt'), rethrow(ME_); end
                        fprintf('  ⚠ Skipping "%s": %s\n', vname_vi_, ME_.message);
                        continue
                    end
                    [T_vi_, prof_vi_] = se_profile(T_vi_, options.MissingStrings);
                    [~, fn_, fe_]     = fileparts(string(source));
                    prof_vi_.source_name = sprintf('%s%s [%s]', fn_, fe_, vname_vi_);
                    se_echo_load_code(string(source), T_vi_);
                    se_report(T_vi_, prof_vi_);
                    panel_vi_  = se_detect_panel(T_vi_, prof_vi_);
                    se_plot(T_vi_, prof_vi_, opts_vi_, panel_vi_);
                    recipe_vi_ = se_assemble_recipe(string(source), T_vi_, prof_vi_, ...
                        panel_vi_, opts_vi_);
                end
                if ~isempty(recipe_vi_)
                    T_ret_ = T_vi_; run(recipe_vi_); T_vi_ = T_ret_;
                end
                T = T_vi_;
            end
```

- [ ] **Step 6: Run the new test**

```
python3 -m pytest tests/ -m slow -k test_netcdf_spatial_grid_produces_geoscatter_figure -v
```
Expected: PASS.

- [ ] **Step 7: Run all NetCDF slow tests to verify no regression**

```
python3 -m pytest tests/ -m slow -k "netcdf" -v
```
Expected: all pass.

- [ ] **Step 8: Run full fast suite**

```
python3 -m pytest tests/ -v
```
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "feat: route NetCDF spatial grids to de_geoscatter via SampleNetCDF in fast-path"
```

---

## Task 5: Recipe verification for spatial grids

**Files:**
- Modify: `tests/test_DataExplorer.m`

The recipe generated by `cg_netcdf_spatial_recipe` (Task 4) must contain `SampleNetCDF` and `de_geoscatter`, and must pass `checkcode`.

- [ ] **Step 1: Write the test**

Add inside `methods (Test, TestTags={'slow'})`:

```matlab
function test_netcdf_spatial_recipe_contains_geoscatter(testCase)
    % Recipe for a spatial grid NetCDF must call SampleNetCDF and de_geoscatter.
    tmp = [tempname '.nc'];
    cl  = onCleanup(@() delete(tmp));
    nlon = 8; nlat = 6; ntime = 3;
    nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
    nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
    nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
    nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
    ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
    ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
    ncwrite(tmp,'time',      (1:ntime)');
    ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    DataExplorer(tmp);

    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    testCase.assertNotEmpty(hits, 'Expected a recipe file in tempdir');
    [~, newest] = max([hits.datenum]);
    recipe_path = fullfile(hits(newest).folder, hits(newest).name);
    recipe_text = fileread(recipe_path);

    testCase.verifyTrue(contains(recipe_text, 'SampleNetCDF'), ...
        'Recipe must call SampleNetCDF');
    testCase.verifyTrue(contains(recipe_text, 'de_geoscatter'), ...
        'Recipe must call de_geoscatter');

    info = checkcode(recipe_path, '-string');
    n    = numel(regexp(info, 'L \d+', 'match'));
    testCase.verifyEqual(n, 0, ...
        sprintf('Recipe has %d checkcode issue(s):\n%s', n, info));
end
```

- [ ] **Step 2: Run test**

```
python3 -m pytest tests/ -m slow -k test_netcdf_spatial_recipe_contains_geoscatter -v
```
Expected: PASS (recipe already written correctly in Task 4).

- [ ] **Step 3: Run full fast suite**

```
python3 -m pytest tests/ -v
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add tests/test_DataExplorer.m
git commit -m "test: verify spatial NetCDF recipe calls SampleNetCDF and de_geoscatter"
```

---

## Self-review

**Spec coverage:**
- ✅ Stride sampling — Task 3 (SampleNetCDF) + Task 4 (routing)
- ✅ de_geoscatter: color=time, size=value, size legend — Task 2
- ✅ One geo scatter figure per variable — Task 4 loop
- ✅ Negative values in size_data handled (linear normalisation over full range) — Task 2
- ✅ Student can call de_geoscatter with own data — public function with documented API
- ✅ LatRange / LonRange / TimeRange filters — Task 3
- ✅ Ctrl+C re-throw fix — Task 1 + Task 4
- ✅ raw='1' → raw='2' fix — Task 1
- ✅ Recipe shows SampleNetCDF + de_geoscatter calls — Task 4 + Task 5
- ✅ Tabular path unchanged for non-spatial variables — Task 4

**Out of scope (write a separate plan):**
- Spatial / temporal pairplot decomposition for variable pairs
- Categorical drill-down generalisation (collapse-one/overlay-other)
