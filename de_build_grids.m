function result = de_build_grids(varargin)
%DE_BUILD_GRIDS  Lazy YAML→.mat compilation for tile-grid data.
%
%   grids = de_build_grids()
%     Return the full compiled struct array (one element per grid file).
%     Reads data/grids/grids.mat when up to date; recompiles from YAML otherwise.
%     Sanity-checks each file: duplicate codes, duplicate (row,col), duplicate aliases.
%
%   entries = de_build_grids(yaml_path)
%     Parse a single YAML file directly (bypasses cache). Returns cell array of structs.
%
%   Struct array fields:
%     name        — grid name string (e.g. 'us-states')
%     codes       — Nx1 cell of upper-cased primary codes
%     rows        — Nx1 double (0-indexed grid row)
%     cols        — Nx1 double (0-indexed grid column)
%     territory   — Nx1 logical (true = territory/dependency)
%     alias_keys  — Mx1 cell of upper-cased names/aliases
%     alias_vals  — Mx1 cell of corresponding primary codes

if nargin > 0
    result = dg_parse_yaml(char(string(varargin{1})));
    return
end

persistent CACHE
if ~isempty(CACHE)
    result = CACHE;
    return
end

grids_dir = fullfile(fileparts(mfilename('fullpath')), 'data', 'grids');
mat_path  = fullfile(grids_dir, 'grids.mat');
yaml_list = dir(fullfile(grids_dir, '*.yaml'));

if isempty(yaml_list)
    result = dg_empty_struct(0);
    return
end

% Use cached .mat when newer than every YAML file
if exist(mat_path, 'file')
    mat_d = dir(mat_path);
    if mat_d.datenum >= max([yaml_list.datenum])
        s = load(mat_path, 'grids');
        CACHE  = s.grids;
        result = CACHE;
        return
    end
end

% Compile from YAML
grids = dg_empty_struct(numel(yaml_list));
n_ok  = 0;
for fi = 1:numel(yaml_list)
    fpath = fullfile(yaml_list(fi).folder, yaml_list(fi).name);
    [~, gname] = fileparts(yaml_list(fi).name);
    try
        entries = dg_parse_yaml(fpath);
    catch ME
        fprintf('  ⚠ de_build_grids: skipping %s — %s\n', yaml_list(fi).name, ME.message);
        continue
    end
    if isempty(entries), continue; end

    n      = numel(entries);
    codes  = cell(n, 1);
    rows   = zeros(n, 1);
    cols   = zeros(n, 1);
    terr   = false(n, 1);
    a_keys = {};
    a_vals = {};

    for i = 1:n
        e        = entries{i};
        codes{i} = upper(strtrim(char(e.code)));
        rows(i)  = double(e.row);
        cols(i)  = double(e.col);
        if isfield(e, 'territory') && ~isempty(e.territory)
            terr(i) = logical(e.territory);
        end
        if isfield(e, 'names') && ~isempty(e.names)
            nms = e.names;
            if ischar(nms) || isstring(nms), nms = {char(nms)}; end
            for ni = 1:numel(nms)
                k = upper(strtrim(char(nms{ni})));
                if strlength(k) > 0
                    a_keys{end+1} = k; %#ok<AGROW>
                    a_vals{end+1} = codes{i}; %#ok<AGROW>
                end
            end
        end
    end

    dg_check(gname, codes, rows, cols, a_keys);

    n_ok = n_ok + 1;
    grids(n_ok).name       = gname;
    grids(n_ok).codes      = codes;
    grids(n_ok).rows       = rows;
    grids(n_ok).cols       = cols;
    grids(n_ok).territory  = terr;
    grids(n_ok).alias_keys = a_keys(:);
    grids(n_ok).alias_vals = a_vals(:);
end
grids = grids(1:n_ok);

try
    save(mat_path, 'grids');
    fprintf('  de_build_grids: compiled %d grid(s).\n', n_ok);
catch
    % read-only install — keep in-process cache only
end
CACHE  = grids;
result = CACHE;
end


%% ── dg_check ─────────────────────────────────────────────────────────────────
function dg_check(name, codes, rows, cols, alias_keys)
[u, ~, ic] = unique(codes);
if numel(u) < numel(codes)
    dups = u(accumarray(ic, 1) > 1);
    fprintf('  ⚠ %s: duplicate code(s): %s\n', name, strjoin(dups, ', '));
end
[~, ~, ip] = unique([rows, cols], 'rows');
if numel(unique(ip)) < numel(rows)
    fprintf('  ⚠ %s: %d duplicate (row,col) position(s)\n', ...
        name, numel(rows) - numel(unique(ip)));
end
if ~isempty(alias_keys)
    [u2, ~, ik] = unique(alias_keys);
    if numel(u2) < numel(alias_keys)
        dups2 = u2(accumarray(ik, 1) > 1);
        fprintf('  ⚠ %s: duplicate alias(es): %s\n', name, ...
            strjoin(dups2(1:min(5, end)), ', '));
    end
end
end


%% ── dg_empty_struct ──────────────────────────────────────────────────────────
function s = dg_empty_struct(n)
proto = struct('name', '', 'codes', {{}}, 'rows', [], 'cols', [], ...
               'territory', [], 'alias_keys', {{}}, 'alias_vals', {{}});
if n == 0
    s = proto(false(0, 1));
else
    s = repmat(proto, n, 1);
end
end


%% ── dg_parse_yaml ────────────────────────────────────────────────────────────
function entries = dg_parse_yaml(fpath)
%DG_PARSE_YAML  Parse grid YAML subset: a top-level sequence of mappings.
raw      = fileread(fpath);
lines    = regexp(raw, '\r?\n', 'split');
entries  = {};
cur      = struct();
in_entry = false;

for li = 1:numel(lines)
    ln       = lines{li};
    stripped = strtrim(ln);
    if isempty(stripped) || stripped(1) == '#', continue; end

    if strncmp(ln, '- ', 2) || strcmp(stripped, '-')
        if in_entry && isfield(cur, 'code')
            entries{end+1} = cur; %#ok<AGROW>
        end
        cur      = struct();
        in_entry = true;
        ln_kv    = strtrim(ln(3:end));
    else
        ln_kv = stripped;
    end

    if isempty(ln_kv) || ln_kv(1) == '#', continue; end

    ci = strfind(ln_kv, ':');
    if isempty(ci), continue; end
    key     = strtrim(ln_kv(1:ci(1)-1));
    val_str = strtrim(ln_kv(ci(1)+1:end));
    if isempty(key), continue; end

    cur.(matlab.lang.makeValidName(key)) = dg_parse_value(val_str);
end

if in_entry && isfield(cur, 'code')
    entries{end+1} = cur;
end
end


%% ── dg_parse_value ───────────────────────────────────────────────────────────
function val = dg_parse_value(s)
s = strtrim(s);
if isempty(s), val = ''; return; end

if s(1) == '['
    inner = s(2:end);
    if ~isempty(inner) && inner(end) == ']', inner = inner(1:end-1); end
    parts = dg_split_csv(inner);
    val   = cellfun(@dg_parse_scalar, parts, 'UniformOutput', false);
    return
end
val = dg_parse_scalar(s);
end


%% ── dg_parse_scalar ──────────────────────────────────────────────────────────
function val = dg_parse_scalar(s)
s = strtrim(s);
if isempty(s), val = ''; return; end

if s(1) == '"'
    inner = s(2:end);
    if ~isempty(inner) && inner(end) == '"', inner = inner(1:end-1); end
    val = strrep(strrep(inner, '\\"', '"'), '\\', '\');
    return
end
if s(1) == ''''
    inner = s(2:end);
    if ~isempty(inner) && inner(end) == '''', inner = inner(1:end-1); end
    val = strrep(inner, '''''', '''');
    return
end
if strcmpi(s, 'true'),  val = true;  return; end
if strcmpi(s, 'false'), val = false; return; end
n = str2double(s);
if ~isnan(n), val = n; return; end
val = s;
end


%% ── dg_split_csv ─────────────────────────────────────────────────────────────
function parts = dg_split_csv(s)
%DG_SPLIT_CSV  Split CSV respecting quoted strings.
parts     = {};
n         = numel(s);
cur_start = 1;
in_dq     = false;
in_sq     = false;

for i = 1:n
    c = s(i);
    if c == '"'  && ~in_sq, in_dq = ~in_dq; end
    if c == '''' && ~in_dq, in_sq = ~in_sq; end
    if c == ',' && ~in_dq && ~in_sq
        parts{end+1} = strtrim(s(cur_start:i-1)); %#ok<AGROW>
        cur_start = i + 1;
    end
end
parts{end+1} = strtrim(s(cur_start:end));
end
