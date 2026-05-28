function [fig, ax] = de_countrybins(T, options)
%DE_COUNTRYBINS  World tile choropleth — thin wrapper around de_geobins.
%   Default grid: 'world' (data/grids/world.json).
%
%   Usage
%   ─────
%   de_countrybins(T, 'CountryCol','ISO2', 'ColorCol','Rate')
%   de_countrybins(T, 'CountryCol','Name', 'ColorCol','GDP', 'TimeCol','Year')
%
%   CountryCol accepts ISO alpha-2 (GB), alpha-3 (GBR), full English names,
%   endonyms, and historical codes (USSR→RU, etc.) via data/grids/world.json.
%
%   See de_geobins for full documentation.

arguments
    T (:,:) table
    options.CountryCol   (1,1) string = ""
    options.ColorCol     (1,1) string = ""
    options.TimeCol      (1,1) string = ""
    options.Title        (1,1) string = ""
    options.Colormap                  = 'parula'
    options.GridFile     (1,1) string = ""   % legacy: path to alternate world JSON
    options.CellRenderer (1,1) string = "color"
    options.CatCol       (1,1) string = ""
    options.TopK         (1,1) double = 5
    options.SharedYLim   (1,2) double = [NaN NaN]
    options.CatColors                 = []
    options.XCol         (1,1) string = ""
    options.YCol         (1,1) string = ""
    options.SharedXLim   (1,2) double = [NaN NaN]
    options.CLim         (1,2) double = [NaN NaN]
end

% GridFile (legacy) overrides default; otherwise use 'world' preset
if options.GridFile ~= ""
    grid = options.GridFile;
else
    grid = 'world';
end

[fig, ax] = de_geobins(T, ...
    'GeoCol',       options.CountryCol, ...
    'ColorCol',     options.ColorCol, ...
    'TimeCol',      options.TimeCol, ...
    'Title',        options.Title, ...
    'Colormap',     options.Colormap, ...
    'Grid',         grid, ...
    'FontSize',     5.5, ...
    'CellRenderer', options.CellRenderer, ...
    'CatCol',       options.CatCol, ...
    'TopK',         options.TopK, ...
    'SharedYLim',   options.SharedYLim, ...
    'CatColors',    options.CatColors, ...
    'XCol',         options.XCol, ...
    'YCol',         options.YCol, ...
    'SharedXLim',   options.SharedXLim, ...
    'CLim',         options.CLim);
end
