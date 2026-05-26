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
%   Variable must have exactly 3 dimensions.  Use ncinfo() to inspect your file.
%
%   Usage
%   ─────
%   T = SampleNetCDF('climate.nc')                         % first data variable, 10 000 rows
%   T = SampleNetCDF('climate.nc', Variable='prcp')        % specific variable
%   T = SampleNetCDF('climate.nc', LatRange=[30 60])       % restrict latitude window
%   DataExplorer(SampleNetCDF('climate.nc', LonRange=[-100 -70]))   % chain into DataExplorer
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
