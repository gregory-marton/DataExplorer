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
if isempty(source) && ~istable(source)
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

%% ── 1a.  NetCDF multi-variable fast-path ─────────────────────────────────
if ischar(source) || isstring(source)
    [~, ~, nc_ext_] = fileparts(string(source));
    if ismember(lower(string(nc_ext_)), [".nc", ".nc4", ".netcdf"]) && ...
            strlength(options.NCVariable) == 0
        nc_info_   = ncinfo(string(source));
        data_vars_ = nc_list_data_vars(nc_info_);
        if ~isempty(data_vars_)
            n_plot_ = min(options.MaxVars, numel(data_vars_));
            fprintf('  NetCDF: %d data variable(s) found; plotting %d.\n', ...
                numel(data_vars_), n_plot_);
            T = table();
            [~, fn_, fe_] = fileparts(string(source));

            % ── Pass 1: load all spatial-grid variables into one table ────────
            sp_vars_ = data_vars_(cellfun(@(v) nc_is_spatial_grid(nc_info_, v), ...
                data_vars_(1:n_plot_)));
            T_sp_ = table();
            if ~isempty(sp_vars_)
                fprintf('  Loading %d spatial grid variable(s): %s\n', ...
                    numel(sp_vars_), strjoin(sp_vars_, ', '));
                try
                    T_sp_ = de_stride_sample(string(source), ...
                        Variable=string(sp_vars_{1}), ...
                        MaxRows=options.MaxRows, Verbose=true);
                    for sp_k_ = 2:numel(sp_vars_)
                        try
                            T_extra_ = de_stride_sample(string(source), ...
                                Variable=string(sp_vars_{sp_k_}), ...
                                MaxRows=options.MaxRows, Verbose=false);
                            vn_ = matlab.lang.makeValidName(sp_vars_{sp_k_});
                            if height(T_extra_) == height(T_sp_)
                                T_sp_.(vn_) = T_extra_.(vn_);
                            end
                        catch ME_
                            if strcmp(ME_.identifier, 'MATLAB:interrupt'), rethrow(ME_); end
                            fprintf('  ⚠ Skipping "%s": %s\n', sp_vars_{sp_k_}, ME_.message);
                        end
                    end
                catch ME_
                    if strcmp(ME_.identifier, 'MATLAB:interrupt'), rethrow(ME_); end
                    fprintf('  ⚠ Could not load spatial grid: %s\n', ME_.message);
                    T_sp_ = table();
                end
            end
            if height(T_sp_) > 0
                % Fully recipe-driven (no direct render path): the spatial recipe
                % loads, profiles, overviews, and geo-scatters every spatial var.
                recipe_sp_ = cg_netcdf_spatial_recipe(string(source), sp_vars_);
                T_ret_ = T_sp_; run(recipe_sp_); T_sp_ = T_ret_;
                T = T_sp_;
            end

            % ── Pass 2: non-spatial-grid variables, one at a time ────────────
            for nc_vi_ = 1:n_plot_
                vname_vi_ = data_vars_{nc_vi_};
                if nc_is_spatial_grid(nc_info_, vname_vi_), continue; end
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
                prof_vi_.source_name = sprintf('%s%s [%s]', fn_, fe_, vname_vi_);
                se_echo_load_code(string(source), T_vi_);
                se_report(T_vi_, prof_vi_);
                panel_vi_  = prof_vi_.panel;
                T = T_vi_; prof = prof_vi_;
                [~, recipe_vi_] = se_assemble_recipe(string(source), T, prof, panel_vi_, opts_vi_);
                idx_ = strfind(recipe_vi_, '%% === Overview ===');
                if ~isempty(idx_), eval(recipe_vi_(idx_(1):end)); else, eval(recipe_vi_); end
            end
            return
        end
        % No data vars found — fall through to normal single-variable path
    end
end

if ischar(source) || isstring(source)
    T = se_load(string(source), options);
elseif istable(source)
    T = source;
    if height(T) == 0
        fprintf('  ℹ Empty table (0 rows) — nothing to explore.\n');
        return
    end
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

%% ── 4 + 5.  Recipe ────────────────────────────────────────────────────────
% The recipe is the canonical code path for all figure production.
% It is assembled, written to /tmp/, and echoed; then only the plot sections
% are eval'd here (T and prof are already loaded above, so re-running the
% load/clean sections would be redundant and slow).  The saved recipe file
% is always complete (load + clean + plots) so it re-runs correctly standalone.
panel = prof.panel;
src_str_ = '';
if ischar(source) || isstring(source)
    src_str_ = string(source);
end
[~, recipe_text] = se_assemble_recipe(src_str_, T, prof, panel, options);
idx_ = strfind(recipe_text, '%% === Overview ===');
if ~isempty(idx_), eval(recipe_text(idx_(1):end)); else, eval(recipe_text); end

end % ── DataExplorer ──────────────────────────────────────────────────────


%% ═══════════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTIONS  (se_ prefix = private to DataExplorer.m)
%  Shared internal utilities live in de__*.m files on the path.
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
    cleanup_tmp = onCleanup(@() rmdir(tmpdir, 's'));

    ok_exts = {'.csv', '.tsv', '.txt', '.xlsx', '.xls', '.asc'};
    SMALL_FILE_BYTES = 5000;

    % Try Java listing first: avoids full extraction of large archives (e.g.
    % DWCA zips with 20 000 files).  Entry names may have trailing spaces
    % (common in some zip tools) — use strtrim for extension checks but keep
    % the raw name for Java lookups, then strtrim when writing to disk.
    did_selective = false;
    zip_entries   = zip_list_entries(filepath);   % struct array: .name, .bytes

    if ~isempty(zip_entries)
        % Filter to data-file candidates
        keep = false(1, numel(zip_entries));
        for k = 1:numel(zip_entries)
            [~, ~, ext] = fileparts(strtrim(zip_entries(k).name));
            keep(k) = ismember(lower(ext), ok_exts);
        end
        cand = zip_entries(keep);   % struct array: .name, .bytes

        if ~isempty(cand)
            % InnerFile override — compare trimmed names
            if strlength(options.InnerFile) > 0
                target = char(options.InnerFile);
                idx    = find(strcmp(strtrim({cand.name}), strtrim(target)), 1);
                if isempty(idx)
                    error('DataExplorer:innerFileNotFound', ...
                        'File "%s" not found inside ZIP. Available: %s', ...
                        target, strjoin(strtrim({cand.name}), ', '));
                end
                cand = cand(idx);
            end

            % If multiple candidates, pick ONE before extracting so we never
            % decompress multi-GB archives we won't use.
            if numel(cand) > 1
                [sizes_s, ord] = sort([cand.bytes], 'ascend');
                cand_s         = cand(ord);
                names_s        = strtrim({cand_s.name});

                if numel(cand) > 10
                    shown_k      = find(sizes_s >= SMALL_FILE_BYTES);
                    suppressed_n = sum(sizes_s < SMALL_FILE_BYTES);
                else
                    shown_k      = 1:numel(cand_s);
                    suppressed_n = 0;
                end

                fprintf('  Files found inside ZIP (sorted by size):\n');
                for k = 1:numel(shown_k)
                    sk = shown_k(k);
                    sz = sizes_s(sk);
                    if sz >= 1e6
                        sz_str = sprintf('%.1f MB', sz/1e6);
                    else
                        sz_str = sprintf('%.0f KB', sz/1e3);
                    end
                    fprintf('    [%2d]  %-40s  %s\n', k, names_s{sk}, sz_str);
                end
                if suppressed_n > 0
                    fprintf('  (%d lookup/admin files under 5 KB hidden)\n', suppressed_n);
                end
                fprintf('\n');
                default_k = shown_k(end);
                fprintf('  Enter number (default %d = %s),\n', ...
                    numel(shown_k), names_s{default_k});

                if options.AutoSelect
                    pick_idx = default_k;
                    fprintf('  AutoSelect: picking largest "%s"\n', names_s{default_k});
                else
                    while true
                        raw = input('  or filename for a hidden file: ', 's');
                        if isempty(raw)
                            pick_idx = default_k;
                            break
                        elseif all(ismember(raw, '0123456789'))
                            n = str2double(raw);
                            if n >= 1 && n <= numel(shown_k)
                                pick_idx = shown_k(n);
                                break
                            else
                                fprintf('  Please enter a number between 1 and %d.\n', numel(shown_k));
                            end
                        else
                            match = find(strcmp(names_s, raw), 1);
                            if ~isempty(match)
                                pick_idx = match;
                                break
                            else
                                fprintf('  File "%s" not found in ZIP.\n', raw);
                            end
                        end
                    end
                end
                cand = cand_s(pick_idx);
            end

            % Extract only the chosen candidate(s)
            selected_zip_entry = cand(1).name;   % original name (may have trailing space)
            all_ok = true;
            for k = 1:numel(cand)
                try
                    zip_extract_entry(filepath, cand(k).name, tmpdir);
                catch
                    all_ok = false;
                    break;
                end
            end
            if all_ok
                did_selective = true;
            end
        end
    end

    if ~did_selective
        unzip(filepath, tmpdir);
    end

    % Collect extracted files (search root and subdirs; ** may miss root on macOS)
    all_files = [dir(fullfile(tmpdir, '*.*')); dir(fullfile(tmpdir, '**', '*.*'))];
    all_files = all_files(~[all_files.isdir]);
    full_paths = fullfile({all_files.folder}, {all_files.name});
    [~, ia]   = unique(full_paths);
    all_files  = all_files(ia);
    keep = false(1, numel(all_files));
    for k = 1:numel(all_files)
        [~, ~, ext] = fileparts(strtrim(all_files(k).name));  % strtrim defensive
        keep(k) = ismember(lower(ext), ok_exts);
    end
    files = all_files(keep);

    if isempty(files)
        error('DataExplorer:emptyZip', 'No CSV/TSV/XLSX/ASC found inside the ZIP.');
    end

    if did_selective || isscalar(files)
        choice_idx = 1;
    else
        % Fallback picker — only reached when Java listing failed and full
        % unzip produced multiple data files.
        [~, size_ord] = sort([files.bytes], 'ascend');
        files_sorted  = files(size_ord);

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
    if isempty(T.Properties.UserData)
        T.Properties.UserData = struct('sheet', '', 'inner_file', strtrim(files(choice_idx).name));
    else
        T.Properties.UserData.inner_file = strtrim(files(choice_idx).name);
    end
    % Preserve the original ZIP entry name (may have trailing whitespace) so
    % the recipe's unzip command can reference it exactly.
    if did_selective && exist('selected_zip_entry', 'var')
        T.Properties.UserData.inner_file_zip = selected_zip_entry;
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
    names_before = T.Properties.VariableNames;
    T = se_fix_names(T, filepath, '.xlsx', sheetname);
    if ~isequal(names_before, T.Properties.VariableNames)
        T.Properties.UserData.explicit_header = true;
    end
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
        T = de_reservoir_sample(filepath, options.MaxRows, Verbose=true);
        T = se_record_sampled(T, height(T));
    else
        opts = detectImportOptions(filepath, 'FileType', 'text', 'Delimiter', delim);
        opts.MissingRule = 'fill';
        T = readtable(filepath, opts);
        n_before = height(T);
        T = se_sample(T, options.MaxRows);
        if height(T) < n_before
            T = se_record_sampled(T, height(T), n_before);
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

        auto_ival = 1;   % middle slice index, set by NCVariable heuristic below

        % Resolve reduction choice non-interactively when requested
        nc_red = lower(char(options.NCReduction));
        if ismember(nc_red, {'flatten','mean','slice'})
            raw = struct('flatten','3','mean','1','slice','2');
            raw = raw.(nc_red);
            fprintf('  NCReduction="%s": using option %s\n', nc_red, raw);
        elseif options.AutoSelect
            raw = '3';   % flatten preserves all coordinates — best for grouping flow
            fprintf('  AutoSelect: flattening to long-format table\n');
        elseif strlength(options.NCVariable) > 0
            % NCVariable was explicitly set → use size heuristic, no prompt
            if total_elems <= options.MaxRows * 10
                raw = '3';
                fprintf('  Auto: flattening to long-format (%d elements)\n', total_elems);
            else
                % Mean over time-like dimension if present; else dim 1
                dim_choice = 1;
                for k = 1:ndim
                    if ~isempty(regexpi(dim_names{k}, 'time|^t$|day|month|year', 'once'))
                        dim_choice = k; break;
                    end
                end
                raw = '2';
                auto_ival = ceil(sz(dim_choice) / 2);
                fprintf('  Auto: middle slice of "%s" (index %d/%d, %d elements > MaxRows×10)\n', ...
                    dim_names{dim_choice}, auto_ival, sz(dim_choice), total_elems);
            end
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
            elseif strlength(options.NCVariable) > 0
                % dim_choice already set by heuristic above — no prompt needed
                fprintf('  Auto dim: %d ("%s")\n', dim_choice, dim_names{dim_choice});
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
                    elseif strlength(options.NCVariable) > 0
                        ival = auto_ival;
                        fprintf('  Auto slice: index %d of %d\n', ival, sz(dim_choice));
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
    T.Properties.UserData = struct('sheet', '', 'inner_file', '', 'nc_varname', varname);
end

% ── nc_list_data_vars ─────────────────────────────────────────────────────────
function data_vars = nc_list_data_vars(info)
%NC_LIST_DATA_VARS  Names of data variables in a NetCDF file.
%   A coordinate variable is one whose name matches any dimension name used
%   anywhere in the file.  Everything else with at least one element is a
%   data variable.
dim_per_var = cell(1, numel(info.Variables));
for k = 1:numel(info.Variables)
    d = info.Variables(k).Dimensions;
    if ~isempty(d)
        dim_per_var{k} = {d.Name};
    end
end
all_dims = unique([dim_per_var{:}]);

nv = numel(info.Variables);
data_vars = cell(1, nv);
nd = 0;
for k = 1:nv
    v = info.Variables(k);
    if ~ismember(v.Name, all_dims) && ~isempty(v.Size) && prod(v.Size) > 0
        nd = nd + 1;
        data_vars{nd} = v.Name;
    end
end
data_vars = data_vars(1:nd);
end

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

function recipe_path = cg_netcdf_spatial_recipe(filepath, sp_vars)
%CG_NETCDF_SPATIAL_RECIPE  Write a single recipe for all spatial NetCDF variables.
%   sp_vars is a cell array of variable name strings.
%   Recipe calls de_stride_sample + de_geoscatter for each variable.
    d = dir(filepath);
    if ~isempty(d)
        filepath = fullfile(d(1).folder, d(1).name);
    end
    fpath_sq = strrep(char(filepath), '''', '''''');
    [~, basename] = fileparts(filepath);
    src_base_sq = strrep(basename, '''', '''''');

    all_safe = cellfun(@matlab.lang.makeValidName, sp_vars, 'UniformOutput', false);
    vars_cell_str = ['{''', strjoin(all_safe, ''','''), '''}'];

    L = {};
    L{end+1} = sprintf('%% DataExplorer recipe — %s  [%s]', filepath, strjoin(sp_vars, ', '));
    L{end+1} = '';
    L{end+1} = 'addpath(fileparts(which(''DataExplorer'')));';
    L{end+1} = '';
    L{end+1} = '% Stride-sample each variable and combine into one table';
    first_sq = strrep(sp_vars{1}, '''', '''''');
    L{end+1} = sprintf('T = de_stride_sample(''%s'', Variable=''%s'', Verbose=false);', fpath_sq, first_sq);
    stride_sub = cell(1, numel(sp_vars)-1);
    for k = 2:numel(sp_vars)
        vn_sq   = strrep(sp_vars{k}, '''', '''''');
        vn_safe = all_safe{k};
        stride_sub{k-1} = sprintf('T.%s = de_stride_sample(''%s'', Variable=''%s'', Verbose=false).%s;', ...
            vn_safe, fpath_sq, vn_sq, vn_safe);
    end
    L = [L, stride_sub];
    L{end+1} = '';
    L{end+1} = '% Profile + overview of the spatial sample';
    L{end+1} = '[T, prof] = de_profile(T);';
    L{end+1} = 'de_overview(T, prof);';
    L{end+1} = '';
    L{end+1} = '% Aggregate by grid cell: mean and std across all time steps';
    L{end+1} = sprintf('T_agg = groupsummary(T, {''longitude'',''latitude''}, {''mean'',''std''}, %s);', vars_cell_str);
    L{end+1} = '';
    L{end+1} = '% Geo scatter per variable: color = temporal mean, size = temporal std';
    geo_sub = cell(1, 3*numel(sp_vars));
    for k = 1:numel(sp_vars)
        vn_sq   = strrep(sp_vars{k}, '''', '''''');
        vn_safe = all_safe{k};
        geo_sub{3*k-2} = sprintf('de_geoscatter(T_agg.longitude, T_agg.latitude, T_agg.mean_%s, T_agg.std_%s, ...', vn_safe, vn_safe);
        geo_sub{3*k-1} = sprintf('    ColorLabel=''mean(%s)'', SizeLabel=''std(%s)'', MinSize=5, MaxSize=150, ...', vn_sq, vn_sq);
        geo_sub{3*k}   = sprintf('    Title=''%s'', Source=''%s'');', vn_sq, src_base_sq);
    end
    L = [L, geo_sub];
    code = strjoin(L, newline);

    recipe_path = fullfile(tempdir, sprintf('dataexplorer_%s.m', ...
        matlab.lang.makeValidName(basename)));
    fid = fopen(recipe_path, 'w');
    fprintf(fid, '%s\n', code);
    fclose(fid);
    se_print_recipe(code, sprintf('%s_recipe.m', basename));
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

        % A row looks like a pure-text header if every cell is non-numeric text
        is_text = cellfun(@(v) ischar(v) || isstring(v), firstrow);
        is_num  = cellfun(@(v) ~isnan(str2double(string(v))), firstrow);
        looks_like_header = all(is_text) && ~all(is_num);

        % Also detect mixed headers: some text labels + year-like integers
        % (e.g. "Data_Status, StateCode, MSN, 1960, 1961, …, 2023").
        % Require ≥3 year-like integers to avoid false positives on data rows
        % that happen to include one year value (e.g. survey year).
        YEAR_MIN  = 1900;  YEAR_MAX = 2100;
        year_vals = cellfun(@(v) isnumeric(v) && isscalar(v) && ~isnan(v) && ...
            v >= YEAR_MIN && v <= YEAR_MAX && v == floor(v), firstrow);
        looks_like_mixed_header = any(is_text) && sum(year_vals) >= 3 && ~looks_like_header;

        if looks_like_header || looks_like_mixed_header
            % Build candidate names; convert numeric cells (e.g. 1960) to
            % their string representation before makeValidName.
            cand = cell(1, numel(firstrow));
            for j = 1:numel(firstrow)
                v = firstrow{j};
                if isnumeric(v) && isscalar(v)
                    cand{j} = sprintf('%g', v);   % 1960 → '1960' → x1960
                else
                    cand{j} = char(string(v));
                end
            end
            valid = matlab.lang.makeValidName(cand);
            T.Properties.VariableNames = cellstr(valid);
            T(1, :) = [];   % drop the now-redundant first row
            if looks_like_mixed_header
                fprintf('  ✓ Header row has mixed text + year columns — names reassigned:\n');
            else
                fprintf('  ✓ Reassigned variable names from first data row:\n');
            end
            preview = strjoin(valid(1:min(6, end)), ',  ');
            if numel(valid) > 6
                fprintf('      %s, … (%d more)\n', preview, numel(valid) - 6);
            else
                fprintf('      %s\n', preview);
            end
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


% ── se_filter_choro_cols ──────────────────────────────────────────────────────
function idxs = se_filter_choro_cols(idxs, prof, families)
%SE_FILTER_CHORO_COLS  Remove non-data-variable candidates from choropleth selection.
%   Excludes: constant, time-named, lat/lon coordinate, integer id-named columns,
%   and non-representative members of correlated families (keeps only fam(1)).
if nargin < 3, families = {}; end
if isempty(idxs), return; end

LAT_LON      = ["lat","latitude","lat_","latitude_dd","decimallatitude", ...
                "lon","long","longitude","lon_","longitude_dd","decimallongitude"];
names_lower  = lower(string(prof.name));

is_const     = prof.nunique(idxs) <= 1;
is_coord     = ismember(names_lower(idxs), LAT_LON);
% Identifier (id-like last token) and time-named columns, via robust tokenizer
% (MATLAB regexp \b does not work, and CamelCase needs de_name_tokens).
is_id        = false(size(idxs));
is_time_name = false(size(idxs));
TIME_TOKENS  = ["year","month","day","date","time"];
for ji = 1:numel(idxs)
    toks = de_name_tokens(prof.name{idxs(ji)});
    if ismember(toks(end), ["code","id","num","number"])
        is_id(ji) = true;
    end
    if any(ismember(toks, TIME_TOKENS))
        is_time_name(ji) = true;
    end
end

% Non-representative family members (keep only fam(1) per family)
is_fam_nonrep = false(size(idxs));
if ~isempty(families)
    non_rep = cell2mat(cellfun(@(f) f(2:end), families, 'UniformOutput', false));
    is_fam_nonrep = ismember(idxs, non_rep);
end

idxs = idxs(~is_const & ~is_time_name & ~is_coord & ~is_id & ~is_fam_nonrep);
end


% ── se_logcolor_arg ───────────────────────────────────────────────────────────
function s = se_logcolor_arg(prof, idx)
%SE_LOGCOLOR_ARG  Return ", 'LogColor','on'" for strongly-skewed numeric columns,
%   else ''.  Lets the recipe decide log color from the profiled skewness.
s = '';
if isfield(prof, 'skewness') && idx >= 1 && idx <= numel(prof.skewness) ...
        && ~isnan(prof.skewness(idx)) && abs(prof.skewness(idx)) > 2
    s = ', ''LogColor'',''on''';
end
end


% ── se_record_sampled ─────────────────────────────────────────────────────────
function T = se_record_sampled(T, n, n_orig)
% Store how many rows were sampled so cg_load_code can emit SampleData().
% n_orig is the pre-sampling row count (stored so de_overview can display "n of N").
    if nargin < 3, n_orig = n; end
    if isempty(T.Properties.UserData)
        T.Properties.UserData = struct('sheet', '', 'inner_file', '', ...
            'sampled', n, 'n_orig', n_orig);
    else
        T.Properties.UserData.sampled = n;
        T.Properties.UserData.n_orig  = n_orig;
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
function s = truncate(str, maxlen)
% Truncate a string for display, adding … if needed.
    if numel(str) > maxlen
        s = [str(1:maxlen-1), '…'];
    else
        s = str;
    end
end
function code = cg_load_code(filepath, T)
%CG_LOAD_CODE  Return MATLAB code string that loads this dataset.
if isempty(filepath)
    code = sprintf('%s\n%s\n%s\n%s\n%s', ...
        '% T was provided directly as a MATLAB table.', ...
        '% Replace this block with your own load code, for example:', ...
        '%   opts = detectImportOptions(''your_file.csv'');', ...
        '%   opts.MissingRule = ''fill'';', ...
        '%   T = readtable(''your_file.csv'', opts);');
    return
end

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
    inner     = '';
    inner_zip = '';   % original ZIP entry name (may have trailing whitespace)
    sampled_n = 0;
    if isstruct(ud)
        if isfield(ud, 'inner_file')     && ~isempty(ud.inner_file),     inner     = ud.inner_file; end
        if isfield(ud, 'inner_file_zip') && ~isempty(ud.inner_file_zip), inner_zip = ud.inner_file_zip; end
        if isfield(ud, 'sampled')        && ~isempty(ud.sampled),        sampled_n = ud.sampled; end
    end
    if isempty(inner_zip), inner_zip = inner; end
    [~, ~, inner_ext] = fileparts(inner);
    inner_ext = lower(inner_ext);
    % Use system unzip -j for selective extraction: avoids unpacking the
    % entire archive (critical for large ZIPs like DWCA with 20 000+ files).
    % inner_zip preserves any trailing whitespace in the original entry name.
    L{end+1} = 'tmpdir = tempname; mkdir(tmpdir);';
    L{end+1} = sprintf('system([''unzip -j -d "'' tmpdir ''" "%s" "%s"'']);', ...
        filepath, inner_zip);
    % If the ZIP entry name has trailing whitespace, rename the extracted file
    % to the clean (trimmed) name before referencing it.
    if ~strcmp(inner, inner_zip)
        L{end+1} = sprintf('raw_p_ = fullfile(tmpdir, ''%s'');', inner_zip);
        L{end+1} = sprintf('if exist(raw_p_, ''file''), movefile(raw_p_, fullfile(tmpdir, ''%s'')); end', inner);
    end
    L{end+1} = sprintf('inner_path = fullfile(tmpdir, ''%s'');', inner);
    if ismember(inner_ext, {'.xlsx','.xls','.xlsm'})
        sheet = '';
        if isstruct(ud) && ~isempty(ud.sheet), sheet = ud.sheet; end
        L{end+1} = sprintf('opts = detectImportOptions(inner_path, ''Sheet'', ''%s'');', sheet);
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = sprintf('T = readtable(inner_path, opts, ''Sheet'', ''%s'');', sheet);
    elseif sampled_n > 0
        L{end+1} = sprintf('T = de_reservoir_sample(inner_path, %d, Seed=42);', sampled_n);
    else
        L{end+1} = 'opts = detectImportOptions(inner_path, ''FileType'', ''text'');';
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = 'T = readtable(inner_path, opts);';
    end
elseif ismember(ext, [".xlsx", ".xls", ".xlsm"])
    sheet = '';
    explicit_hdr = false;
    if isstruct(ud)
        if ~isempty(ud.sheet), sheet = ud.sheet; end
        if isfield(ud, 'explicit_header') && ud.explicit_header
            explicit_hdr = true;
        end
    end
    if explicit_hdr
        L{end+1} = sprintf('opts = detectImportOptions(''%s'', ''Sheet'', ''%s'', ''VariableNamesRange'', ''A1'', ''DataRange'', ''A2'');', filepath, sheet);
    else
        L{end+1} = sprintf('opts = detectImportOptions(''%s'', ''Sheet'', ''%s'');', filepath, sheet);
    end
    L{end+1} = 'opts.MissingRule = ''fill'';';
    L{end+1} = sprintf('T = readtable(''%s'', opts, ''Sheet'', ''%s'');', filepath, sheet);
elseif ismember(ext, [".nc", ".nc4", ".netcdf"])
    nc_var = '';
    if isstruct(ud) && isfield(ud, 'nc_varname') && ~isempty(ud.nc_varname)
        nc_var = char(ud.nc_varname);
    end
    if ~isempty(nc_var)
        L{end+1} = sprintf('T = de_stride_sample(''%s'', Variable=''%s'');', filepath, nc_var);
    else
        L{end+1} = sprintf('T = de_stride_sample(''%s'');', filepath);
        L{end+1} = sprintf('%% Available variables: see ncinfo(''%s'').Variables', filepath);
    end
else
    sampled_n = 0;
    if isstruct(ud) && isfield(ud, 'sampled')
        sampled_n = ud.sampled;
    end
    if sampled_n > 0
        L{end+1} = sprintf('T = de_reservoir_sample(''%s'', %d, Seed=42);', filepath, sampled_n);
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

% Short figure-name prefix: use only the [sheet/var] tag if present, else empty.
% Never put the bare filename in a window title.
m_src = regexp(char(source_name), '\[([^\]]+)\]\s*$', 'tokens', 'once');
if ~isempty(m_src)
    fig_prefix = [strrep(strtrim(m_src{1}), '''', '''''') ' — '];
else
    fig_prefix = '';
end

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
    L{end+1} = sprintf('    figure(''Name'', ''%s%s vs %s'', ''NumberTitle'', ''off'', ''Color'', [1 1 1]);', ...
        fig_prefix, strrep(cn1,'''',''''''), strrep(cn2,'''',''''''));
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
[time_idx, is_year_axis] = de_find_time_axis(prof);
ts_num = sel_num;
if ~isempty(time_idx) && is_year_axis
    ts_num = ts_num(ts_num ~= time_idx);
end

if ~isempty(time_idx) && ~isempty(ts_num)
    tcn      = prof.name{time_idx};
    tcn_sq   = strrep(tcn, '''', '''''');
    ncn_list = prof.name(ts_num);
    n_ts     = numel(ts_num);

    % Aggregate to per-time-point means (same logic as live plotters) then
    % apply the shared compositional test.
    if is_year_axis
        xdata_g = double(T.(prof.name{time_idx}));
        valid_g  = ~isnan(xdata_g);
    else
        xdata_g = T.(prof.name{time_idx});
        valid_g  = ~isnat(xdata_g);
    end
    [~, ~, xidx_g] = unique(xdata_g(valid_g));
    n_ug = max(xidx_g);
    if isempty(n_ug) || n_ug < 2
        is_compositional = false;
    else
    Y_g  = NaN(n_ug, n_ts);
    for kk = 1:n_ts
        col_g = double(T.(ncn_list{kk})); col_g = col_g(valid_g);
        for tt = 1:n_ug
            v = col_g(xidx_g == tt); v = v(~isnan(v));
            if ~isempty(v), Y_g(tt, kk) = mean(v); end
        end
    end
    is_compositional = se_is_compositional(Y_g, T, prof);
    end

    if ~isempty(n_ug) && n_ug >= 2
    lbl_items = strjoin(cellfun(@(s) sprintf('''%s''', strrep(s,'''','''''')), ncn_list, 'UniformOutput', false), ', ');
    if is_compositional, comp_arg = 'on'; else, comp_arg = 'off'; end

    L{end+1} = sprintf('%% Time series: %d series over %s', n_ts, tcn);
    L{end+1} = sprintf('de_timeseries(T, ''%s'', {%s}, ''Compositional'', ''%s'', ''TitlePrefix'', ''%s'');', ...
        tcn_sq, lbl_items, comp_arg, fig_prefix);
    L{end+1} = '';
    end  % n_ug >= 2
end

if isempty(L)
    code = '% No plottable numeric columns found.';
else
    code = strjoin(L, newline);
end
end


% ── cg_cat_association_code ─────────────────────────────────────────────────
function lines = cg_cat_association_code(T, prof)
%CG_CAT_ASSOCIATION_CODE  Recipe lines for categorical association figures.
%   Returns one line per figure: first the V-matrix, then one line per pair.
lines = {};
cat_mask = (prof.type == "categorical" | prof.type == "logical") & ~prof.skip;
cat_idx  = find(cat_mask);
if numel(cat_idx) < 2, return; end
names = prof.name(cat_idx);
nc    = numel(cat_idx);
p         = de__cat_assoc_params();
V_THRESH  = p.VThresh;
MAX_PAIRS = p.MaxPairs;
pairs = zeros(nc*(nc-1)/2, 3);
np = 0;
for i = 1:nc
    for j = i+1:nc
        v = de_cramer_v(T.(names{i}), T.(names{j}));
        if v >= V_THRESH
            np = np + 1;
            pairs(np,:) = [i, j, v];
        end
    end
end
pairs = pairs(1:np,:);
out = cell(1 + MAX_PAIRS, 1);
nl  = 1;
out{nl} = 'de_plot_cat_association(T, prof, Figure="vmatrix");';
if ~isempty(pairs)
    [~, ord] = sort(pairs(:,3), 'descend');
    pairs = pairs(ord(1:min(MAX_PAIRS,end)), :);
    for k = 1:size(pairs,1)
        ni = pairs(k,1); nj = pairs(k,2);
        a = T.(names{ni}); b = T.(names{nj});
        if ~iscategorical(a), a = categorical(a); end
        if ~iscategorical(b), b = categorical(b); end
        nu_i = numel(categories(removecats(a)));
        nu_j = numel(categories(removecats(b)));
        if nu_i <= nu_j
            col_grp = names{ni}; col_val = names{nj}; ng_pair = nu_i;
        else
            col_grp = names{nj}; col_val = names{ni}; ng_pair = nu_j;
        end
        switch de_cat_routing(ng_pair)
            case 'pareto',  fn = 'de_pareto_multiples';
            case 'stacked', fn = 'de_stacked_bars';
            otherwise,      fn = 'de_cond_heatmap';
        end
        nl = nl + 1;
        out{nl} = sprintf('%s(T, "%s", "%s");  %% V=%.2f', fn, col_grp, col_val, pairs(k,3));
    end
end
lines = out(1:nl);
end


% ── cg_state_choropleth_code ────────────────────────────────────────────────
function code = cg_state_choropleth_code(prof, families)
%CG_STATE_CHOROPLETH_CODE  Return recipe code for state choropleth figures.
if nargin < 2, families = {}; end
code = '';
cat_all = find(prof.type == "categorical" & ~prof.skip);
geo_idx = [];
for ci = cat_all(:)'
    if isfield(prof, 'geo_grid') && numel(prof.geo_grid) >= ci && ...
            strcmp(prof.geo_grid{ci}, 'us-states')
        geo_idx = ci; break;
    end
end
if isempty(geo_idx), return; end

catname = prof.name{geo_idx};
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
[time_idx, ~] = de_find_time_axis(prof);
num_idxs = find(prof.type == "numeric" & ~prof.skip);
num_idxs = se_filter_choro_cols(num_idxs, prof, families);
L = {};

if ~isempty(wide_yr_idxs)
    [~, yr_ord] = sort(wide_yr_vals);
    yr_names_s = prof.name(wide_yr_idxs(yr_ord));
    yr_cell = strjoin(cellfun(@(s) sprintf('''%s''', s), yr_names_s, 'UniformOutput', false), ', ');

    L{end+1} = sprintf('%% Choropleth: %s (wide years → long)', catname);
    L{end+1} = sprintf('yr_ch = {%s};', yr_cell);
    L{end+1} = 'T_long_ch = de_pivot_wide_years(T, yr_ch);';
    L{end+1} = sprintf('de_statebins(T_long_ch, ''StateCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''Title'',''Choropleth: %s'');', catname, catname);
    L{end+1} = '';
else
    num_plot = num_idxs(~ismember(num_idxs, [geo_idx, time_idx]));
    sub = cell(1, 2*numel(num_plot));
    for j = 1:numel(num_plot)
        ncn = prof.name{num_plot(j)};
        lca = se_logcolor_arg(prof, num_plot(j));
        if isempty(time_idx)
            sub{2*j-1} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''ColorCol'',''%s'', ''Title'',''Choropleth: %s''%s);', catname, ncn, ncn, lca);
        else
            tcn = prof.name{time_idx};
            sub{2*j-1} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''ColorCol'',''%s'', ''TimeCol'',''%s'', ''Title'',''Choropleth: %s''%s);', catname, ncn, tcn, ncn, lca);
        end
        sub{2*j} = '';
    end
    L = [L, sub];
end

if isempty(L), return; end
code = strjoin(L, newline);
end


% ── cg_country_choropleth_code ───────────────────────────────────────────────
function code = cg_country_choropleth_code(prof, families)
%CG_COUNTRY_CHOROPLETH_CODE  Return recipe code for world choropleth figures.
if nargin < 2, families = {}; end
code = '';
cat_all = find(prof.type == "categorical" & ~prof.skip);
geo_idx = [];
for ci = cat_all(:)'
    if isfield(prof, 'geo_grid') && numel(prof.geo_grid) >= ci && ...
            strcmp(prof.geo_grid{ci}, 'world')
        geo_idx = ci; break;
    end
end
if isempty(geo_idx), return; end

catname = prof.name{geo_idx};
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
[time_idx, ~] = de_find_time_axis(prof);
num_idxs = find(prof.type == "numeric" & ~prof.skip);
num_idxs = se_filter_choro_cols(num_idxs, prof, families);
L = {};

if ~isempty(wide_yr_idxs)
    [~, yr_ord] = sort(wide_yr_vals);
    yr_names_s = prof.name(wide_yr_idxs(yr_ord));
    yr_cell = strjoin(cellfun(@(s) sprintf('''%s''', s), yr_names_s, 'UniformOutput', false), ', ');

    L{end+1} = sprintf('%% World choropleth: %s (wide years → long)', catname);
    L{end+1} = sprintf('yr_co = {%s};', yr_cell);
    L{end+1} = 'T_long_co = de_pivot_wide_years(T, yr_co);';
    L{end+1} = sprintf('de_countrybins(T_long_co, ''CountryCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''Title'',''World choropleth: %s'');', catname, catname);
    L{end+1} = '';
else
    num_plot = num_idxs(~ismember(num_idxs, [geo_idx, time_idx]));
    sub = cell(1, 2*numel(num_plot));
    for j = 1:numel(num_plot)
        ncn = prof.name{num_plot(j)};
        lca = se_logcolor_arg(prof, num_plot(j));
        if isempty(time_idx)
            sub{2*j-1} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''ColorCol'',''%s'', ''Title'',''World choropleth: %s''%s);', catname, ncn, ncn, lca);
        else
            tcn = prof.name{time_idx};
            sub{2*j-1} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''ColorCol'',''%s'', ''TimeCol'',''%s'', ''Title'',''World choropleth: %s''%s);', catname, ncn, tcn, ncn, lca);
        end
        sub{2*j} = '';
    end
    L = [L, sub];
end

if isempty(L), return; end
code = strjoin(L, newline);
end


% ── cg_geo_multicategorical_code ────────────────────────────────────────────
function code = cg_geo_multicategorical_code(T, prof)
%CG_GEO_MULTICATEGORICAL_CODE  Recipe code for geo x categorical heatmap figures.
code = '';
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
if isempty(wide_yr_idxs), return; end

cat_all = find(prof.type == "categorical" & ~prof.skip);
if numel(cat_all) < 2, return; end

if isfield(prof, 'geo_grid')
    geo_cats = cat_all(arrayfun(@(ci) numel(prof.geo_grid) >= ci && ~isempty(prof.geo_grid{ci}), cat_all));
else
    geo_cats = [];
end
other_cats = cat_all(~ismember(cat_all, geo_cats));
if isempty(geo_cats) || isempty(other_cats), return; end

TOTAL_WORDS = {'total','totals','grand total','all totals'};
[~, yr_ord] = sort(wide_yr_vals);
yr_names_s = prof.name(wide_yr_idxs(yr_ord));
yr_cell = strjoin(cellfun(@(s) sprintf('''%s''',s), yr_names_s, 'UniformOutput',false), ', ');

% 4 header lines + up to 4 lines per geo×cat pair
L = cell(1, 4 + 4*numel(geo_cats)*numel(other_cats));
li = 0;
li = li+1; L{li} = '%% Geo x categorical heatmap';
li = li+1; L{li} = sprintf('yr_gm = {%s};', yr_cell);
li = li+1; L{li} = 'T_long_gm = de_pivot_wide_years(T, yr_gm);';
li = li+1; L{li} = '';

n_pairs = 0;
for gi = 1:numel(geo_cats)
    geo_idx      = geo_cats(gi);
    geo_name     = prof.name{geo_idx};
    geo_grid_name = prof.geo_grid{geo_idx};
    is_states_geo = strcmp(geo_grid_name, 'us-states');

    for oi = 1:numel(other_cats)
        cat_idx  = other_cats(oi);
        cat_name = prof.name{cat_idx};
        n_geo    = prof.nunique(geo_idx);
        n_other  = prof.nunique(cat_idx);
        ratio    = height(T) / (n_geo * n_other);
        if ratio < 0.5 || ratio > 1.5, continue; end

        % Top-K non-total levels
        cat_col = T.(cat_name);
        cat_levs = cellstr(categories(cat_col));
        cnt_levs = countcats(cat_col);
        is_tot   = cellfun(@(lv) any(strcmpi(lv, TOTAL_WORDS)), cat_levs);
        cat_levs = cat_levs(~is_tot);
        cnt_levs = cnt_levs(~is_tot);
        if isempty(cat_levs), continue; end
        [~, ord] = sort(cnt_levs,'descend');
        K = min(5, numel(cat_levs));
        top_levs = cat_levs(ord(1:K));

        levs_cell = strjoin(cellfun(@(s) sprintf('''%s''',strrep(s,'''','''''')), top_levs, 'UniformOutput',false), ', ');
        title_str = strrep(sprintf('%s x %s: Value by category over time', geo_name, cat_name), '''', '''''');

        li = li+1; L{li} = sprintf('top_gm = {%s};', levs_cell);
        li = li+1; L{li} = sprintf('T_filt_gm = T_long_gm(ismember(string(T_long_gm.%s), string(top_gm)), :);', cat_name);
        if is_states_geo
            li = li+1; L{li} = sprintf('de_statebins(T_filt_gm, ''StateCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''heatmap_cat'', ''CatCol'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, cat_name, K, title_str);
        elseif strcmp(geo_grid_name, 'world')
            li = li+1; L{li} = sprintf('de_countrybins(T_filt_gm, ''CountryCol'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''heatmap_cat'', ''CatCol'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, cat_name, K, title_str);
        else
            li = li+1; L{li} = sprintf('de_geobins(T_filt_gm, ''GeoCol'',''%s'', ''Grid'',''%s'', ''ColorCol'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''heatmap_cat'', ''CatCol'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, geo_grid_name, cat_name, K, title_str);
        end
        li = li+1; L{li} = '';
        n_pairs = n_pairs + 1;
    end
end
L = L(1:li);

if n_pairs == 0
    code = ''; return;
end
code = strjoin(L, newline);
end


% ── cg_geoscatter_code ───────────────────────────────────────────────────────
function code = cg_geoscatter_code(T, prof)
%CG_GEOSCATTER_CODE  Recipe code for a lat/lon point map (tabular data).
%   Colors points by the first numeric data column, sizes by the second (if any).
%   Skipped for NetCDF spatial grids (those get their own de_geoscatter recipe).
code = '';
if isfield(prof, 'nc_spatial_grid') && prof.nc_spatial_grid, return; end

LAT_NAMES = ["lat","latitude","lat_","latitude_dd","decimallatitude"];
LON_NAMES = ["lon","long","longitude","lon_","longitude_dd","decimallongitude"];
nl = lower(string(prof.name));
lat_i = find(ismember(nl, LAT_NAMES) & ~prof.skip, 1);
lon_i = find(ismember(nl, LON_NAMES) & ~prof.skip, 1);
if isempty(lat_i) || isempty(lon_i), return; end

lat = double(T.(prof.name{lat_i}));
lon = double(T.(prof.name{lon_i}));
if sum(~isnan(lat) & ~isnan(lon)) < 2, return; end

% Numeric data columns to encode (exclude the coordinates themselves)
num = find(prof.type == "numeric" & ~prof.skip);
num = num(~ismember(num, [lat_i, lon_i]));
if isempty(num), return; end

latn = prof.name{lat_i};
lonn = prof.name{lon_i};
ccol = prof.name{num(1)};
if numel(num) >= 2
    scol = prof.name{num(2)};
    code = sprintf(['de_geoscatter(T.%s, T.%s, T.%s, T.%s, ' ...
        'ColorLabel=''%s'', SizeLabel=''%s'', Title=''Map'');'], ...
        lonn, latn, ccol, scol, ccol, scol);
else
    code = sprintf(['de_geoscatter(T.%s, T.%s, T.%s, ones(height(T),1), ' ...
        'ColorLabel=''%s'', SizeLabel='''', Title=''Map'');'], ...
        lonn, latn, ccol, ccol);
end
end


% ── cg_corr_family_code ──────────────────────────────────────────────────────
function code = cg_corr_family_code(~, prof, families)
%CG_CORR_FAMILY_CODE  Recipe code for each correlated family.
%   The medoid/family/scale decisions are resolved here (generation time); the
%   emitted recipe is flat and editable: a member pairplot and, when a geo key
%   exists, a per-region value-ladder, both driven by one editable name list.
code = '';
if isempty(families), return; end

% Geo key (first non-skipped categorical with a recognised grid)
geo_idx = [];
if isfield(prof, 'geo_grid')
    for gk = find(prof.type == "categorical" & ~prof.skip)
        if numel(prof.geo_grid) >= gk && ~isempty(prof.geo_grid{gk})
            geo_idx = gk; break
        end
    end
end

L  = cell(1, 5 * numel(families));   % up to 5 lines per family
li = 0;
for fi = 1:numel(families)
    fam   = families{fi};                       % medoid-ordered column indices
    rep   = prof.name{fam(1)};
    names = prof.name(fam);
    cols_cell = strjoin(cellfun(@(s) sprintf('''%s''', strrep(s,'''','''''')), ...
        names, 'UniformOutput', false), ', ');

    li = li+1; L{li} = sprintf('%% Correlated family: %s (+%d correlated)', rep, numel(fam)-1);
    li = li+1; L{li} = sprintf('fam_cols = {%s};', cols_cell);
    li = li+1; L{li} = 'de_pairplot(T, prof, fam_cols);';
    if ~isempty(geo_idx)
        gname   = prof.name{geo_idx};
        grid_nm = prof.geo_grid{geo_idx};
        sk = max(prof.skewness(fam), [], 'omitnan');
        if isempty(sk) || isnan(sk), sk = 0; end
        if sk > 2, scale = 'log'; else, scale = 'linear'; end
        switch grid_nm
            case 'us-states'
                li = li+1; L{li} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''CellRenderer'',''value_ladder'', ''ValueCols'',fam_cols, ''Scale'',''%s'');', gname, scale);
            case 'world'
                li = li+1; L{li} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''CellRenderer'',''value_ladder'', ''ValueCols'',fam_cols, ''Scale'',''%s'');', gname, scale);
            otherwise
                li = li+1; L{li} = sprintf('de_geobins(T, ''GeoCol'',''%s'', ''Grid'',''%s'', ''CellRenderer'',''value_ladder'', ''ValueCols'',fam_cols, ''Scale'',''%s'');', gname, grid_nm, scale);
        end
    end
    li = li+1; L{li} = '';
end
code = strjoin(L(1:li), newline);
end


% ── cg_panel_code ────────────────────────────────────────────────────────────
function code = cg_panel_code(~, ~, panel)
%CG_PANEL_CODE  Recipe code for panel (wide-year) stacked-area and grouped
%   time-series figures.  Uses standalone de_* library functions.
code = '';
if ~isstruct(panel) || ~panel.is_panel, return; end
L = {};
L{end+1} = '% Panel: stacked-area and grouped time series';
L{end+1} = 'if prof.panel.is_panel';
L{end+1} = '    de_plot_panel_totals(T, prof, prof.panel);';
L{end+1} = '    sel_ = de_select_columns(T, prof, 8);';
L{end+1} = '    de_plot_categorical_drilldown(T, prof, sel_);';
L{end+1} = 'end';
code = strjoin(L, newline);
end


% ── se_assemble_recipe ───────────────────────────────────────────────────────
function [recipe_path, recipe_text] = se_assemble_recipe(filepath, T, prof, panel, options)
%SE_ASSEMBLE_RECIPE  Build a self-contained recipe, write to /tmp/, print, return.
%
%   Returns:
%     recipe_path — path to the saved .m file (for save_recipe())
%     recipe_text — the script as a string; caller should eval() this
%
%   For table input (empty filepath) the Load section is a placeholder comment.

assert(isstruct(panel), 'panel must be a struct');

if isempty(filepath)
    bname_safe = 'table_input';
else
    [~, bname, ~] = fileparts(filepath);
    bname_safe = regexprep(bname, '[^A-Za-z0-9_]', '_');
end
recipe_path = fullfile(tempdir, sprintf('dataexplorer_%s.m', bname_safe));

% Detect correlated families so they collapse to one representative everywhere.
families = de_corr_families(T, prof);

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
    sel = de_select_columns(T, prof, options.MaxVars, families);
end

load_code   = cg_load_code(filepath, T);
clean_code  = cg_clean_code();
plots_code  = cg_best_plots_code(T, prof, sel, prof.source_name);
choro_code         = cg_state_choropleth_code(prof, families);
country_code       = cg_country_choropleth_code(prof, families);
geo_multi_code     = cg_geo_multicategorical_code(T, prof);
geoscatter_code    = cg_geoscatter_code(T, prof);
family_code        = cg_corr_family_code(T, prof, families);
panel_code         = cg_panel_code(T, prof, panel);

header = sprintf([...
    '%% DataExplorer recipe — %s\n' ...
    '%% Generated %s\n' ...
    '%% Requires DataExplorer.m on the MATLAB path (for de_profile, de_overview, de_histogram).\n' ...
    '%% To save this script: save_recipe(''%s_recipe.m'')\n'], ...
    prof.source_name, datetime('now','Format','yyyy-MM-dd HH:mm'), ...
    regexprep(prof.source_name, '[^A-Za-z0-9]', '_'));

pairplot_code = sprintf('de_pairplot(T, prof, de_select_columns(T, prof, %d, fams));', ...
    options.MaxVars);

cat_assoc_lines = cg_cat_association_code(T, prof);

sections = { ...
    header, ...
    '%% === Load ===', load_code, '', ...
    '%% === Clean ===', clean_code, '', ...
    '%% === Overview ===', 'de_overview(T, prof);', '', ...
    '%% === Pairplot ===', 'fams = de_corr_families(T, prof);', pairplot_code, '', ...
    '%% === Best-of Plots ===', plots_code ...
};
if ~isempty(family_code)
    sections = [sections, {'', '%% === Correlated families ===', family_code}];
end
if ~isempty(cat_assoc_lines)
    sections = [sections, {'', '%% === Categorical Associations ==='}, cat_assoc_lines(:)'];
end
if ~isempty(choro_code)
    sections{end+1} = '';
    sections{end+1} = '%% === State Choropleth ===';
    sections{end+1} = choro_code;
end
if ~isempty(country_code)
    sections{end+1} = '';
    sections{end+1} = '%% === World Choropleth ===';
    sections{end+1} = country_code;
end
if ~isempty(geo_multi_code)
    sections{end+1} = '';
    sections{end+1} = '%% === Geo x Categorical ===';
    sections{end+1} = geo_multi_code;
end
if ~isempty(geoscatter_code)
    sections{end+1} = '';
    sections{end+1} = '%% === Geo Scatter (lat/lon) ===';
    sections{end+1} = geoscatter_code;
end
if ~isempty(panel_code)
    sections{end+1} = '';
    sections{end+1} = '%% === Panel (stacked area + grouped time series) ===';
    sections{end+1} = panel_code;
end

recipe_text = strjoin(sections, newline);

fid = fopen(recipe_path, 'w');
if fid == -1
    warning('DataExplorer:recipeFailed', ...
        'Could not write recipe to %s', recipe_path);
    recipe_path = '';
    return
end
fprintf(fid, '%s\n', recipe_text);
fclose(fid);
se_print_recipe(recipe_text, sprintf('%s_recipe.m', bname_safe));
end


% ── se_print_recipe ──────────────────────────────────────────────────────────
function se_print_recipe(code, save_name)
%SE_PRINT_RECIPE  Print recipe code to the console with a save command.
sep = repmat('═', 1, 64);
fprintf('\n  %s\n', sep);
fprintf('%s\n', code);
fprintf('  %s\n', sep);
fprintf('  save_recipe(''%s'')\n', save_name);
fprintf('  %s\n\n', sep);
end
function tf = se_is_compositional(Y_mean, T, prof)
% True when numeric time series form a compositional whole (parts sum to a
% near-constant total).  Two signals, in priority order:
%   1. Any categorical column has a "Total"-like level name.
%   2. Row sums of per-time-point means have CV < 0.05.
TOTAL_WORDS = {'total', 'totals', 'grand total', 'all totals'};
has_total_label = false;
cat_search = find(prof.type == "categorical" & ~prof.skip);
for kk = 1:numel(cat_search)
    lvls = cellstr(categories(T.(prof.name{cat_search(kk)})));
    if any(cellfun(@(lv) any(strcmpi(lv, TOTAL_WORDS)), lvls))
        has_total_label = true; break;
    end
end
Y_comp     = Y_mean(all(~isnan(Y_mean), 2), :);
all_nonneg = ~isempty(Y_comp) && size(Y_comp, 1) > 1 && size(Y_comp, 2) > 1 && all(Y_comp(:) >= 0);
if has_total_label && all_nonneg
    tf = true;
elseif all_nonneg
    row_sums = sum(Y_comp, 2);
    tf = std(row_sums) / max(abs(mean(row_sums)), eps) < 0.05;
else
    tf = false;
end
end
function zip_extract_entry(zippath, entry_name, outdir)
% Extract one named entry using the system unzip tool (-j junks paths).
    cmd = sprintf('unzip -j -d "%s" "%s" "%s"', outdir, zippath, entry_name);
    [status, out] = system(cmd);
    if status ~= 0
        error('DataExplorer:zipExtractFailed', ...
            'unzip failed for entry "%s":\n%s', entry_name, out);
    end
    % Some ZIP tools encode filenames with trailing whitespace.  unzip
    % preserves that in the output filename; rename to the clean version.
    [~, base, ext] = fileparts(entry_name);
    raw_base   = [base ext];
    clean_base = strtrim(raw_base);
    if ~strcmp(raw_base, clean_base)
        src = fullfile(outdir, raw_base);
        dst = fullfile(outdir, clean_base);
        if exist(src, 'file') && ~exist(dst, 'file')
            movefile(src, dst);
        end
    end
end


% ── zip_list_entries ──────────────────────────────────────────────────────────
function entries = zip_list_entries(filepath)
% Return struct array (.name, .bytes) for all non-directory ZIP entries.
% Uses system unzip -l — fast even for archives with 20 000+ entries.
[status, out] = system(sprintf('unzip -l "%s" 2>/dev/null', filepath));
entries = struct('name', {}, 'bytes', {});
if status ~= 0, return; end
lines = strsplit(out, newline);
% Data lines: leading spaces, byte count, date MM-DD-YY[YY], time HH:MM, name
pat = '^\s*(\d+)\s+\d{2}-\d{2}-\d{2,4}\s+\d{2}:\d{2}\s+(.+)$';
buf = repmat(struct('name', '', 'bytes', 0), 1, numel(lines));
ne = 0;
for k = 1:numel(lines)
    tok = regexp(lines{k}, pat, 'tokens', 'once');
    if isempty(tok), continue; end
    name = tok{2};
    if isempty(name), continue; end
    if name(end) == '/', continue; end  % skip directory entries
    ne = ne + 1;
    buf(ne).name  = name;
    buf(ne).bytes = str2double(tok{1});
end
entries = buf(1:ne);
end
