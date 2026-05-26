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

if ismember(ext_lc, [".nc", ".nc4", ".netcdf"])
    T = stride_netcdf(filepath, fname, ext_lc, options);
else
    T = stride_tabular(filepath, fname, ext_lc, options);
end
end


%% ── Tabular stride path ───────────────────────────────────────────────────────

function T = stride_tabular(filepath, fname, ext, options)

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
file_info  = dir(filepath);
file_bytes = file_info.bytes;
if n_nl > 1
    bytes_per_row = numel(probe) / n_nl;
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

    chunk_rows = global_row + (1:n_chunk);
    keep_mask  = mod(chunk_rows - 1, stride) == 0;
    global_row = global_row + n_chunk;

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
