function [fig, ax] = de_geobins(T, options)
%DE_GEOBINS  Tile-grid choropleth for any geographic or conceptual grid.
%   No Mapping Toolbox required.
%
%   Usage
%   ─────
%   de_geobins(T, 'GeoCol','State',   'ColorCol','Rate', 'Grid','us-states')
%   de_geobins(T, 'GeoCol','Country', 'ColorCol','GDP',  'Grid','world')
%   de_geobins(T, 'GeoCol','Prov',    'ColorCol','Val',  'Grid','ca-provinces')
%
%   Grid argument
%   ─────────────
%   String (no separator, no .json suffix)
%                  Named preset: loads data/grids/<name>.json relative to
%                  this file.  Drop any JSON there to add a new region.
%   String (.json or contains path separator)
%                  Direct file path.
%   Struct array   Fields: code (string/char), row, col (0-indexed integers).
%                  Optional: territory (logical) — excluded unless
%                  ShowTerritories=true.
%
%   JSON schema for data/grids/*.json
%   ──────────────────────────────────
%   [
%     {"code":"CA", "row":4, "col":1,
%      "names":["California","CALIFORNIA"],
%      "territory":false}
%   ]
%   "names" — all strings (endonyms, exonyms, abbreviations, historical
%             names) that should match to this tile.  Case-insensitive.
%   "territory" — optional boolean; tile hidden unless ShowTerritories=true.
%
%   Optional name-value arguments
%   ─────────────────────────────
%   GeoCol           Column of codes / names in T
%   ColorCol         Numeric column for tile fill
%   TimeCol          Time axis — activates slider
%   Title            Figure title
%   Colormap         Name or Nx3 matrix (default 'parula')
%   Grid             Grid specification (see above, default 'us-states')
%   ShowTerritories  Include territory tiles (default false)
%   Aliases          Nx2 cell {from,to} or containers.Map for normalization
%   MapLabel         Label shown in legend/title (default: Grid name)
%   FontSize         Tile font size (default 7)
%   CLim             Fix color axis [lo, hi]
%   CellRenderer     'color' (default) or 'heatmap_cat'
%   CatCol, TopK, SharedYLim, CatColors, XCol, YCol, SharedXLim
%                    Passed through to de_tilegrid
%
%   Returns
%   ───────
%   fig   Figure handle
%   ax    Axes handle

arguments
    T (:,:) table
    options.GeoCol           (1,1) string  = ""
    options.ColorCol         (1,1) string  = ""
    options.TimeCol          (1,1) string  = ""
    options.Title            (1,1) string  = ""
    options.Colormap                       = 'parula'
    options.Grid                           = 'us-states'
    options.ShowTerritories  (1,1) logical = false
    options.Aliases                        = []
    options.MapLabel         (1,1) string  = ""
    options.FontSize         (1,1) double  = 7
    options.CellRenderer     (1,1) string  = "color"
    options.CatCol           (1,1) string  = ""
    options.TopK             (1,1) double  = 5
    options.SharedYLim       (1,2) double  = [NaN NaN]
    options.CatColors                      = []
    options.XCol             (1,1) string  = ""
    options.YCol             (1,1) string  = ""
    options.SharedXLim       (1,2) double  = [NaN NaN]
    options.CLim             (1,2) double  = [NaN NaN]
end

fig = []; ax = [];

%% ── Validate ─────────────────────────────────────────────────────────────────
varnames    = string(T.Properties.VariableNames);
needs_color = options.CellRenderer == "color" || options.CellRenderer == "heatmap_cat";
if options.GeoCol == "" || ~ismember(options.GeoCol, varnames) || ...
   (needs_color && options.ColorCol == "")
    fprintf('  ℹ de_geobins: need GeoCol + ColorCol — nothing to plot.\n');
    return
end

%% ── Load / build grid ────────────────────────────────────────────────────────
[CODES, ROWS, COLS, NAMES_MAP] = gb_load_grid(options.Grid, options.ShowTerritories);
if isempty(CODES)
    fprintf('  ℹ de_geobins: no grid tiles — nothing to plot.\n');
    return
end
IS_OVERFLOW = false(numel(CODES), 1);

%% ── Build normalizer ─────────────────────────────────────────────────────────
% Priority: code identity first, then all names[] entries, then user aliases.
norm = containers.Map('KeyType','char','ValueType','char');
for i = 1:numel(CODES)
    k = char(upper(strtrim(CODES{i})));
    if ~isKey(norm, k), norm(k) = k; end
end
% All names in the grid (endonyms, exonyms, abbreviations, historical codes)
if ~isempty(NAMES_MAP)
    ks = keys(NAMES_MAP);
    for ki = 1:numel(ks)
        k = upper(strtrim(ks{ki}));
        if ~isKey(norm, k), norm(k) = NAMES_MAP(ks{ki}); end
    end
end
% User-supplied aliases (lowest priority)
if ~isempty(options.Aliases)
    if isa(options.Aliases, 'containers.Map')
        ks = keys(options.Aliases);
        for ki = 1:numel(ks)
            k = upper(strtrim(char(ks{ki})));
            if ~isKey(norm, k)
                norm(k) = upper(strtrim(char(options.Aliases(ks{ki}))));
            end
        end
    else
        al = options.Aliases;  % Nx2 cell
        for ki = 1:size(al,1)
            k = upper(strtrim(char(al{ki,1})));
            if ~isKey(norm, k), norm(k) = upper(strtrim(char(al{ki,2}))); end
        end
    end
end

%% ── Normalize GeoCol ─────────────────────────────────────────────────────────
raw_codes = upper(strtrim(string(T.(char(options.GeoCol)))));
normed    = raw_codes;
for ri = 1:numel(raw_codes)
    k = char(raw_codes(ri));
    if isKey(norm, k), normed(ri) = string(norm(k)); end
end

%% ── Detect overflow codes ────────────────────────────────────────────────────
grid_set  = containers.Map(CODES, true(numel(CODES), 1));
data_uniq = unique(normed);
data_uniq = data_uniq(strtrim(data_uniq) ~= "" & ~ismissing(data_uniq));
is_orph   = ~cellfun(@(c) isKey(grid_set, c), cellstr(data_uniq));
orphans   = cellstr(data_uniq(is_orph));
n_ov      = numel(orphans);
if n_ov > 0
    fprintf('  de_geobins: %d unrecognized code(s) → overflow row: %s\n', ...
        n_ov, strjoin(orphans, ', '));
    ov_cols = double(max(COLS)) + 1;
    ov_base = double(max(ROWS)) + 2;
    k_vec   = (0:n_ov-1);
    CODES(end+1:end+n_ov)       = orphans;
    ROWS(end+1:end+n_ov)        = ov_base + floor(k_vec / ov_cols);
    COLS(end+1:end+n_ov)        = mod(k_vec, ov_cols);
    IS_OVERFLOW(end+1:end+n_ov) = true(1, n_ov);
end

%% ── MapLabel default ─────────────────────────────────────────────────────────
map_label = options.MapLabel;
if map_label == ""
    gs = options.Grid;
    if ischar(gs) || isstring(gs)
        [~, gs_name] = fileparts(string(gs));
        map_label = gs_name;
    else
        map_label = "Regions";
    end
end

%% ── Assemble grid struct and delegate ────────────────────────────────────────
g.codes       = CODES;
g.rows        = ROWS;
g.cols        = COLS;
g.is_overflow = IS_OVERFLOW;

[fig, ax] = de_tilegrid(T, g, normed, ...
    'ColorCol',      options.ColorCol, ...
    'TimeCol',       options.TimeCol, ...
    'Title',         options.Title, ...
    'Colormap',      options.Colormap, ...
    'MapLabel',      char(map_label), ...
    'FontSize',      options.FontSize, ...
    'CellRenderer',  options.CellRenderer, ...
    'CatCol',        options.CatCol, ...
    'TopK',          options.TopK, ...
    'SharedYLim',    options.SharedYLim, ...
    'CatColors',     options.CatColors, ...
    'XCol',          options.XCol, ...
    'YCol',          options.YCol, ...
    'SharedXLim',    options.SharedXLim, ...
    'CLim',          options.CLim);

end % de_geobins


%% ── gb_load_grid ─────────────────────────────────────────────────────────────
function [CODES, ROWS, COLS, NAMES_MAP] = gb_load_grid(grid_spec, show_terr)
%GB_LOAD_GRID  Return (CODES, ROWS, COLS, NAMES_MAP) for a grid spec.
%   Named grids are resolved via de_build_grids() (YAML→.mat cache).
%   NAMES_MAP is a containers.Map from upper-cased name/alias → primary code.

CODES = {};  ROWS = [];  COLS = [];
NAMES_MAP = containers.Map('KeyType','char','ValueType','char');

if isstruct(grid_spec)
    % Caller-supplied struct array: code/row/col/territory/names fields
    for i = 1:numel(grid_spec)
        if ~show_terr && isfield(grid_spec, 'territory') && grid_spec(i).territory
            continue
        end
        CODES{end+1} = upper(strtrim(char(grid_spec(i).code))); %#ok<AGROW>
        ROWS(end+1)  = double(grid_spec(i).row);                %#ok<AGROW>
        COLS(end+1)  = double(grid_spec(i).col);                %#ok<AGROW>
        if isfield(grid_spec, 'names') && ~isempty(grid_spec(i).names)
            nms = grid_spec(i).names;
            if ischar(nms) || isstring(nms), nms = {char(nms)}; end
            for ni = 1:numel(nms)
                k = upper(strtrim(char(nms{ni})));
                if ~isKey(NAMES_MAP, k), NAMES_MAP(k) = CODES{end}; end
            end
        end
    end
    CODES = CODES(:);  ROWS = ROWS(:);  COLS = COLS(:);
    return
end

% Named grid or file path
gs = char(string(grid_spec));
is_path = any(gs == filesep) || any(gs == '/') || ...
          endsWith(gs, '.yaml') || endsWith(gs, '.json');

if ~is_path
    % Look up by name in the compiled grid cache
    grids = de_build_grids();
    gi = find(strcmp({grids.name}, gs), 1);
    if isempty(gi)
        fprintf('  ℹ de_geobins: grid "%s" not found in data/grids/\n', gs);
        return
    end
    g = grids(gi);
    keep = ~g.territory | show_terr;
    CODES = g.codes(keep);
    ROWS  = g.rows(keep);
    COLS  = g.cols(keep);
    % Build NAMES_MAP from alias_keys/alias_vals
    ak = g.alias_keys;  av = g.alias_vals;
    for ki = 1:numel(ak)
        if ~isKey(NAMES_MAP, ak{ki}), NAMES_MAP(ak{ki}) = av{ki}; end
    end
    return
end

% Direct file path (.yaml or .json)
yaml_path = gs;
if endsWith(gs, '.json')
    yaml_path = [gs(1:end-5) '.yaml'];
end
if ~exist(yaml_path, 'file')
    fprintf('  ℹ de_geobins: grid file not found: %s\n', yaml_path);
    return
end
try
    entries = de_build_grids_parse_file(yaml_path);
catch ME
    fprintf('  ℹ de_geobins: could not parse %s: %s\n', yaml_path, ME.message);
    return
end
n = numel(entries);
CODES = cell(n,1);  ROWS = zeros(n,1);  COLS = zeros(n,1);  kept = true(n,1);
for i = 1:n
    e = entries{i};
    is_terr = isfield(e,'territory') && logical(e.territory);
    if is_terr && ~show_terr, kept(i) = false; continue; end
    CODES{i} = upper(strtrim(char(e.code)));
    ROWS(i)  = double(e.row);
    COLS(i)  = double(e.col);
    if isfield(e,'names') && ~isempty(e.names)
        nms = e.names;
        if ischar(nms)||isstring(nms), nms = {char(nms)}; end
        for ni = 1:numel(nms)
            k = upper(strtrim(char(nms{ni})));
            if strlength(k)>0 && ~isKey(NAMES_MAP,k), NAMES_MAP(k)=CODES{i}; end
        end
    end
end
CODES = CODES(kept);  ROWS = ROWS(kept);  COLS = COLS(kept);
end


%% ── endsWith ─────────────────────────────────────────────────────────────────
function tf = endsWith(s, suffix)
tf = numel(s) >= numel(suffix) && strcmp(s(end-numel(suffix)+1:end), suffix);
end
