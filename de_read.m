function T = de_read(filepath, options)
%DE_READ  Load a tabular file (CSV/TSV/TXT/XLSX/ZIP) into a raw (unprofiled) table.
%   The shared loader used by both DataExplorer and de_load.  NetCDF is handled
%   separately by DataExplorer (its multi-variable orchestration lives above this).
%
%   options is a struct with the same fields DataExplorer/de_load use:
%   AutoSelect, Sheet, InnerFile, MaxRows, VariableNamesRange, DataRange.

if ~isfile(filepath)
    error('DataExplorer:fileNotFound', ...
        'File not found: %s\n(current folder: %s)', filepath, pwd);
end

[~, basename, ext] = fileparts(filepath);
ext = string(lower(ext));
fprintf('\n  Loading: %s%s\n', basename, ext);

%  ZIP → unzip to temp, recurse
if ext == ".zip"
    T = de_read_from_zip(filepath, options);
    return
end

%  Excel
if ismember(ext, [".xlsx", ".xls", ".xlsm"])
    T = de_read_excel(filepath, options);
    return
end

%  Text (CSV / TSV / TXT / DAT)
T = de_read_text(filepath, options);
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = de_read_from_zip(filepath, options)
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

    T = de_read(fullfile(files(choice_idx).folder, files(choice_idx).name), options);
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
function T = de_read_excel(filepath, options)
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
    T = de__fix_names(T, filepath, '.xlsx', sheetname);
    if ~isequal(names_before, T.Properties.VariableNames)
        T.Properties.UserData.explicit_header = true;
    end
    T = de__sample(T, options.MaxRows);
end

% ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
function T = de_read_text(filepath, options)
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
        T = de__record_sampled(T, height(T));
    else
        opts = detectImportOptions(filepath, 'FileType', 'text', 'Delimiter', delim);
        opts.MissingRule = 'fill';
        T = readtable(filepath, opts);
        n_before = height(T);
        T = de__sample(T, options.MaxRows);
        if height(T) < n_before
            T = de__record_sampled(T, height(T), n_before);
        end
    end

    T = de__fix_names(T, filepath, '.csv', []);
end
