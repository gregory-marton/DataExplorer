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
    [~, fname, fext] = fileparts(source);
    base = [fname, fext];
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

end % ── DataExplorer ──────────────────────────────────────────────────────


%% ═══════════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTIONS
%% ═══════════════════════════════════════════════════════════════════════════

% ── se_load ─────────────────────────────────────────────────────────────────
function T = se_load(filepath, options)
%SE_LOAD  Detect format, sniff delimiter, detect header row, load table.

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

    % collect candidate data files recursively
    exts   = {'*.csv','*.tsv','*.txt','*.xlsx','*.xls'};
    files  = [];
    for k = 1:numel(exts)
        files = [files; dir(fullfile(tmpdir, '**', exts{k}))]; %#ok<AGROW>
    end

    if isempty(files)
        error('DataExplorer:emptyZip', 'No CSV/TSV/XLSX found inside the ZIP.');
    end

    if numel(files) == 1
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

    if numel(sheets) == 1
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
    else
        opts = detectImportOptions(filepath, 'FileType', 'text', 'Delimiter', delim);
        opts.MissingRule = 'fill';
        T = readtable(filepath, opts);
        T = se_sample(T, options.MaxRows);
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

        while true
            raw = input('  Choice (Enter = 1): ', 's');
            if isempty(raw), raw = '1'; end
            if ismember(raw, {'1','2','3'}), break; end
            fprintf('  Please enter 1, 2, or 3.\n');
        end

        % For options 1 and 2, ask which dimension
        if ismember(raw, {'1','2'})
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

[~, ~, ext] = fileparts(filepath);
ext = lower(ext);
ud  = T.Properties.UserData;

fprintf('\n  ══════════════════════════════════════════════════════════\n');
fprintf('  To load this dataset in a script:\n');
fprintf('  ──────────────────────────────────────────────────────────\n');

if ext == ".zip"
    % They loaded a file from inside a zip — they need to unzip first
    inner = '';
    if isstruct(ud) && ~isempty(ud.inner_file)
        inner = ud.inner_file;
    end
    [~, inner_base, inner_ext] = fileparts(inner);
    inner_ext = lower(inner_ext);
    fprintf('  tmpdir = tempname; mkdir(tmpdir);\n');
    fprintf('  unzip(''%s'', tmpdir);\n', filepath);
    if ismember(inner_ext, {'.xlsx','.xls','.xlsm'})
        sheet = '';
        if isstruct(ud) && ~isempty(ud.sheet)
            sheet = ud.sheet;
        end
        fprintf('  opts = detectImportOptions(fullfile(tmpdir, ''%s''), ''Sheet'', ''%s'');\n', ...
            inner, sheet);
        fprintf('  opts.MissingRule = ''fill'';\n');
        fprintf('  T = readtable(fullfile(tmpdir, ''%s''), opts, ''Sheet'', ''%s'');\n', ...
            inner, sheet);
    else
        fprintf('  opts = detectImportOptions(fullfile(tmpdir, ''%s''), ''FileType'', ''text'');\n', inner);
        fprintf('  opts.MissingRule = ''fill'';\n');
        fprintf('  T = readtable(fullfile(tmpdir, ''%s''), opts);\n', inner);
    end

elseif ismember(ext, {'.xlsx','.xls','.xlsm'})
    sheet = '';
    if isstruct(ud) && ~isempty(ud.sheet)
        sheet = ud.sheet;
    end
    fprintf('  opts = detectImportOptions(''%s'', ''Sheet'', ''%s'');\n', filepath, sheet);
    fprintf('  opts.MissingRule = ''fill'';\n');
    fprintf('  T = readtable(''%s'', opts, ''Sheet'', ''%s'');\n', filepath, sheet);

elseif ismember(ext, {'.nc','.nc4','.netcdf'})
    fprintf('  %% NetCDF — adjust variable name, start, and count as needed:\n');
    fprintf('  data = ncread(''%s'', ''varname'');\n', filepath);
    fprintf('  %% See ncinfo(''%s'') for available variables.\n', filepath);

else
    % Plain text
    fprintf('  opts = detectImportOptions(''%s'', ''FileType'', ''text'');\n', filepath);
    fprintf('  opts.MissingRule = ''fill'';\n');
    fprintf('  T = readtable(''%s'', opts);\n', filepath);
    % If the file is large, also suggest SampleData
    info = dir(filepath);
    if info.bytes > 100e6
        fprintf('\n  %% File is large (%.0f MB) — for a random sample use:\n', ...
            info.bytes/1e6);
        fprintf('  T = SampleData(''%s'', %d);\n', filepath, height(T));
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


% ── se_profile ───────────────────────────────────────────────────────────────
function [T, prof] = se_profile(T, missingStrings)
%SE_PROFILE  Classify each column, fix types, count missing values.

n    = height(T);
ncol = width(T);

prof.name        = T.Properties.VariableNames;
prof.source_name = '';
prof.skip        = false(1, ncol);
prof.skip_reason = repmat("", 1, ncol);
prof.type     = repmat("unknown",  1, ncol);
prof.nmissing = zeros(1, ncol);
prof.nunique  = zeros(1, ncol);
prof.skip     = false(1, ncol);     % true if >80% missing

% Common numeric sentinel values used as stand-ins for missing
SENTINELS = [-999, -9999, -99999, 9999, 99999, 999];

for k = 1:ncol
    col  = T.(prof.name{k});
    cname = prof.name{k};

    % ── String/char/cellstr: try numeric conversion, else categorical ──────
    if ischar(col) || iscellstr(col) || (isstring(col) && ~isscalar(col))
        col = string(col);

        % Recode known missing strings
        col(ismember(col, missingStrings)) = missing;

        % Attempt numeric conversion: keep as numeric only if ≥70% succeed
        numvals = str2double(col);
        pct_numeric = sum(~isnan(numvals)) / n;
        if pct_numeric >= 0.70
            col = numvals;
        else
            col = categorical(col);
        end
        T.(cname) = col;
    end

    % Re-fetch after possible conversion
    col = T.(cname);

    % ── Classify ────────────────────────────────────────────────────────────
    if isnumeric(col) || islogical(col)
        % Recode sentinel values
        if isnumeric(col)
            for s = SENTINELS
                col(col == s) = NaN;
            end
            T.(cname) = col;
        end

        if islogical(col)
            prof.type(k) = "logical";
            nmiss = 0;
        else
            prof.type(k) = "numeric";
            nmiss = sum(isnan(col));
        end
        prof.nmissing(k) = nmiss;
        prof.nunique(k)  = numel(unique(col(~isnan(col))));

    elseif iscategorical(col)
        % Remove any category labels that are known missing strings
        bad_cats = intersect(categories(col), cellstr(missingStrings));
        if ~isempty(bad_cats)
            col = setcats(col, setdiff(categories(col), bad_cats));
            T.(cname) = col;
        end
        prof.type(k)     = "categorical";
        prof.nmissing(k) = sum(isundefined(col));
        prof.nunique(k)  = numel(categories(col));

    elseif isdatetime(col)
        prof.type(k)     = "datetime";
        prof.nmissing(k) = sum(isnat(col));
        valid            = col(~isnat(col));
        prof.nunique(k)  = numel(unique(valid));

    elseif isduration(col)
        prof.type(k)     = "datetime";
        prof.nmissing(k) = sum(isnan(seconds(col)));
        valid            = col(~isnan(seconds(col)));
        prof.nunique(k)  = numel(unique(valid));

    else
        prof.type(k) = "other";
    end

    % Flag columns that are mostly empty
    if prof.nmissing(k) / n > 0.80
        prof.skip(k)        = true;
        prof.skip_reason(k) = "mostly missing";
    end

    % Flag ID-like columns: every non-missing value is unique → useless for plots
    % Only applies to categoricals — numeric measurements naturally have unique values
    n_present = n - prof.nmissing(k);
    if n_present > 1 && prof.nunique(k) == n_present && ...
            prof.type(k) == "categorical"
        prof.skip(k)        = true;
        prof.skip_reason(k) = "all values unique (ID column)";
    end
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
        ~isempty(regexpi(prof.name{i}, 'year')), num_cols));
    if numel(year_candidates) == 1
        year_col = year_candidates;
        fprintf('  ℹ "%s" treated as time axis (year column).\n', prof.name{year_col});
    end
end

if numel(dt_cols) == 1 && numel(num_cols) >= 2
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
fig = figure('Name', sprintf('DataExplorer — %s', prof.source_name), ...
    'Color', [0.97 0.97 0.97], ...
    'NumberTitle', 'off');

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
    title_str = sprintf('%s  —  n = %d  (%d of %d variables shown)', ...
        prof.source_name, n, np, n_total_plottable);
else
    title_str = sprintf('%s  —  n = %d', prof.source_name, n);
end
title(tl, title_str, 'FontSize', 11, 'Interpreter', 'none');
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
        fig_name = sprintf('DataExplorer (overview) — %s', prof.source_name);
    else
        fig_name = sprintf('DataExplorer (overview %d/%d) — %s', ...
            pg, n_pages, prof.source_name);
    end

    fig = figure('Name', fig_name, 'Color', [0.97 0.97 0.97], ...
        'NumberTitle', 'off');

    tl = tiledlayout(fig, NROWS, NCOLS, 'TileSpacing', 'tight', 'Padding', 'compact');

    if n_pages == 1
        title_str = sprintf('%s  —  all %d variables', prof.source_name, nv);
    else
        title_str = sprintf('%s  —  variables %d–%d of %d  (page %d/%d)', ...
            prof.source_name, idx_range(1), idx_range(end), nv, pg, n_pages);
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
if numel(dt_cols) == 1
    encoding = 'time';
    enc_col  = dt_cols;
elseif numel(num_cols) == 1
    encoding = 'size';
    enc_col  = num_cols;
elseif numel(cat_cols) == 1
    encoding = 'color_cat';
    enc_col  = cat_cols;
end

% ── Build figure ─────────────────────────────────────────────────────────────
fig = figure('Name', sprintf('DataExplorer (map) — %s', prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');

BASE_SZ = 20;   % default marker area in points²

if has_mapping
    ax = geoaxes(fig);
    switch encoding
        case 'time'
            tdata  = T.(prof.name{enc_col});
            tdata  = tdata(valid);
            tnums  = datenum(tdata);
            geoscatter(ax, lat, lon, BASE_SZ, tnums, 'filled', ...
                'MarkerFaceAlpha', 0.6);
            colormap(ax, 'turbo');
            cb = colorbar(ax);
            cb.TickLabels = datestr(linspace(min(tnums), max(tnums), 5), 'mmm yyyy');
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
                'MarkerFaceAlpha', 0.6);
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

title(ax, sprintf('%s  —  map  (n = %d)', prof.source_name, sum(valid)), ...
    'FontSize', 11, 'Interpreter', 'none');
end


% ── se_plot_timeseries ────────────────────────────────────────────────────────
function se_plot_timeseries(T, prof, dt_idx, options)
%SE_PLOT_TIMESERIES  All numeric variables on one plot against a datetime axis.
%
%   If all values are non-negative: stacked area chart (shows composition).
%   Otherwise: z-scored overlaid lines (shows relative patterns).

tdata   = T.(prof.name{dt_idx});
num_idx = find(prof.type == "numeric" & ~prof.skip);
n_series = numel(num_idx);
if n_series == 0, return; end

% Sort by time
valid_t      = ~isnat(tdata);
[tdata_s, ord] = sort(tdata(valid_t));

% Build data matrix (rows = time, cols = series), NaN for missing
Y = NaN(sum(valid_t), n_series);
labels = cell(1, n_series);
for k = 1:n_series
    col = T.(prof.name{num_idx(k)});
    col = col(valid_t);
    Y(:, k) = col(ord);
    labels{k} = prof.name{num_idx(k)};
end

% Decide plot mode: stacked area if all values non-negative, else z-score lines
all_nonneg = all(Y(~isnan(Y)) >= 0);

fig = figure( ...
    'Name',        sprintf('DataExplorer (time series) — %s', prof.source_name), ...
    'Color',       [0.97 0.97 0.97], ...
    'NumberTitle', 'off');

ax = axes(fig);

% Keep raw copy for correlation heatmap regardless of plot mode
Y_raw = Y;

if all_nonneg
    % Replace NaN with 0 for area chart (gaps would be misleading anyway)
    Y(isnan(Y)) = 0;
    % Sort series by mean value descending so largest is at bottom
    [~, sord] = sort(mean(Y, 1), 'descend');
    Y      = Y(:, sord);
    labels = labels(sord);

    area(ax, tdata_s, Y, 'LineStyle', 'none', 'FaceAlpha', 0.85);
    ylabel(ax, 'Generation (stacked)', 'FontSize', 8);
    mode_note = 'stacked area';
else
    % Raw overlaid lines — dominant series will be visible, small ones less so,
    % but that relative scale is meaningful. Students can drill down with Columns=.
    plot(ax, tdata_s, Y, 'LineWidth', 1.0);
    ylabel(ax, 'Value (raw)', 'FontSize', 8);
    yline(ax, 0, ':', 'Color', [0.5 0.5 0.5]);
    mode_note = 'raw values';
end

legend(ax, labels, 'Location', 'bestoutside', 'FontSize', 7, ...
    'Interpreter', 'none');
set(ax, 'FontSize', 8);
box(ax, 'off');

title(ax, sprintf('%s  —  time series, %s  (n = %d, %d series)', ...
    prof.source_name, mode_note, height(T), n_series), ...
    'FontSize', 11, 'Interpreter', 'none');

% Also produce a correlation heatmap so co-movement patterns are visible
se_plot_corrheatmap(Y_raw, labels, prof.source_name);
end


% ── se_plot_timeseries_numeric ────────────────────────────────────────────────
function se_plot_timeseries_numeric(T, prof, year_idx, options)
%SE_PLOT_TIMESERIES_NUMERIC  Like se_plot_timeseries but for a numeric year axis.

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

all_nonneg = all(Y(~isnan(Y)) >= 0);
Y_raw      = Y;

fig = figure('Name', sprintf('DataExplorer (time series) — %s', prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
ax = axes(fig);

if all_nonneg
    Y(isnan(Y)) = 0;
    [~, sord] = sort(mean(Y,1), 'descend');
    Y = Y(:,sord);  labels = labels(sord);
    area(ax, xdata_s, Y, 'LineStyle', 'none', 'FaceAlpha', 0.85);
    ylabel(ax, 'Value (stacked)', 'FontSize', 8);
    mode_note = 'stacked area';
else
    plot(ax, xdata_s, Y, 'LineWidth', 1.0);
    ylabel(ax, 'Value (raw)', 'FontSize', 8);
    yline(ax, 0, ':', 'Color', [0.5 0.5 0.5]);
    mode_note = 'raw values';
end

xlabel(ax, prof.name{year_idx}, 'FontSize', 8, 'Interpreter', 'none');
legend(ax, labels, 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
set(ax, 'FontSize', 8);
box(ax, 'off');
title(ax, sprintf('%s  —  time series, %s  (n = %d, %d series)', ...
    prof.source_name, mode_note, height(T), n_series), ...
    'FontSize', 11, 'Interpreter', 'none');

se_plot_corrheatmap(Y_raw, labels, prof.source_name);
end


% ── se_plot_corrheatmap ───────────────────────────────────────────────────────
function se_plot_corrheatmap(Y, labels, source_name)
%SE_PLOT_CORRHEATMAP  Pearson correlation matrix with hierarchical clustering.
%   Variables are reordered by average linkage clustering so co-moving
%   groups appear as blocks along the diagonal.

% Drop columns that are all-NaN or constant (corr would be NaN/undefined)
valid_cols = false(1, size(Y, 2));
for k = 1:size(Y, 2)
    col = Y(:, k);
    col = col(~isnan(col));
    valid_cols(k) = numel(col) >= 3 && std(col) > 0;
end
Y      = Y(:, valid_cols);
labels = labels(valid_cols);
n      = size(Y, 2);

if n < 2, return; end

% Pairwise Pearson correlation (complete cases per pair)
R = corr(Y, 'rows', 'pairwise');
R(isnan(R)) = 0;   % treat uncorrelated-by-missing as zero

% Hierarchical clustering on dissimilarity = 1 - r to reorder variables
D    = 1 - R;
D    = (D + D') / 2;          % ensure symmetry
D(1:n+1:end) = 0;             % zero diagonal
link = linkage(squareform(max(D, 0)), 'average');
ord  = optimalleaforder(link, squareform(max(D, 0)));

R_ord      = R(ord, ord);
labels_ord = labels(ord);

% ── Plot ─────────────────────────────────────────────────────────────────────
fig = figure( ...
    'Name',        sprintf('DataExplorer (correlations) — %s', source_name), ...
    'Color',       [0.97 0.97 0.97], ...
    'NumberTitle', 'off');

ax = axes(fig);
imagesc(ax, R_ord, [-1 1]);

% Diverging red-white-blue colormap
cmap = diverging_rwb(64);
colormap(ax, cmap);
cb = colorbar(ax);
cb.Label.String = 'Pearson r';
cb.FontSize = 8;

% Tick labels
set(ax, 'XTick', 1:n, 'YTick', 1:n, ...
    'XTickLabel', labels_ord, 'YTickLabel', labels_ord, ...
    'XTickLabelRotation', 45, 'FontSize', 8, 'TickLabelInterpreter', 'none');

% Annotate each cell with the r value
for r = 1:n
    for c = 1:n
        val = R_ord(r, c);
        % White text on dark cells, dark text on light cells
        txt_color = [1 1 1] * (abs(val) > 0.5);
        text(ax, c, r, sprintf('%.2f', val), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'FontSize', max(5, min(8, 80/n)), 'Color', txt_color);
    end
end

title(ax, sprintf('%s  —  pairwise correlations (%d variables)', ...
    source_name, n), 'FontSize', 11, 'Interpreter', 'none');
axis(ax, 'square');
box(ax, 'off');
end

function cmap = diverging_rwb(n)
% Red-white-blue diverging colormap, n levels.
    half  = floor(n/2);
    red   = [linspace(0.80, 1, half)', linspace(0.10, 1, half)', linspace(0.10, 1, half)'];
    blue  = [linspace(1, 0.17, n-half)', linspace(1, 0.40, n-half)', linspace(1, 0.70, n-half)'];
    cmap  = [red; blue];
end


% ── Cell-type plot helpers ────────────────────────────────────────────────────

function plot_num_diag(ax, x, name, nmissing, n)
% Histogram with summary stats annotation (mean, std, min, max).
    valid = x(~isnan(x));
    if isempty(valid)
        axis(ax, 'off');
        text(ax, 0.5, 0.5, 'all missing', 'HorizontalAlignment', 'center', ...
            'Units', 'normalized', 'Color', [0.6 0.6 0.6]);
        return
    end
    histogram(ax, valid, 'FaceColor', [0.35 0.55 0.75], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.8);

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
function plot_cat_diag(ax, x, name, nmissing, n)
% Horizontal bar chart: quantile-spaced sample of categories by count.
    MAX_K = 15;
    if iscategorical(x)
        total_cats = numel(categories(x));
        cats       = categories(x);
        counts     = histcounts(x);
    elseif islogical(x)
        total_cats = 2;
        cats       = {'false','true'};
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

    % Fix hover tooltip: replace numeric Y position with the category name
    b.DataTipTemplate.DataTipRows(1).Label = 'Count';
    b.DataTipTemplate.DataTipRows(2).Label = 'Category';
    b.DataTipTemplate.DataTipRows(2).Value = cats_s;   % bar i → cats_s{i}

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
function plot_time_diag(ax, x, name)
% Histogram of datetime values by year (or month if span < 2 years).
    if isduration(x)
        x = datetime(0,0,0) + x;   % convert to datetime for uniform handling
    end
    valid = x(~isnat(x));
    if isempty(valid), axis(ax,'off'); return; end
    span_yrs = years(max(valid) - min(valid));
    if span_yrs < 2
        histogram(ax, month(valid), 1:13, 'FaceColor', [0.65 0.50 0.75], ...
            'EdgeColor', 'none');
        text(ax, 0.98, 0.97, sprintf('%d months', round(span_yrs*12)), ...
            'Units','normalized','HorizontalAlignment','right', ...
            'VerticalAlignment','top','FontSize',6.5,'Color',[0.2 0.2 0.2]);
    else
        histogram(ax, year(valid), 'FaceColor', [0.65 0.50 0.75], ...
            'EdgeColor', 'none');
        text(ax, 0.98, 0.97, sprintf('%d–%d', year(min(valid)), year(max(valid))), ...
            'Units','normalized','HorizontalAlignment','right', ...
            'VerticalAlignment','top','FontSize',6.5,'Color',[0.2 0.2 0.2]);
    end
    set(ax, 'YTick', [], 'FontSize', 7);
    box(ax, 'off');
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_num_num(ax, x, y, xname, yname)
% Scatter with transparency for dense data; adds a least-squares line.
    valid = ~isnan(x) & ~isnan(y);
    xv = x(valid);
    yv = y(valid);
    if isempty(xv), axis(ax,'off'); return; end

    % Thin further if extremely dense (>5k points)
    MAX_SCATTER = 5000;
    if numel(xv) > MAX_SCATTER
        idx = randperm(numel(xv), MAX_SCATTER);
        xv = xv(idx); yv = yv(idx);
    end

    scatter(ax, xv, yv, 8, [0.25 0.45 0.70], 'filled', ...
        'MarkerFaceAlpha', min(1, 500/numel(xv)));
    hold(ax, 'on');

    % Least-squares line
    p = polyfit(xv, yv, 1);
    xl = xlim(ax);
    plot(ax, xl, polyval(p, xl), 'r-', 'LineWidth', 1.2);

    % Pearson r in corner — bold with background box for readability
    r = corr(xv, yv, 'rows', 'complete');
    text(ax, 0.03, 0.97, sprintf('r = %.2f', r), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 7.5, ...
        'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.7], 'Margin', 1);

    hold(ax, 'off');
    box(ax, 'off');
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function plot_num_cat(ax, catdata, numdata, catname, numname, has_stats, flipped)
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
        [sorted_meds, sort_ord] = sort(med_vals(valid_med));
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
function plot_cat_cat(ax, x, y, xname, yname)
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
function plot_time_pair(ax, x, y, xname, yname, rtype, ctype)
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
    col = col(~isnan(col));
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
        % Build matrix of valid rows for correlation check
        cols_so_far = cell2mat(cellfun(@(n) ...
            T.(n)(~any(isnan(cell2mat( ...
                cellfun(@(nn) T.(nn), prof.name(num_sel), 'UniformOutput', false) ...
            )), 2)), ...
            prof.name(num_sel), 'UniformOutput', false));
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