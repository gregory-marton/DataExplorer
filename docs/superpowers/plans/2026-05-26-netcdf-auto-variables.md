# NetCDF Auto-Variable Iteration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **STATUS (reviewed 2026-06-08): DONE, then SUPERSEDED.** Implemented as the multi-variable NetCDF fast-path (`nc_list_data_vars`, `load_netcdf` loop, NCVariable override, fixed recipe load code), then replaced this session by the "conformable or ask" `de_load` unification (commits 8b67efd, 1371691, c9eb563, bea399e) — `nc_list_data_vars`/`load_netcdf` were deleted. Kept for history; not actionable.

**Goal:** DataExplorer automatically iterates all data variables in a NetCDF file (no user prompt), applies a size-based heuristic for >2D reduction, and emits `DataExplorer(filepath, NCVariable='...')` in the echo/recipe load code instead of the misleading `ncread(...)`.

**Architecture:** Three changes to `DataExplorer.m`: (1) a new `nc_list_data_vars(info)` helper that identifies coordinate vs. data variables; (2) a multi-variable fast-path in the main entry point that loops over data variables when no `NCVariable` is specified; (3) a non-interactive heuristic inside `load_netcdf` for >2D data when `NCVariable` is set; and (4) fixed echo/recipe load code for NetCDF. The `NCVariable` option continues to work as an explicit override that loads a single named variable.

**Tech Stack:** MATLAB, `ncinfo`/`ncread`/`nccreate`/`ncwrite` (base MATLAB), `pytest` + `matlab.unittest`.

---

## Background: existing code to read first

- `DataExplorer.m` lines 1–133: main entry point — the multi-variable fast-path inserts just before `T = se_load(...)` at line 71.
- `DataExplorer.m` lines 538–755: `load_netcdf` — the heuristic replaces the interactive `input()` prompts for >2D data when `NCVariable` is set.
- `DataExplorer.m` lines 818–844: `nc_flatten_to_table` — used by the flatten heuristic.
- `DataExplorer.m` lines 2427–2434: `cg_load_code` NetCDF branch — the section to fix.

## File structure

**Modified:**
- `DataExplorer.m` — new `nc_list_data_vars` local function; multi-variable loop in main entry; heuristic in `load_netcdf`; fixed `cg_load_code` NetCDF branch.
- `tests/test_DataExplorer.m` — three new tests.

---

## Task 1: `nc_list_data_vars` helper + non-interactive >2D heuristic

**Files:**
- Modify: `DataExplorer.m`
- Modify: `tests/test_DataExplorer.m`

### Step 1: Write the failing test

In `tests/test_DataExplorer.m`, add before the class-closing `end`:

```matlab
function test_load_netcdf_with_ncvariable_no_prompt(testCase)
    % load_netcdf with NCVariable set must not error on >2D data (no prompt).
    % Uses a 2D variable (lon×lat) so no reduction needed — just verifies
    % that setting NCVariable bypasses any interactive path.
    tmp = [tempname '.nc'];
    cl = onCleanup(@() delete(tmp));
    nccreate(tmp, 'lon',  'Dimensions', {'lon', 4}, 'Format', 'classic');
    nccreate(tmp, 'lat',  'Dimensions', {'lat', 3}, 'Format', 'classic');
    nccreate(tmp, 'temp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
    ncwrite(tmp, 'lon',  [100;110;120;130]);
    ncwrite(tmp, 'lat',  [10;20;30]);
    ncwrite(tmp, 'temp', rand(4,3));

    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    % Should complete without error and return a table
    T = DataExplorer(tmp, NCVariable='temp');
    testCase.verifyClass(T, 'table');
    testCase.verifyGreaterThan(height(T), 0);
end
```

Run fast suite (smoke check — fast only, no `-m slow`):
```bash
python3 -m pytest tests/ -v
```
Expected: same 4 pre-existing failures, no new failures. The new test is marked slow so it won't run here.

### Step 2: Add `nc_list_data_vars` local function to `DataExplorer.m`

Find the line `function rc = filter_coords(coord_vars, dim_names)` (around line 758) and insert this new function immediately before it:

```matlab
% ── nc_list_data_vars ─────────────────────────────────────────────────────────
function data_vars = nc_list_data_vars(info)
%NC_LIST_DATA_VARS  Names of data variables in a NetCDF file.
%   A coordinate variable is one whose name matches any dimension name used
%   anywhere in the file.  Everything else with at least one element is a
%   data variable.
all_dims = {};
for k = 1:numel(info.Variables)
    if ~isempty(info.Variables(k).Dimensions)
        all_dims = [all_dims, {info.Variables(k).Dimensions.Name}]; %#ok<AGROW>
    end
end
all_dims = unique(all_dims);

data_vars = {};
for k = 1:numel(info.Variables)
    v = info.Variables(k);
    if ~ismember(v.Name, all_dims) && ~isempty(v.Size) && prod(v.Size) > 0
        data_vars{end+1} = v.Name; %#ok<AGROW>
    end
end
end
```

### Step 3: Add non-interactive heuristic in `load_netcdf` for >2D when `NCVariable` is set

Read `DataExplorer.m` lines 660–676 — the section that resolves the reduction choice. It currently has three branches:
1. `ismember(nc_red, {'flatten','mean','slice'})` — NCReduction was set
2. `options.AutoSelect` — pick flatten
3. `else` — interactive prompt

Add a fourth branch between 2 and 3 (i.e., before the `else` block), for when `NCVariable` is explicitly set (meaning we're in a scripted or auto-iteration context):

```matlab
        elseif strlength(options.NCVariable) > 0
            % NCVariable was specified → use size heuristic, no prompt
            if total_elems <= options.MaxRows * 10
                raw = '3';
                fprintf('  Auto: flattening to long-format (%d elements)\n', total_elems);
            else
                % Find a time-like dimension to average over
                dim_choice = 1;
                for k = 1:ndim
                    if ~isempty(regexpi(dim_names{k}, 'time|^t$|day|month|year', 'once'))
                        dim_choice = k; break;
                    end
                end
                raw = '1';
                fprintf('  Auto: mean over "%s" (%d elements > MaxRows×10)\n', ...
                    dim_names{dim_choice}, total_elems);
            end
```

Read the exact existing code before editing to get the right insertion point.

### Step 4: Run the fast suite

```bash
python3 -m pytest tests/ -v
```

Expected: same 4 pre-existing failures. `test_checkcode_clean[DataExplorer.m]` must still PASS.

### Step 5: Commit

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "Add nc_list_data_vars; non-interactive heuristic for >2D NetCDF when NCVariable set"
```

---

## Task 2: Multi-variable fast-path in the main entry point

When `DataExplorer` receives a NetCDF file and no `NCVariable` is specified, iterate all data variables (up to `MaxVars`) and run the full pipeline (profile → echo → report → plot → recipe) for each.

**Files:**
- Modify: `DataExplorer.m` (main entry, lines 70–133)
- Modify: `tests/test_DataExplorer.m`

### Step 1: Write the failing test

Add before the class-closing `end` in `tests/test_DataExplorer.m`:

```matlab
function test_netcdf_multi_var_produces_multiple_figures(testCase)
    % DataExplorer on a 2-data-variable NetCDF must produce at least 2 figures.
    tmp = [tempname '.nc'];
    cl = onCleanup(@() delete(tmp));
    nccreate(tmp, 'lon',  'Dimensions', {'lon', 4}, 'Format', 'classic');
    nccreate(tmp, 'lat',  'Dimensions', {'lat', 3}, 'Format', 'classic');
    nccreate(tmp, 'temp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
    nccreate(tmp, 'prcp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
    ncwrite(tmp, 'lon',  [100;110;120;130]);
    ncwrite(tmp, 'lat',  [10;20;30]);
    ncwrite(tmp, 'temp', rand(4,3));
    ncwrite(tmp, 'prcp', rand(4,3) * 10);

    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
    figs_before = findobj(0,'Type','figure');

    DataExplorer(tmp);

    figs_after  = findobj(0,'Type','figure');
    new_figs    = setdiff(figs_after, figs_before);
    cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

    testCase.verifyGreaterThanOrEqual(numel(new_figs), 2, ...
        'Expected at least one figure per NetCDF data variable');
end
```

Run fast suite:
```bash
python3 -m pytest tests/ -v
```
Expected: same results, no new failures (new test is slow-marked).

### Step 2: Add the multi-variable fast-path

Read `DataExplorer.m` lines 70–85 to see the exact text around `T = se_load(string(source), options)`.

Insert the multi-variable block BEFORE the `T = se_load(...)` call. The check must be:
- `ischar(source) || isstring(source)` (file path)
- Extension is `.nc`, `.nc4`, or `.netcdf`
- `options.NCVariable` is empty (no explicit variable requested)

If all three, enumerate data vars and run a per-variable sub-pipeline, then `return`.

```matlab
%% ── 1a.  NetCDF multi-variable fast-path ─────────────────────────────────
if (ischar(source) || isstring(source))
    [~, ~, nc_ext] = fileparts(string(source));
    if ismember(lower(string(nc_ext)), [".nc", ".nc4", ".netcdf"]) && ...
            strlength(options.NCVariable) == 0
        nc_info   = ncinfo(string(source));
        data_vars = nc_list_data_vars(nc_info);
        if ~isempty(data_vars)
            n_plot = min(options.MaxVars, numel(data_vars));
            fprintf('  NetCDF: %d data variable(s) found; plotting %d.\n', ...
                numel(data_vars), n_plot);
            T = table();   % default return if all vars fail
            for nc_vi = 1:n_plot
                opts_vi = options;
                opts_vi.NCVariable = string(data_vars{nc_vi});
                try
                    T_vi = se_load(string(source), opts_vi);
                catch ME
                    fprintf('  ⚠ Skipping "%s": %s\n', data_vars{nc_vi}, ME.message);
                    continue
                end
                [T_vi, prof_vi] = se_profile(T_vi, options.MissingStrings);
                [~, fn, fe] = fileparts(string(source));
                prof_vi.source_name = sprintf('%s%s [%s]', fn, fe, data_vars{nc_vi});
                se_echo_load_code(string(source), T_vi);
                se_report(T_vi, prof_vi);
                panel_vi = se_detect_panel(T_vi, prof_vi);
                se_plot(T_vi, prof_vi, opts_vi, panel_vi);
                recipe_vi = se_assemble_recipe(string(source), T_vi, prof_vi, panel_vi, opts_vi);
                if ~isempty(recipe_vi)
                    T_ret = T_vi;
                    run(recipe_vi);
                    T_vi = T_ret;
                end
                T = T_vi;
            end
            return
        end
        % If no data vars found, fall through to normal single-var path
    end
end
```

This block goes between the `end` of the file-picker block (line ~68) and the `T = se_load(...)` line (line 71). Place it at line 70, so the existing `if ischar(source) || isstring(source)` block (line 70) gets this prefix before the `T = se_load` call.

**Read the actual code at lines 70–84 before editing** to get the exact context for the `old_string`.

### Step 3: Run the fast suite

```bash
python3 -m pytest tests/ -v
```

Expected: `test_checkcode_clean[DataExplorer.m]` PASSES; same 4 pre-existing failures elsewhere.

### Step 4: Commit

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "NetCDF multi-variable fast-path: iterate all data variables automatically"
```

---

## Task 3: Fix echo/recipe load code for NetCDF

Replace `ncread(...)` in the recipe load section with `DataExplorer(filepath, NCVariable='...')`.

**Files:**
- Modify: `DataExplorer.m` (`cg_load_code`, lines ~2427–2434)
- Modify: `tests/test_DataExplorer.m`

### Step 1: Write the failing test

Add before the class-closing `end`:

```matlab
function test_netcdf_recipe_load_code_uses_dataexplorer(testCase)
    % Recipe load code for NetCDF must contain DataExplorer(...), not ncread.
    tmp = [tempname '.nc'];
    cl = onCleanup(@() delete(tmp));
    nccreate(tmp, 'lon',  'Dimensions', {'lon', 4}, 'Format', 'classic');
    nccreate(tmp, 'lat',  'Dimensions', {'lat', 3}, 'Format', 'classic');
    nccreate(tmp, 'temp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
    ncwrite(tmp, 'lon',  [100;110;120;130]);
    ncwrite(tmp, 'lat',  [10;20;30]);
    ncwrite(tmp, 'temp', rand(4,3));

    old_vis = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

    DataExplorer(tmp, NCVariable='temp');

    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    testCase.assertNotEmpty(hits, 'Expected a recipe file in tempdir');
    [~, newest] = max([hits.datenum]);
    recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
    testCase.verifyTrue(contains(recipe_text, 'DataExplorer'), ...
        'Recipe load code must use DataExplorer(), not ncread()');
    testCase.verifyFalse(contains(recipe_text, 'ncread'), ...
        'Recipe load code must not contain ncread');
end
```

Run fast suite:
```bash
python3 -m pytest tests/ -v
```
Expected: same results.

### Step 2: Fix `cg_load_code` NetCDF branch

Read `DataExplorer.m` around lines 2427–2434. The current content:

```matlab
elseif ismember(ext, [".nc", ".nc4", ".netcdf"])
    nc_var = 'varname';
    if isstruct(ud) && isfield(ud, 'nc_varname') && ~isempty(ud.nc_varname)
        nc_var = char(ud.nc_varname);
    end
    L{end+1} = sprintf('%% NetCDF — adjust variable/start/count as needed:');
    L{end+1} = sprintf('data = ncread(''%s'', ''%s'');', filepath, nc_var);
    L{end+1} = sprintf('%% See ncinfo(''%s'') for available variables.', filepath);
```

Replace it with:

```matlab
elseif ismember(ext, [".nc", ".nc4", ".netcdf"])
    nc_var = '';
    if isstruct(ud) && isfield(ud, 'nc_varname') && ~isempty(ud.nc_varname)
        nc_var = char(ud.nc_varname);
    end
    if ~isempty(nc_var)
        L{end+1} = sprintf('T = DataExplorer(''%s'', NCVariable=''%s'');', filepath, nc_var);
    else
        L{end+1} = sprintf('T = DataExplorer(''%s'');', filepath);
    end
    L{end+1} = sprintf('%% Available variables: see ncinfo(''%s'').Variables', filepath);
```

### Step 3: Run the fast suite

```bash
python3 -m pytest tests/ -v
```

Expected: `test_checkcode_clean[DataExplorer.m]` PASSES; same 4 pre-existing failures.

### Step 4: Commit

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "Fix NetCDF echo/recipe load code: emit DataExplorer() instead of ncread()"
```

---

## Self-review

**Spec coverage:**
- ✅ Iterate all data variables automatically when no `NCVariable` given (Task 2)
- ✅ Coordinate variable exclusion via `nc_list_data_vars` (Task 1)
- ✅ Non-interactive >2D heuristic: flatten if ≤ MaxRows×10, else mean over time dim (Task 1)
- ✅ `NCVariable` override still works as explicit single-variable path (existing code, unchanged)
- ✅ Cap at `MaxVars` variables (Task 2)
- ✅ Echo/recipe load code fixed to `DataExplorer(filepath, NCVariable='...')` (Task 3)
- ✅ Geo figure (`se_plot_geo`) fires for variables with `lat`/`lon` columns — already handled by the existing profiler detecting lat/lon column names in the flattened table

**Gaps acknowledged:**
- Lat/lon column names in the flattened table depend on the NetCDF dimension naming convention. If dimensions are named `x`/`y` rather than `lon`/`lat`, geo detection won't fire. This is a pre-existing limitation of `se_plot_geo`, not introduced here.
- Time dimension becomes a numeric column (seconds since epoch or similar) — not converted to datetime. This is also pre-existing. A future improvement would parse the `units` attribute.
- The `se_echo_load_code` call inside the multi-variable loop (Task 2) prints the load snippet to the console for each variable. This is intentional — the user sees a reproducible snippet per variable.
