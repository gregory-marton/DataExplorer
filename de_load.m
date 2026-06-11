function [T, prof] = de_load(filepath, options)
%DE_LOAD  Load a tabular file (CSV/TSV/TXT/XLSX/ZIP), optionally sample, profile.
%   The single loader shared by DataExplorer and direct/student use.  NetCDF is
%   handled by DataExplorer (its multi-variable orchestration sits above this).
%
%   T          = de_load('data.csv')
%   T          = de_load('data.xlsx', Sheet='Data')      % name or 1-based index
%   [T, prof]  = de_load('bigfile.csv', MaxRows=50000)
%   T          = de_load('annual_aqi_by_county_2025.zip')      % single file → opens it
%   T          = de_load('multi.zip', InnerFile='the_one.csv') % pick from several
%
%   Ambiguity (multi-file ZIP, multi-sheet workbook) resolves three ways:
%     Interactive=false (default)  → error listing the candidates + the option to
%                                    add (InnerFile=…/Sheet=…) and re-run.
%     Interactive=true             → prompt (what DataExplorer uses).
%     AutoSelect=true              → pick the default (largest) without asking.
%
%   Name-value options
%   ──────────────────
%   Sheet                Sheet name (string) or 1-based index (integer) for xlsx
%   InnerFile            Which file to read from a multi-file ZIP
%   AutoSelect           Pick the default on ambiguity without prompting
%   Interactive          Prompt on ambiguity (default false)
%   MissingStrings       Extra strings to recode as missing (passed to de_profile)
%   VariableNamesRange   Header cell range, e.g. 'A1' (xlsx only)
%   DataRange            Data start cell, e.g. 'A2' (xlsx only)
%   VariableNamesLine    Header line number for delimited TEXT, 1-based (e.g. 8).
%                        Also auto-detected when preamble rows sit above the header.
%   DataLines            [first last] data line range for text, e.g. [9 Inf]
%   MaxRows              Row budget. Inf = load everything (default).

arguments
    filepath (1,1) string
    options.Sheet               = ""
    options.InnerFile           (1,1) string  = ""
    options.NCVariable          (1,1) string  = ""
    options.AutoSelect          (1,1) logical = false
    options.Interactive         (1,1) logical = false
    options.MissingStrings      (1,:) string  = string([])
    options.VariableNamesRange  (1,1) string  = ""
    options.DataRange           (1,1) string  = ""
    options.VariableNamesLine   (1,1) double  = NaN
    options.DataLines           (1,2) double  = [NaN NaN]
    options.MaxRows             (1,1) double {de__must_be_row_budget} = Inf
end

T = de_load_dispatch(filepath, options);

if isempty(options.MissingStrings)
    [T, prof] = de_profile(T);
else
    [T, prof] = de_profile(T, options.MissingStrings);
end
end


% ── de_load_dispatch ──────────────────────────────────────────────────────────
function T = de_load_dispatch(filepath, options)
%DE_LOAD_DISPATCH  Detect format and load a raw (unprofiled) table.
if ~isfile(filepath)
    error('DataExplorer:fileNotFound', ...
        'File not found: %s\n(current folder: %s)', filepath, pwd);
end

[~, basename, ext] = fileparts(filepath);
ext = string(lower(ext));
fprintf('\n  Loading: %s%s\n', basename, ext);
de_load_warn_options(ext, options);

if ext == ".zip"
    T = de_load_from_zip(filepath, options);
    return
end
if ismember(ext, [".xlsx", ".xls", ".xlsm"])
    T = de_load_excel(filepath, options);
    return
end
if ismember(ext, [".nc", ".nc4", ".netcdf"])
    T = de_load_netcdf(filepath, options);
    return
end
T = de_load_text(filepath, options);
end

% ── de_load_warn_options ──────────────────────────────────────────────────────
function de_load_warn_options(ext, options)
%DE_LOAD_WARN_OPTIONS  Warn about format-specific options the chosen format can't
%   use, instead of silently ignoring them.
is_xlsx = ismember(ext, [".xlsx", ".xls", ".xlsm"]);
is_zip  = ext == ".zip";
is_nc   = ismember(ext, [".nc", ".nc4", ".netcdf"]);
is_text = ~(is_xlsx || is_zip || is_nc);

names  = ["VariableNamesRange", "DataRange", "Sheet", "InnerFile", "NCVariable", ...
          "VariableNamesLine", "DataLines"];
isset  = [ strlength(options.VariableNamesRange) > 0, strlength(options.DataRange) > 0, ...
           strlength(string(options.Sheet)) > 0, strlength(options.InnerFile) > 0, ...
           strlength(options.NCVariable) > 0, ~isnan(options.VariableNamesLine), ...
           ~all(isnan(options.DataLines)) ];
usable = [ is_xlsx, is_xlsx, is_xlsx, is_zip, is_nc, is_text, is_text ];
ig = names(isset & ~usable);
if isempty(ig), return; end

if is_xlsx,    label = "Excel";
elseif is_zip, label = "ZIP";
elseif is_nc,  label = "NetCDF";
else,          label = "text/CSV";
end
hint = "";
if is_text && any(ismember(["VariableNamesRange", "DataRange"], ig))
    hint = " — for delimited text use VariableNamesLine / DataLines";
end
warning('DataExplorer:ignoredLoadOptions', ...
    'These options do not apply to a %s file and are ignored: %s%s', ...
    label, strjoin(cellstr(ig), ', '), hint);
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = de_load_from_zip(filepath, options)
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
    zip_entries   = de__zip_list(filepath);   % struct array: .name, .bytes

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
                    error('de_load:innerFileNotFound', ...
                        'InnerFile "%s" not found inside ZIP. Available: %s', ...
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

                default_k = shown_k(end);

                if options.AutoSelect
                    pick_idx = default_k;
                    fprintf('  AutoSelect: picking largest "%s"\n', names_s{default_k});
                elseif ~options.Interactive
                    de_load_zip_ambiguous_error(filepath, string(names_s), sizes_s);
                else
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
                    fprintf('  Enter number (default %d = %s),\n', ...
                        numel(shown_k), names_s{default_k});
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
                    de__zip_extract(filepath, cand(k).name, tmpdir);
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

        default_num = numel(shown);

        if options.AutoSelect
            choice_idx = shown(default_num);
            fprintf('  AutoSelect: picking default "%s"\n', files_sorted(choice_idx).name);
        elseif ~options.Interactive
            de_load_zip_ambiguous_error(filepath, string({files_sorted.name}), [files_sorted.bytes]);
        else
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
        end

        files = files_sorted;
    end

    T = de_load_dispatch(fullfile(files(choice_idx).folder, files(choice_idx).name), options);
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
function T = de_load_excel(filepath, options)
    sheets = sheetnames(filepath);

    % Sheet pinned by name or 1-based index?
    sheet_val   = options.Sheet;
    sheet_given = (isnumeric(sheet_val) && isscalar(sheet_val) && sheet_val > 0) || ...
                  (~isnumeric(sheet_val) && strlength(string(sheet_val)) > 0);

    if sheet_given
        if isnumeric(sheet_val)
            if sheet_val > numel(sheets)
                error('DataExplorer:sheetNotFound', ...
                    'Sheet index %d out of range (1–%d).', sheet_val, numel(sheets));
            end
            sheetname = sheets{sheet_val};
        else
            if ~ismember(string(sheet_val), sheets)
                error('DataExplorer:sheetNotFound', ...
                    'Sheet "%s" not found. Available: %s', ...
                    string(sheet_val), strjoin(sheets, ', '));
            end
            sheetname = char(string(sheet_val));
        end
    elseif isscalar(sheets)
        sheetname = sheets{1};
    else
        % Multiple sheets — count rows for a size-ranked listing.
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

        [~, ord] = sort(nrows, 'ascend');
        sheets_s = sheets(ord);
        nrows_s  = nrows(ord);
        ncols_s  = ncols(ord);
        default_num = numel(sheets_s);

        if options.AutoSelect
            sheetname = sheets_s{default_num};
            fprintf('  AutoSelect: picking largest sheet "%s"\n', sheetname);
        elseif ~options.Interactive
            lines = strings(numel(sheets_s), 1);
            for k = 1:numel(sheets_s)
                lines(k) = sprintf('  %s  (%d rows × %d columns)', ...
                    sheets_s{k}, nrows_s(k), ncols_s(k));
            end
            error('de_load:multipleSheets', ...
                ['%s has %d sheets; de_load will not guess. Re-run with Sheet set ' ...
                 'to one of:\n%s\ne.g.  de_load("%s", Sheet="%s")'], ...
                filepath, numel(sheets_s), strjoin(lines, newline), ...
                filepath, sheets_s{default_num});
        else
            fprintf('  Sheets found in workbook (sorted by row count):\n');
            for k = 1:numel(sheets_s)
                fprintf('    [%2d]  %-35s  %d rows × %d columns\n', ...
                    k, sheets_s{k}, nrows_s(k), ncols_s(k));
            end
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
    end

    fprintf('  Reading sheet "%s"…\n', sheetname);
    io_args = {'Sheet', sheetname};
    if strlength(options.VariableNamesRange) > 0
        io_args = [io_args, {'VariableNamesRange', char(options.VariableNamesRange)}];
    end
    if strlength(options.DataRange) > 0
        io_args = [io_args, {'DataRange', char(options.DataRange)}];
    end
    opts = detectImportOptions(filepath, io_args{:});
    opts.MissingRule = 'fill';
    T = readtable(filepath, opts, 'Sheet', sheetname);
    T.Properties.UserData = struct('sheet', sheetname, 'inner_file', '');
    names_before = T.Properties.VariableNames;
    T = de__fix_names(T, filepath, '.xlsx', sheetname);
    if ~isequal(names_before, T.Properties.VariableNames)
        T.Properties.UserData.explicit_header = true;
    end
    T = de__sample(T, options.MaxRows);
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = de_load_text(filepath, options)
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
    delims     = {',', '\t', ';', '|'};
    delims_raw = {',', char(9), ';', '|'};
    delim      = delims{delim_char};
    delim_raw  = delims_raw{delim_char};

    delim_names = {'comma-separated','tab-separated','semicolon-separated','pipe-separated'};
    fprintf('  Detected: %s\n', delim_names{delim_char});

    % An explicit VariableNamesLine wins.  Otherwise we may auto-guess a header
    % below preamble rows — but ONLY as a fallback, after a normal read comes back
    % with default Var1..VarN names (header not on row 1 and not auto-detected).
    hdr_line = options.VariableNamesLine;   % NaN if unset

    % Check file size — reservoir-sample big files, but only when the header is on
    % row 1 (the reservoir reader assumes that).
    LARGE_FILE_MB = 100;
    info = dir(filepath);
    file_mb = info.bytes / 1e6;

    if file_mb > LARGE_FILE_MB && isfinite(options.MaxRows) && isnan(hdr_line)
        fprintf('  ℹ Large file (%.0f MB) — using reservoir sampling to read %d rows.\n', ...
            file_mb, options.MaxRows);
        fprintf('    This avoids loading the full file into memory.\n');
        T = de_reservoir_sample(filepath, options.MaxRows, Verbose=true);
        T = de__record_sampled(T, height(T));
    else
        opts = detectImportOptions(filepath, 'FileType', 'text', 'Delimiter', delim);
        opts.MissingRule = 'fill';
        if ~isnan(hdr_line)
            opts.VariableNamesLine = hdr_line;
            if ~all(isnan(options.DataLines))
                opts.DataLines = options.DataLines;
            else
                opts.DataLines = [hdr_line + 1, Inf];
            end
        end
        T = readtable(filepath, opts);

        % Fallback only: a normal read produced Var1..VarN → the header probably
        % sits below preamble rows.  Guess an all-text header line and re-read.
        if isnan(hdr_line)
            nm = T.Properties.VariableNames;
            is_default = all(cellfun(@(s) ~isempty(regexp(s, '^Var\d+$', 'once')), nm));
            if is_default
                g = de__guess_header_line(filepath, delim_raw);
                if ~isnan(g) && g > 1
                    opts.VariableNamesLine = g;
                    opts.DataLines = [g + 1, Inf];
                    T = readtable(filepath, opts);
                    fprintf('  ✓ Header looks like line %d (skipping %d preamble row(s)).\n', g, g - 1);
                end
            end
        end

        n_before = height(T);
        T = de__sample(T, options.MaxRows);
        if height(T) < n_before
            T = de__record_sampled(T, height(T), n_before);
        end
    end

    T = de__fix_names(T, filepath, '.csv', []);
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function de_load_zip_ambiguous_error(zip_path, names, bytes)
%DE_LOAD_ZIP_AMBIGUOUS_ERROR  Error listing ZIP data files + the InnerFile hint.
[~, ord] = sort(bytes, 'descend');
lines = strings(numel(ord), 1);
for k = 1:numel(ord)
    b = bytes(ord(k));
    if b >= 1e6
        szs = sprintf('%.1f MB', b / 1e6);
    else
        szs = sprintf('%.0f KB', b / 1e3);
    end
    lines(k) = sprintf('  %s  (%s)', names(ord(k)), szs);
end
error('de_load:multipleFilesInZip', ...
    ['%s contains %d data files; de_load will not guess. Re-run with InnerFile ' ...
     'set to one of:\n%s\ne.g.  de_load("%s", InnerFile="%s")'], ...
    zip_path, numel(names), strjoin(lines, newline), zip_path, names(ord(1)));
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = de_load_netcdf(filepath, options)
%DE_LOAD_NETCDF  Load NetCDF into one table.  Data variables sharing a dimension
%   signature are conformable and combine into one long-format table (coordinate
%   columns + one column per variable) via de_stride_sample.  A file mixing
%   differently-shaped variables is resolved like a multi-sheet workbook:
%   NCVariable= picks one; AutoSelect picks the largest; otherwise the
%   non-interactive default errors with the variable list, or an interactive
%   prompt asks.
info = ncinfo(char(filepath));
dv   = de_load_nc_data_vars(info);
if isempty(dv)
    error('de_load:ncNoData', 'No data variables found in %s.', filepath);
end

% Dimension signature + element count per data variable.
sigs  = strings(1, numel(dv));
elems = zeros(1, numel(dv));
for k = 1:numel(dv)
    vi = find(strcmp({info.Variables.Name}, dv{k}), 1);
    dn = string({info.Variables(vi).Dimensions.Name});
    sigs(k)  = strjoin(sort(dn), '|');
    elems(k) = prod(double(info.Variables(vi).Size));
end

if strlength(options.NCVariable) > 0
    if ~ismember(char(options.NCVariable), dv)
        error('de_load:ncVarNotFound', ...
            'NetCDF variable "%s" not found. Available: %s', ...
            options.NCVariable, strjoin(dv, ', '));
    end
    sel = {char(options.NCVariable)};
else
    groups = unique(sigs, 'stable');
    if isscalar(groups)
        sel = dv;                                  % all conformable → combine all
    else
        [~, big] = max(elems);                     % largest variable's group
        big_grp  = dv(sigs == sigs(big));
        if options.AutoSelect
            sel = big_grp;
            fprintf('  AutoSelect: largest NetCDF group "%s" (%d variable(s))\n', ...
                strjoin(big_grp, ', '), numel(big_grp));
        elseif ~options.Interactive
            de_load_nc_ambiguous_error(filepath, dv, sigs, elems);
        else
            sel = de_load_nc_prompt(dv, sigs, elems);
        end
    end
end

% Combine the chosen variables into one table (identical striding → aligned rows).
T = de_stride_sample(filepath, Variable=string(sel{1}), MaxRows=options.MaxRows, Verbose=false);
for k = 2:numel(sel)
    vk = matlab.lang.makeValidName(sel{k});
    Tk = de_stride_sample(filepath, Variable=string(sel{k}), MaxRows=options.MaxRows, Verbose=false);
    if height(Tk) == height(T) && ismember(vk, Tk.Properties.VariableNames)
        T.(vk) = Tk.(vk);
    else
        fprintf('  ⚠ Skipping non-conformable variable "%s".\n', sel{k});
    end
end

ud = T.Properties.UserData;
if ~isstruct(ud), ud = struct('sheet', '', 'inner_file', ''); end
ud.nc_vars = sel;
T.Properties.UserData = ud;
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function data_vars = de_load_nc_data_vars(info)
%DE_LOAD_NC_DATA_VARS  Names of data (non-coordinate) variables in a NetCDF file.
%   A coordinate variable is one whose name matches a dimension name.
dim_per_var = cell(1, numel(info.Variables));
for k = 1:numel(info.Variables)
    d = info.Variables(k).Dimensions;
    if ~isempty(d), dim_per_var{k} = {d.Name}; end
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

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function de_load_nc_ambiguous_error(filepath, dv, sigs, elems)
%DE_LOAD_NC_AMBIGUOUS_ERROR  Error listing NetCDF variables + the NCVariable hint.
[~, ord] = sort(elems, 'descend');
lines = strings(numel(ord), 1);
for k = 1:numel(ord)
    lines(k) = sprintf('  %s  [%s]  (%d elems)', dv{ord(k)}, ...
        strrep(sigs(ord(k)), '|', char(215)), elems(ord(k)));
end
error('de_load:multipleNCGroups', ...
    ['%s mixes differently-shaped variables; de_load will not guess. Re-run with ' ...
     'NCVariable set to one of (or AutoSelect=true for the largest):\n%s\n' ...
     'e.g.  de_load("%s", NCVariable="%s")'], ...
    filepath, strjoin(lines, newline), filepath, dv{ord(1)});
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function sel = de_load_nc_prompt(dv, sigs, elems)
%DE_LOAD_NC_PROMPT  Ask which NetCDF variable to load; return its conformable group.
[~, ord] = sort(elems, 'ascend');
fprintf('  Variables in NetCDF file (sorted by size):\n');
for k = 1:numel(ord)
    fprintf('    [%2d]  %-24s  [%s]  (%d elems)\n', k, dv{ord(k)}, ...
        strrep(sigs(ord(k)), '|', char(215)), elems(ord(k)));
end
default_k = numel(ord);   % largest
fprintf('\n');
pick = '';
while isempty(pick)
    raw = input(sprintf('  Which variable? (number or name, Enter = %d = %s): ', ...
        default_k, dv{ord(default_k)}), 's');
    if isempty(raw)
        pick = dv{ord(default_k)};
    elseif all(ismember(raw, '0123456789'))
        n = str2double(raw);
        if n >= 1 && n <= numel(ord)
            pick = dv{ord(n)};
        else
            fprintf('  Please enter a number between 1 and %d.\n', numel(ord));
        end
    elseif ismember(raw, dv)
        pick = raw;
    else
        fprintf('  Variable "%s" not found. Options: %s\n', raw, strjoin(dv, ', '));
    end
end
pidx = find(strcmp(dv, pick), 1);
sel  = dv(sigs == sigs(pidx));
end
