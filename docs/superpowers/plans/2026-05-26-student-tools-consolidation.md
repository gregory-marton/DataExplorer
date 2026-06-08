# Student Tools Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **STATUS (reviewed 2026-06-08): DONE.** `SampleData`/`SampleNetCDF` replaced by `de_reservoir_sample.m`/`de_stride_sample.m` (the `de_` prefix superseded the bare `ReservoirSample`/`StrideSample` names here); `de_pivot_wide_years.m` added. Call sites updated; old files removed.

**Goal:** Replace `SampleData` + `SampleNetCDF` with `ReservoirSample` (tabular random) + `StrideSample` (tabular/NetCDF deterministic), update all call sites, ensure every recipe always prints inline + offers `save_recipe()`, and document recipe abstraction opportunities.

**Architecture:** `StrideSample` auto-detects format by file extension (`.nc`/`.nc4`/`.netcdf` → NetCDF stride; everything else → tabular stride). It uses a 64 KB file probe to estimate row count and compute stride without reading the full file. `ReservoirSample` is a transparent rename of `SampleData` — no behavioral changes. The fast-path recipe print block is brought in line with the slow path. No backward compatibility — this is a teaching toy.

**Tech Stack:** MATLAB R2025b, `datastore`, `ncread`/`nccreate`/`ncwrite`, matlab.unittest, pytest harness (`python3 -m pytest tests/ -v` for fast suite; `pytest tests/ -m slow` for integration).

**Testing discipline:** Run `python3 -m pytest tests/ -v` (fast suite, includes checkcode) after every commit. Never call `matlab -batch "runtests(...)"` directly. Never run `-m slow` during individual task steps — that is the background integration pass after all tasks complete.

---

## File map

| Action | File | Purpose |
|--------|------|---------|
| Create | `StrideSample.m` | Unified stride sampling: tabular CSV/TSV + NetCDF 3-D variables |
| Create | `ReservoirSample.m` | Rename of SampleData; Algorithm R reservoir sampling for tabular files |
| Delete | `SampleData.m` | Superseded by ReservoirSample |
| Delete | `SampleNetCDF.m` | Superseded by StrideSample |
| Modify | `DataExplorer.m` | 5 call sites: se_load, cg_load_code (×2), fast-path, cg_netcdf_spatial_recipe; fast-path recipe print block |
| Modify | `tests/test_DataExplorer.m` | Rename 4 test methods; update 1 assertion; add 2 new tests |
| Modify | `CLAUDE.md` | Update function name references |

---

## Task 1: Create StrideSample.m

**Files:**
- Create: `StrideSample.m`
- Modify: `tests/test_DataExplorer.m`

- [ ] **Step 1: Write two failing tests for the tabular stride path**

Add these two methods inside the `methods (Test, TestTags = {'integration'})` block in `tests/test_DataExplorer.m` (after the last existing test method, before the final `end` of the methods block):

```matlab
function test_stridesample_tabular_returns_within_maxrows(testCase)
    % StrideSample on a CSV with 500 rows and MaxRows=50 must return ≤ 60 rows.
    tmp = [tempname '.csv'];
    cl  = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w');
    fprintf(fid, 'idx,val\n');
    for i = 1:500
        fprintf(fid, '%d,%d\n', i, i*2);
    end
    fclose(fid);

    T = StrideSample(string(tmp), MaxRows=50, Verbose=false);
    testCase.verifyClass(T, 'table');
    testCase.verifyLessThanOrEqual(height(T), 60, ...
        'StrideSample tabular should not exceed MaxRows significantly');
    testCase.verifyGreaterThan(height(T), 0, 'Expected non-empty output');
end

function test_stridesample_tabular_spans_full_range(testCase)
    % Stride sampling should produce rows from across the file (not just the top).
    tmp = [tempname '.csv'];
    cl  = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w');
    fprintf(fid, 'idx,val\n');
    for i = 1:1000
        fprintf(fid, '%d,%d\n', i, i*2);
    end
    fclose(fid);

    T = StrideSample(string(tmp), MaxRows=100, Verbose=false);
    idx_col = double(T.idx);
    testCase.verifyLessThan(min(idx_col), 50, ...
        'Stride sample should include rows near the beginning');
    testCase.verifyGreaterThan(max(idx_col), 900, ...
        'Stride sample should include rows near the end');
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
python3 -m pytest tests/ -v -k "stridesample_tabular"
```

Expected: FAIL — `StrideSample` is not defined.

- [ ] **Step 3: Write StrideSample.m (tabular path only)**

Create `StrideSample.m` in the repo root:

```matlab
function T = StrideSample(filepath, options)
%STRIDESAMPLE  Deterministic stride sample from a CSV/TSV or 3-D NetCDF file.
%
%   Uses stride sampling — reads every Nth row/element — so the sample covers
%   the full extent of the file deterministically (same result each run).
%   For random sampling use ReservoirSample instead.
%
%   Usage
%   ─────
%   T = StrideSample('bigfile.csv')
%   T = StrideSample('bigfile.csv', MaxRows=5000)
%   T = StrideSample('climate.nc', Variable='prcp', MaxRows=5000)
%   T = StrideSample('climate.nc', LatRange=[30 60])
%   DataExplorer(StrideSample('climate.nc'))
%
%   For tabular files the stride is estimated from file size + a 64 KB probe.
%   For NetCDF files the variable must have exactly 3 dimensions; stride is
%   uniform across all three so the sample stays within MaxRows.
%
%   Optional arguments
%   ──────────────────
%   Variable   ("")          NetCDF variable name. Empty = first data variable.
%   MaxRows    (10000)       Target row count for the output table.
%   LatRange   ([-Inf Inf])  [min max] latitude filter (NetCDF, post-sample).
%   LonRange   ([-Inf Inf])  [min max] longitude filter (NetCDF, post-sample).
%   TimeRange  ([1 Inf])     [first last] time index range (NetCDF, 1-based).
%   Verbose    (true)        Print progress.

arguments
    filepath              (1,1) string
    options.Variable      (1,1) string  = ""
    options.MaxRows       (1,1) double  = 10000
    options.LatRange      (1,2) double  = [-Inf Inf]
    options.LonRange      (1,2) double  = [-Inf Inf]
    options.TimeRange     (1,2) double  = [1 Inf]
    options.Verbose       (1,1) logical = true
end

if ~isfile(filepath)
    error('StrideSample:notFound', 'File not found: %s', filepath);
end

[~, fname, ext] = fileparts(filepath);
ext_lc = lower(ext);
nc_exts = [".nc", ".nc4", ".netcdf"];

if ismember(ext_lc, nc_exts)
    T = stride_netcdf(filepath, fname, ext_lc, options);
else
    T = stride_tabular(filepath, fname, ext_lc, options);
end
end


%% ── Tabular stride path ───────────────────────────────────────────────────────

function T = stride_tabular(filepath, fname, ext, options)
%STRIDE_TABULAR  Stride-sample a delimited text file without loading it fully.

tab_exts = [".csv", ".tsv", ".txt", ".dat", ".tab", ".asc"];
if ~ismember(ext, tab_exts)
    warning('StrideSample:format', ...
        'Unexpected extension "%s". Attempting to read as delimited text.', ext);
end

%% ── Sniff delimiter ──────────────────────────────────────────────────────────
fid = fopen(filepath, 'r', 'n', 'UTF-8');
if fid == -1, fid = fopen(filepath, 'r'); end
firstline = fgetl(fid);
fclose(fid);

counts = [sum(firstline == ','), sum(firstline == char(9)), ...
          sum(firstline == ';'),  sum(firstline == '|')];
delims  = {',', '\t', ';', '|'};
dnames  = {'comma-separated', 'tab-separated', 'semicolon-separated', 'pipe-separated'};
[~, di] = max(counts);
delim   = delims{di};

if options.Verbose
    info = dir(filepath);
    fprintf('\n  StrideSample: %s%s  (%.1f MB)\n', fname, ext, info.bytes/1e6);
    fprintf('  Format: %s\n', dnames{di});
    fprintf('  Target rows: %d\n', options.MaxRows);
end

%% ── Estimate stride from file size + 64 KB probe ─────────────────────────────
PROBE_BYTES = 65536;
fid = fopen(filepath, 'r', 'n', 'UTF-8');
if fid == -1, fid = fopen(filepath, 'r'); end
probe = fread(fid, PROBE_BYTES, '*char')';
fclose(fid);

n_nl = sum(probe == newline);
file_info   = dir(filepath);
file_bytes  = file_info.bytes;
if n_nl > 1
    bytes_per_row = numel(probe) / n_nl;   % includes header line, slight undercount
else
    bytes_per_row = max(1, numel(probe));
end
est_rows = max(1, round(file_bytes / bytes_per_row));
stride   = max(1, floor(est_rows / options.MaxRows));

if options.Verbose
    fprintf('  Estimated rows: ~%d  →  stride %d\n\n', est_rows, stride);
end

%% ── Set up datastore ─────────────────────────────────────────────────────────
try
    ds = datastore(filepath, 'Type', 'tabulartext', ...
        'Delimiter',      delim, ...
        'ReadSize',       50000, ...
        'FileExtensions', {'.csv','.tsv','.txt','.dat','.tab','.asc'});
    ds.TextscanFormats = repmat({'%q'}, 1, numel(ds.VariableNames));
catch ME
    error('StrideSample:datastoreError', ...
        'Could not create datastore: %s', ME.message);
end

%% ── Stream with stride filter ────────────────────────────────────────────────
result     = {};
global_row = 0;

while hasdata(ds)
    n_collected = sum(cellfun(@height, result));
    if n_collected >= options.MaxRows, break; end

    chunk   = read(ds);
    n_chunk = height(chunk);
    if n_chunk == 0, continue; end

    chunk_rows  = global_row + (1:n_chunk);
    keep_mask   = mod(chunk_rows - 1, stride) == 0;
    global_row  = global_row + n_chunk;

    if any(keep_mask)
        result{end+1} = chunk(keep_mask, :); %#ok<AGROW>
    end

    if options.Verbose
        fprintf('  Processed %d rows…\r', global_row);
    end
end

if isempty(result)
    T = table();
else
    T = vertcat(result{:});
    if height(T) > options.MaxRows
        T = T(1:options.MaxRows, :);
    end
end

if options.Verbose
    fprintf('  ✓ Done. %d rows from ~%d total.%s\n\n', ...
        height(T), global_row, repmat(' ', 1, 20));
end
end


%% ── NetCDF stride path ────────────────────────────────────────────────────────

function T = stride_netcdf(filepath, fname, ext, options)
%STRIDE_NETCDF  Stride-sample a 3-D NetCDF variable (lon × lat × time).

%% ── Discover variable ────────────────────────────────────────────────────────
info          = ncinfo(filepath);
all_var_names = {info.Variables.Name};

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
        error('StrideSample:noVar', 'Variable "%s" not found in %s', varname, filepath);
    end
else
    var_idx = [];
    for k = 1:numel(info.Variables)
        v = info.Variables(k);
        if ~ismember(v.Name, all_dim_names) && ~isempty(v.Size) && prod(v.Size) > 0
            var_idx = k; break;
        end
    end
    if isempty(var_idx)
        error('StrideSample:noVar', 'No data variable found in %s', filepath);
    end
    varname = info.Variables(var_idx).Name;
end

v         = info.Variables(var_idx);
sz        = double(v.Size);
ndim      = numel(sz);
if ndim ~= 3
    error('StrideSample:unsupported', ...
        'Variable "%s" has %d dimensions; StrideSample requires exactly 3.', varname, ndim);
end
dim_names = {v.Dimensions.Name};

if options.Verbose
    fprintf('\n  StrideSample (NetCDF): %s%s  —  "%s"  [%s]\n', fname, ext, varname, ...
        strjoin(arrayfun(@num2str, sz, 'UniformOutput', false), '×'));
    fprintf('  Target rows: %d\n\n', options.MaxRows);
end

%% ── Read coordinate variables ────────────────────────────────────────────────
coords = cell(1, ndim);
for k = 1:ndim
    dn = dim_names{k};
    if ismember(dn, all_var_names)
        coords{k} = double(ncread(filepath, dn));
    else
        coords{k} = (1:sz(k))';
    end
end

%% ── Compute uniform stride ───────────────────────────────────────────────────
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

%% ── Read with stride ─────────────────────────────────────────────────────────
start_idx = ones(1, ndim);
count_idx = ceil(sz ./ strides);
data      = double(ncread(filepath, varname, start_idx, count_idx, strides));

%% ── Build strided coordinate vectors ────────────────────────────────────────
strided_coords = cell(1, ndim);
for k = 1:ndim
    c = coords{k}(1:strides(k):end);
    strided_coords{k} = c(1:count_idx(k));
end

%% ── Flatten to long-format table ─────────────────────────────────────────────
[G1, G2, G3] = ndgrid(strided_coords{1}, strided_coords{2}, strided_coords{3});
vname_safe   = matlab.lang.makeValidName(varname);
T = table(G1(:), G2(:), G3(:), data(:), ...
    'VariableNames', {dim_names{1}, dim_names{2}, dim_names{3}, vname_safe});

%% ── Normalise lat/lon/time column names ──────────────────────────────────────
rename_map = {'lat|latitude|^y$', 'latitude'; ...
              'lon|longitude|^x$', 'longitude'; ...
              'time|^t$|day|month|year', 'time'};
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

%% ── Apply range filters ──────────────────────────────────────────────────────
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
        keep    = keep & ismember(T.time, valid_t);
    end
end
T = T(keep, :);

if options.Verbose
    fprintf('  ✓ %d rows after range filter.\n\n', height(T));
end
end
```

- [ ] **Step 4: Run tests to confirm tabular tests pass**

```bash
python3 -m pytest tests/ -v -k "stridesample_tabular"
```

Expected: PASS for both tabular tests. Checkcode also runs on StrideSample.m automatically.

- [ ] **Step 5: Write two failing tests for the NetCDF stride path**

Add these inside the same `methods (Test, TestTags = {'integration'})` block, after the tabular tests just added:

```matlab
function test_stridesample_netcdf_returns_table_within_maxrows(testCase)
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

    T = StrideSample(string(tmp), Variable='prcp', MaxRows=100, Verbose=false);
    testCase.verifyClass(T, 'table');
    testCase.verifyLessThanOrEqual(height(T), 120, ...
        'StrideSample NetCDF should not exceed MaxRows significantly');
    expected_cols = {'longitude','latitude','time','prcp'};
    for k = 1:numel(expected_cols)
        testCase.verifyTrue(ismember(expected_cols{k}, T.Properties.VariableNames), ...
            sprintf('Expected column "%s"', expected_cols{k}));
    end
end

function test_stridesample_netcdf_latrange_filters_rows(testCase)
    tmp = [tempname '.nc'];
    cl  = onCleanup(@() delete(tmp));
    nlon = 10; nlat = 10; ntime = 3;
    nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
    nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
    nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
    nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
    ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
    ncwrite(tmp,'latitude',  linspace(0,90,nlat)');
    ncwrite(tmp,'time',      (1:ntime)');
    ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

    T = StrideSample(string(tmp), Variable='prcp', LatRange=[30 60], Verbose=false);
    testCase.verifyTrue(all(T.latitude >= 30 & T.latitude <= 60), ...
        'All returned rows must satisfy LatRange');
    testCase.verifyGreaterThan(height(T), 0, 'Expected some rows in LatRange [30,60]');
end
```

- [ ] **Step 6: Run tests — NetCDF tests should FAIL (NetCDF path not yet wired)**

```bash
python3 -m pytest tests/ -v -k "stridesample_netcdf"
```

Expected: FAIL — `StrideSample` rejects `.nc` because only tabular branch exists.

Wait — actually the full `StrideSample.m` in Step 3 already includes the NetCDF path (`stride_netcdf`). So NetCDF tests will PASS here. Skip to Step 7 if that's the case.

- [ ] **Step 7: Run all new StrideSample tests + fast suite**

```bash
python3 -m pytest tests/ -v -k "stridesample"
```

Expected: all 4 PASS.

```bash
python3 -m pytest tests/ -v
```

Expected: full fast suite PASS (checkcode covers StrideSample.m automatically).

- [ ] **Step 8: Commit**

```bash
git add StrideSample.m tests/test_DataExplorer.m
git commit -m "Add StrideSample: unified stride sampling for tabular + NetCDF"
```

---

## Task 2: Create ReservoirSample.m

**Files:**
- Create: `ReservoirSample.m`
- Modify: `tests/test_DataExplorer.m`

- [ ] **Step 1: Write failing test**

Add inside the `methods (Test, TestTags = {'integration'})` block:

```matlab
function test_reservoir_sample_returns_within_nrows(testCase)
    % ReservoirSample on a CSV with 500 rows and nrows=50 must return ≤ 50 rows.
    tmp = [tempname '.csv'];
    cl  = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w');
    fprintf(fid, 'idx,val\n');
    for i = 1:500
        fprintf(fid, '%d,%d\n', i, i*2);
    end
    fclose(fid);

    T = ReservoirSample(string(tmp), 50, Verbose=false);
    testCase.verifyClass(T, 'table');
    testCase.verifyLessThanOrEqual(height(T), 50, ...
        'ReservoirSample must not exceed requested row count');
    testCase.verifyGreaterThan(height(T), 0, 'Expected non-empty output');
end
```

- [ ] **Step 2: Run test to confirm failure**

```bash
python3 -m pytest tests/ -v -k "reservoir_sample"
```

Expected: FAIL — `ReservoirSample` is not defined.

- [ ] **Step 3: Write ReservoirSample.m**

Copy `SampleData.m` to `ReservoirSample.m`, then change:
1. First line: `function T = SampleData(filepath, nrows, options)` → `function T = ReservoirSample(filepath, nrows, options)`
2. Header comment: replace `SAMPLEDATA` with `RESERVOIRSAMPLE` and update the function name in usage examples
3. Error IDs: `SampleData:notFound` → `ReservoirSample:notFound`, `SampleData:format` → `ReservoirSample:format`, `SampleData:datastoreError` → `ReservoirSample:datastoreError`
4. Verbose print: `SampleData: %s%s` → `ReservoirSample: %s%s`

The full file content for `ReservoirSample.m`:

```matlab
function T = ReservoirSample(filepath, nrows, options)
%RESERVOIRSAMPLE  Uniform random sample from a large CSV/TSV/text file.
%
%   Reads the file in chunks without loading it fully into memory,
%   using reservoir sampling (Algorithm R) to guarantee that every
%   row in the file has an equal probability of appearing in the result.
%
%   Usage
%   ─────
%   T = ReservoirSample('ebirddata.tsv')          % 10 000 rows (default)
%   T = ReservoirSample('ebirddata.tsv', 50000)   % 50 000 rows
%   T = ReservoirSample('bigfile.csv', 10000, Seed=42)   % reproducible sample
%
%   The result is a MATLAB table you can pass directly to DataExplorer:
%       T = ReservoirSample('ebirddata.tsv', 10000);
%       DataExplorer(T);
%   or save for later:
%       save('my_sample.mat', 'T');
%
%   Optional arguments
%   ──────────────────
%   Seed      ([]   )   Random seed for reproducibility. Empty = unseeded.
%   ChunkSize (50000)   Rows per read. Larger = faster but more memory per chunk.
%   Verbose   (true )   Print progress to the command window.
%
%   Supported formats: CSV, TSV, TXT, DAT (delimiter auto-detected).
%   For Excel or ZIP files, load manually and pass the table to DataExplorer.

arguments
    filepath  (1,1) string
    nrows     (1,1) double = 10000
    options.Seed      = []
    options.ChunkSize (1,1) double = 50000
    options.Verbose   (1,1) logical = true
end

if ~isfile(filepath)
    error('ReservoirSample:notFound', 'File not found: %s', filepath);
end

[~, fname, ext] = fileparts(filepath);
ext = lower(ext);
if ~ismember(ext, [".csv", ".tsv", ".txt", ".dat", ".tab", ".asc"])
    warning('ReservoirSample:format', ...
        'Unexpected extension "%s". Attempting to read as delimited text.', ext);
end

if ~isempty(options.Seed)
    rng(options.Seed);
end

fid = fopen(filepath, 'r', 'n', 'UTF-8');
if fid == -1
    fid = fopen(filepath, 'r');
end
firstline = fgetl(fid);
fclose(fid);

counts    = [sum(firstline == ','), sum(firstline == char(9)), ...
             sum(firstline == ';'),  sum(firstline == '|')];
delims    = {',', '\t', ';', '|'};
dnames    = {'comma-separated', 'tab-separated', 'semicolon-separated', 'pipe-separated'};
[~, di]   = max(counts);
delim     = delims{di};

if options.Verbose
    info   = dir(filepath);
    fprintf('\n  ReservoirSample: %s%s  (%.1f MB)\n', fname, ext, info.bytes/1e6);
    fprintf('  Format: %s\n', dnames{di});
    fprintf('  Target sample: %d rows\n\n', nrows);
end

try
    ds = datastore(filepath, 'Type', 'tabulartext', ...
        'Delimiter',      delim, ...
        'ReadSize',       options.ChunkSize, ...
        'FileExtensions', {'.csv','.tsv','.txt','.dat','.tab','.asc'});
    ds.TextscanFormats = repmat({'%q'}, 1, numel(ds.VariableNames));
catch ME
    error('ReservoirSample:datastoreError', ...
        'Could not create datastore: %s\nCheck that the file is readable text.', ...
        ME.message);
end

reservoir = [];
n_seen    = 0;
k         = nrows;

while hasdata(ds)
    chunk   = read(ds);
    n_chunk = height(chunk);
    if n_chunk == 0, continue; end

    if isempty(reservoir) && n_chunk < k
        reservoir = chunk;
        n_seen    = n_chunk;
        continue
    end

    if isempty(reservoir)
        reservoir = chunk(1:k, :);
        n_seen    = k;
        start_row = k + 1;
    else
        start_row = 1;
    end

    for i = start_row : n_chunk
        n_seen = n_seen + 1;

        if height(reservoir) < k
            reservoir(end+1, :) = chunk(i, :); %#ok<AGROW>
        else
            j = randi(n_seen);
            if j <= k
                reservoir(j, :) = chunk(i, :); %#ok<AGROW>
            end
        end
    end

    if options.Verbose
        fprintf('  Processed %d rows…\r', n_seen);
    end
end

if options.Verbose
    fprintf('  ✓ Done. Sampled %d of %d rows total.%s\n', ...
        height(reservoir), n_seen, repmat(' ', 1, 20));
    if n_seen <= k
        fprintf('  ℹ File had fewer rows than requested — returning all %d.\n', n_seen);
    end
    fprintf('\n');
end

T = reservoir;

names      = T.Properties.VariableNames;
is_default = all(cellfun(@(n) ~isempty(regexp(n, '^Var\d+$', 'once')), names));
if is_default
    fprintf(['  ⚠ All column names are Var1, Var2, … — the header row may\n' ...
             '    not have been detected. Check the file manually.\n\n']);
end
end
```

- [ ] **Step 4: Run test to confirm pass**

```bash
python3 -m pytest tests/ -v -k "reservoir_sample"
```

Expected: PASS.

- [ ] **Step 5: Run full fast suite**

```bash
python3 -m pytest tests/ -v
```

Expected: PASS (checkcode on ReservoirSample.m runs automatically).

- [ ] **Step 6: Commit**

```bash
git add ReservoirSample.m tests/test_DataExplorer.m
git commit -m "Add ReservoirSample: Algorithm R reservoir sampling (rename of SampleData)"
```

---

## Task 3: Delete old files + update DataExplorer.m call sites

**Files:**
- Delete: `SampleData.m`, `SampleNetCDF.m`
- Modify: `DataExplorer.m` (5 sites)
- Modify: `CLAUDE.md`

There are no new tests for this task — the existing tests already cover the call sites end-to-end. If the replacements break something, existing tests catch it.

- [ ] **Step 1: Delete old files**

```bash
git rm SampleData.m SampleNetCDF.m
```

- [ ] **Step 2: Update se_load (line ~591)**

In `DataExplorer.m`, find:

```matlab
        T = SampleData(filepath, options.MaxRows, 'Verbose', true);
```

Replace with:

```matlab
        T = ReservoirSample(filepath, options.MaxRows, Verbose=true);
```

Note: `SampleData` used positional+name-value mixed; `ReservoirSample` uses the `arguments` block so named args work with `=` syntax.

- [ ] **Step 3: Update cg_load_code (two sites, lines ~2568 and ~2607)**

Find:

```matlab
        L{end+1} = sprintf('T = SampleData(inner_path, %d, ''Seed'', 42);', sampled_n);
```

Replace with:

```matlab
        L{end+1} = sprintf('T = ReservoirSample(inner_path, %d, Seed=42);', sampled_n);
```

Find:

```matlab
        L{end+1} = sprintf('T = SampleData(''%s'', %d, ''Seed'', 42);', filepath, sampled_n);
```

Replace with:

```matlab
        L{end+1} = sprintf('T = ReservoirSample(''%s'', %d, Seed=42);', filepath, sampled_n);
```

- [ ] **Step 4: Update fast-path (line ~91)**

Find:

```matlab
                        T_vi_ = SampleNetCDF(string(source), ...
                            Variable=string(vname_vi_), ...
                            MaxRows=options.MaxRows, Verbose=false);
```

Replace with:

```matlab
                        T_vi_ = StrideSample(string(source), ...
                            Variable=string(vname_vi_), ...
                            MaxRows=options.MaxRows, Verbose=false);
```

- [ ] **Step 5: Update cg_netcdf_spatial_recipe (line ~905)**

Find:

```matlab
    L{end+1} = sprintf('T = SampleNetCDF(''%s'', Variable=''%s'');', filepath, varname);
```

Replace with:

```matlab
    L{end+1} = sprintf('T = StrideSample(''%s'', Variable=''%s'');', filepath, varname);
```

Also update the comment above it:

Find:

```matlab
    L{end+1} = '% Load with stride sampling (never reads the full array)';
```

(No change needed — already accurate.)

Also update the function comment:

Find:

```matlab
%CG_NETCDF_SPATIAL_RECIPE  Write a recipe for a spatial NetCDF grid variable.
%   Recipe calls SampleNetCDF + de_geoscatter — both are public library
%   functions the student can re-use with different arguments.
```

Replace with:

```matlab
%CG_NETCDF_SPATIAL_RECIPE  Write a recipe for a spatial NetCDF grid variable.
%   Recipe calls StrideSample + de_geoscatter — both are public library
%   functions the student can re-use with different arguments.
```

- [ ] **Step 6: Update CLAUDE.md**

In `CLAUDE.md`, update the Usage section. Find:

```markdown
% Efficient uniform random sampling for large files (reservoir sampling)
T = SampleData('bigfile.csv', 50000)
```

Replace with:

```markdown
% Random reservoir sample for large files (any order, equal probability)
T = ReservoirSample('bigfile.csv', 50000)

% Deterministic stride sample for large files or 3-D NetCDF grids
T = StrideSample('bigfile.csv', MaxRows=50000)
T = StrideSample('climate.nc', Variable='prcp', MaxRows=10000)
```

Also update any sentence-level references to `SampleData` or `SampleNetCDF` in CLAUDE.md. Search with:

```bash
grep -n "SampleData\|SampleNetCDF" /Users/gregorymarton/Documents/GitHub/DataExplorer/CLAUDE.md
```

- [ ] **Step 7: Run fast suite**

```bash
python3 -m pytest tests/ -v
```

Expected: PASS. The `test_samplenetcdf_*` and `test_sampledata_*` tests still reference the old function names (the test methods themselves still call `SampleNetCDF`/`SampleData` which are now deleted) — those will FAIL here and get fixed in Task 4.

Actually: Task 4 should be done BEFORE this commit. Reorder: complete Step 1–6 edits, then fix the tests (Task 4 steps 1–4), then run the fast suite, then commit everything together.

OR: commit the DataExplorer.m + file deletions in one step, accept that some MATLAB-tagged tests break until Task 4 fixes them. The fast suite (`-v` without `-m slow`) does not run MATLAB tests, so the fast suite will still PASS after Step 6. The MATLAB tests (marked `slow`) are deferred to the background integration run after all tasks complete.

- [ ] **Step 8: Commit DataExplorer.m + deletions**

```bash
git add DataExplorer.m CLAUDE.md
git commit -m "Replace SampleData/SampleNetCDF with ReservoirSample/StrideSample at all call sites"
```

---

## Task 4: Update tests — rename SampleNetCDF → StrideSample references

**Files:**
- Modify: `tests/test_DataExplorer.m`

The following 4 test methods currently call `SampleNetCDF` or check for `'SampleNetCDF'` in recipe text. Each must be updated in place (rename method, update body).

- [ ] **Step 1: Rename test_samplenetcdf_returns_table_within_maxrows**

Find the method `test_samplenetcdf_returns_table_within_maxrows` (line ~1593). Change:
- Method name: `test_samplenetcdf_returns_table_within_maxrows` → `test_stridesample_netcdf_returns_table_within_maxrows`
- Body line: `T = SampleNetCDF(tmp, Variable='prcp', MaxRows=100, Verbose=false);` → `T = StrideSample(string(tmp), Variable='prcp', MaxRows=100, Verbose=false);`
- Comment: `SampleNetCDF should not exceed MaxRows significantly` → `StrideSample should not exceed MaxRows significantly`

- [ ] **Step 2: Rename test_samplenetcdf_latrange_filters_rows**

Find `test_samplenetcdf_latrange_filters_rows` (line ~1617). Change:
- Method name: → `test_stridesample_netcdf_latrange_filters_rows`
- Body line: `T = SampleNetCDF(tmp, Variable='prcp', LatRange=[30 60], Verbose=false);` → `T = StrideSample(string(tmp), Variable='prcp', LatRange=[30 60], Verbose=false);`
- Assertion message: `SampleNetCDF` → `StrideSample` in any string literals

- [ ] **Step 3: Rename test_samplenetcdf_auto_selects_first_data_variable**

Find `test_samplenetcdf_auto_selects_first_data_variable` (line ~1636). Change:
- Method name: → `test_stridesample_netcdf_auto_selects_first_data_variable`
- Body line: `T = SampleNetCDF(tmp, Verbose=false);` → `T = StrideSample(string(tmp), Verbose=false);`

- [ ] **Step 4: Update test_netcdf_spatial_recipe_contains_geoscatter**

Find `test_netcdf_spatial_recipe_contains_geoscatter` (line ~1684). Change:
- The assertion on line ~1710:
  ```matlab
  testCase.verifyTrue(contains(recipe_text, 'SampleNetCDF'), ...
      'Recipe must call SampleNetCDF');
  ```
  → 
  ```matlab
  testCase.verifyTrue(contains(recipe_text, 'StrideSample'), ...
      'Recipe must call StrideSample');
  ```
- Also update the comment on line ~1685: `% Recipe for a spatial grid NetCDF must call SampleNetCDF and de_geoscatter.` → `% Recipe for a spatial grid NetCDF must call StrideSample and de_geoscatter.`

- [ ] **Step 5: Run the updated tests (fast suite)**

```bash
python3 -m pytest tests/ -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tests/test_DataExplorer.m
git commit -m "Update tests: SampleNetCDF → StrideSample references"
```

---

## Task 5: Fix fast-path recipe display

**Files:**
- Modify: `DataExplorer.m` (lines ~131–134)

The slow path (single-variable, line ~191) already prints the recipe path and offers `save_recipe()` after running. The fast-path (multi-variable NetCDF loop) runs the recipe silently. Fix that.

- [ ] **Step 1: Locate the fast-path recipe block**

In `DataExplorer.m`, find (lines ~131–134):

```matlab
                if ~isempty(recipe_vi_)
                    T_ret_ = T_vi_; run(recipe_vi_); T_vi_ = T_ret_;
                end
                T = T_vi_;
```

- [ ] **Step 2: Replace with version that prints + offers save**

```matlab
                if ~isempty(recipe_vi_)
                    T_ret_ = T_vi_; run(recipe_vi_); T_vi_ = T_ret_;
                    fprintf('\n  ══════════════════════════════════════════════════════════\n');
                    fprintf('  Recipe script: %s\n', recipe_vi_);
                    fprintf('  To keep it:    save_recipe(''%s_%s_recipe.m'')\n', fn_, vname_vi_);
                    fprintf('  ══════════════════════════════════════════════════════════\n\n');
                end
                T = T_vi_;
```

Both `fn_` (file basename without extension) and `vname_vi_` (variable name) are in scope at this point in both the spatial-grid and tabular branches of the loop.

- [ ] **Step 3: Run fast suite**

```bash
python3 -m pytest tests/ -v
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add DataExplorer.m
git commit -m "Fast-path NetCDF loop: always print recipe path + save_recipe offer"
```

---

## Task 6: Recipe abstraction audit

**Files:**
- Modify: `CLAUDE.md` (add a note in Planned Work)

This task measures actual recipe output length for the key `cg_*` generators and identifies sections worth wrapping as library functions. No code changes unless a single clear win emerges.

- [ ] **Step 1: Measure output of each cg_* generator**

Read `DataExplorer.m` sections and count approximate lines of generated code per section for a representative dataset (e.g., Prod_dataset.xlsx with wide-year columns and a state column):

| Generator | Typical output lines | Notes |
|-----------|---------------------|-------|
| `cg_load_code` | 1–8 | Varies by format; usually 1 line for CSV |
| `cg_clean_code` | 5–10 | Fixed boilerplate |
| `cg_best_plots_code` | 20–55 | Larger with compositional time series |
| `cg_state_choropleth_code` | 8–10 (non-wide) / 10–12 (wide) | Calls `de_statebins` |
| `cg_country_choropleth_code` | 8–10 | Calls `de_countrybins` |
| `cg_geo_multicategorical_code` | 10 (pivot) + 4 per pair | Pivot boilerplate repeated |
| `cg_netcdf_spatial_recipe` | 9 | Calls `StrideSample` + `de_geoscatter` |

For a Prod_dataset.xlsx-style file: ~5 + 8 + 45 + 12 + 0 + 20 ≈ **~90 lines total**. Borderline.

The `cg_best_plots_code` time-series block with stacked variant is the largest single section (~30 lines for the overlaid+stacked block).

- [ ] **Step 2: Identify repeated boilerplate**

The wide-year pivot block appears in `cg_state_choropleth_code`, `cg_country_choropleth_code`, AND `cg_geo_multicategorical_code`. Each emits a 7-line pivot:

```matlab
yr_XX = {'x1960', ..., 'x2023'};   % very long when 60+ years
yr_v_XX = [1960, ..., 2023];
n_yr_XX = numel(yr_v_XX); n_r_XX = height(T);
kp_XX = T.Properties.VariableNames(~ismember(T.Properties.VariableNames, yr_XX));
T_long_XX = repmat(T(:,kp_XX), n_yr_XX, 1);
T_long_XX.Year = repelem(yr_v_XX(:), n_r_XX);
T_long_XX.Value = reshape(cell2mat(cellfun(@(c) double(T.(c)), yr_XX, ...
    'UniformOutput', false).'), [], 1);
```

This is the main abstraction opportunity. A `de_pivot_wide_years(T, yr_cols)` helper would collapse each block to 1 line. However, each block uses a different variable suffix (`_ch`, `_co`, `_gm`) to avoid collisions when all three sections appear in the same recipe — so a refactor would also need to unify variable names.

The `cg_best_plots_code` time-series block (overlaid + stacked) is ~30 lines per call. It could become a call to `de_timeseries(T, time_col, value_cols)` — but that function does not yet exist and would require significant work.

- [ ] **Step 3: Write findings to CLAUDE.md**

In `CLAUDE.md`, find the `### Task 5` entry and add a note at the end:

```markdown
**Recipe abstraction candidates (2026-05-26):**
- **Wide-year pivot** (highest priority): the 7-line pivot block (`repmat` + `repelem` + `reshape/cell2mat`) appears in all three geo recipe generators. Wrapping as `de_pivot_wide_years(T, yr_cols)` → `T_long` would reduce each block to 1 line and shrink a Prod_dataset recipe by ~14 lines. Requires renaming the per-section variable suffixes (`_ch`, `_co`, `_gm`) to a single `T_long`.
- **Time-series block** (lower priority): the overlaid+stacked block in `cg_best_plots_code` (~30 lines) could become `de_timeseries(T, time_col, value_cols)` but that library function doesn't exist yet.
- **Overall recipe length**: ~90 lines for a Prod_dataset-style file — below the 100-line concern threshold but the wide-year pivot makes it verbose and hard to read.
```

- [ ] **Step 4: Run fast suite + commit**

```bash
python3 -m pytest tests/ -v
git add CLAUDE.md
git commit -m "Recipe audit: document wide-year pivot and timeseries block as abstraction candidates"
```

---

## Self-Review

**Spec coverage:**
- ✅ StrideSample.m — tabular stride + NetCDF stride — Task 1
- ✅ ReservoirSample.m — rename of SampleData — Task 2
- ✅ Delete SampleData.m + SampleNetCDF.m — Task 3
- ✅ Update call sites: se_load, cg_load_code (×2), fast-path, cg_netcdf_spatial_recipe — Task 3
- ✅ Update CLAUDE.md — Task 3
- ✅ Update tests — Task 4
- ✅ Recipe print + save offer on fast-path — Task 5
- ✅ Recipe abstraction audit — Task 6

**Placeholder scan:** No TBDs or vague requirements.

**Type consistency:**
- `StrideSample(filepath, options)` — arguments block with named options; callers use `Variable=`, `MaxRows=`, etc. ✅
- `ReservoirSample(filepath, nrows, options)` — positional `nrows` then named options. ✅
- `cg_load_code` emits `ReservoirSample('path', N, Seed=42)` — matches the `arguments` block. ✅
- Fast-path: `StrideSample(string(source), Variable=string(vname_vi_), MaxRows=options.MaxRows, Verbose=false)` — matches the `arguments` block. ✅
