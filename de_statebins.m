function [fig, ax] = de_statebins(T, options)
%DE_STATEBINS  Tile-grid choropleth for states, provinces, counties, or any
%   geographic/conceptual region that fits in a regular grid.
%   No Mapping Toolbox required.
%
%   Usage
%   ─────
%   % US states (default)
%   de_statebins(T, 'StateCol','State', 'ColorCol','Rate')
%   de_statebins(T, 'StateCol','State', 'ColorCol','Rate', 'TimeCol','Year')
%
%   % Named preset (looks for data/grids/ca-provinces.json)
%   de_statebins(T, 'StateCol','Prov', 'ColorCol','Value', 'Grid','ca-provinces')
%
%   % Custom grid from struct array
%   g(1).code='ON'; g(1).row=1; g(1).col=5;
%   g(2).code='QC'; g(2).row=2; g(2).col=7;
%   de_statebins(T, 'StateCol','Prov', 'ColorCol','Value', 'Grid', g)
%
%   Grid argument
%   ─────────────
%   'us-states'    Built-in US 8×12 layout (default).  ShowTerritories adds
%                  PR, VI, GU, AS tiles.
%   String         Any other string is treated as a named preset: loads
%                  data/grids/<name>.json relative to this file.  If the
%                  string contains a path separator or ends in .json, it is
%                  used as a direct file path.
%   Struct array   Fields: code (string/char), row, col (0-indexed integers).
%                  Optional: territory (logical) — excluded unless
%                  ShowTerritories=true.
%
%   JSON format for custom grids
%   ────────────────────────────
%   [{"code":"ON","row":1,"col":5}, {"code":"QC","row":2,"col":7}, ...]
%   Optional field: "territory": true (excluded when ShowTerritories=false)
%
%   Optional name-value arguments
%   ─────────────────────────────
%   StateCol         Column of codes / names in T
%   ColorCol         Numeric column for tile fill
%   TimeCol          Time axis — activates slider
%   Title            Figure title
%   Colormap         Name or Nx3 matrix (default 'parula')
%   Grid             Grid specification (see above, default 'us-states')
%   ShowTerritories  Include territory tiles (default false)
%   Aliases          Nx2 cell {from,to} or containers.Map for normalization
%
%   Returns
%   ───────
%   fig   Figure handle
%   ax    Axes handle

arguments
    T (:,:) table
    options.StateCol         (1,1) string  = ""
    options.ColorCol         (1,1) string  = ""
    options.TimeCol          (1,1) string  = ""
    options.Title            (1,1) string  = ""
    options.Colormap                       = 'parula'
    options.Grid                           = 'us-states'
    options.ShowTerritories  (1,1) logical = false
    options.Aliases                        = []
    options.CellRenderer      (1,1) string  = "color"
    options.CatCol            (1,1) string  = ""
    options.TopK              (1,1) double  = 5
    options.SharedYLim        (1,2) double  = [NaN NaN]
    options.CatColors                       = []
    options.XCol              (1,1) string  = ""
    options.YCol              (1,1) string  = ""
    options.SharedXLim        (1,2) double  = [NaN NaN]
end

fig = []; ax = [];

%% ── Validate ─────────────────────────────────────────────────────────────────
varnames  = string(T.Properties.VariableNames);
needs_color = options.CellRenderer == "color" || options.CellRenderer == "sparkline_cat";
if options.StateCol == "" || ~ismember(options.StateCol, varnames) || ...
   (needs_color && options.ColorCol == "")
    fprintf('  ℹ de_statebins: need StateCol + ColorCol — nothing to plot.\n');
    return
end

%% ── Load / build grid ────────────────────────────────────────────────────────
[CODES, ROWS, COLS] = sb_load_grid(options.Grid, options.ShowTerritories);
if isempty(CODES)
    fprintf('  ℹ de_statebins: no grid tiles — nothing to plot.\n');
    return
end
IS_OVERFLOW = false(numel(CODES), 1);

%% ── Build normalizer ─────────────────────────────────────────────────────────
% Seed with all grid codes (identity mappings).
norm = containers.Map('KeyType','char','ValueType','char');
for i = 1:numel(CODES)
    k = char(upper(strtrim(CODES{i})));
    if ~isKey(norm, k), norm(k) = k; end
end

% For the built-in US grid, add full state name → 2-letter code.
if isequal(options.Grid, 'us-states') || ...
   (ischar(options.Grid) && strcmp(options.Grid, 'us-states'))
    [US_NAMES, US_CODES] = sb_us_lookup();
    for ki = 1:numel(US_NAMES)
        if ~isKey(norm, US_NAMES{ki}), norm(US_NAMES{ki}) = US_CODES{ki}; end
    end
end

% User-supplied aliases (lowest priority).
if ~isempty(options.Aliases)
    if isa(options.Aliases, 'containers.Map')
        ks = keys(options.Aliases);
        for ki = 1:numel(ks)
            k = upper(strtrim(char(ks{ki})));
            if ~isKey(norm, k), norm(k) = upper(strtrim(char(options.Aliases(ks{ki})))); end
        end
    else
        al = options.Aliases;  % Nx2 cell
        for ki = 1:size(al,1)
            k = upper(strtrim(char(al{ki,1})));
            if ~isKey(norm, k), norm(k) = upper(strtrim(char(al{ki,2}))); end
        end
    end
end

%% ── Normalize code column ────────────────────────────────────────────────────
raw_codes = upper(strtrim(string(T.(char(options.StateCol)))));
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
    fprintf('  de_statebins: %d unrecognized code(s) → overflow row: %s\n', ...
        n_ov, strjoin(orphans, ', '));
    ov_cols = double(max(COLS)) + 1;
    ov_base = double(max(ROWS)) + 2;
    k_vec   = (0:n_ov-1);
    CODES(end+1:end+n_ov)       = orphans;
    ROWS(end+1:end+n_ov)        = ov_base + floor(k_vec / ov_cols);
    COLS(end+1:end+n_ov)        = mod(k_vec, ov_cols);
    IS_OVERFLOW(end+1:end+n_ov) = true(1, n_ov);
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
    'MapLabel',      'States', ...
    'FontSize',      7, ...
    'CellRenderer',  options.CellRenderer, ...
    'CatCol',        options.CatCol, ...
    'TopK',          options.TopK, ...
    'SharedYLim',    options.SharedYLim, ...
    'CatColors',     options.CatColors, ...
    'XCol',          options.XCol, ...
    'YCol',          options.YCol, ...
    'SharedXLim',    options.SharedXLim);

end % de_statebins


%% ── Local helpers ────────────────────────────────────────────────────────────

function [CODES, ROWS, COLS] = sb_load_grid(grid_spec, show_terr)
if isstruct(grid_spec)
    CODES   = cellstr(upper(strtrim(string({grid_spec.code}))));
    ROWS    = double([grid_spec.row]);
    COLS    = double([grid_spec.col]);
    if isfield(grid_spec, 'territory')
        is_terr = logical([grid_spec.territory]);
        if ~show_terr
            keep  = ~is_terr;
            CODES = CODES(keep);  ROWS = ROWS(keep);  COLS = COLS(keep);
        end
    end
    CODES = CODES(:);  ROWS = ROWS(:);  COLS = COLS(:);
    return
end

% String: built-in preset, named preset, or file path
gs = char(grid_spec);

if strcmp(gs, 'us-states')
    [CODES, ROWS, COLS] = sb_us_grid(show_terr);
    return
end

% Named preset vs explicit path
if ~any(gs == filesep) && ~any(gs == '/') && ~endsWith(gs, '.json')
    json_path = fullfile(fileparts(mfilename('fullpath')), 'data', 'grids', [gs '.json']);
else
    json_path = gs;
end

if ~exist(json_path, 'file')
    fprintf('  ℹ de_statebins: grid file not found: %s\n', json_path);
    CODES = {}; ROWS = []; COLS = [];
    return
end

raw = jsondecode(fileread(json_path));
n = numel(raw);
CODES = cell(n,1);  ROWS = zeros(n,1);  COLS = zeros(n,1);
is_terr = false(n,1);
for i = 1:n
    CODES{i} = upper(strtrim(raw(i).code));
    ROWS(i)  = raw(i).row;
    COLS(i)  = raw(i).col;
    if isfield(raw(i), 'territory'), is_terr(i) = logical(raw(i).territory); end
end
if ~show_terr
    keep  = ~is_terr;
    CODES = CODES(keep);  ROWS = ROWS(keep);  COLS = COLS(keep);
end
end


function tf = endsWith(s, suffix)
tf = numel(s) >= numel(suffix) && strcmp(s(end-numel(suffix)+1:end), suffix);
end


function [CODES, ROWS, COLS] = sb_us_grid(show_terr)
%   Row 0:  . . . . . . . . . . . ME
%   Row 1:  . . . . . . WI . . . VT NH
%   Row 2:  . WA ID MT ND MN IL MI . NY MA .
%   Row 3:  . OR NV WY SD IA IN OH PA NJ CT RI
%   Row 4:  . CA UT CO NE MO KY WV VA MD DE .
%   Row 5:  . . AZ NM KS AR TN NC SC DC . .
%   Row 6:  AK . . . OK LA MS AL GA . . .
%   Row 7:  HI . . . TX . . . . FL . .
CODES = { ...
    'ME', ...
    'WI','VT','NH', ...
    'WA','ID','MT','ND','MN','IL','MI','NY','MA', ...
    'OR','NV','WY','SD','IA','IN','OH','PA','NJ','CT','RI', ...
    'CA','UT','CO','NE','MO','KY','WV','VA','MD','DE', ...
    'AZ','NM','KS','AR','TN','NC','SC','DC', ...
    'AK','OK','LA','MS','AL','GA', ...
    'HI','TX','FL'}';
ROWS = [ ...
    0, ...
    1,1,1, ...
    2,2,2,2,2,2,2,2,2, ...
    3,3,3,3,3,3,3,3,3,3,3, ...
    4,4,4,4,4,4,4,4,4,4, ...
    5,5,5,5,5,5,5,5, ...
    6,6,6,6,6,6, ...
    7,7,7]';
COLS = [ ...
    11, ...
    6,10,11, ...
    1,2,3,4,5,6,7,9,10, ...
    1,2,3,4,5,6,7,8,9,10,11, ...
    1,2,3,4,5,6,7,8,9,10, ...
    2,3,4,5,6,7,8,9, ...
    0,4,5,6,7,8, ...
    0,4,9]';
if show_terr
    CODES = [CODES; {'GU';'AS';'TR';'PR';'VI'}];
    ROWS  = [ROWS;  [6;7;7;6;7]];
    COLS  = [COLS;  [1;1;2;11;11]];
end
end


function [US_NAMES, US_CODES] = sb_us_lookup()
US_NAMES = { ...
    'ALABAMA','ALASKA','ARIZONA','ARKANSAS','CALIFORNIA','COLORADO', ...
    'CONNECTICUT','DELAWARE','FLORIDA','GEORGIA','HAWAII','IDAHO', ...
    'ILLINOIS','INDIANA','IOWA','KANSAS','KENTUCKY','LOUISIANA','MAINE', ...
    'MARYLAND','MASSACHUSETTS','MICHIGAN','MINNESOTA','MISSISSIPPI', ...
    'MISSOURI','MONTANA','NEBRASKA','NEVADA','NEW HAMPSHIRE','NEW JERSEY', ...
    'NEW MEXICO','NEW YORK','NORTH CAROLINA','NORTH DAKOTA','OHIO', ...
    'OKLAHOMA','OREGON','PENNSYLVANIA','RHODE ISLAND','SOUTH CAROLINA', ...
    'SOUTH DAKOTA','TENNESSEE','TEXAS','UTAH','VERMONT','VIRGINIA', ...
    'WASHINGTON','WEST VIRGINIA','WISCONSIN','WYOMING', ...
    'DISTRICT OF COLUMBIA','PUERTO RICO','VIRGIN ISLANDS', ...
    'GUAM','AMERICAN SAMOA'};
US_CODES = { ...
    'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN', ...
    'IA','KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV', ...
    'NH','NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN', ...
    'TX','UT','VT','VA','WA','WV','WI','WY','DC','PR','VI','GU','AS'};
end
