function T = DataExplorer(source, options)
%SMARTEXPLORE  Forgiving data exploration for mixed-type tables.
%
%   T = DataExplorer()                  file picker dialog
%   T = DataExplorer(filename)          load CSV, TSV, TXT, XLSX, or ZIP
%   T = DataExplorer(T_in)             explore an existing table
%
%   Optional name-value arguments
%   ─────────────────────────────
%   MaxRows        (10000)   random-sample large files to this many rows
%   MaxVars        (8)       columns shown in the plot matrix; prefers numeric
%   Columns        ([])      override: specific names or indices to plot
%   MissingStrings (list)    extra strings to recode as missing (see defaults)
%   AutoSelect     (false)   skip all interactive prompts; pick defaults
%                            (largest sheet/file; NetCDF: largest variable, flatten 3D+)
%   Sheet          ("")      load a specific Excel sheet by name (bypasses prompt)
%   InnerFile      ("")      load a specific file from a ZIP by name (bypasses prompt)
%   NCVariable     ("")      NetCDF: variable name to load (bypasses variable prompt)
%   NCReduction    ("")      NetCDF 3D+: "flatten" | "mean" | "slice" (bypasses reduction prompt)
%   NCDimension    (1)       NetCDF: dimension index for "mean" or "slice" reduction
%   NCSliceIndex   (1)       NetCDF: element index along NCDimension when NCReduction="slice"
%
%   Examples
%   ────────
%   T = DataExplorer();                       % pick a file interactively
%   T = DataExplorer('bluebikes_2024.csv');
%   T = DataExplorer('wonder_export.txt', MaxRows=50000);
%   T = DataExplorer(T, Columns=["age","sbp","dbp","sex"]);

arguments
    source = []
    options.MaxRows         (1,1) double  = 10000
    options.MaxVars         (1,1) double  = 8
    options.Columns                       = []          % names (string/char/cell) or indices
    options.MissingStrings  (1,:) string  = [...
        "Suppressed", "N/A", "NA", "n/a", "--", "-", ...
        "None", "none", "null", "NULL", "missing", ...
        "Missing", "?", "Unknown", "unknown", "*"]
    options.AutoSelect      (1,1) logical = false       % skip interactive prompts, pick default
    options.Sheet           (1,1) string  = ""          % load a specific Excel sheet by name
    options.InnerFile       (1,1) string  = ""          % load a specific file from a ZIP
    options.NCVariable      (1,1) string  = ""          % NetCDF: variable name to load
    options.NCReduction     (1,1) string  = ""          % NetCDF 3D+: "flatten"|"mean"|"slice"
    options.NCDimension     (1,1) double  = 1           % NetCDF: dimension index for mean/slice
    options.NCSliceIndex    (1,1) double  = 1           % NetCDF: element index when NCReduction="slice"
end

%% ── 0.  Version check ────────────────────────────────────────────────────
% Developed and tested on R2025b (25.2). Features like DataTipTemplate,
% boxchart, and the arguments block require recent releases.
if isMATLABReleaseOlderThan('R2025b')
    warning('DataExplorer:oldMatlab', ...
        'DataExplorer targets R2025b; running %s — tooltips, boxchart, and arguments blocks may not work.', ...
        version('-release'));
end

%% ── 1.  Load ──────────────────────────────────────────────────────────────
if isempty(source)
    [fname, fpath] = uigetfile( ...
        {'*.csv;*.tsv;*.txt;*.xlsx;*.xls;*.xlsm;*.zip;*.nc;*.nc4;*.netcdf', 'Data files'}, ...
        'Select a data file');
    if isequal(fname, 0)
        fprintf('  No file selected.\n');
        T = table();
        return
    end
    source = fullfile(fpath, fname);
end

if ischar(source) || isstring(source)
    T = se_load(string(source), options);
elseif istable(source)
    T = source;
    fprintf('  Using existing table: %d × %d\n', height(T), width(T));
else
    error('DataExplorer:badInput', ...
        'source must be a filename (string/char) or a table.');
end

%% ── 2.  Profile & clean ───────────────────────────────────────────────────
[T, prof] = se_profile(T, options.MissingStrings);

% Attach a display name for the figure title
if ischar(source) || isstring(source)
    [~, fname, fext] = fileparts(string(source));
    base = fname + fext;
    ud   = T.Properties.UserData;
    if isstruct(ud)
        if ~isempty(ud.inner_file)
            base = sprintf('%s » %s', base, ud.inner_file);
        end
        if ~isempty(ud.sheet)
            base = sprintf('%s [%s]', base, ud.sheet);
        end
    end
    prof.source_name = base;
elseif istable(source)
    prof.source_name = 'table input';
end

%% ── 3.  Echo load code ────────────────────────────────────────────────────
if ischar(source) || isstring(source)
    se_echo_load_code(string(source), T);
end

%% ── 4.  Report ────────────────────────────────────────────────────────────
se_report(T, prof);

%% ── 4.  Plot ──────────────────────────────────────────────────────────────
se_plot(T, prof, options);

%% ── 5.  Recipe ────────────────────────────────────────────────────────────
if ischar(source) || isstring(source)
    recipe_path = se_assemble_recipe(string(source), T, prof, options);
    if ~isempty(recipe_path)
        fprintf('  Running recipe to produce best-of plots…\n');
        T_return = T;   % run() shares our workspace; save T so recipe can't overwrite it
        run(recipe_path);
        T = T_return;
        [~, bname, ~] = fileparts(source);
        fprintf('\n  ══════════════════════════════════════════════════════════\n');
        fprintf('  Recipe script: %s\n', recipe_path);
        fprintf('  To keep it:    save_recipe(''%s_recipe.m'')\n', bname);
        fprintf('  ══════════════════════════════════════════════════════════\n\n');
    end
end

end % ── DataExplorer ──────────────────────────────────────────────────────


%% ═══════════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTIONS
%% ═══════════════════════════════════════════════════════════════════════════

% ── se_load ─────────────────────────────────────────────────────────────────
function T = se_load(filepath, options)
%SE_LOAD  Detect format, sniff delimiter, detect header row, load table.

if ~isfile(filepath)
    error('DataExplorer:fileNotFound', ...
        'File not found: %s\n(current folder: %s)', filepath, pwd);
end

[~, basename, ext] = fileparts(filepath);
ext = string(lower(ext));
fprintf('\n  Loading: %s%s\n', basename, ext);

%  ZIP → unzip to temp, recurse
if ext == ".zip"
    T = load_from_zip(filepath, options);
    return
end

%  NetCDF
if ismember(ext, [".nc", ".nc4", ".netcdf"])
    T = load_netcdf(filepath, options);
    return
end

%  Excel
if ismember(ext, [".xlsx", ".xls", ".xlsm"])
    T = load_excel(filepath, options);
    return
end

%  Text (CSV / TSV / TXT / DAT)
T = load_text(filepath, options);
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = load_from_zip(filepath, options)
    tmpdir = tempname;
    mkdir(tmpdir);
    unzip(filepath, tmpdir);

    % collect candidate data files recursively (case-insensitive extension match)
    ok_exts = {'.csv', '.tsv', '.txt', '.xlsx', '.xls', '.asc'};
    all_files = dir(fullfile(tmpdir, '**', '*.*'));
    all_files = all_files(~[all_files.isdir]);
    keep = false(1, numel(all_files));
    for k = 1:numel(all_files)
        [~, ~, ext] = fileparts(all_files(k).name);
        keep(k) = ismember(lower(ext), ok_exts);
    end
    files = all_files(keep);

    if isempty(files)
        error('DataExplorer:emptyZip', 'No CSV/TSV/XLSX/ASC found inside the ZIP.');
    end

    if strlength(options.InnerFile) > 0
        % Caller pinned a specific inner file — find it by name.
        all_names = {files.name};
        match = find(strcmp(all_names, char(options.InnerFile)), 1);
        if isempty(match)
            error('DataExplorer:innerFileNotFound', ...
                'File "%s" not found inside ZIP. Available: %s', ...
                options.InnerFile, strjoin(all_names, ', '));
        end
        choice_idx = match;
    elseif isscalar(files)
        choice_idx = 1;
    else
        SMALL_FILE_BYTES = 5000;

        % Always sort ascending by size so largest (default) is at the bottom
        [~, size_ord] = sort([files.bytes], 'ascend');
        files_sorted  = files(size_ord);

        % Suppress tiny files only when there are many files overall
        if numel(files) > 10
            shown      = find([files_sorted.bytes] >= SMALL_FILE_BYTES);
            suppressed = find([files_sorted.bytes] <  SMALL_FILE_BYTES);
        else
            shown      = 1:numel(files_sorted);
            suppressed = [];
        end

        fprintf('  Files found inside ZIP (sorted by size):\n');
        for k = 1:numel(shown)
            idx = shown(k);
            sz  = files_sorted(idx).bytes;
            if sz >= 1e6
                sz_str = sprintf('%.1f MB', sz/1e6);
            else
                sz_str = sprintf('%.0f KB', sz/1e3);
            end
            fprintf('    [%2d]  %-40s  %s\n', k, files_sorted(idx).name, sz_str);
        end

        if ~isempty(suppressed)
            fprintf('  (%d lookup/admin files under 5 KB hidden — enter filename to load one)\n', ...
                numel(suppressed));
        end

        fprintf('\n');
        default_num = numel(shown);
        fprintf('  Enter number (default %d = %s),\n', ...
            default_num, files_sorted(shown(default_num)).name);

        if options.AutoSelect
            choice_idx = shown(default_num);
            fprintf('  AutoSelect: picking default "%s"\n', files_sorted(choice_idx).name);
        else
            while true
                raw = input('  or filename for a hidden file: ', 's');
                if isempty(raw)
                    choice_idx = shown(default_num);
                    break
                elseif all(ismember(raw, '0123456789'))
                    n = str2double(raw);
                    if n >= 1 && n <= numel(shown)
                        choice_idx = shown(n);
                        break
                    else
                        fprintf('  Please enter a number between 1 and %d.\n', numel(shown));
                    end
                else
                    match = find(strcmp({files_sorted.name}, raw), 1);
                    if ~isempty(match)
                        choice_idx = match;
                        break
                    else
                        fprintf('  File "%s" not found in ZIP.\n', raw);
                    end
                end
            end
        end

        files = files_sorted;
    end

    T = se_load(fullfile(files(choice_idx).folder, files(choice_idx).name), options);
    % Annotate with the inner filename so source_name can reference it
    if isempty(T.Properties.UserData)
        T.Properties.UserData = struct('sheet', '', 'inner_file', files(choice_idx).name);
    else
        T.Properties.UserData.inner_file = files(choice_idx).name;
    end
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = load_excel(filepath, options)
    sheets = sheetnames(filepath);

    if strlength(options.Sheet) > 0
        % Caller pinned a specific sheet — validate and use it directly.
        if ~ismember(options.Sheet, sheets)
            error('DataExplorer:sheetNotFound', ...
                'Sheet "%s" not found. Available: %s', ...
                options.Sheet, strjoin(sheets, ', '));
        end
        sheetname = char(options.Sheet);
    elseif isscalar(sheets)
        sheetname = sheets{1};
    else
        % Get row and column count for each sheet
        fprintf('  Counting rows in each sheet…\n');
        nrows = zeros(numel(sheets), 1);
        ncols = zeros(numel(sheets), 1);
        for k = 1:numel(sheets)
            try
                o = detectImportOptions(filepath, 'Sheet', sheets{k});
                ncols(k) = numel(o.VariableNames);
                if ncols(k) > 0
                    o.SelectedVariableNames = o.VariableNames(1);
                    tmp = readtable(filepath, o, 'Sheet', sheets{k});
                    nrows(k) = height(tmp);
                end
            catch
                nrows(k) = 0;
                ncols(k) = 0;
            end
        end

        % Sort ascending so largest is at the bottom (closest to prompt)
        [~, ord] = sort(nrows, 'ascend');
        sheets_s = sheets(ord);
        nrows_s  = nrows(ord);
        ncols_s  = ncols(ord);

        fprintf('  Sheets found in workbook (sorted by row count):\n');
        for k = 1:numel(sheets_s)
            fprintf('    [%2d]  %-35s  %d rows × %d columns\n', ...
                k, sheets_s{k}, nrows_s(k), ncols_s(k));
        end

        default_num = numel(sheets_s);
        fprintf('\n');

        if options.AutoSelect
            sheetname = sheets_s{default_num};
            fprintf('  AutoSelect: picking largest sheet "%s"\n', sheetname);
        else
            while true
                raw = input(sprintf('  Which sheet? (name or number, Enter = %d = %s): ', ...
                    default_num, sheets_s{default_num}), 's');
                if isempty(raw)
                    sheetname = sheets_s{default_num};
                    break
                elseif all(ismember(raw, '0123456789'))
                    idx = str2double(raw);
                    if idx >= 1 && idx <= numel(sheets_s)
                        sheetname = sheets_s{idx};
                        break
                    else
                        fprintf('  Please enter a number between 1 and %d.\n', numel(sheets_s));
                    end
                elseif ismember(raw, sheets_s)
                    sheetname = raw;
                    break
                else
                    fprintf('  Sheet "%s" not found. Options: %s\n', raw, strjoin(sheets_s, ', '));
                end
            end
        end
    end

    fprintf('  Reading sheet "%s"…\n', sheetname);
    opts = detectImportOptions(filepath, 'Sheet', sheetname);
    opts.MissingRule = 'fill';
    T = readtable(filepath, opts, 'Sheet', sheetname);
    T.Properties.UserData = struct('sheet', sheetname, 'inner_file', '');
    T = se_fix_names(T, filepath, '.xlsx', sheetname);
    T = se_sample(T, options.MaxRows);
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = load_text(filepath, options)
    % Sniff delimiter from the first line
    fid = fopen(filepath, 'r', 'n', 'UTF-8');
    if fid == -1
        fid = fopen(filepath, 'r');
    end
    firstline = fgetl(fid);
    fclose(fid);

    ntabs   = sum(firstline == char(9));
    ncommas = sum(firstline == ',');
    nsemis  = sum(firstline == ';');
    npipes  = sum(firstline == '|');

    [~, delim_char] = max([ncommas, ntabs, nsemis, npipes]);
    delims = {',', '\t', ';', '|'};
    delim  = delims{delim_char};

    delim_names = {'comma-separated','tab-separated','semicolon-separated','pipe-separated'};
    fprintf('  Detected: %s\n', delim_names{delim_char});

    % Check file size — use reservoir sampling for files over threshold
    LARGE_FILE_MB = 100;
    info = dir(filepath);
    file_mb = info.bytes / 1e6;

    if file_mb > LARGE_FILE_MB
        fprintf('  ℹ Large file (%.0f MB) — using reservoir sampling to read %d rows.\n', ...
            file_mb, options.MaxRows);
        fprintf('    This avoids loading the full file into memory.\n');
        T = SampleData(filepath, options.MaxRows, 'Verbose', true);
        T = se_record_sampled(T, height(T));
    else
        opts = detectImportOptions(filepath, 'FileType', 'text', 'Delimiter', delim);
        opts.MissingRule = 'fill';
        T = readtable(filepath, opts);
        n_before = height(T);
        T = se_sample(T, options.MaxRows);
        if height(T) < n_before
            T = se_record_sampled(T, height(T));
        end
    end

    T = se_fix_names(T, filepath, '.csv', []);
end




% ── load_netcdf ───────────────────────────────────────────────────────────────
function T = load_netcdf(filepath, options)
%LOAD_NETCDF  Interactive extraction of a NetCDF variable into a table.

    info = ncinfo(filepath);

    % ── Inventory variables ───────────────────────────────────────────────────
    nvars = numel(info.Variables);
    if nvars == 0
        error('DataExplorer:ncEmpty', 'No variables found in NetCDF file.');
    end

    var_names  = {info.Variables.Name};
    var_nelems = zeros(1, nvars);
    var_dimstr = cell(1, nvars);
    for k = 1:nvars
        sz = [info.Variables(k).Size];
        if isempty(sz)
            var_nelems(k) = 0;
            var_dimstr{k} = '(scalar)';
        else
            var_nelems(k) = prod(sz);
            dim_names = {info.Variables(k).Dimensions.Name};
            var_dimstr{k} = sprintf('(%s)', strjoin( ...
                cellfun(@(d,s) sprintf('%s=%d',d,s), dim_names, ...
                num2cell(sz), 'UniformOutput', false), ', '));
        end
    end

    % Sort ascending by element count so largest (default) is at the bottom
    [~, ord] = sort(var_nelems, 'ascend');

    fprintf('  Variables in NetCDF file (sorted by size):\n');
    for k = 1:nvars
        idx = ord(k);
        fprintf('    [%2d]  %-30s  %s\n', k, var_names{idx}, var_dimstr{idx});
    end

    default_num = nvars;   % largest = last = default
    if strlength(options.NCVariable) > 0
        match = find(strcmp(var_names, char(options.NCVariable)), 1);
        if isempty(match)
            error('DataExplorer:ncVariableNotFound', ...
                'Variable "%s" not found. Available: %s', ...
                options.NCVariable, strjoin(var_names, ', '));
        end
        var_idx = match;
    elseif options.AutoSelect
        var_idx = ord(default_num);
        fprintf('  AutoSelect: picking largest variable "%s"\n', var_names{var_idx});
    else
        while true
            raw = input(sprintf('  Which variable? (number or name, Enter = %d = %s): ', ...
                default_num, var_names{ord(default_num)}), 's');
            if isempty(raw)
                var_idx = ord(default_num);
                break
            elseif all(ismember(raw, '0123456789'))
                n = str2double(raw);
                if n >= 1 && n <= nvars
                    var_idx = ord(n);
                    break
                else
                    fprintf('  Please enter a number between 1 and %d.\n', nvars);
                end
            else
                match = find(strcmp(var_names, raw), 1);
                if ~isempty(match)
                    var_idx = match;
                    break
                else
                    fprintf('  Variable "%s" not found.\n', raw);
                end
            end
        end
    end

    varinfo = info.Variables(var_idx);
    varname = varinfo.Name;
    sz      = varinfo.Size;
    ndim    = numel(sz);
    fprintf('  Selected: %s  %s\n', varname, var_dimstr{var_idx});

    % ── Identify coordinate variables ─────────────────────────────────────────
    dim_names = {};
    if ndim > 0
        dim_names = {varinfo.Dimensions.Name};
    end
    coord_vars = struct();
    for k = 1:numel(dim_names)
        dn = dim_names{k};
        if any(strcmp(var_names, dn))
            try
                coord_vars.(matlab.lang.makeValidName(dn)) = ncread(filepath, dn);
            catch
            end
        end
    end

    % ── Dispatch by dimensionality ────────────────────────────────────────────
    if ndim <= 1
        data = ncread(filepath, varname);
        T    = nc_1d_to_table(data, varname, dim_names, coord_vars);

    elseif ndim == 2
        data = ncread(filepath, varname);
        T    = nc_2d_to_table(data, varname, dim_names, coord_vars);

    else
        total_elems = prod(sz);
        fprintf('\n  ⚠ %s is %dD (%s = %d elements total).\n', ...
            varname, ndim, strjoin(arrayfun(@num2str,sz,'UniformOutput',false),'×'), ...
            total_elems);
        fprintf('  Dimensions:\n');
        for k = 1:ndim
            fprintf('    [%d]  %s  (%d)\n', k, dim_names{k}, sz(k));
        end
        fprintf('  Options:\n');
        fprintf('    [1]  Mean over a dimension → %dD slice\n', ndim-1);
        fprintf('    [2]  Single index along a dimension\n');
        fprintf('    [3]  Flatten everything to long-format table\n');

        % Resolve reduction choice non-interactively when requested
        nc_red = lower(char(options.NCReduction));
        if ismember(nc_red, {'flatten','mean','slice'})
            raw = struct('flatten','3','mean','1','slice','2');
            raw = raw.(nc_red);
            fprintf('  NCReduction="%s": using option %s\n', nc_red, raw);
        elseif options.AutoSelect
            raw = '3';   % flatten preserves all coordinates — best for grouping flow
            fprintf('  AutoSelect: flattening to long-format table\n');
        else
            while true
                raw = input('  Choice (Enter = 1): ', 's');
                if isempty(raw), raw = '1'; end
                if ismember(raw, {'1','2','3'}), break; end
                fprintf('  Please enter 1, 2, or 3.\n');
            end
        end

        % For options 1 and 2, resolve which dimension non-interactively when possible
        if ismember(raw, {'1','2'})
            if options.NCDimension >= 1 && options.NCDimension <= ndim && ...
                    (strlength(options.NCReduction) > 0 || options.AutoSelect)
                dim_choice = options.NCDimension;
                fprintf('  Using NCDimension=%d ("%s")\n', dim_choice, dim_names{dim_choice});
            else
                while true
                    raw_dim = input(sprintf('  Which dimension? (1–%d, Enter = 1 = %s): ', ...
                        ndim, dim_names{1}), 's');
                    if isempty(raw_dim)
                        dim_choice = 1;
                        break
                    end
                    dim_choice = str2double(raw_dim);
                    if ~isnan(dim_choice) && dim_choice >= 1 && dim_choice <= ndim
                        break
                    end
                    fprintf('  Please enter a number between 1 and %d.\n', ndim);
                end
            end
        end

        % Helper: remove chosen dimension from dim list, keep its coords
        switch raw
            case '1'
                remaining_dims   = dim_names([1:dim_choice-1, dim_choice+1:end]);
                remaining_coords = filter_coords(coord_vars, remaining_dims);
                fprintf('  Computing mean over "%s"…\n', dim_names{dim_choice});
                data = squeeze(mean(ncread(filepath, varname), dim_choice, 'omitnan'));
                if ndim-1 == 1
                    T = nc_1d_to_table(data, varname, remaining_dims, remaining_coords);
                else
                    T = nc_2d_to_table(data, varname, remaining_dims, remaining_coords);
                end

            case '2'
                remaining_dims   = dim_names([1:dim_choice-1, dim_choice+1:end]);
                remaining_coords = filter_coords(coord_vars, remaining_dims);
                fprintf('  Dimension "%s" has %d indices (1–%d).\n', ...
                    dim_names{dim_choice}, sz(dim_choice), sz(dim_choice));
                while true
                    if options.NCSliceIndex >= 1 && options.NCSliceIndex <= sz(dim_choice) && ...
                            (strlength(options.NCReduction) > 0 || options.AutoSelect)
                        ival = options.NCSliceIndex;
                        fprintf('  Using NCSliceIndex=%d\n', ival);
                        break;
                    end
                    raw2 = input('  Which index? ', 's');
                    ival = str2double(raw2);
                    if ~isnan(ival) && ival >= 1 && ival <= sz(dim_choice), break; end
                    fprintf('  Please enter a number between 1 and %d.\n', sz(dim_choice));
                end
                start             = ones(1, ndim);
                count             = sz;
                start(dim_choice) = ival;
                count(dim_choice) = 1;
                data = squeeze(ncread(filepath, varname, start, count));
                if ndim-1 == 1
                    T = nc_1d_to_table(data, varname, remaining_dims, remaining_coords);
                else
                    T = nc_2d_to_table(data, varname, remaining_dims, remaining_coords);
                end

            case '3'
                if total_elems > options.MaxRows * 10
                    fprintf('  ⚠ %d elements — will sample to %d rows.\n', ...
                        total_elems, options.MaxRows);
                end
                data = ncread(filepath, varname);
                T    = nc_flatten_to_table(data, varname, dim_names, coord_vars, ...
                    sz, options.MaxRows);
        end
    end

    T = se_sample(T, options.MaxRows);
    fprintf('  ✓ Loaded %d × %d table from "%s".\n', height(T), width(T), varname);
end

function rc = filter_coords(coord_vars, dim_names)
% Return only the coord_vars entries matching the given dim_names.
    rc = struct();
    for k = 1:numel(dim_names)
        vdn = matlab.lang.makeValidName(dim_names{k});
        if isfield(coord_vars, vdn)
            rc.(vdn) = coord_vars.(vdn);
        end
    end
end

function T = nc_1d_to_table(data, varname, dim_names, coord_vars)
    vname = matlab.lang.makeValidName(varname);
    if ~isempty(dim_names)
        dn = matlab.lang.makeValidName(dim_names{1});
        if isfield(coord_vars, dn)
            coord = coord_vars.(dn)(:);
        else
            coord = (1:numel(data))';
        end
        T = table(coord, data(:), 'VariableNames', {dn, vname});
    else
        T = table(data(:), 'VariableNames', {vname});
    end
end

function T = nc_2d_to_table(data, varname, dim_names, coord_vars)
% 2D variable → long-format table: one row per element, one column per dimension + value.
% Long format means geo detection, pairplot, and time series all work naturally.
    vname = matlab.lang.makeValidName(varname);
    [nr, nc_] = size(data);

    % Row coordinate
    dn1 = 'dim1';
    if numel(dim_names) >= 1, dn1 = dim_names{1}; end
    dn1v = matlab.lang.makeValidName(dn1);
    if isfield(coord_vars, dn1v)
        row_coords = coord_vars.(dn1v)(:);
    else
        row_coords = (1:nr)';
    end

    % Column coordinate
    dn2 = 'dim2';
    if numel(dim_names) >= 2, dn2 = dim_names{2}; end
    dn2v = matlab.lang.makeValidName(dn2);
    if isfield(coord_vars, dn2v)
        col_coords = coord_vars.(dn2v)(:);
    else
        col_coords = (1:nc_)';
    end

    % Build long format: replicate row/col coords for every combination
    row_rep = repmat(row_coords, nc_, 1);   % nr*nc_ × 1
    col_rep = repelem(col_coords, nr);       % nr*nc_ × 1
    val_rep = data(:);                       % nr*nc_ × 1, column-major matches repmat/repelem

    T = table(row_rep, col_rep, val_rep, 'VariableNames', {dn1v, dn2v, vname});
end

function T = nc_flatten_to_table(data, varname, dim_names, coord_vars, sz, maxrows)
    vname  = matlab.lang.makeValidName(varname);
    n_dims = numel(sz);
    idx_vecs = arrayfun(@(s) 1:s, sz, 'UniformOutput', false);
    grids    = cell(1, n_dims);
    [grids{:}] = ndgrid(idx_vecs{:});
    n_total = prod(sz);
    cols    = cell(1, n_dims + 1);
    col_names = cell(1, n_dims + 1);
    for k = 1:n_dims
        flat = grids{k}(:);
        dn   = matlab.lang.makeValidName(dim_names{k});
        cols{k} = flat;
        if isfield(coord_vars, dn)
            cols{k} = coord_vars.(dn)(flat);
        end
        col_names{k} = dn;
    end
    cols{end}     = data(:);
    col_names{end} = vname;
    if n_total > maxrows
        idx = sort(randperm(n_total, maxrows));
        cols = cellfun(@(c) c(idx), cols, 'UniformOutput', false);
        fprintf('  ℹ Sampled %d of %d elements.\n', maxrows, n_total);
    end
    T = table(cols{:}, 'VariableNames', col_names);
end


% ── se_echo_load_code ─────────────────────────────────────────────────────────
function se_echo_load_code(filepath, T)
%SE_ECHO_LOAD_CODE  Print copy-pasteable MATLAB code to reload this dataset.
code = cg_load_code(filepath, T);
fprintf('\n  ══════════════════════════════════════════════════════════\n');
fprintf('  To load this dataset in a script:\n');
fprintf('  ──────────────────────────────────────────────────────────\n');
lines = strsplit(code, newline);
for i = 1:numel(lines)
    if ~isempty(strtrim(lines{i}))
        fprintf('  %s\n', lines{i});
    end
end
fprintf('  ══════════════════════════════════════════════════════════\n\n');
end


% ── se_fix_names ─────────────────────────────────────────────────────────────
function T = se_fix_names(T, filepath, ext, sheet)
%SE_FIX_NAMES  If all names are Var1, Var2, …, try using the literal first row.

    names = T.Properties.VariableNames;
    is_default = all(cellfun(@(n) ~isempty(regexp(n, '^Var\d+$', 'once')), names));

    if ~is_default
        return
    end

    fprintf('  ⚠ All column names are Var1, Var2, … — inspecting raw first row.\n');

    try
        if ismember(ext, [".xlsx", ".xls", ".xlsm"])
            raw = readtable(filepath, 'Sheet', sheet, ...
                'ReadVariableNames', false, 'ReadRowNames', false);
        else
            % Re-sniff delimiter
            fid = fopen(filepath, 'r');
            fl  = fgetl(fid);
            fclose(fid);
            ntabs = sum(fl == char(9));
            delim = ',';
            if ntabs > sum(fl == ','), delim = '\t'; end
            raw = readtable(filepath, 'Delimiter', delim, ...
                'ReadVariableNames', false, 'ReadRowNames', false);
        end

        firstrow = table2cell(raw(1, :));

        % A row looks like a header if every cell is non-numeric text
        is_text = cellfun(@(v) ischar(v) || isstring(v), firstrow);
        is_num  = cellfun(@(v) ~isnan(str2double(string(v))), firstrow);
        looks_like_header = all(is_text) && ~all(is_num);

        if looks_like_header
            candidate = string(firstrow);
            valid     = matlab.lang.makeValidName(candidate);
            T.Properties.VariableNames = cellstr(valid);
            T(1, :) = [];   % drop the now-redundant first row
            fprintf('  ✓ Reassigned variable names from first data row:\n');
            fprintf('      %s\n', strjoin(valid, ',  '));
        else
            fprintf('  First row looks like data (not headers). Keeping Var1/Var2/…\n');
            fprintf('  TODO: rename columns manually via T.Properties.VariableNames\n');
        end

    catch ME
        fprintf('  Could not re-read for header check: %s\n', ME.message);
    end
end


% ── se_sample ────────────────────────────────────────────────────────────────
function T = se_sample(T, maxrows)
    n = height(T);
    if n > maxrows
        idx = sort(randperm(n, maxrows));
        T   = T(idx, :);
        fprintf('  ℹ Large file: keeping %d of %d rows (random sample).\n', ...
            maxrows, n);
        fprintf('    Increase with:  DataExplorer(file, MaxRows=N)\n');
    end
end


% ── se_record_sampled ─────────────────────────────────────────────────────────
function T = se_record_sampled(T, n)
% Store how many rows were sampled so cg_load_code can emit SampleData().
    if isempty(T.Properties.UserData)
        T.Properties.UserData = struct('sheet', '', 'inner_file', '', 'sampled', n);
    else
        T.Properties.UserData.sampled = n;
    end
end


% ── se_profile ───────────────────────────────────────────────────────────────
function [T, prof] = se_profile(T, missingStrings)
%SE_PROFILE  Thin wrapper — delegates to the standalone de_profile library function.
if nargin < 2
    [T, prof] = de_profile(T);
else
    [T, prof] = de_profile(T, missingStrings);
end
end


% ── se_report ────────────────────────────────────────────────────────────────
function se_report(T, prof)
%SE_REPORT  Print a compact summary table to the command window.

n    = height(T);
ncol = width(T);
nskip = sum(prof.skip);

fprintf('\n');
fprintf('  ══════════════════════════════════════════════════════════\n');
fprintf('  DataExplorer  —  %d rows × %d columns\n', n, ncol);
fprintf('  ══════════════════════════════════════════════════════════\n');
fprintf('  %-26s  %-12s  %-14s  %s\n', 'Column', 'Type', 'Missing', 'Unique');
fprintf('  %s\n', repmat('─', 1, 66));

for k = 1:ncol
    skip_flag = '';
    if prof.skip(k)
        skip_flag = '  ⚠ skipped';
    end
    pct = 100 * prof.nmissing(k) / n;
    if pct == 0
        miss_str = '0';
    else
        miss_str = sprintf('%d (%.1f%%)', prof.nmissing(k), pct);
    end
    fprintf('  %-26s  %-12s  %-14s  %d%s\n', ...
        truncate(prof.name{k}, 26), ...
        prof.type(k), miss_str, prof.nunique(k), skip_flag);
end

if nskip > 0
    fprintf('  %s\n', repmat('─', 1, 66));
    for reason = ["mostly missing", "all values unique (ID column)"]
        cols_r = prof.name(prof.skip & prof.skip_reason == reason);
        if ~isempty(cols_r)
            fprintf('  ⚠ Excluded (%s):\n', reason);
            fprintf('      %s\n', strjoin(cols_r, ', '));
        end
    end
end

fprintf('  ══════════════════════════════════════════════════════════\n\n');
end


% ── se_plot ──────────────────────────────────────────────────────────────────
function se_plot(T, prof, options)
%SE_PLOT  Produces: (1) variable overview, (2) time series if datetime detected,
%         (3) pairwise scatter matrix for selected columns.

has_stats = ~isempty(ver('stats'));

% ── Figure 1: variable overview — one diagnostic tile per column ─────────────
se_plot_overview(T, prof);

% ── Geo detection: map figure if lat+lon columns found ───────────────────────
se_plot_geo(T, prof);

% ── Datetime detection: produce time series figure if applicable ─────────────
dt_cols  = find(prof.type == "datetime" & ~prof.skip);
num_cols = find(prof.type == "numeric"  & ~prof.skip);

% Fallback: if no datetime column, look for a single numeric column whose
% name contains "year" (case-insensitive) and use that as the time axis
year_col = [];
if isempty(dt_cols)
    year_candidates = num_cols(arrayfun(@(i) ...
        ~isempty(regexpi(prof.name{i}, 'year', 'once')), num_cols));
    if isscalar(year_candidates)
        year_col = year_candidates;
        fprintf('  ℹ "%s" treated as time axis (year column).\n', prof.name{year_col});
    end
end

if isscalar(dt_cols) && numel(num_cols) >= 2
    fprintf('  ℹ Datetime column "%s" detected — producing time series figure.\n', ...
        prof.name{dt_cols});
    fprintf('    Scatter matrix follows for structural relationships.\n\n');
    se_plot_timeseries(T, prof, dt_cols, options);
elseif ~isempty(year_col) && numel(num_cols) >= 2
    fprintf('  ℹ Treating "%s" as time axis — producing time series figure.\n', ...
        prof.name{year_col});
    fprintf('    Scatter matrix follows for structural relationships.\n\n');
    se_plot_timeseries_numeric(T, prof, year_col, options);
elseif numel(dt_cols) > 1
    fprintf('  ℹ Multiple datetime columns found (%s) — skipping time series auto-plot.\n', ...
        strjoin(prof.name(dt_cols), ', '));
    fprintf('    Use Columns= to specify which to use.\n\n');
end

% ── Select columns to plot ──────────────────────────────────────────────────
if ~isempty(options.Columns)
    % User specified columns explicitly
    if isnumeric(options.Columns)
        sel = options.Columns(:)';
    else
        cols = string(options.Columns);
        sel  = find(ismember(string(prof.name), cols));
        if numel(sel) < numel(cols)
            missing_cols = cols(~ismember(cols, string(prof.name)));
            warning('DataExplorer:colNotFound', ...
                'Column(s) not found: %s', strjoin(missing_cols, ', '));
        end
    end
    sel = sel(~prof.skip(sel));   % still drop >80%-missing columns

else
    sel = se_select_columns(T, prof, options.MaxVars);
end

if isempty(sel)
    fprintf('  No plottable columns found.\n');
    return
end

np = numel(sel);   % number of columns in the plot grid

% ── Build figure ────────────────────────────────────────────────────────────
fig = figure('Name', se_fig_title('Pairplot', prof.source_name), ...
    'Color', [0.97 0.97 0.97], ...
    'NumberTitle', 'off');
se_stamp_source(fig, prof.source_name);
tl = tiledlayout(fig, np, np, 'TileSpacing', 'tight', 'Padding', 'compact');

n = height(T);

for r = 1:np
    for c = 1:np
        ax = nexttile(tl);
        ri = sel(r);
        ci = sel(c);

        rtype = prof.type(ri);
        ctype = prof.type(ci);

        xdata = T.(prof.name{ci});
        ydata = T.(prof.name{ri});
        xname = prof.name{ci};
        yname = prof.name{ri};

        % ── Diagonal ─────────────────────────────────────────────────────
        if r == c
            switch rtype
                case "numeric"
                    plot_num_diag(ax, xdata, xname, prof.nmissing(ci), n);
                case {"categorical", "logical"}
                    plot_cat_diag(ax, xdata, xname, prof.nmissing(ci), n);
                case "datetime"
                    plot_time_diag(ax, xdata, xname);
                otherwise
                    axis(ax, 'off');
                    text(ax, 0.5, 0.5, rtype, ...
                        'HorizontalAlignment', 'center', 'Units', 'normalized');
            end

        % ── Off-diagonal ─────────────────────────────────────────────────
        elseif rtype == "numeric" && ctype == "numeric"
            plot_num_num(ax, xdata, ydata, xname, yname);

        elseif rtype == "numeric" && ismember(ctype, ["categorical","logical"])
            plot_num_cat(ax, xdata, ydata, xname, yname, has_stats, false);

        elseif ismember(rtype, ["categorical","logical"]) && ctype == "numeric"
            plot_num_cat(ax, ydata, xdata, yname, xname, has_stats, true);

        elseif ismember(rtype, ["categorical","logical"]) && ...
               ismember(ctype, ["categorical","logical"])
            plot_cat_cat(ax, xdata, ydata, xname, yname);

        elseif rtype == "datetime" || ctype == "datetime"
            plot_time_pair(ax, xdata, ydata, xname, yname, rtype, ctype);

        else
            axis(ax, 'off');
        end

        % Strip all ticks, tick labels, and axis label text from every cell
        set(ax, 'XTick', [], 'YTick', []);
        xlabel(ax, '');
        ylabel(ax, '');

        if r == 1
            ctype_ci = prof.type(ci);
            if ismember(ctype_ci, ["categorical","logical"]) && prof.nunique(ci) > 15
                col_title = {wrapped_name(xname), ...
                    sprintf('\\rm\\fontsize{6}15 sampled of %d groups', prof.nunique(ci))};
            else
                col_title = wrapped_name(xname);
            end
            title(ax, col_title, 'FontSize', 8, 'FontWeight', 'bold', ...
                'Interpreter', 'tex');
        end
        if r == c && r > 1
            title(ax, wrapped_name(yname), 'FontSize', 8, 'FontWeight', 'bold', ...
                'Interpreter', 'none');
        end
        if c == 1
            yl = ylabel(ax, wrapped_name(yname), 'FontSize', 6, 'Interpreter', 'none');
            set(yl, 'Rotation', 0, 'HorizontalAlignment', 'right');
        end
    end
end

n_total_plottable = sum(~prof.skip);
if np < n_total_plottable
    title_str = se_src_prefix(prof.source_name, ...
        sprintf('n = %d  (%d of %d variables shown)', n, np, n_total_plottable));
else
    title_str = se_src_prefix(prof.source_name, sprintf('n = %d', n));
end
title(tl, title_str, 'FontSize', 11, 'Interpreter', 'none');

% ── Categorical drill-down ──────────────────────────────────────────────────
se_plot_categorical_drilldown(T, prof, sel);

end


% ── se_plot_overview ──────────────────────────────────────────────────────────
function se_plot_overview(T, prof)
%SE_PLOT_OVERVIEW  One diagnostic tile per variable, paginated.
%   Shows ALL variables — overview is comprehensive.

NCOLS    = 5;
NROWS    = 3;
PER_PAGE = NCOLS * NROWS;

not_skip = 1:numel(prof.name);
nv       = numel(not_skip);
if nv == 0, return; end

n_pages = ceil(nv / PER_PAGE);
n       = height(T);

for pg = 1:n_pages
    idx_range = (pg-1)*PER_PAGE+1 : min(pg*PER_PAGE, nv);
    n_this    = numel(idx_range);

    if n_pages == 1
        fig_name = se_fig_title('Overview', prof.source_name);
    else
        fig_name = se_fig_title(sprintf('Overview %d/%d', pg, n_pages), prof.source_name);
    end

    fig = figure('Name', fig_name, 'Color', [0.97 0.97 0.97], ...
        'NumberTitle', 'off');
    se_stamp_source(fig, prof.source_name);
    tl = tiledlayout(fig, NROWS, NCOLS, 'TileSpacing', 'tight', 'Padding', 'compact');

    if n_pages == 1
        title_str = se_src_prefix(prof.source_name, sprintf('all %d variables', nv));
    else
        title_str = se_src_prefix(prof.source_name, ...
            sprintf('variables %d–%d of %d  (page %d/%d)', ...
                idx_range(1), idx_range(end), nv, pg, n_pages));
    end
    title(tl, title_str, 'FontSize', 11, 'Interpreter', 'none');

    for k = 1:n_this
        idx = not_skip(idx_range(k));
        ax  = nexttile(tl);

        switch prof.type(idx)
            case "numeric"
                plot_num_diag(ax, T.(prof.name{idx}), prof.name{idx}, ...
                    prof.nmissing(idx), n);
            case {"categorical", "logical"}
                plot_cat_diag(ax, T.(prof.name{idx}), prof.name{idx}, ...
                    prof.nmissing(idx), n);
            case "datetime"
                plot_time_diag(ax, T.(prof.name{idx}), prof.name{idx});
            otherwise
                axis(ax, 'off');
        end

        title(ax, wrapped_name(prof.name{idx}), 'FontSize', 7, ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    end

    % Turn off unused tiles on last page
    for k = n_this+1 : PER_PAGE
        nexttile(tl);
        axis off;
    end
end
end


% ── se_plot_geo ───────────────────────────────────────────────────────────────
function se_plot_geo(T, prof)
%SE_PLOT_GEO  If lat+lon columns are detected, produce a map figure.
%   Encoding priority (first match wins):
%     datetime column  → color by time
%     1 numeric col    → size proportional to value
%     1 categorical col → color by category
%     otherwise        → plain scatter

LAT_NAMES = ["lat","latitude","lat_","latitude_dd","decimallatitude"];
LON_NAMES = ["lon","long","longitude","lon_","longitude_dd","decimallongitude"];

names_lower = lower(string(prof.name));

lat_idx = find(ismember(names_lower, LAT_NAMES) & ~prof.skip, 1);
lon_idx = find(ismember(names_lower, LON_NAMES) & ~prof.skip, 1);

if isempty(lat_idx) || isempty(lon_idx)
    return
end

lat = T.(prof.name{lat_idx});
lon = T.(prof.name{lon_idx});

% Drop rows where lat or lon is missing
valid = ~isnan(lat) & ~isnan(lon);
lat = lat(valid);
lon = lon(valid);
if numel(lat) < 2, return; end

fprintf('  ℹ Lat/lon columns detected ("%s", "%s") — producing map figure.\n', ...
    prof.name{lat_idx}, prof.name{lon_idx});

% ── Decide encoding ───────────────────────────────────────────────────────────
has_mapping = ~isempty(ver('map'));

dt_cols  = find(prof.type == "datetime"    & ~prof.skip);
num_cols  = find(prof.type == "numeric"    & ~prof.skip & ...
    ~ismember((1:numel(prof.name)), [lat_idx, lon_idx]));
cat_cols  = find(ismember(prof.type, ["categorical","logical"]) & ~prof.skip);

encoding = 'plain';
enc_col  = [];
if isscalar(dt_cols)
    encoding = 'time';
    enc_col  = dt_cols;
elseif isscalar(num_cols)
    encoding = 'size';
    enc_col  = num_cols;
elseif isscalar(cat_cols)
    encoding = 'color_cat';
    enc_col  = cat_cols;
end

% ── Build figure ─────────────────────────────────────────────────────────────
fig = figure('Name', se_fig_title('Map', prof.source_name),...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
se_stamp_source(fig, prof.source_name);
BASE_SZ = 20;   % default marker area in points²

if has_mapping
    ax = geoaxes(fig);
    switch encoding
        case 'time'
            tdata  = T.(prof.name{enc_col});
            tdata  = tdata(valid);
            tnums  = datenum(tdata); %#ok<DATNM>
            geoscatter(ax, lat, lon, BASE_SZ, tnums, 'filled', ...
                'MarkerFaceAlpha', 0.6);
            colormap(ax, 'turbo');
            cb = colorbar(ax);
            cb.TickLabels = datestr(linspace(min(tnums), max(tnums), 5), 'mmm yyyy'); %#ok<DATST>
            cb.Label.String = prof.name{enc_col};

        case 'size'
            sdata = T.(prof.name{enc_col});
            sdata = sdata(valid);
            % Scale to [4, 80] point² range
            lo = min(sdata); hi = max(sdata);
            if hi > lo
                sz = 4 + 76 * (sdata - lo) / (hi - lo);
            else
                sz = repmat(BASE_SZ, size(sdata));
            end
            sz(isnan(sz)) = BASE_SZ;
            geoscatter(ax, lat, lon, sz, [0.22 0.44 0.69], 'filled', ...
                'MarkerFaceAlpha', 0.5);
            title(ax, sprintf('size → %s', prof.name{enc_col}), ...
                'FontSize', 9, 'Interpreter', 'none');

        case 'color_cat'
            cdata = T.(prof.name{enc_col});
            cdata = cdata(valid);
            cats  = categories(cdata);
            nc    = numel(cats);
            cmap  = lines(nc);
            hold(ax, 'on');
            for ki = 1:nc
                mask = cdata == cats{ki};
                if ~any(mask), continue; end
                geoscatter(ax, lat(mask), lon(mask), BASE_SZ, ...
                    cmap(ki,:), 'filled', 'MarkerFaceAlpha', 0.6, ...
                    'DisplayName', cats{ki});
            end
            legend(ax, 'Location', 'bestoutside', 'FontSize', 7, ...
                'Interpreter', 'none');

        otherwise
            geoscatter(ax, lat, lon, BASE_SZ, [0.22 0.44 0.69], 'filled', ...
                'MarkerFaceAlpha', 0.5);
    end
    geobasemap(ax, 'streets-light');

else
    % Fallback: plain scatter with axis labels
    ax = axes(fig);
    switch encoding
        case 'time'
            tdata = T.(prof.name{enc_col});
            tdata = tdata(valid);
            scatter(ax, lon, lat, BASE_SZ, datenum(tdata), 'filled', ...
                'MarkerFaceAlpha', 0.6); %#ok<DATNM>
            colormap(ax, 'turbo');
            cb = colorbar(ax); cb.Label.String = prof.name{enc_col};
        case 'size'
            sdata = T.(prof.name{enc_col});
            sdata = sdata(valid);
            lo = min(sdata); hi = max(sdata);
            if hi > lo
                sz = 4 + 76 * (sdata - lo) / (hi - lo);
            else
                sz = repmat(BASE_SZ, size(sdata));
            end
            sz(isnan(sz)) = BASE_SZ;
            scatter(ax, lon, lat, sz, [0.22 0.44 0.69], 'filled', ...
                'MarkerFaceAlpha', 0.5);
        case 'color_cat'
            cdata = T.(prof.name{enc_col});
            cdata = cdata(valid);
            cats  = categories(cdata);
            cmap  = lines(numel(cats));
            hold(ax, 'on');
            for ki = 1:numel(cats)
                mask = cdata == cats{ki};
                scatter(ax, lon(mask), lat(mask), BASE_SZ, cmap(ki,:), ...
                    'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', cats{ki});
            end
            legend(ax, 'Location', 'bestoutside', 'FontSize', 7, ...
                'Interpreter', 'none');
        otherwise
            scatter(ax, lon, lat, BASE_SZ, [0.22 0.44 0.69], 'filled', ...
                'MarkerFaceAlpha', 0.5);
    end
    xlabel(ax, prof.name{lon_idx}, 'Interpreter', 'none');
    ylabel(ax, prof.name{lat_idx}, 'Interpreter', 'none');
    axis(ax, 'equal');
    box(ax, 'off');
    fprintf('    (Mapping Toolbox not found — using plain scatter as fallback)\n');
end

title(ax, se_src_prefix(prof.source_name, sprintf('map  (n = %d)', sum(valid))), ...
    'FontSize', 11, 'Interpreter', 'none');
end


% ── se_plot_timeseries ────────────────────────────────────────────────────────
function se_plot_timeseries(T, prof, dt_idx, ~)
%SE_PLOT_TIMESERIES  All numeric variables on one plot against a datetime axis.
%
%   Aggregates multiple rows per time point to mean, with bootstrap 95% CI shading.
%   If series are compositional (stable total): stacked area chart.
%   Otherwise: overlaid lines with bootstrap CI bands.

tdata   = T.(prof.name{dt_idx});
num_idx = find(prof.type == "numeric" & ~prof.skip);
n_series = numel(num_idx);
if n_series == 0, return; end

% Sort by time, drop missing
valid_t        = ~isnat(tdata);
[tdata_s, ord] = sort(tdata(valid_t));

% Build data matrix (rows = sorted obs, cols = series)
Y = NaN(sum(valid_t), n_series);
labels = cell(1, n_series);
for k = 1:n_series
    col = T.(prof.name{num_idx(k)});
    col = col(valid_t);
    Y(:, k) = col(ord);
    labels{k} = prof.name{num_idx(k)};
end

% Aggregate by unique datetime: mean + bootstrap 95% CI
[tdata_u, ~, tidx] = unique(tdata_s);
n_u    = numel(tdata_u);
Y_mean = NaN(n_u, n_series);
Y_lo   = NaN(n_u, n_series);
Y_hi   = NaN(n_u, n_series);
B = 500;
for k = 1:n_series
    for t = 1:n_u
        vals = Y(tidx == t, k);
        vals = vals(~isnan(vals));
        n_v = numel(vals);
        if n_v == 0, continue; end
        Y_mean(t, k) = mean(vals);
        if n_v >= 2
            bm = mean(vals(randi(n_v, n_v, B)), 1);
            bm_s = sort(bm);
            Y_lo(t, k) = bm_s(max(1, round(0.025*B)));
            Y_hi(t, k) = bm_s(min(B, round(0.975*B)));
        end
    end
end

% Compositional test: stacked only when data clearly has parts summing to a whole.
% Primary signal: any categorical column has a "Total"-like level.
% Fallback: row sums of aggregated means are extremely stable (CV < 0.05).
TOTAL_WORDS = {'total', 'totals', 'grand total', 'all totals'};
has_total_label = false;
cat_search = find(prof.type == "categorical" & ~prof.skip);
for kk = 1:numel(cat_search)
    lvls_kk = cellstr(categories(T.(prof.name{cat_search(kk)})));
    if any(cellfun(@(lv) any(strcmpi(lv, TOTAL_WORDS)), lvls_kk))
        has_total_label = true;
        break;
    end
end
Y_complete = Y_mean(all(~isnan(Y_mean), 2), :);
all_nonneg  = ~isempty(Y_complete) && size(Y_complete, 2) > 1 && all(Y_complete(:) >= 0);
if has_total_label && all_nonneg
    use_stacked = true;
elseif all_nonneg
    row_sums    = sum(Y_complete, 2);
    cv_sums     = std(row_sums) / max(abs(mean(row_sums)), eps);
    use_stacked = cv_sums < 0.05;
else
    use_stacked = false;
end

colors_ts = lines(n_series);

if use_stacked
    % Compositional data: stacked area figure first, then overlaid + Total.
    fig_s = figure('Name', se_fig_title('Time series (stacked)', prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    se_stamp_source(fig_s, prof.source_name);
    ax_s = axes(fig_s);
    Y_plot = Y_mean; Y_plot(isnan(Y_plot)) = 0;
    [~, sord] = sort(mean(Y_plot, 1), 'descend');
    labels_s = labels(sord);
    area(ax_s, tdata_u, Y_plot(:, sord), 'LineStyle', 'none', 'FaceAlpha', 0.85);
    ylabel(ax_s, 'Value (stacked)', 'FontSize', 8);
    legend(ax_s, labels_s, 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
    set(ax_s, 'FontSize', 8); box(ax_s, 'off');
    title(ax_s, se_src_prefix(prof.source_name, ...
        sprintf('time series, stacked area  (n = %d, %d series)', height(T), n_series)), ...
        'FontSize', 11, 'Interpreter', 'none');

    fig_o = figure('Name', se_fig_title('Time series (overlaid)', prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    se_stamp_source(fig_o, prof.source_name);
    ax_o = axes(fig_o);
    hold(ax_o, 'on');
    for k = 1:n_series
        has_ci = ~isnan(Y_lo(:, k)) & ~isnan(Y_hi(:, k));
        if sum(has_ci) >= 2
            t_fwd = tdata_u(has_ci); t_rev = t_fwd(end:-1:1);
            patch(ax_o, [t_fwd; t_rev], [Y_hi(has_ci,k); Y_lo(has_ci(end:-1:1),k)], ...
                colors_ts(k,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end
    end
    for k = 1:n_series
        plot(ax_o, tdata_u, Y_mean(:,k), '-', 'Color', colors_ts(k,:), ...
            'LineWidth', 1.5, 'DisplayName', labels{k});
    end
    Y_total = sum(Y_mean, 2, 'omitnan');
    plot(ax_o, tdata_u, Y_total, '-', 'Color', [0.10 0.10 0.10], ...
        'LineWidth', 3, 'DisplayName', 'Total');
    hold(ax_o, 'off');
    ylabel(ax_o, 'Value', 'FontSize', 8);
    legend(ax_o, [labels, {'Total'}], 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
    set(ax_o, 'FontSize', 8); box(ax_o, 'off');
    title(ax_o, se_src_prefix(prof.source_name, ...
        sprintf('time series, overlaid lines  (n = %d, %d series)', height(T), n_series)), ...
        'FontSize', 11, 'Interpreter', 'none');
else
    fig = figure('Name', se_fig_title('Time series', prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    ax = axes(fig);
    hold(ax, 'on');
    for k = 1:n_series
        has_ci = ~isnan(Y_lo(:, k)) & ~isnan(Y_hi(:, k));
        if sum(has_ci) >= 2
            t_fwd = tdata_u(has_ci); t_rev = t_fwd(end:-1:1);
            patch(ax, [t_fwd; t_rev], [Y_hi(has_ci,k); Y_lo(has_ci(end:-1:1),k)], ...
                colors_ts(k,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end
    end
    for k = 1:n_series
        plot(ax, tdata_u, Y_mean(:,k), '-', 'Color', colors_ts(k,:), ...
            'LineWidth', 1.5, 'DisplayName', labels{k});
    end
    hold(ax, 'off');
    ylabel(ax, 'Value', 'FontSize', 8);
    legend(ax, labels, 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
    set(ax, 'FontSize', 8); box(ax, 'off');
    title(ax, se_src_prefix(prof.source_name, ...
        sprintf('time series, overlaid lines  (n = %d, %d series)', height(T), n_series)), ...
        'FontSize', 11, 'Interpreter', 'none');
end
end


% ── se_plot_timeseries_numeric ────────────────────────────────────────────────
function se_plot_timeseries_numeric(T, prof, year_idx, ~)
%SE_PLOT_TIMESERIES_NUMERIC  Like se_plot_timeseries but for a numeric year axis.
%   Aggregates multiple rows per year to mean, with bootstrap 95% CI shading.

xdata    = T.(prof.name{year_idx});
num_idx  = find(prof.type == "numeric" & ~prof.skip & ...
    ~ismember((1:numel(prof.name)), year_idx));
n_series = numel(num_idx);
if n_series == 0, return; end

% Sort by year, drop missing
valid = ~isnan(xdata);
[xdata_s, ord] = sort(xdata(valid));

Y      = NaN(sum(valid), n_series);
labels = cell(1, n_series);
for k = 1:n_series
    col    = T.(prof.name{num_idx(k)});
    col    = col(valid);
    Y(:,k) = col(ord);
    labels{k} = prof.name{num_idx(k)};
end

% Aggregate by unique year: mean + bootstrap 95% CI
[xdata_u, ~, xidx] = unique(xdata_s);
n_u    = numel(xdata_u);
if n_u < 2
    % Only one unique time point — nothing to plot as a time series
    fprintf('  ℹ "%s" has only one unique value — skipping time series.\n', ...
        prof.name{year_idx});
    return
end
Y_mean = NaN(n_u, n_series);
Y_lo   = NaN(n_u, n_series);
Y_hi   = NaN(n_u, n_series);
B = 500;
for k = 1:n_series
    for t = 1:n_u
        vals = Y(xidx == t, k);
        vals = vals(~isnan(vals));
        n_v = numel(vals);
        if n_v == 0, continue; end
        Y_mean(t, k) = mean(vals);
        if n_v >= 2
            bm = mean(vals(randi(n_v, n_v, B)), 1);
            bm_s = sort(bm);
            Y_lo(t, k) = bm_s(max(1, round(0.025*B)));
            Y_hi(t, k) = bm_s(min(B, round(0.975*B)));
        end
    end
end

% Compositional test: stacked only when data clearly has parts summing to a whole.
% Primary signal: any categorical column has a "Total"-like level.
% Fallback: row sums of aggregated means are extremely stable (CV < 0.05).
TOTAL_WORDS = {'total', 'totals', 'grand total', 'all totals'};
has_total_label = false;
cat_search = find(prof.type == "categorical" & ~prof.skip);
for kk = 1:numel(cat_search)
    lvls_kk = cellstr(categories(T.(prof.name{cat_search(kk)})));
    if any(cellfun(@(lv) any(strcmpi(lv, TOTAL_WORDS)), lvls_kk))
        has_total_label = true;
        break;
    end
end
Y_complete = Y_mean(all(~isnan(Y_mean), 2), :);
all_nonneg  = ~isempty(Y_complete) && size(Y_complete, 2) > 1 && all(Y_complete(:) >= 0);
if has_total_label && all_nonneg
    use_stacked = true;
elseif all_nonneg
    row_sums    = sum(Y_complete, 2);
    cv_sums     = std(row_sums) / max(abs(mean(row_sums)), eps);
    use_stacked = cv_sums < 0.05;
else
    use_stacked = false;
end

colors_ts = lines(n_series);
x_lbl     = prof.name{year_idx};

if use_stacked
    % Compositional: stacked area first, then overlaid + Total.
    fig_s = figure('Name', se_fig_title('Time series (stacked)', prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    ax_s = axes(fig_s);
    Y_plot = Y_mean; Y_plot(isnan(Y_plot)) = 0;
    [~, sord] = sort(mean(Y_plot, 1), 'descend');
    labels_s = labels(sord);
    area(ax_s, xdata_u, Y_plot(:, sord), 'LineStyle', 'none', 'FaceAlpha', 0.85);
    ylabel(ax_s, 'Value (stacked)', 'FontSize', 8);
    xlabel(ax_s, x_lbl, 'FontSize', 8, 'Interpreter', 'none');
    legend(ax_s, labels_s, 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
    set(ax_s, 'FontSize', 8); box(ax_s, 'off');
    title(ax_s, se_src_prefix(prof.source_name, ...
        sprintf('time series, stacked area  (n = %d, %d series)', height(T), n_series)), ...
        'FontSize', 11, 'Interpreter', 'none');

    fig_o = figure('Name', se_fig_title('Time series (overlaid)', prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    ax_o = axes(fig_o);
    hold(ax_o, 'on');
    for k = 1:n_series
        has_ci = ~isnan(Y_lo(:, k)) & ~isnan(Y_hi(:, k));
        if sum(has_ci) >= 2
            x_fwd = xdata_u(has_ci); x_rev = x_fwd(end:-1:1);
            patch(ax_o, [x_fwd; x_rev], [Y_hi(has_ci,k); Y_lo(has_ci(end:-1:1),k)], ...
                colors_ts(k,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end
    end
    for k = 1:n_series
        plot(ax_o, xdata_u, Y_mean(:,k), '-', 'Color', colors_ts(k,:), ...
            'LineWidth', 1.5, 'DisplayName', labels{k});
    end
    Y_total = sum(Y_mean, 2, 'omitnan');
    plot(ax_o, xdata_u, Y_total, '-', 'Color', [0.10 0.10 0.10], ...
        'LineWidth', 3, 'DisplayName', 'Total');
    hold(ax_o, 'off');
    ylabel(ax_o, 'Value', 'FontSize', 8);
    xlabel(ax_o, x_lbl, 'FontSize', 8, 'Interpreter', 'none');
    legend(ax_o, [labels, {'Total'}], 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
    set(ax_o, 'FontSize', 8); box(ax_o, 'off');
    title(ax_o, se_src_prefix(prof.source_name, ...
        sprintf('time series, overlaid lines  (n = %d, %d series)', height(T), n_series)), ...
        'FontSize', 11, 'Interpreter', 'none');
else
    fig = figure('Name', se_fig_title('Time series', prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    ax = axes(fig);
    hold(ax, 'on');
    for k = 1:n_series
        has_ci = ~isnan(Y_lo(:, k)) & ~isnan(Y_hi(:, k));
        if sum(has_ci) >= 2
            x_fwd = xdata_u(has_ci); x_rev = x_fwd(end:-1:1);
            patch(ax, [x_fwd; x_rev], [Y_hi(has_ci,k); Y_lo(has_ci(end:-1:1),k)], ...
                colors_ts(k,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end
    end
    for k = 1:n_series
        plot(ax, xdata_u, Y_mean(:,k), '-', 'Color', colors_ts(k,:), ...
            'LineWidth', 1.5, 'DisplayName', labels{k});
    end
    hold(ax, 'off');
    ylabel(ax, 'Value', 'FontSize', 8);
    xlabel(ax, x_lbl, 'FontSize', 8, 'Interpreter', 'none');
    legend(ax, labels, 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
    set(ax, 'FontSize', 8); box(ax, 'off');
    title(ax, se_src_prefix(prof.source_name, ...
        sprintf('time series, overlaid lines  (n = %d, %d series)', height(T), n_series)), ...
        'FontSize', 11, 'Interpreter', 'none');
end
end





% ── Cell-type plot helpers ────────────────────────────────────────────────────

function plot_num_diag(ax, x, varname, nmissing, n)
% Histogram with summary stats annotation (mean, std, min, max).
    x = double(x);   % NetCDF and some other sources yield integer arrays
    valid = x(~isnan(x));
    if isempty(valid)
        axis(ax, 'off');
        text(ax, 0.5, 0.5, 'all missing', 'HorizontalAlignment', 'center', ...
            'Units', 'normalized', 'Color', [0.6 0.6 0.6]);
        return
    end
    h = histogram(ax, valid, 'FaceColor', [0.35 0.55 0.75], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.8);
    h.DataTipTemplate.DataTipRows(1).Label = char(varname);

    % Stats block — top-right corner
    lo = min(valid);  hi = max(valid);
    mu = mean(valid); sg = std(valid);
    text(ax, 0.98, 0.97, ...
        sprintf('μ = %.3g\nσ = %.3g\n[%.3g, %.3g]', mu, sg, lo, hi), ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', 'FontSize', 6.5, ...
        'Color', [0.2 0.2 0.2]);

    if nmissing > 0
        pct = 100 * nmissing / n;
        text(ax, 0.02, 0.97, sprintf('%d missing (%.0f%%)', nmissing, pct), ...
            'Units', 'normalized', 'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'top', 'FontSize', 6.5, 'Color', [0.6 0.3 0.3]);
    end
    set(ax, 'FontSize', 7);
    box(ax, 'off');
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_cat_diag(ax, x, varname, nmissing, n)
% Horizontal bar chart: quantile-spaced sample of categories by count.
    MAX_K = 15;
    if iscategorical(x)
        cats   = categories(x);
        counts = histcounts(x);
    elseif islogical(x)
        cats   = {'false','true'};
        counts     = [sum(~x), sum(x)];
    else
        axis(ax, 'off'); return
    end

    % Sort by count descending, then quantile-sample to cover full range
    [counts_s, ord] = sort(counts(:), 'descend');
    cats_s = cats(ord);
    nc = numel(cats_s);
    if nc > MAX_K
        pick = unique(round(linspace(1, nc, MAX_K)));
        counts_s = counts_s(pick);
        cats_s   = cats_s(pick);
    end
    n_shown = numel(counts_s);

    b = barh(ax, n_shown:-1:1, counts_s, 'FaceColor', [0.45 0.70 0.55], 'EdgeColor', 'none');

    % Fix hover tooltip: variable name + category name + count
    b.DataTipTemplate.DataTipRows(1).Label = 'Count';
    b.DataTipTemplate.DataTipRows(2).Label = 'Category';
    b.DataTipTemplate.DataTipRows(2).Value = cats_s;   % bar i → cats_s{i}
    b.DataTipTemplate.DataTipRows(end+1) = ...
        dataTipTextRow('Variable', repmat({char(varname)}, n_shown, 1));

    % Category name tick labels, truncated to fit
    yticks(ax, 1:n_shown);
    yticklabels(ax, flip(cellfun(@(s) truncate(s, 14), cats_s, 'UniformOutput', false)));
    set(ax, 'XTick', [], 'FontSize', 6.5, 'TickDir', 'out');

    if nmissing > 0
        pct = 100 * nmissing / n;
        text(ax, 0.98, 0.97, sprintf('%d undef. (%.0f%%)', nmissing, pct), ...
            'Units', 'normalized', 'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'top', 'FontSize', 6.5, 'Color', [0.6 0.3 0.3]);
    end
    box(ax, 'off');
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_time_diag(ax, x, varname)
% Histogram of datetime values by year (or month if span < 2 years).
    if isduration(x)
        x = datetime(0,0,0) + x;   % convert to datetime for uniform handling
    end
    valid = x(~isnat(x));
    if isempty(valid), axis(ax,'off'); return; end
    span_yrs = years(max(valid) - min(valid));
    if span_yrs < 2
        h = histogram(ax, month(valid), 1:13, 'FaceColor', [0.65 0.50 0.75], ...
            'EdgeColor', 'none');
        text(ax, 0.98, 0.97, sprintf('%d months', round(span_yrs*12)), ...
            'Units','normalized','HorizontalAlignment','right', ...
            'VerticalAlignment','top','FontSize',6.5,'Color',[0.2 0.2 0.2]);
    else
        h = histogram(ax, year(valid), 'FaceColor', [0.65 0.50 0.75], ...
            'EdgeColor', 'none');
        text(ax, 0.98, 0.97, sprintf('%d–%d', year(min(valid)), year(max(valid))), ...
            'Units','normalized','HorizontalAlignment','right', ...
            'VerticalAlignment','top','FontSize',6.5,'Color',[0.2 0.2 0.2]);
    end
    h.DataTipTemplate.DataTipRows(1).Label = char(varname);
    set(ax, 'YTick', [], 'FontSize', 7);
    box(ax, 'off');
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_num_num(ax, x, y, ~, ~)
% Scatter with transparency for dense data; adds a least-squares line.
% When one axis is discrete (few unique integer values, e.g. years), uses
% box plots instead.
    valid = ~isnan(x) & ~isnan(y);
    xv = x(valid);
    yv = y(valid);
    if isempty(xv), axis(ax,'off'); return; end

    x_disc = num_is_discrete(xv);
    y_disc = num_is_discrete(yv);

    if x_disc && ~y_disc
        plot_boxchart_by_group(ax, xv, yv);
        return;
    elseif y_disc && ~x_disc
        plot_boxchart_by_group(ax, yv, xv);
        return;
    end

    % Thin further if extremely dense (>5k points)
    MAX_SCATTER = 5000;
    if numel(xv) > MAX_SCATTER
        idx = randperm(numel(xv), MAX_SCATTER);
        xv = xv(idx); yv = yv(idx);
    end

    scatter(ax, xv, yv, 8, [0.25 0.45 0.70], 'filled', ...
        'MarkerFaceAlpha', min(1, 500/numel(xv)));
    hold(ax, 'on');

    % Least-squares line — skip silently when polyfit is badly conditioned
    prev_warn = warning('off', 'MATLAB:polyfit:RepeatedPointsOrRescale');
    lastwarn('');
    p = polyfit(xv, yv, 1);
    [~, wid] = lastwarn();
    warning(prev_warn);
    if isempty(wid)
        xl = xlim(ax);
        plot(ax, xl, polyval(p, xl), 'r-', 'LineWidth', 1.2);
    end

    % Pearson r in corner — bold with background box for readability
    r = corr(xv, yv, 'rows', 'complete');
    if isnan(r), r_str = 'r = ?'; else, r_str = sprintf('r = %.2f', r); end
    text(ax, 0.03, 0.97, r_str, ...
        'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 7.5, ...
        'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.7], 'Margin', 1);

    hold(ax, 'off');
    box(ax, 'off');
end

function tf = num_is_discrete(v)
% True when v looks like a discrete group axis: ≤25 unique integer values.
tf = numel(unique(v)) <= 25 && max(abs(v - round(v))) < 0.01;
end

function plot_boxchart_by_group(ax, grp, vals)
% Box-and-whisker per unique value of grp (e.g. one box per year).
grp_cat = categorical(grp);
try
    boxchart(ax, grp_cat, vals, ...
        'BoxFaceColor', [0.25 0.45 0.70], ...
        'WhiskerLineColor', [0.25 0.45 0.70], ...
        'MarkerColor', [0.25 0.45 0.70], ...
        'MarkerStyle', '.', ...
        'BoxWidth', 0.6);
    xtickangle(ax, 45);
    ax.XAxis.FontSize = 6;
catch
    scatter(ax, double(grp_cat), vals, 8, [0.25 0.45 0.70], 'filled', ...
        'MarkerFaceAlpha', min(1, 500/numel(vals)));
end
box(ax, 'off');
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_num_cat(ax, catdata, numdata, ~, ~, ~, ~)
% ≤5 categories  → hand-drawn box plot (within-group distribution)
% >5 categories  → horizontal median dot plot ranked by median (top 15)

    MAX_BOX  = 5;
    MAX_DOTS = 15;

    if iscategorical(catdata)
        cats  = categories(catdata);
        valid = ~isundefined(catdata) & ~isnan(numdata);
    elseif islogical(catdata)
        cats    = {'false','true'};
        catdata = categorical(double(catdata), [0 1], {'false','true'});
        valid   = ~isnan(numdata);
    else
        axis(ax, 'off'); return
    end

    catdata = catdata(valid);
    numdata = numdata(valid);
    if isempty(numdata), axis(ax, 'off'); return; end

    if numel(cats) <= MAX_BOX
        % ── Box plot ─────────────────────────────────────────────────────────
        nc   = numel(cats);
        xpos = double(catdata);
        hold(ax, 'on');
        for ki = 1:nc
            mask = xpos == ki;
            if ~any(mask), continue; end
            vals = numdata(mask);
            q    = quantile(vals, [0.25 0.5 0.75]);
            iqr_ = q(3) - q(1);
            wlo  = max(min(vals), q(1) - 1.5*iqr_);
            whi  = min(max(vals), q(3) + 1.5*iqr_);
            patch(ax, ki + [-0.3 0.3 0.3 -0.3], [q(1) q(1) q(3) q(3)], ...
                [0.35 0.55 0.75], 'EdgeColor', [0.2 0.2 0.2], 'LineWidth', 0.8);
            plot(ax, ki + [-0.3 0.3], [q(2) q(2)], '-', ...
                'Color', [0.1 0.1 0.1], 'LineWidth', 1.5);
            plot(ax, [ki ki], [wlo q(1)], '-', 'Color', [0.2 0.2 0.2]);
            plot(ax, [ki ki], [q(3) whi], '-', 'Color', [0.2 0.2 0.2]);
        end
        hold(ax, 'off');

    else
        % ── Median dot plot, top MAX_DOTS groups ranked by median ─────────────
        all_cats = categories(catdata);
        n_cats   = numel(all_cats);
        med_vals = NaN(n_cats, 1);
        iqr_vals = NaN(n_cats, 1);
        for ki = 1:n_cats
            vals = numdata(catdata == all_cats{ki});
            if ~isempty(vals)
                med_vals(ki) = median(vals, 'omitnan');
                iqr_vals(ki) = iqr(vals);
            end
        end

        % Sample MAX_DOTS groups to cover the full range of medians:
        % always include min and max, fill remaining slots with
        % evenly-spaced quantiles of the median distribution.
        valid_med = find(~isnan(med_vals));
        [~, sort_ord] = sort(med_vals(valid_med));
        valid_med = valid_med(sort_ord);   % indices into all_cats, sorted by median

        if numel(valid_med) <= MAX_DOTS
            sel = valid_med;
        else
            % Quantile-spaced picks across the sorted median list
            pick_pos = round(linspace(1, numel(valid_med), MAX_DOTS));
            pick_pos = unique(pick_pos);   % linspace rounding can duplicate endpoints
            sel = valid_med(pick_pos);
        end

        % Display bottom-to-top (lowest median at y=1)
        [~, disp_ord] = sort(med_vals(sel), 'ascend');
        sel = sel(disp_ord);

        hold(ax, 'on');
        for ki = 1:numel(sel)
            oi  = sel(ki);
            med = med_vals(oi);
            if isnan(med), continue; end
            half_iqr = iqr_vals(oi) / 2;
            plot(ax, [med - half_iqr, med + half_iqr], [ki ki], '-', ...
                'Color', [0.6 0.7 0.8], 'LineWidth', 1.5);
            plot(ax, med, ki, 'o', 'MarkerSize', 5, ...
                'MarkerFaceColor', [0.22 0.44 0.69], 'MarkerEdgeColor', 'none');
        end
        hold(ax, 'off');
    end

    set(ax, 'XTick', [], 'YTick', []);
    box(ax, 'off');
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_cat_cat(ax, x, y, ~, ~)
% Co-occurrence heatmap for two categorical columns.
    MAX_CATS = 10;   % heatmap becomes unreadable beyond this

    if ~iscategorical(x), x = categorical(x); end
    if ~iscategorical(y), y = categorical(y); end

    valid = ~isundefined(x) & ~isundefined(y);
    x = x(valid);
    y = y(valid);

    if isempty(x), axis(ax, 'off'); return; end

    % Pick top MAX_CATS categories by frequency (not alphabetically)
    cx = top_cats(x, MAX_CATS);
    cy = top_cats(y, MAX_CATS);

    % Filter rows jointly so x and y stay the same length
    keep = ismember(x, cx) & ismember(y, cy);
    x = x(keep);
    y = y(keep);

    if isempty(x), axis(ax, 'off'); return; end

    % Build count matrix
    M = zeros(numel(cy), numel(cx));
    for r = 1:numel(cy)
        for c = 1:numel(cx)
            M(r,c) = sum(x == cx{c} & y == cy{r});
        end
    end

    imagesc(ax, M);
    blues = interp1([0 1], [1 1 1; 0.13 0.44 0.71], linspace(0,1,64));
    colormap(ax, blues);
    set(ax, 'XTick', [], 'YTick', []);
    xticklabels(ax, {});
    yticklabels(ax, {});

    % For binary × binary, add tiny labels so orientation is unambiguous
    if numel(cx) <= 2 && numel(cy) <= 2
        set(ax, 'XTick', 1:numel(cx), 'YTick', 1:numel(cy), ...
            'XTickLabel', cellfun(@(s) truncate(s,6), cx, 'UniformOutput', false), ...
            'YTickLabel', cellfun(@(s) truncate(s,6), cy, 'UniformOutput', false), ...
            'FontSize', 6, 'TickLength', [0 0]);
    end

    box(ax, 'off');
end

function cats = top_cats(x, k)
% Return the top-k most frequent category labels as a cell array of chars.
    all_cats = categories(x);
    counts   = histcounts(x);          % one count per category, in category order
    [~, ord] = sort(counts, 'descend');
    cats     = all_cats(ord(1:min(k, end)));
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_time_pair(ax, x, y, ~, ~, rtype, ctype)
% Scatter or line for one datetime + one numeric column.
    if rtype == "datetime" && ctype == "numeric"
        tdata = x;  ndata = y;
    elseif ctype == "datetime" && rtype == "numeric"
        tdata = y;  ndata = x;
    else
        axis(ax, 'off'); return
    end
    valid = ~isnat(tdata) & ~isnan(ndata);
    if ~any(valid), axis(ax,'off'); return; end
    [ts, ord] = sort(tdata(valid));
    ns = ndata(valid);
    ns = ns(ord);
    plot(ax, ts, ns, '.', 'Color', [0.35 0.55 0.75], 'MarkerSize', 4);
    box(ax, 'off');
end


% ── se_select_columns ────────────────────────────────────────────────────────
function sel = se_select_columns(T, prof, maxv)
%SE_SELECT_COLUMNS  Pick the most informative, non-redundant columns to plot.
%
%   Numeric columns are scored by spread (std/range) and then pruned
%   greedily so that no two selected columns have |r| > CORR_THRESH.
%   Categorical columns are scored by Shannon entropy of their value
%   distribution (uniform = high entropy = informative; near-constant = 0).
%   The final selection interleaves: fill numeric slots first, then
%   categorical, up to maxv total.

CORR_THRESH  = 0.92;   % drop a numeric column if it's this correlated
                        % with any already-selected numeric column
MAX_NUM_FRAC = 0.75;   % at most this fraction of slots go to numeric columns

not_skip = find(~prof.skip);

% ── Score categorical columns (needed to know if any exist before numeric loop)
cat_idx = not_skip(prof.type(not_skip) == "categorical" | ...
                   prof.type(not_skip) == "logical");

% ── Score numeric columns ────────────────────────────────────────────────────
num_idx = not_skip(prof.type(not_skip) == "numeric");

num_scores = zeros(1, numel(num_idx));
for k = 1:numel(num_idx)
    col = T.(prof.name{num_idx(k)});
    col = double(col(~isnan(col)));
    if numel(col) < 2
        num_scores(k) = 0;
        continue
    end
    r = range(col);
    if r == 0
        num_scores(k) = 0;   % constant column — useless
    else
        num_scores(k) = std(col) / r;   % in (0, 0.5]; higher = more spread out
    end
end

% Sort numeric candidates by score descending
[~, num_ord] = sort(num_scores, 'descend');
num_ranked   = num_idx(num_ord);

% Greedy correlation pruning:
% Accept the top-scoring column, then keep accepting columns whose max
% absolute correlation with all already-accepted columns is < CORR_THRESH.
num_sel = [];
for k = 1:numel(num_ranked)
    candidate = num_ranked(k);
    if num_scores(num_ord(k)) == 0, continue; end   % constant, skip

    if isempty(num_sel)
        num_sel(end+1) = candidate; %#ok<AGROW>
    else
        cand_col = T.(prof.name{candidate});

        % Keep rows where both candidate and all selected are non-NaN
        valid = ~isnan(cand_col);
        for s = num_sel
            valid = valid & ~isnan(T.(prof.name{s}));
        end

        if sum(valid) < 10
            % Too few complete rows to compute correlation — accept it
            num_sel(end+1) = candidate; %#ok<AGROW>
        else
            existing = cell2mat(arrayfun(@(s) T.(prof.name{s})(valid), ...
                num_sel, 'UniformOutput', false));
            r_vals = abs(corr(cand_col(valid), existing));
            if max(r_vals) < CORR_THRESH
                num_sel(end+1) = candidate; %#ok<AGROW>
            end
        end
    end

    if numel(num_sel) >= floor(maxv * MAX_NUM_FRAC) && ~isempty(cat_idx)
        break
    end
    if numel(num_sel) >= maxv
        break
    end
end

% ── Score categorical columns ────────────────────────────────────────────────

cat_scores = zeros(1, numel(cat_idx));
for k = 1:numel(cat_idx)
    col = T.(prof.name{cat_idx(k)});
    if islogical(col)
        p = [mean(col), 1-mean(col)];
        p = p(p > 0);
    else
        col = col(~isundefined(col));
        if isempty(col), continue; end
        counts = histcounts(col);
        p = counts(counts > 0) / numel(col);
    end
    cat_scores(k) = -sum(p .* log2(p));   % Shannon entropy (bits)
end

[~, cat_ord] = sort(cat_scores, 'descend');
cat_sel = cat_idx(cat_ord);

% ── Combine: fill remaining slots with top-entropy categoricals ──────────────
remaining = maxv - numel(num_sel);
cat_sel   = cat_sel(1 : min(end, remaining));
sel       = [num_sel, cat_sel];

% ── Report what was selected and why ─────────────────────────────────────────
n_total = sum(~prof.skip);
if n_total > maxv
    fprintf('  ℹ Auto-selected %d of %d plottable columns:\n', numel(sel), n_total);
    for k = 1:numel(sel)
        idx = sel(k);
        t   = prof.type(idx);
        if t == "numeric"
            col  = T.(prof.name{idx});
            col  = col(~isnan(col));
            sc   = std(col) / (range(col) + eps);
            fprintf('    %-28s  numeric      spread = %.2f\n', ...
                prof.name{idx}, sc);
        else
            col = T.(prof.name{idx});
            col = col(~isundefined(col));
            counts = histcounts(col);
            p   = counts(counts > 0) / numel(col);
            ent = -sum(p .* log2(p));
            fprintf('    %-28s  categorical  entropy = %.2f bits\n', ...
                prof.name{idx}, ent);
        end
    end
    fprintf('    Use Columns= to override, or increase MaxVars.\n\n');
end
end


% ── Utilities ────────────────────────────────────────────────────────────────

function s = truncate(str, maxlen)
% Truncate a string for display, adding … if needed.
    if numel(str) > maxlen
        s = [str(1:maxlen-1), '…'];
    else
        s = str;
    end
end

function [colors, plot_order] = se_level_colors(levels)
% Assign colors to category levels.  The "Other" bucket (last level when it
% matches the "N more groups" pattern) gets light gray and is drawn first so
% it is occluded by the named levels.
n = numel(levels);
colors = lines(n);
is_other = n > 0 && ~isempty(regexp(levels{n}, '^\d+ more groups', 'once'));
if is_other
    colors(n, :) = [0.78 0.78 0.78];
    plot_order = [n, 1:n-1];
else
    plot_order = 1:n;
end
end


function s = se_label_name(name, compact)
% Return short_name (compact) or wrapped_name (full) depending on flag.
if compact
    s = short_name(name);
else
    s = wrapped_name(name);
end
end

function s = short_name(name)
% Shorten a variable name for axis labels.
    MAX = 18;
    if numel(name) > MAX
        s = [name(1:MAX-1) '…'];
    else
        s = name;
    end
end

function s = wrapped_name(name)
% Break a variable name at underscores/spaces into multiple lines,
% keeping each line under MAX_LINE chars. No truncation — full name shown.
    MAX_LINE = 16;
    if numel(name) <= MAX_LINE
        s = name;
        return
    end

    % Split at underscores and spaces
    parts = regexp(name, '[^_ ]+', 'match');
    if isempty(parts)
        s = name;
        return
    end

    lines    = {};
    cur_line = parts{1};
    for k = 2:numel(parts)
        candidate = [cur_line '_' parts{k}];
        if numel(candidate) <= MAX_LINE
            cur_line = candidate;
        else
            lines{end+1} = cur_line; %#ok<AGROW>
            cur_line = parts{k};
        end
    end
    lines{end+1} = cur_line;
    s = strjoin(lines, newline);
end


% ── cg_load_code ───────────────────────────────────────────────────────
function code = cg_load_code(filepath, T)
%SE_BUILD_LOAD_CODE  Return MATLAB code string that reloads this dataset.

% Resolve to absolute path so the recipe works regardless of working directory.
d = dir(filepath);
if ~isempty(d)
    filepath = fullfile(d(1).folder, d(1).name);
end

[~, ~, ext] = fileparts(filepath);
ext = lower(string(ext));
ud  = T.Properties.UserData;
L   = {};   % lines

if ext == ".zip"
    inner = '';
    if isstruct(ud) && ~isempty(ud.inner_file)
        inner = ud.inner_file;
    end
    [~, ~, inner_ext] = fileparts(inner);
    inner_ext = lower(inner_ext);
    L{end+1} = sprintf('tmpdir = tempname; mkdir(tmpdir);');
    L{end+1} = sprintf('unzip(''%s'', tmpdir);', filepath);
    if ismember(inner_ext, {'.xlsx','.xls','.xlsm'})
        sheet = '';
        if isstruct(ud) && ~isempty(ud.sheet), sheet = ud.sheet; end
        L{end+1} = sprintf('opts = detectImportOptions(fullfile(tmpdir, ''%s''), ''Sheet'', ''%s'');', inner, sheet);
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = sprintf('T = readtable(fullfile(tmpdir, ''%s''), opts, ''Sheet'', ''%s'');', inner, sheet);
    else
        L{end+1} = sprintf('opts = detectImportOptions(fullfile(tmpdir, ''%s''), ''FileType'', ''text'');', inner);
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = sprintf('T = readtable(fullfile(tmpdir, ''%s''), opts);', inner);
    end
elseif ismember(ext, [".xlsx", ".xls", ".xlsm"])
    sheet = '';
    if isstruct(ud) && ~isempty(ud.sheet), sheet = ud.sheet; end
    L{end+1} = sprintf('opts = detectImportOptions(''%s'', ''Sheet'', ''%s'');', filepath, sheet);
    L{end+1} = 'opts.MissingRule = ''fill'';';
    L{end+1} = sprintf('T = readtable(''%s'', opts, ''Sheet'', ''%s'');', filepath, sheet);
elseif ismember(ext, [".nc", ".nc4", ".netcdf"])
    L{end+1} = sprintf('%% NetCDF — adjust variable/start/count as needed:');
    L{end+1} = sprintf('data = ncread(''%s'', ''varname'');', filepath);
    L{end+1} = sprintf('%% See ncinfo(''%s'') for available variables.', filepath);
else
    sampled_n = 0;
    if isstruct(ud) && isfield(ud, 'sampled')
        sampled_n = ud.sampled;
    end
    if sampled_n > 0
        L{end+1} = sprintf('T = SampleData(''%s'', %d, ''Seed'', 42);', filepath, sampled_n);
    else
        L{end+1} = sprintf('opts = detectImportOptions(''%s'', ''FileType'', ''text'');', filepath);
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = sprintf('T = readtable(''%s'', opts);', filepath);
    end
end

code = strjoin(L, newline);
end


% ── cg_clean_code ──────────────────────────────────────────────────────
function code = cg_clean_code()
%CG_CLEAN_CODE  Emit recipe code for the clean/profile step.
%   Uses de_profile, which handles type conversion and missing-value recoding.
code = '[T, prof] = de_profile(T);';
end


% ── cg_best_plots_code ─────────────────────────────────────────────────
function code = cg_best_plots_code(T, prof, sel, source_name)
%CG_BEST_PLOTS_CODE  Emit recipe code for standalone full-page plots.
%
%   Top histogram, top scatter, and a full multi-series time-series block
%   (both overlaid + Total and stacked, when the data is compositional).

COLOR = '[0.35 0.55 0.75]';
L = {};
src_sq = strrep(source_name, '''', '''''');

% ── Numeric columns in sel ───────────────────────────────────────────────────
sel_num = sel(prof.type(sel) == "numeric");

% ── Best histogram ───────────────────────────────────────────────────────────
if ~isempty(sel_num)
    cn1 = prof.name{sel_num(1)};
    L{end+1} = sprintf('%% Best histogram: %s', cn1);
    L{end+1} = sprintf('de_histogram(T.%s, ''%s'');', cn1, strrep(cn1,'''',''''''));
    L{end+1} = '';
end

% ── Best scatter ─────────────────────────────────────────────────────────────
if numel(sel_num) >= 2
    cn1 = prof.name{sel_num(1)};
    cn2 = prof.name{sel_num(2)};
    L{end+1} = sprintf('%% Best scatter: %s vs %s', cn1, cn2);
    L{end+1} = sprintf('x = T.%s; y = T.%s;', cn1, cn2);
    L{end+1} = 'if isnumeric(x) && isnumeric(y)';
    L{end+1} = sprintf('    figure(''Name'', ''%s — %s vs %s'', ''NumberTitle'', ''off'', ''Color'', [1 1 1]);', ...
        src_sq, strrep(cn1,'''',''''''), strrep(cn2,'''',''''''));
    L{end+1} = '    valid = ~isnan(x) & ~isnan(y); n_pts = sum(valid);';
    L{end+1} = '    alpha = max(0.05, min(0.8, 500 / max(n_pts, 1)));';
    L{end+1} = sprintf('    scatter(x(valid), y(valid), 20, %s, ''filled'', ''MarkerFaceAlpha'', alpha);', COLOR);
    L{end+1} = sprintf('    xlabel(''%s''); ylabel(''%s'');', ...
        strrep(cn1,'''',''''''), strrep(cn2,'''',''''''));
    L{end+1} = sprintf('    title(sprintf(''%s vs %s  (n=%%d)'', n_pts));', ...
        strrep(cn1,'''',''''''), strrep(cn2,'''',''''''));
    L{end+1} = '    box off;';
    L{end+1} = 'end'; L{end+1} = '';
end

% ── Time series (datetime or year-axis) ──────────────────────────────────────
[time_idx, is_year_axis] = se_find_time_axis(prof);
ts_num = sel_num;
if ~isempty(time_idx) && is_year_axis
    ts_num = ts_num(ts_num ~= time_idx);
end

if ~isempty(time_idx) && ~isempty(ts_num)
    tcn      = prof.name{time_idx};
    tcn_sq   = strrep(tcn, '''', '''''');
    ncn_list = prof.name(ts_num);
    n_ts     = numel(ts_num);

    % Compositional: all non-negative across all selected numeric columns?
    is_compositional = false;
    if n_ts > 1
        all_ok = true;
        for kk = 1:n_ts
            v = double(T.(ncn_list{kk}));
            v = v(~isnan(v));
            if isempty(v) || any(v < 0), all_ok = false; break; end
        end
        is_compositional = all_ok;
    end

    col_args  = strjoin(cellfun(@(s) sprintf('T.%s', s), ncn_list, 'UniformOutput', false), ' ');
    lbl_items = strjoin(cellfun(@(s) sprintf('''%s''', strrep(s,'''','''''')), ncn_list, 'UniformOutput', false), ', ');

    L{end+1} = sprintf('%% Time series: %d series over %s', n_ts, tcn);
    L{end+1} = sprintf('t_col = T.%s;', tcn);
    L{end+1} = 'if isdatetime(t_col) || isnumeric(t_col)';
    L{end+1} = '    valid_t = ~ismissing(t_col);';
    L{end+1} = sprintf('    col_mat = [%s];', col_args);
    L{end+1} = sprintf('    ts_labels = {%s};', lbl_items);
    L{end+1} = '    t_u = unique(t_col(valid_t));';
    L{end+1} = sprintf('    n_u = numel(t_u); n_s = %d; Y = NaN(n_u, n_s);', n_ts);
    L{end+1} = '    for i = 1:n_u';
    L{end+1} = '        mask = t_col == t_u(i);';
    L{end+1} = '        for k = 1:n_s';
    L{end+1} = '            v = col_mat(mask, k); v = v(~isnan(v));';
    L{end+1} = '            if ~isempty(v), Y(i,k) = mean(v); end';
    L{end+1} = '        end';
    L{end+1} = '    end';
    L{end+1} = '';

    % Overlaid + Total
    L{end+1} = sprintf('    figure(''Name'', ''%s — time series (overlaid)'', ''NumberTitle'', ''off'', ''Color'', [1 1 1]);', src_sq);
    L{end+1} = '    ax = gca; hold(ax, ''on''); colors_ts = lines(n_s);';
    L{end+1} = '    for k = 1:n_s';
    L{end+1} = '        plot(ax, t_u, Y(:,k), ''-'', ''Color'', colors_ts(k,:), ''LineWidth'', 1.5, ''DisplayName'', ts_labels{k});';
    L{end+1} = '    end';
    if is_compositional
        L{end+1} = '    Y_total = sum(Y, 2, ''omitnan'');';
        L{end+1} = '    plot(ax, t_u, Y_total, ''-'', ''Color'', [0.10 0.10 0.10], ''LineWidth'', 3, ''DisplayName'', ''Total'');';
        L{end+1} = '    legend(ax, [ts_labels {''Total''}], ''Location'', ''bestoutside'', ''Interpreter'', ''none'', ''FontSize'', 8);';
    else
        L{end+1} = '    legend(ax, ts_labels, ''Location'', ''bestoutside'', ''Interpreter'', ''none'', ''FontSize'', 8);';
    end
    L{end+1} = sprintf('    xlabel(ax, ''%s'', ''Interpreter'', ''none''); ylabel(ax, ''Value''); box off; hold(ax, ''off'');', tcn_sq);
    L{end+1} = '';

    % Stacked (only when compositional and ≥2 time points)
    if is_compositional
        L{end+1} = '    if n_u > 1';
        L{end+1} = sprintf('        figure(''Name'', ''%s — time series (stacked)'', ''NumberTitle'', ''off'', ''Color'', [1 1 1]);', src_sq);
        L{end+1} = '        ax = gca; Y_plot = Y; Y_plot(isnan(Y_plot)) = 0;';
        L{end+1} = '        [~, sord] = sort(mean(Y_plot, 1), ''descend'');';
        L{end+1} = '        area(ax, t_u, Y_plot(:, sord), ''LineStyle'', ''none'', ''FaceAlpha'', 0.85);';
        L{end+1} = '        legend(ax, ts_labels(sord), ''Location'', ''bestoutside'', ''Interpreter'', ''none'', ''FontSize'', 8);';
        L{end+1} = sprintf('        xlabel(ax, ''%s'', ''Interpreter'', ''none''); ylabel(ax, ''Value (stacked)''); box off;', tcn_sq);
        L{end+1} = '    end';
        L{end+1} = '';
    end
    L{end+1} = 'end';  % close: if isdatetime(t_col) || isnumeric(t_col)
end

if isempty(L)
    code = '% No plottable numeric columns found.';
else
    code = strjoin(L, newline);
end
end


% ── se_assemble_recipe ───────────────────────────────────────────────────────
function recipe_path = se_assemble_recipe(filepath, T, prof, options)
%SE_ASSEMBLE_RECIPE  Build a standalone script, write to /tmp/, return path.
%
%   The script is self-contained: load + clean + 1-2 best-of plots.
%   It runs without DataExplorer installed.

[~, bname, ~] = fileparts(filepath);
bname_safe = regexprep(bname, '[^A-Za-z0-9_]', '_');
recipe_path = fullfile(tempdir, sprintf('dataexplorer_%s.m', bname_safe));

% Select the same columns the pairplot used
if ~isempty(options.Columns)
    if isnumeric(options.Columns)
        sel = options.Columns(:)';
    else
        cols = string(options.Columns);
        sel  = find(ismember(string(prof.name), cols));
    end
    sel = sel(~prof.skip(sel));
else
    sel = se_select_columns(T, prof, options.MaxVars);
end

load_code  = cg_load_code(filepath, T);
clean_code = cg_clean_code();
plots_code = cg_best_plots_code(T, prof, sel, prof.source_name);

header = sprintf([...
    '%% DataExplorer recipe — %s\n' ...
    '%% Generated %s\n' ...
    '%% Requires DataExplorer.m on the MATLAB path (for de_profile, de_histogram).\n' ...
    '%% To save this script: save_recipe(''%s_recipe.m'')\n'], ...
    prof.source_name, datetime('now','Format','yyyy-MM-dd HH:mm'), ...
    regexprep(prof.source_name, '[^A-Za-z0-9]', '_'));

sections = { ...
    header, ...
    '%% === Load ===', load_code, '', ...
    '%% === Clean ===', clean_code, '', ...
    '%% === Best-of Plots ===', plots_code ...
};

script_text = strjoin(sections, newline);

fid = fopen(recipe_path, 'w');
if fid == -1
    warning('DataExplorer:recipeFailed', ...
        'Could not write recipe to %s', recipe_path);
    recipe_path = '';
    return
end
fprintf(fid, '%s\n', script_text);
fclose(fid);
end


% ── se_find_time_axis ────────────────────────────────────────────────────────
function [time_idx, is_year_axis] = se_find_time_axis(prof)
%SE_FIND_TIME_AXIS  Return index of the time axis column and whether it is a
%   year-named numeric (true) or a proper datetime column (false).
%   Returns time_idx=[] if no time axis is found.

dt_idx = find(prof.type == "datetime" & ~prof.skip, 1, 'first');
if ~isempty(dt_idx)
    time_idx    = dt_idx;
    is_year_axis = false;
    return
end

num_cols = find(prof.type == "numeric" & ~prof.skip);
year_candidates = num_cols(arrayfun(@(i) ...
    ~isempty(regexpi(prof.name{i}, 'year', 'once')), num_cols));
if isscalar(year_candidates)
    time_idx    = year_candidates;
    is_year_axis = true;
else
    time_idx    = [];
    is_year_axis = false;
end
end


% ── se_plot_categorical_drilldown ────────────────────────────────────────────
function se_plot_categorical_drilldown(T, prof, sel)
%SE_PLOT_CATEGORICAL_DRILLDOWN  Grouped time series + scatter matrices by category.
%
%   For each qualifying categorical (non-constant, ≤15 levels):
%     1. Grouped time series: one subplot per numeric variable, one line per level.
%     2. Scatter matrix: np×np grid of scatters colored by that categorical.
%   For geo-like categoricals (name contains "state", or levels are state codes):
%     Bar charts of mean per state + state×time heatmap.

MAX_LEVELS = 15;

cat_all    = find(prof.type == "categorical" & ~prof.skip);
cat_useful = cat_all(prof.nunique(cat_all) > 1 & ...
                     prof.nunique(cat_all) <= MAX_LEVELS);
cat_big    = cat_all(prof.nunique(cat_all) > MAX_LEVELS);

[time_idx, is_year_axis] = se_find_time_axis(prof);

% Numeric columns for scatter matrix: selected numerics excluding time axis
sel_num = sel(prof.type(sel) == "numeric");
if ~isempty(time_idx)
    sel_num = sel_num(sel_num ~= time_idx);
end
% Cap scatter grid width for readability
MAX_NP_DRILL = 6;
if numel(sel_num) > MAX_NP_DRILL
    sel_num = sel_num(1:MAX_NP_DRILL);
end

% All non-skip numerics excluding time axis for time series subplots
if ~isempty(time_idx)
    ts_num = find(prof.type == "numeric" & ~prof.skip);
    ts_num = ts_num(ts_num ~= time_idx);
else
    ts_num = [];
end

if ~isempty(cat_useful)
    fprintf('  Categorical drill-down: %d grouping variable(s).\n', numel(cat_useful));
    for k = 1:numel(cat_useful)
        ci = cat_useful(k);
        if ~isempty(time_idx) && ~isempty(ts_num)
            se_plot_grouped_timeseries(T, prof, ci, time_idx, ts_num, is_year_axis);
        end
        if numel(sel_num) >= 2
            se_plot_scatter_by_cat(T, prof, ci, sel_num);
        end
    end
end

% High-cardinality categoricals: geo treatment OR top-K drill-down with Other
TOP_K = 8;
for k = 1:numel(cat_big)
    ci = cat_big(k);
    if se_looks_like_states(prof, ci, T)
        se_plot_state_summary(T, prof, ci, sel_num, ts_num, time_idx, is_year_axis);
    else
        catname_k  = prof.name{ci};
        cat_col_k  = T.(catname_k);
        all_levels = cellstr(categories(cat_col_k));  % N×1 column
        cnt        = countcats(cat_col_k);            % N×1 column, same order
        [~, ord]   = sort(cnt, 'descend');
        n_show     = min(TOP_K, numel(all_levels));
        top_levels = all_levels(ord(1:n_show));
        n_other    = numel(all_levels) - n_show;

        top_counts = cnt(ord(1:n_show));
        top_labels = cellfun(@(lv, c) sprintf('%s (n=%d)', lv, c), ...
            top_levels, num2cell(top_counts), 'UniformOutput', false);

        if n_other > 0
            n_other_rows = sum(~ismember(cat_col_k, top_levels) & ~isundefined(cat_col_k));
            other_label  = sprintf('%d more groups (n=%d)', n_other, n_other_rows);
            cat_str = string(cat_col_k);
            for ti = 1:n_show
                cat_str(cat_col_k == top_levels{ti}) = top_labels{ti};
            end
            cat_str(~ismember(cat_col_k, top_levels) & ~isundefined(cat_col_k)) = other_label;
            cat_str(isundefined(cat_col_k)) = missing;
            T_sub = T;
            T_sub.(catname_k) = categorical(cat_str, [top_labels; {other_label}]);
            T_sub = T_sub(~isundefined(T_sub.(catname_k)), :);
            fprintf('  Drill-down: %s — top %d of %d levels + Other\n', ...
                catname_k, n_show, prof.nunique(ci));
        else
            cat_str = string(cat_col_k);
            for ti = 1:n_show
                cat_str(cat_col_k == top_levels{ti}) = top_labels{ti};
            end
            cat_str(isundefined(cat_col_k)) = missing;
            T_sub = T;
            T_sub.(catname_k) = categorical(cat_str, top_labels);
            T_sub = T_sub(~isundefined(T_sub.(catname_k)), :);
            fprintf('  Drill-down: %s — all %d levels\n', catname_k, n_show);
        end

        if ~isempty(time_idx) && ~isempty(ts_num)
            se_plot_grouped_timeseries(T_sub, prof, ci, time_idx, ts_num, is_year_axis);
        end
        if numel(sel_num) >= 2
            se_plot_scatter_by_cat(T_sub, prof, ci, sel_num);
        end
    end
end

if isempty(cat_useful) && isempty(cat_big), return; end
end


% ── se_plot_grouped_timeseries ───────────────────────────────────────────────
function se_plot_grouped_timeseries(T, prof, cat_idx, time_idx, num_idxs, is_year_axis)
%SE_PLOT_GROUPED_TIMESERIES  One figure per categorical: mean of each numeric
%   over time, one line per category level.  Aggregates rows sharing the same
%   (level, time) by mean — appropriate when multiple rows exist per time point.

catname = prof.name{cat_idx};
cat_col = T.(catname);
levels  = cellstr(categories(cat_col));
[colors, plot_order] = se_level_colors(levels);
tdata   = T.(prof.name{time_idx});

% Vertical layout: one row per numeric variable, legend on every subplot
n_num  = numel(num_idxs);

fig = figure( ...
    'Name',        se_fig_title(sprintf('By %s', catname), prof.source_name), ...
    'Color',       [0.97 0.97 0.97], ...
    'NumberTitle', 'off');
tl = tiledlayout(fig, n_num, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

B_CI = 500;
for j = 1:n_num
    ax = nexttile(tl);
    ncn   = prof.name{num_idxs(j)};
    ydata = T.(ncn);

    for lk = plot_order
        mask = cat_col == levels{lk};
        t_sub = tdata(mask);
        y_sub = ydata(mask);

        if is_year_axis
            valid = ~isnan(t_sub) & ~isnan(y_sub);
        else
            valid = ~isnat(t_sub) & ~isnan(y_sub);
        end
        if sum(valid) < 2, continue; end

        t_v = t_sub(valid);
        y_v = y_sub(valid);

        % Bootstrap 95% CI per unique time value
        [t_u, ~, tidx] = unique(t_v);
        n_u = numel(t_u);
        y_agg = nan(n_u, 1);
        y_lo  = nan(n_u, 1);
        y_hi  = nan(n_u, 1);
        for tt = 1:n_u
            vals = y_v(tidx == tt);
            vals = vals(~isnan(vals));
            nv = numel(vals);
            if nv == 0, continue; end
            y_agg(tt) = mean(vals);
            if nv >= 2
                bm = mean(vals(randi(nv, nv, B_CI)), 1);
                bm = sort(bm);
                y_lo(tt) = bm(max(1, round(0.025*B_CI)));
                y_hi(tt) = bm(min(B_CI, round(0.975*B_CI)));
            else
                y_lo(tt) = vals; y_hi(tt) = vals;
            end
        end

        % CI shading (only where both bounds are finite)
        ok_ci = ~isnan(y_lo) & ~isnan(y_hi);
        if sum(ok_ci) >= 2
            hold(ax, 'on');
            t_ci = t_u(ok_ci);
            fill(ax, [t_ci; flipud(t_ci)], [y_hi(ok_ci); flipud(y_lo(ok_ci))], ...
                colors(lk,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
                'HandleVisibility', 'off');
        end

        h = plot(ax, t_u, y_agg, '-o', ...
            'Color',      colors(lk, :), ...
            'MarkerSize', 3, ...
            'LineWidth',  1.2, ...
            'DisplayName', levels{lk});
        hold(ax, 'on');
        try
            h.DataTipTemplate.DataTipRows(end+1) = ...
                dataTipTextRow(catname, repmat(levels(lk), numel(t_u), 1));
        catch
        end
    end

    if j == n_num
        xlabel(ax, prof.name{time_idx}, 'FontSize', 8, 'Interpreter', 'none');
    end
    ylabel(ax, ncn, 'FontSize', 7, 'Interpreter', 'none');
    legend(ax, 'Location', 'bestoutside', 'FontSize', 6, 'Interpreter', 'none');
    box(ax, 'off');
end

title(tl, se_src_prefix(prof.source_name, sprintf('by %s', catname)), ...
    'FontSize', 10, 'Interpreter', 'none');
end


% ── se_plot_scatter_by_cat ───────────────────────────────────────────────────
function se_plot_scatter_by_cat(T, prof, cat_idx, sel_num)
%SE_PLOT_SCATTER_BY_CAT  np×np scatter matrix with points colored by category.
%   Diagonal: overlapping probability-normalized histograms per level.
%   Off-diagonal: scatter plots, one color per level.

catname = prof.name{cat_idx};
cat_col = T.(catname);
levels  = cellstr(categories(cat_col));
n_lev   = numel(levels);
[colors, plot_order] = se_level_colors(levels);

MAX_NP = 6;
sel_num = sel_num(1:min(end, MAX_NP));
np = numel(sel_num);

fig = figure( ...
    'Name',        se_fig_title(catname, prof.source_name), ...
    'Color',       [0.97 0.97 0.97], ...
    'NumberTitle', 'off');
tl = tiledlayout(fig, np, np, 'TileSpacing', 'tight', 'Padding', 'compact');

% Choose alpha based on total non-missing point count
n_total = height(T);
pt_alpha = max(0.1, min(0.7, 300 / max(n_total, 1)));

% Collect one handle per level for the shared legend
legend_handles = gobjects(n_lev, 1);

for r = 1:np
    for c = 1:np
        ax = nexttile(tl);
        ri    = sel_num(r);
        ci    = sel_num(c);
        xname = prof.name{ci};
        yname = prof.name{ri};
        xdata = T.(xname);
        ydata = T.(yname);

        if r == c
            % Diagonal: overlapping normalized histograms
            for lk = plot_order
                mask = cat_col == levels{lk};
                x = xdata(mask);
                x = x(~isnan(x));
                if numel(x) < 2, continue; end
                h = histogram(ax, x, 15, ...
                    'Normalization', 'probability', ...
                    'FaceColor',     colors(lk, :), ...
                    'FaceAlpha',     0.45, ...
                    'EdgeColor',     'none', ...
                    'DisplayName',   levels{lk});
                hold(ax, 'on');
                h.DataTipTemplate.DataTipRows(1).Label = ...
                    sprintf('%s = %s', char(catname), char(levels{lk}));
                if ~isgraphics(legend_handles(lk))
                    legend_handles(lk) = h;
                end
            end
        else
            % Off-diagonal: colored scatter + per-level regression line + r
            for lk = plot_order
                mask  = cat_col == levels{lk};
                x     = xdata(mask);
                y     = ydata(mask);
                valid = ~isnan(x) & ~isnan(y);
                if ~any(valid), continue; end
                xv = x(valid);  yv = y(valid);
                if numel(xv) >= 5
                    r_val = corr(xv, yv);
                    lbl   = sprintf('%s (r=%.2f)', levels{lk}, r_val);
                    [ci_lo, ci_hi, x_fit, y_fit] = de_bootstrap_poly_ci(xv, yv, 1, 0.95, 300);
                    if ~isempty(y_fit)
                        hold(ax, 'on');
                        x_poly = [x_fit; flipud(x_fit)];
                        y_poly = [ci_hi; flipud(ci_lo)];
                        h_fill = fill(ax, x_poly, y_poly, ...
                            colors(lk,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
                            'HandleVisibility', 'off');
                        if isprop(h_fill, 'DataTipTemplate') && ...
                                ~isempty(h_fill.DataTipTemplate.DataTipRows)
                            h_fill.DataTipTemplate.DataTipRows(1).Label = ...
                                sprintf('%s = %s (CI)', char(catname), char(levels{lk}));
                        end
                        h_line = plot(ax, x_fit, y_fit, '-', 'Color', colors(lk,:), ...
                            'LineWidth', 1.5, 'HandleVisibility', 'off');
                        try
                            h_line.DataTipTemplate.DataTipRows(end+1) = ...
                                dataTipTextRow(catname, repmat(levels(lk), numel(x_fit), 1));
                        catch
                        end
                    end
                else
                    lbl = levels{lk};
                end
                h = scatter(ax, xv, yv, 8, colors(lk, :), 'filled', ...
                    'MarkerFaceAlpha', pt_alpha, 'DisplayName', lbl);
                hold(ax, 'on');
                try
                    h.DataTipTemplate.DataTipRows(end+1) = ...
                        dataTipTextRow(catname, repmat(levels(lk), numel(xv), 1));
                catch
                end
                if ~isgraphics(legend_handles(lk))
                    legend_handles(lk) = h;
                end
            end
        end

        % Tick strategy: full auto-ticks for small grids (≤5), endpoint-only for large.
        show_y = (c == 1 && r ~= c);
        show_x = (r == np && r ~= c);
        if np <= 5
            if show_y, set(ax, 'YTickMode', 'auto', 'FontSize', 6);
            else,       set(ax, 'YTick', []); end
            if show_x, set(ax, 'XTickMode', 'auto', 'FontSize', 6, 'XTickLabelRotation', 45);
            else,       set(ax, 'XTick', []); end
        else
            if show_y
                yl = ylim(ax);
                set(ax, 'YTick', [yl(1) yl(2)], 'FontSize', 5.5);
            else
                set(ax, 'YTick', []);
            end
            if show_x
                xl = xlim(ax);
                set(ax, 'XTick', [xl(1) xl(2)], 'FontSize', 5.5, 'XTickLabelRotation', 45);
            else
                set(ax, 'XTick', []);
            end
        end
        box(ax, 'off');

        name_fn = @(s) se_label_name(s, np >= 6);
        if r == 1
            title(ax, name_fn(xname), 'FontSize', 7, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
        end
        if r == c && r > 1
            title(ax, name_fn(yname), 'FontSize', 7, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
        end
        if c == 1
            yl = ylabel(ax, name_fn(yname), 'FontSize', 6, 'Interpreter', 'none');
            set(yl, 'Rotation', 0, 'HorizontalAlignment', 'right');
        end
    end
end

% One shared legend for the whole figure, placed in the east tile strip
valid_mask   = isgraphics(legend_handles);
valid_h      = legend_handles(valid_mask);
valid_labels = levels(valid_mask);
if ~isempty(valid_h)
    lgd = legend(nexttile(tl, 1), valid_h, valid_labels, ...
        'FontSize', 6, 'Interpreter', 'none');
    lgd.Layout.Tile = 'east';
end

title(tl, se_src_prefix(prof.source_name, sprintf('colored by %s', catname)), ...
    'FontSize', 10, 'Interpreter', 'none');
end


% ── se_looks_like_states ──────────────────────────────────────────────────────
function tf = se_looks_like_states(prof, idx, T)
%SE_LOOKS_LIKE_STATES  True if categorical column looks like U.S. state identifiers.
%   Matches on: column name containing "state"; ≥80% of levels are 2-letter
%   U.S. state/territory abbreviations; or ≥80% are full U.S. state names.
tf = false;
catname = prof.name{idx};
if contains(lower(catname), 'state')
    tf = true;
    return;
end
US_CODES = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA", ...
            "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD", ...
            "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ", ...
            "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC", ...
            "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY", ...
            "DC","PR","GU","VI","AS","MP"];
US_NAMES = ["ALABAMA","ALASKA","ARIZONA","ARKANSAS","CALIFORNIA", ...
            "COLORADO","CONNECTICUT","DELAWARE","FLORIDA","GEORGIA", ...
            "HAWAII","IDAHO","ILLINOIS","INDIANA","IOWA","KANSAS", ...
            "KENTUCKY","LOUISIANA","MAINE","MARYLAND","MASSACHUSETTS", ...
            "MICHIGAN","MINNESOTA","MISSISSIPPI","MISSOURI","MONTANA", ...
            "NEBRASKA","NEVADA","NEW HAMPSHIRE","NEW JERSEY","NEW MEXICO", ...
            "NEW YORK","NORTH CAROLINA","NORTH DAKOTA","OHIO","OKLAHOMA", ...
            "OREGON","PENNSYLVANIA","RHODE ISLAND","SOUTH CAROLINA", ...
            "SOUTH DAKOTA","TENNESSEE","TEXAS","UTAH","VERMONT","VIRGINIA", ...
            "WASHINGTON","WEST VIRGINIA","WISCONSIN","WYOMING", ...
            "DISTRICT OF COLUMBIA","PUERTO RICO","GUAM"];
levels = upper(cellstr(categories(T.(catname))));
if numel(levels) >= 3
    if all(cellfun(@numel, levels) == 2)
        tf = sum(cellfun(@(lv) ismember(lv, cellstr(US_CODES)), levels)) / numel(levels) >= 0.8;
    else
        tf = sum(cellfun(@(lv) ismember(lv, cellstr(US_NAMES)), levels)) / numel(levels) >= 0.8;
    end
end
end


% ── se_plot_state_summary ─────────────────────────────────────────────────────
function se_plot_state_summary(T, prof, cat_idx, sel_num, ts_num, time_idx, is_year_axis)
%SE_PLOT_STATE_SUMMARY  Bar charts of mean-per-state and state×time heatmaps.
%   Figure 1: horizontal bar chart of mean value per state, sorted descending.
%   Figure 2 (if time axis exists): imagesc heatmap of state × time for each numeric.

catname = prof.name{cat_idx};
cat_col = T.(catname);
states  = cellstr(unique(cat_col(~isundefined(cat_col))));
n_st    = numel(states);
if n_st == 0, return; end

% Numeric columns to show: union of sel_num and ts_num
num_idxs = unique([sel_num, ts_num(:)']);
num_idxs = num_idxs(prof.type(num_idxs) == "numeric");
if ~isempty(time_idx)
    num_idxs = num_idxs(num_idxs ~= time_idx);
end
n_num = numel(num_idxs);
if n_num == 0, return; end

fprintf('  State summary: %d states × %d variables.\n', n_st, n_num);

% ── Figure 1: horizontal bar charts of mean per state ────────────────────────
n_cols = min(n_num, 3);
n_rows = ceil(n_num / n_cols);

fig = figure('Name', se_fig_title(sprintf('By %s', catname), prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');

for j = 1:n_num
    ax = nexttile(tl);
    ncn   = prof.name{num_idxs(j)};
    ydata = T.(ncn);
    means = NaN(n_st, 1);
    for s = 1:n_st
        vals = ydata(cat_col == states{s});
        vals = vals(~isnan(vals));
        if ~isempty(vals), means(s) = mean(vals); end
    end
    [means_s, sord] = sort(means, 'descend', 'MissingPlacement', 'last');
    states_s = states(sord);
    barh(ax, 1:n_st, means_s, 'FaceColor', [0.3 0.5 0.8], 'EdgeColor', 'none');
    set(ax, 'YTick', 1:n_st, 'YTickLabel', states_s, 'FontSize', 5, ...
        'YDir', 'reverse');
    title(ax, wrapped_name(ncn), 'FontSize', 8, 'Interpreter', 'none');
    box(ax, 'off');
end
title(tl, se_src_prefix(prof.source_name, sprintf('mean by %s', catname)), ...
    'FontSize', 10, 'Interpreter', 'none');

% ── Figure 2: state × time heatmap ───────────────────────────────────────────
if isempty(time_idx), return; end

tdata = T.(prof.name{time_idx});
if is_year_axis
    valid_t = ~isnan(tdata);
else
    valid_t = ~isnat(tdata);
end
t_vals = unique(tdata(valid_t));
n_t    = numel(t_vals);
if n_t < 2, return; end

fig2 = figure('Name', se_fig_title(sprintf('%s × time', catname), prof.source_name),...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
tl2 = tiledlayout(fig2, n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');

for j = 1:n_num
    ax = nexttile(tl2);
    ncn   = prof.name{num_idxs(j)};
    ydata = T.(ncn);
    Heat  = NaN(n_st, n_t);
    for s = 1:n_st
        s_mask = cat_col == states{s};
        for tt = 1:n_t
            mask = s_mask & (tdata == t_vals(tt));
            vals = ydata(mask);
            vals = vals(~isnan(vals));
            if ~isempty(vals), Heat(s, tt) = mean(vals); end
        end
    end
    imagesc(ax, Heat);
    colorbar(ax);
    if is_year_axis
        step = max(1, floor(n_t / 8));
        set(ax, 'XTick', 1:step:n_t, ...
            'XTickLabel', t_vals(1:step:n_t), ...
            'XTickLabelRotation', 45);
    else
        set(ax, 'XTick', []);
    end
    set(ax, 'YTick', 1:n_st, 'YTickLabel', states, 'FontSize', 5);
    title(ax, wrapped_name(ncn), 'FontSize', 8, 'Interpreter', 'none');
    box(ax, 'off');
end
title(tl2, se_src_prefix(prof.source_name, sprintf('Time %s %s', char(215), catname)), ...
    'FontSize', 10, 'Interpreter', 'none');

% ── Animated choropleth (Mapping Toolbox) ─────────────────────────────────────
se_plot_state_choropleth(T, prof, cat_idx, num_idxs, time_idx, is_year_axis);
end


% ── se_plot_state_choropleth ──────────────────────────────────────────────────
function se_plot_state_choropleth(T, prof, cat_idx, num_idxs, time_idx, is_year_axis) %#ok<INUSL>
%SE_PLOT_STATE_CHOROPLETH  Thin wrapper: calls de_usamap for each numeric variable.
catname = prof.name{cat_idx};
tcn     = '';
if ~isempty(time_idx), tcn = prof.name{time_idx}; end

for j = 1:numel(num_idxs)
    ncn        = prof.name{num_idxs(j)};
    fig_title  = se_fig_title(sprintf('Choropleth: %s', ncn), prof.source_name);
    if isempty(tcn)
        de_usamap(T, 'StateCol', catname, 'ColorCol', ncn, 'Title', fig_title);
    else
        de_usamap(T, 'StateCol', catname, 'ColorCol', ncn, ...
            'TimeCol', tcn, 'Title', fig_title);
    end
end
end


% ── se_fig_title ─────────────────────────────────────────────────────────────
function s = se_fig_title(label, ~)
s = label;
end


% ── se_src_prefix ─────────────────────────────────────────────────────────────
function s = se_src_prefix(~, rest)
s = rest;
end


% ── se_stamp_source ───────────────────────────────────────────────────────────
function se_stamp_source(fig, source_name)
% Add a small gray source footnote at the bottom of the figure.
if strcmp(source_name, 'table input'), return; end
annotation(fig, 'textbox', [0.0, 0.0, 1.0, 0.022], ...
    'String', source_name, ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontSize', 7, 'Color', [0.55 0.55 0.55], 'Interpreter', 'none', ...
    'FitBoxToText', 'off');
end


% de_profile, de_histogram, de_bootstrap_poly_ci are standalone .m files
% in the same directory as DataExplorer.m — callable from any script on the path.