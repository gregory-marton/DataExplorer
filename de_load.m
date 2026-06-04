function [T, prof] = de_load(filepath, options)
%DE_LOAD  Load a tabular file, optionally sample it, and profile it.
%
%   T          = de_load('data.csv')
%   T          = de_load('data.xlsx', Sheet='Data')
%   T          = de_load('data.xlsx', Sheet=7)
%   [T, prof]  = de_load('bigfile.csv', MaxRows=50000)
%   [T, prof]  = de_load('Prod_dataset.xlsx', Sheet='Data', MaxRows=10000)
%
%   For text files (CSV/TSV/TXT) with MaxRows set, uses de_reservoir_sample so
%   every row has equal probability regardless of file size.
%   For Excel with MaxRows set, loads the sheet first then draws a uniform
%   random subsample (Excel cannot be streamed).
%
%   ZIP archives are opened directly when they contain exactly one data file.
%   When several are present de_load does NOT guess — it errors with the list of
%   candidates (the same information the interactive loader shows) so you can add
%   InnerFile="…" to the call and re-run:
%
%   T = de_load('annual_aqi_by_county_2025.zip')              % single file → opens it
%   T = de_load('multi.zip', InnerFile='the_one_i_want.csv')  % pick from several
%
%   Name-value options
%   ──────────────────
%   Sheet                Sheet name (string) or 1-based index (integer) for xlsx (default: first sheet)
%   InnerFile            Which file to read from a multi-file ZIP (default: "" → must be unambiguous)
%   VariableNamesRange   Header cell range, e.g. 'A1' (xlsx, default: auto-detect)
%   DataRange            Data start cell, e.g. 'A2' (xlsx, default: auto-detect)
%   MaxRows              Row budget. Inf = load everything (default).

arguments
    filepath (1,1) string
    options.Sheet               = ""
    options.InnerFile           (1,1) string = ""
    options.VariableNamesRange  (1,1) string = ""
    options.DataRange           (1,1) string = ""
    options.MaxRows             (1,1) double = Inf
end

% ZIP: resolve to a single inner data file (or fail with the candidate list).
[~, ~, ext0] = fileparts(filepath);
if lower(string(ext0)) == ".zip"
    filepath = de_load_pick_zip_member(filepath, options.InnerFile);
end

[~, ~, ext] = fileparts(filepath);
is_excel = ismember(lower(string(ext)), [".xlsx", ".xls", ".xlsm", ".xlsb"]);

if is_excel
    io_args = {};
    if strlength(options.VariableNamesRange) > 0
        io_args = [io_args, {'VariableNamesRange', char(options.VariableNamesRange)}];
    end
    if strlength(options.DataRange) > 0
        io_args = [io_args, {'DataRange', char(options.DataRange)}];
    end
    sheet_val = options.Sheet;
    sheet_given = (isnumeric(sheet_val) && isscalar(sheet_val) && sheet_val > 0) || ...
                  (~isnumeric(sheet_val) && strlength(string(sheet_val)) > 0);
    if sheet_given
        io_args = [io_args, {'Sheet', sheet_val}];
    end
    io = detectImportOptions(filepath, io_args{:});
    io.MissingRule = 'fill';
    T = readtable(filepath, io);
    if isfinite(options.MaxRows) && height(T) > options.MaxRows
        n_total = height(T);
        idx     = sort(randperm(n_total, options.MaxRows));
        T       = T(idx, :);
        fprintf('  de_load: sampled %d of %d rows (uniform random).\n', ...
            options.MaxRows, n_total);
    end
else
    if isfinite(options.MaxRows)
        T = de_reservoir_sample(filepath, options.MaxRows);
    else
        T = readtable(filepath, 'TextType', 'string');
    end
end

[T, prof] = de_profile(T);
end


function inner_path = de_load_pick_zip_member(zip_path, inner_file)
%DE_LOAD_PICK_ZIP_MEMBER  Resolve a single data file inside a ZIP, or error with
%   the candidate list so the caller can re-run with InnerFile set.  Non-
%   interactive by design (see de_load).  (Provisional: when DataExplorer's
%   interactive loader is unified into de_load, this becomes the Interactive=false
%   branch of one shared zip handler.)
ok_exts = [".csv", ".tsv", ".txt", ".xlsx", ".xls", ".asc"];

tmpdir    = tempname;
mkdir(tmpdir);
extracted = string(unzip(char(zip_path), tmpdir));   % extracts all; returns full paths
extracted = extracted(:);

% Keep data-file candidates; drop macOS resource forks (__MACOSX/._*).
keep = false(numel(extracted), 1);
for k = 1:numel(extracted)
    [~, nm, e] = fileparts(extracted(k));
    keep(k) = ~contains(extracted(k), "__MACOSX") ...
        && ~startsWith(string(nm), "._") ...
        && ismember(lower(string(e)), ok_exts);
end
cand = extracted(keep);

if isempty(cand)
    error('de_load:noDataFileInZip', ...
        'No data file (%s) found inside %s.', strjoin(ok_exts, ', '), zip_path);
end

names = strings(numel(cand), 1);
for k = 1:numel(cand)
    [~, nm, e] = fileparts(cand(k));
    names(k) = strtrim(string(nm) + string(e));
end

if inner_file ~= ""
    idx = find(strcmpi(names, strtrim(inner_file)), 1);
    if isempty(idx)
        error('de_load:innerFileNotFound', ...
            'InnerFile "%s" not found in %s. Available: %s', ...
            inner_file, zip_path, strjoin(names, ', '));
    end
    inner_path = cand(idx);
    return
end

if isscalar(cand)
    inner_path = cand(1);
    return
end

% Several candidates, no InnerFile → fail with the listing (never guess).
bytes = zeros(numel(cand), 1);
for k = 1:numel(cand)
    d = dir(cand(k));
    if ~isempty(d), bytes(k) = d(1).bytes; end
end
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
    zip_path, numel(cand), strjoin(lines, newline), zip_path, names(ord(1)));
end
