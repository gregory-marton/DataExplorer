function [fig, ax] = de_countrybins(T, options)
%DE_COUNTRYBINS  World choropleth using a country-bin tile layout.
%   Each country is a colored square placed in a ~24×29 grid that
%   approximates world geography.  No Mapping Toolbox required.
%
%   Grid data: data/world_tile_grid.json (Maarten Lambrechts / BBC standard).
%   Update:    python scripts/update_world_tile_grid.py
%
%   Usage
%   ─────
%   de_countrybins(T, 'CountryCol','ISO2', 'ColorCol','Rate')
%   de_countrybins(T, 'CountryCol','ISO3', 'ColorCol','GDP', 'TimeCol','Year')
%   de_countrybins(T, 'CountryCol','Name', 'ColorCol','Value')
%
%   CountryCol accepts ISO alpha-2 (GB), alpha-3 (GBR), full English country
%   names, and many historical / non-standard codes (USSR→RU, YU→RS, etc.).
%   Unrecognized codes are placed in an overflow row below the main grid with
%   an amber border and a console notice — no data is silently dropped.
%
%   Optional name-value arguments
%   ─────────────────────────────
%   CountryCol   Column of country identifiers (see above)
%   ColorCol     Numeric column for tile fill
%   TimeCol      Column for time axis — activates a slider
%   Title        Figure title / window name
%   Colormap     Name or Nx3 matrix (default 'parula')
%   GridFile     Path to alternate JSON grid (default: data/world_tile_grid.json)
%
%   Returns
%   ───────
%   fig   Figure handle
%   ax    Axes handle

arguments
    T (:,:) table
    options.CountryCol  (1,1) string = ""
    options.ColorCol    (1,1) string = ""
    options.TimeCol     (1,1) string = ""
    options.Title       (1,1) string = ""
    options.Colormap                 = 'parula'
    options.GridFile    (1,1) string = ""
    options.CellRenderer (1,1) string  = "color"
    options.CatCol       (1,1) string  = ""
    options.TopK         (1,1) double  = 5
    options.SharedYLim   (1,2) double  = [NaN NaN]
    options.CatColors                  = []
end

fig = []; ax = [];

%% ── Validate ─────────────────────────────────────────────────────────────────
varnames  = string(T.Properties.VariableNames);
if options.CountryCol == "" || ~ismember(options.CountryCol, varnames) || ...
   options.ColorCol == ""
    fprintf('  ℹ de_countrybins: need CountryCol + ColorCol — nothing to plot.\n');
    return
end

%% ── Resolve grid file ────────────────────────────────────────────────────────
if options.GridFile == ""
    json_path = fullfile(fileparts(mfilename('fullpath')), 'data', 'world_tile_grid.json');
else
    json_path = char(options.GridFile);
end
if ~exist(json_path, 'file')
    fprintf('  ℹ de_countrybins: %s not found.\n', json_path);
    fprintf('    Run:  python scripts/update_world_tile_grid.py\n');
    return
end

%% ── Load grid ────────────────────────────────────────────────────────────────
raw    = jsondecode(fileread(json_path));
n_json = numel(raw);
CODES = cell(n_json,1);  A3 = cell(n_json,1);  NMES = cell(n_json,1);
ROWS  = zeros(n_json,1);  COLS = zeros(n_json,1);
for i = 1:n_json
    ri       = raw{i};
    CODES{i} = upper(strtrim(ri.alpha_2));
    A3{i}    = upper(strtrim(ri.alpha_3));
    NMES{i}  = upper(strtrim(ri.name));
    COLS(i)  = ri.coordinates(1) - 1;
    ROWS(i)  = ri.coordinates(2) - 1;
end

%% ── Build 4-tier normalizer ──────────────────────────────────────────────────
% Priority: alpha-2 > alpha-3 > full name > historical alias.
% Existing entries are never overwritten, so earlier sources win.
norm = containers.Map('KeyType','char','ValueType','char');
for i = 1:n_json
    if ~isKey(norm, CODES{i}), norm(CODES{i}) = CODES{i}; end
end
for i = 1:n_json
    if ~isempty(A3{i}) && ~isKey(norm, A3{i}), norm(A3{i}) = CODES{i}; end
end
for i = 1:n_json
    if ~isempty(NMES{i}) && ~isKey(norm, NMES{i}), norm(NMES{i}) = CODES{i}; end
end

ALIASES = { ...
    'SU',         'RU'; ...  % Soviet Union
    'USSR',       'RU'; ...
    'YU',         'RS'; ...  % Yugoslavia → Serbia (legal successor)
    'YUGOSLAVIA', 'RS'; ...
    'CS',         'CZ'; ...  % Czechoslovakia → Czech Republic
    'CSK',        'CZ'; ...
    'DD',         'DE'; ...  % East Germany
    'DDR',        'DE'; ...
    'ZR',         'CD'; ...  % Zaire → DR Congo
    'ZAR',        'CD'; ...
    'BU',         'MM'; ...  % Burma (old ISO) → Myanmar
    'BUR',        'MM'; ...
    'TP',         'TL'; ...  % East Timor (old) → Timor-Leste
    'TMP',        'TL'; ...
    'AN',         'CW'; ...  % Netherlands Antilles → Curaçao
    'ANT',        'CW'; ...
    'YD',         'YE'; ...  % South Yemen → Yemen
    'VD',         'VN'; ...  % South Vietnam → Vietnam
    'RH',         'ZW'; ...  % Southern Rhodesia → Zimbabwe
    'RHODESIA',   'ZW'; ...
    'NH',         'VU'; ...  % New Hebrides → Vanuatu
    'CT',         'KI'; ...  % Canton/Enderbury → Kiribati
    'NT',         'SA'; ...  % Saudi-Iraqi Neutral Zone → Saudi Arabia
    'PZ',         'PA'; ...  % Panama Canal Zone → Panama
    'UK',         'GB'; ...  % UK (non-ISO but ubiquitous)
    'ENG',        'GB'; ...  % England
    'SCO',        'GB'; ...  % Scotland
    'WAL',        'GB'; ...  % Wales
    'WLS',        'GB'; ...
    'NIR',        'GB'; ...  % Northern Ireland
    'ENGLAND',    'GB'; ...
    'SCOTLAND',   'GB'; ...
    'WALES',      'GB'; ...
};
for k = 1:size(ALIASES,1)
    if ~isKey(norm, ALIASES{k,1}), norm(ALIASES{k,1}) = ALIASES{k,2}; end
end

%% ── Normalize CountryCol ─────────────────────────────────────────────────────
raw_codes = upper(strtrim(string(T.(char(options.CountryCol)))));
normed    = raw_codes;
for ri = 1:numel(raw_codes)
    k = char(raw_codes(ri));
    if isKey(norm, k), normed(ri) = string(norm(k)); end
end

%% ── Detect overflow codes ────────────────────────────────────────────────────
grid_set  = containers.Map(CODES, true(n_json,1));
data_uniq = unique(normed);
data_uniq = data_uniq(strtrim(data_uniq) ~= "" & ~ismissing(data_uniq));
is_orph   = ~cellfun(@(c) isKey(grid_set,c), cellstr(data_uniq));
orphans   = cellstr(data_uniq(is_orph));
n_ov      = numel(orphans);
IS_OVERFLOW = false(n_json,1);

if n_ov > 0
    fprintf('  de_countrybins: %d unrecognized code(s) → overflow row: %s\n', ...
        n_ov, strjoin(orphans, ', '));
    ov_cols = double(max(COLS)) + 1;
    ov_base = double(max(ROWS)) + 2;
    for k = 1:n_ov
        CODES{end+1}       = orphans{k}; %#ok<AGROW>
        ROWS(end+1)        = ov_base + floor((k-1)/ov_cols);
        COLS(end+1)        = mod(k-1, ov_cols);
        IS_OVERFLOW(end+1) = true;
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
    'MapLabel',      'World map', ...
    'FontSize',      5.5, ...
    'CellRenderer',  options.CellRenderer, ...
    'CatCol',        options.CatCol, ...
    'TopK',          options.TopK, ...
    'SharedYLim',    options.SharedYLim, ...
    'CatColors',     options.CatColors);

end % de_countrybins
