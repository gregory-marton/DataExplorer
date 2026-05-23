function [fig, ax_s] = de_usamap(T, options)
%DE_USAMAP  U.S. choropleth map with optional coordinate-point overlay.
%
%   Creates a figure with the contiguous 48 states as the main axes and
%   Alaska / Hawaii as insets (lower-left).  Requires the Mapping Toolbox.
%
%   Usage
%   ─────
%   % Choropleth only
%   de_usamap(T, 'StateCol','StateCode', 'ColorCol','Rate')
%
%   % Choropleth + time slider
%   de_usamap(T, 'StateCol','StateCode', 'ColorCol','Rate', 'TimeCol','Year')
%
%   % Scatter points only (size + color)
%   de_usamap(T, 'LatCol','Lat', 'LonCol','Lon', 'SizeCol','Count', 'PointColorCol','Category')
%
%   % Choropleth + scatter overlay
%   de_usamap(T, 'StateCol','State', 'ColorCol','Rate', ...
%              'LatCol','Lat', 'LonCol','Lon', 'SizeCol','n')
%
%   % Custom shapefile (e.g. county-level, watershed, or any regional boundary)
%   de_usamap(T, 'StateCol','CountyFIPS', 'ColorCol','Value', ...
%              'Shapefile','counties.shp', 'KeyField','FIPS')
%
%   Optional name-value arguments
%   ─────────────────────────────
%   StateCol      Column of 2-letter state codes or full state names (choropleth)
%   ColorCol      Numeric column for choropleth fill
%   LatCol        Latitude column for scatter overlay
%   LonCol        Longitude column for scatter overlay
%   SizeCol       Column for scatter point sizes (optional; default = uniform 40)
%   PointColorCol Column for point color: numeric → colormap; categorical → palette
%   TimeCol       Column for time axis — activates a slider
%   Title         Figure title / window name
%   Shapefile     Path to a custom .shp file (overrides usastatelo.shp)
%   KeyField      Field in the shapefile struct to match StateCol values against
%                 (default 'Name'; ignored when usastatelo.shp default is used)
%   Colormap      Colormap name or Nx3 matrix for choropleth fill (default 'parula')
%
%   Returns
%   ───────
%   fig    Figure handle
%   ax_s   Struct with fields: main (CONUS), alaska, hawaii ([] if absent)

arguments
    T (:,:) table
    options.StateCol      (1,1) string = ""
    options.ColorCol      (1,1) string = ""
    options.LatCol        (1,1) string = ""
    options.LonCol        (1,1) string = ""
    options.SizeCol       (1,1) string = ""
    options.PointColorCol (1,1) string = ""
    options.TimeCol       (1,1) string = ""
    options.Title         (1,1) string = ""
    options.Shapefile     (1,1) string = ""
    options.KeyField      (1,1) string = "Name"
    options.Colormap                   = 'parula'
end

fig = []; ax_s = struct('main',[],'alaska',[],'hawaii',[]);

%% ── Toolbox check ────────────────────────────────────────────────────────────
if isempty(ver('map'))
    fprintf('  ℹ Mapping Toolbox not available — de_usamap skipped.\n');
    return
end

%% ── Load shapefile ───────────────────────────────────────────────────────────
use_default_us = options.Shapefile == "";
shp_path = char(options.Shapefile);
if use_default_us, shp_path = 'usastatelo.shp'; end
try
    S = shaperead(shp_path, 'UseGeoCoords', true);
catch ME
    fprintf('  ℹ de_usamap: cannot load "%s": %s\n', shp_path, ME.message);
    return
end
n_shape    = numel(S);
key_field  = char(options.KeyField);
if use_default_us, key_field = 'Name'; end
shape_keys = upper({S.(key_field)});  % uppercase for case-insensitive matching

%% ── US 2-letter ↔ full-name lookup ──────────────────────────────────────────
US_NAMES = {'ALABAMA','ALASKA','ARIZONA','ARKANSAS','CALIFORNIA','COLORADO', ...
    'CONNECTICUT','DELAWARE','FLORIDA','GEORGIA','HAWAII','IDAHO','ILLINOIS', ...
    'INDIANA','IOWA','KANSAS','KENTUCKY','LOUISIANA','MAINE','MARYLAND', ...
    'MASSACHUSETTS','MICHIGAN','MINNESOTA','MISSISSIPPI','MISSOURI','MONTANA', ...
    'NEBRASKA','NEVADA','NEW HAMPSHIRE','NEW JERSEY','NEW MEXICO','NEW YORK', ...
    'NORTH CAROLINA','NORTH DAKOTA','OHIO','OKLAHOMA','OREGON','PENNSYLVANIA', ...
    'RHODE ISLAND','SOUTH CAROLINA','SOUTH DAKOTA','TENNESSEE','TEXAS','UTAH', ...
    'VERMONT','VIRGINIA','WASHINGTON','WEST VIRGINIA','WISCONSIN','WYOMING', ...
    'DISTRICT OF COLUMBIA'};
US_CODES = {'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN', ...
    'IA','KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH', ...
    'NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX','UT', ...
    'VT','VA','WA','WV','WI','WY','DC'};
SMALL_CODES = {'CT','RI','DE','MD','DC','NJ','MA','NH','VT'};
SMALL_POS   = {[40.8,-68.0],[41.5,-67.5],[38.5,-68.0],[37.5,-68.0],[36.8,-68.0], ...
               [39.7,-68.5],[43.2,-67.5],[44.8,-67.5],[46.0,-68.5]};

% Build shape-key → index lookup (also add 2-letter entries for US default)
key_to_si = containers.Map('KeyType','char','ValueType','double');
for si = 1:n_shape
    key_to_si(shape_keys{si}) = si;
end
if use_default_us
    for ki = 1:numel(US_CODES)
        if isKey(key_to_si, US_NAMES{ki})
            key_to_si(US_CODES{ki}) = key_to_si(US_NAMES{ki});
        end
    end
end

%% ── Identify inset regions (US default only) ─────────────────────────────────
ak_si = []; hi_si = [];
if use_default_us
    if isKey(key_to_si, 'ALASKA'), ak_si = key_to_si('ALASKA'); end
    if isKey(key_to_si, 'HAWAII'), hi_si = key_to_si('HAWAII'); end
end

%% ── Validate column arguments ────────────────────────────────────────────────
varnames = string(T.Properties.VariableNames);
has_state = options.StateCol ~= "" && ismember(options.StateCol, varnames);
has_color = options.ColorCol ~= "" && ismember(options.ColorCol, varnames);
has_lat   = options.LatCol   ~= "" && ismember(options.LatCol,   varnames);
has_lon   = options.LonCol   ~= "" && ismember(options.LonCol,   varnames);
has_pts   = has_lat && has_lon;
has_size  = options.SizeCol  ~= "" && ismember(options.SizeCol,  varnames);
has_pcol  = options.PointColorCol ~= "" && ismember(options.PointColorCol, varnames);
has_time  = options.TimeCol  ~= "" && ismember(options.TimeCol,  varnames);
has_choro = has_state && has_color;

if ~has_choro && ~has_pts
    fprintf('  ℹ de_usamap: need StateCol+ColorCol or LatCol+LonCol — nothing to plot.\n');
    return
end

%% ── Time axis ────────────────────────────────────────────────────────────────
t_vals = []; n_t = 1; is_year_axis = false;
if has_time
    tdata = T.(char(options.TimeCol));
    if isa(tdata, 'datetime')
        t_vals = unique(tdata(~isnat(tdata)));
    else
        tdata_d = double(tdata);
        t_vals = unique(tdata_d(~isnan(tdata_d)));
        is_year_axis = true;
    end
    n_t = numel(t_vals);
    if n_t == 0, has_time = false; t_vals = []; n_t = 1; end
end

%% ── Build choropleth heat matrix ─────────────────────────────────────────────
cmap_ch = de_usamap_cmap(options.Colormap);
Heat  = NaN(n_shape, n_t);
N_obs = zeros(n_shape, n_t);
vmin = NaN; vmax = NaN;

if has_choro
    state_str = upper(string(T.(char(options.StateCol))));
    ydata     = double(T.(char(options.ColorCol)));
    tdata_col = [];
    if has_time
        tdata_col = T.(char(options.TimeCol));
        if ~isa(tdata_col, 'datetime'), tdata_col = double(tdata_col); end
    end

    for si = 1:n_shape
        % Match by shape key (full name or code)
        s_mask = state_str == shape_keys{si};
        if ~any(s_mask) && use_default_us
            % Try matching via 2-letter code
            name_idx = find(strcmp(US_NAMES, shape_keys{si}), 1);
            if ~isempty(name_idx)
                s_mask = state_str == string(US_CODES{name_idx});
            end
        end
        if ~any(s_mask), continue; end

        for tt = 1:n_t
            if has_time
                t_mask = (tdata_col == t_vals(tt));
                vals = ydata(s_mask & t_mask);
            else
                vals = ydata(s_mask);
            end
            vals = vals(~isnan(vals));
            if ~isempty(vals)
                Heat(si, tt)  = mean(vals);
                N_obs(si, tt) = numel(vals);
            end
        end
    end
    vmin = min(Heat(:), [], 'omitnan');
    vmax = max(Heat(:), [], 'omitnan');
    if isnan(vmin) || vmin == vmax
        has_choro = false;  % no valid data — choropleth skipped
    end
end

%% ── Figure and map axes ──────────────────────────────────────────────────────
has_slider = has_time && n_t > 1;
sldr_bot   = 0.07 * double(has_slider);  % reserve bottom strip for slider

% Normalized positions: [left bottom width height]
POS_MAIN = [0.00  0.20+sldr_bot  0.76  0.76-sldr_bot];
POS_AK   = [0.00  0.02+sldr_bot  0.22  0.19];
POS_HI   = [0.23  0.02+sldr_bot  0.15  0.12];
POS_CB   = [0.78  0.20+sldr_bot  0.03  0.76-sldr_bot];

fig = figure('Color', [0.97 0.97 0.97], 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.08 0.88 0.85]);
if options.Title ~= ""
    fig.Name = char(options.Title);
end

ax_main = usamap('conus');
set(ax_main, 'Units', 'normalized', 'Position', POS_MAIN);
setm(ax_main, 'Frame','off','Grid','off','MeridianLabel','off','ParallelLabel','off');
ax_s.main = ax_main;

ax_ak = [];
if ~isempty(ak_si)
    ax_ak = usamap('Alaska');
    set(ax_ak, 'Units', 'normalized', 'Position', POS_AK);
    setm(ax_ak, 'Frame','off','Grid','off','MeridianLabel','off','ParallelLabel','off');
    ax_s.alaska = ax_ak;
end

ax_hi = [];
if ~isempty(hi_si)
    ax_hi = usamap('Hawaii');
    set(ax_hi, 'Units', 'normalized', 'Position', POS_HI);
    setm(ax_hi, 'Frame','off','Grid','off','MeridianLabel','off','ParallelLabel','off');
    ax_s.hawaii = ax_hi;
end

%% ── Draw state patches ───────────────────────────────────────────────────────
patch_h = cell(n_shape, 1);
% patchm uses the CURRENT map axes' projection, not the 'Parent' argument.
% Group states by target axes so we call axes() once per group.
si_groups = {[], [], []};
ax_groups = {ax_main, ax_ak, ax_hi};
for si = 1:n_shape
    ax_for = de_usamap_axes_for(si, ak_si, hi_si, ax_main, ax_ak, ax_hi);
    for gi = 1:3
        if isequal(ax_for, ax_groups{gi})
            si_groups{gi}(end+1) = si;
            break
        end
    end
end
for gi = 1:3
    ax_g = ax_groups{gi};
    if isempty(ax_g) || isempty(si_groups{gi}), continue; end
    axes(ax_g); %#ok<LAXES>
    for si = si_groups{gi}
        fc = de_usamap_val2color(Heat(si,1), vmin, vmax, cmap_ch, has_choro);
        patch_h{si} = patchm(S(si).Lat, S(si).Lon, 0, ...
            'FaceColor', fc, 'EdgeColor', [0.45 0.45 0.45], 'LineWidth', 0.3);
        hh = patch_h{si};
        for hk = 1:numel(hh)
            hh(hk).UserData = struct('state_idx', si, 'state_name', S(si).Name);
        end
    end
end
axes(ax_main); %#ok<LAXES>

%% ── Colorbar ─────────────────────────────────────────────────────────────────
if has_choro
    colormap(ax_main, cmap_ch);
    clim(ax_main, [vmin vmax]);
    cb = colorbar(ax_main, 'Position', POS_CB);
    cb.Label.String = strrep(char(options.ColorCol), '_', ' ');
    cb.FontSize = 8;
end

%% ── State labels ─────────────────────────────────────────────────────────────
[label_h, label_codes] = de_usamap_labels(ax_main, ax_ak, ax_hi, ...
    S, Heat(:,1), shape_keys, ak_si, hi_si, n_shape, ...
    US_NAMES, US_CODES, SMALL_CODES, SMALL_POS, has_choro, use_default_us);

%% ── Title and ticker ─────────────────────────────────────────────────────────
title_str = de_usamap_title_str(options.ColorCol, t_vals, 1, is_year_axis, has_choro, has_time);
title_h = title(ax_main, title_str, 'FontSize', 11, 'Interpreter', 'none');

%% ── Point scatter overlay ────────────────────────────────────────────────────
% Scatter is drawn once (all rows); time-filtering is noted for future work.
if has_pts
    lat_v  = double(T.(char(options.LatCol)));
    lon_v  = double(T.(char(options.LonCol)));
    valid  = ~isnan(lat_v) & ~isnan(lon_v);
    lat_v  = lat_v(valid); lon_v = lon_v(valid);

    BASE_SZ = 40;
    sz = repmat(BASE_SZ, numel(lat_v), 1);
    if has_size
        sv = double(T.(char(options.SizeCol))); sv = sv(valid);
        lo = min(sv); hi = max(sv);
        if hi > lo, sz = 10 + 120 * (sv - lo) / (hi - lo); end
        sz(isnan(sz)) = BASE_SZ;
    end

    pt_c = [0.85 0.20 0.10];  % default red-orange for visibility on choropleth
    if has_pcol
        pv = T.(char(options.PointColorCol)); pv = pv(valid);
        if isnumeric(pv)
            pv = double(pv);
            pv_norm = (pv - min(pv)) / max(max(pv) - min(pv), eps);
            pt_c = interp1(linspace(0,1,256), cmap_ch, pv_norm, 'linear', 'extrap');
        else
            % Categorical: lines palette, one color per level
            cats = unique(pv); nc = numel(cats); pal = lines(nc);
            hold(ax_main, 'on');
            for ki = 1:nc
                m = pv == cats(ki);
                scatterm(ax_main, lat_v(m), lon_v(m), sz(m), pal(ki,:), ...
                    'filled', 'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', 'none', ...
                    'DisplayName', string(cats(ki)));
            end
            hold(ax_main, 'off');
            legend(ax_main, 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
            pt_c = [];  % already drawn
        end
    end
    if ~isempty(pt_c) && isnumeric(pt_c)
        scatterm(ax_main, lat_v, lon_v, sz, pt_c, ...
            'filled', 'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', 'none');
    end
end

%% ── Slider ───────────────────────────────────────────────────────────────────
sld = []; lbl_ctrl = []; %#ok<NASGU>
if has_slider
    sld = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.10 0.02 0.80 0.05], ...
        'Min', 1, 'Max', n_t, 'Value', 1, ...
        'SliderStep', [1/max(n_t-1,1)  max(0.1, 5/max(n_t-1,1))]);
    lbl_ctrl = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.91 0.02 0.08 0.05], ...
        'String', de_usamap_yr_str(t_vals, 1, is_year_axis), ...
        'FontSize', 10, 'BackgroundColor', [0.97 0.97 0.97]);

    % Capture closure variables
    ph_c   = patch_h;   lh_c = label_h;   lc_c = label_codes;
    Heat_c = Heat;      vmin_c = vmin;     vmax_c = vmax;
    cmap_c = cmap_ch;   tvals_c = t_vals;  iyr_c = is_year_axis;
    th_c   = title_h;   cc_c = options.ColorCol;
    ht_c   = has_time;  hchoro_c = has_choro;

    sld.Callback = @(src, ~) de_usamap_update(src, ph_c, lh_c, lc_c, ...
        Heat_c, vmin_c, vmax_c, cmap_c, tvals_c, iyr_c, th_c, lbl_ctrl, cc_c, ht_c, hchoro_c);
end

%% ── Datacursor tooltips ──────────────────────────────────────────────────────
if has_choro
    dcm = datacursormode(fig);
    Heat_dc = Heat; N_dc = N_obs; cn_dc = char(options.ColorCol); sld_dc = sld;
    dcm.UpdateFcn = @(~, ev) de_usamap_datatip(ev, Heat_dc, N_dc, cn_dc, sld_dc);
end

end % de_usamap


%% ── Local helpers ────────────────────────────────────────────────────────────

function ax = de_usamap_axes_for(si, ak_si, hi_si, ax_main, ax_ak, ax_hi)
% Return the axes that shape si should be drawn into.
if ~isempty(ak_si) && si == ak_si && ~isempty(ax_ak)
    ax = ax_ak;
elseif ~isempty(hi_si) && si == hi_si && ~isempty(ax_hi)
    ax = ax_hi;
else
    ax = ax_main;
end
end


function [lat_c, lon_c] = de_usamap_polygon_center(lats, lons)
% Bounding-box center of the largest polygon ring (handles multi-part shapes).
% Avoids mean-of-vertices bias from complex coastlines.
finite_mask = isfinite(lats);
if ~any(finite_mask)
    lat_c = NaN; lon_c = NaN; return
end

% Split at NaN separators into individual rings (nan_idx always column)
nan_idx = find(~finite_mask(:));
starts  = [1; nan_idx + 1];
ends    = [nan_idx - 1; numel(lats)];

best_area = 0;
lat_c = mean(lats(finite_mask));   % fallback
lon_c = mean(lons(finite_mask));

for k = 1:numel(starts)
    r = starts(k):ends(k);
    if numel(r) < 3, continue; end
    la = lats(r); lo = lons(r);
    bbox_area = (max(la) - min(la)) * (max(lo) - min(lo));
    if bbox_area > best_area
        best_area = bbox_area;
        lat_c = (min(la) + max(la)) / 2;
        lon_c = (min(lo) + max(lo)) / 2;
    end
end
end


function [label_h, label_codes] = de_usamap_labels(ax_main, ax_ak, ax_hi, ...
        S, heat_t1, shape_keys, ak_si, hi_si, n_shape, ...
        US_NAMES, US_CODES, SMALL_CODES, SMALL_POS, has_choro, use_default_us)
% Place state-code + value labels on the appropriate axes.

label_h    = cell(n_shape, 1);
label_codes = cell(n_shape, 1);

for si = 1:n_shape
    % Resolve 2-letter code
    code = '';
    if use_default_us
        idx = find(strcmp(US_NAMES, shape_keys{si}), 1);
        if ~isempty(idx), code = US_CODES{idx}; end
    else
        % Use the key directly (truncated to ≤4 chars) as the label
        code = shape_keys{si};
        if numel(code) > 4, code = code(1:4); end
    end
    if isempty(code), continue; end
    label_codes{si} = code;

    [lat_c, lon_c] = de_usamap_polygon_center(S(si).Lat, S(si).Lon);
    if isnan(lat_c), continue; end

    lbl = de_usamap_label_str(code, heat_t1(si), has_choro);
    ax_for = de_usamap_axes_for(si, ak_si, hi_si, ax_main, ax_ak, ax_hi);
    axes(ax_for); %#ok<LAXES>  % textm/plotm use current map axes' projection

    small_idx = find(strcmp(SMALL_CODES, code), 1);
    if ~isempty(small_idx) && isequal(ax_for, ax_main)
        pos = SMALL_POS{small_idx};
        plotm([lat_c, pos(1)], [lon_c, pos(2)], '-', ...
            'Color', [0.55 0.55 0.55], 'LineWidth', 0.6, ...
            'HitTest', 'off', 'PickableParts', 'none');
        label_h{si} = textm(pos(1), pos(2), lbl, ...
            'FontSize', 5.5, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontWeight', 'bold', ...
            'Color', [0.1 0.1 0.1]);
    else
        fs = 5.5 + 0.5 * double(isequal(ax_for, ax_ak) || isequal(ax_for, ax_hi));
        label_h{si} = textm(lat_c, lon_c, lbl, ...
            'FontSize', fs, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontWeight', 'bold', ...
            'Color', [0.1 0.1 0.1]);
    end
end
end


function s = de_usamap_label_str(code, val, has_choro)
if ~has_choro || isnan(val)
    s = code;
else
    s = sprintf('%s\n%.3g', code, val);
end
end


function s = de_usamap_title_str(color_col, t_vals, tt, is_year_axis, has_choro, has_time)
if ~has_choro
    s = 'Map'; return
end
if has_time && ~isempty(t_vals)
    s = sprintf('mean(%s)  —  %s', char(color_col), de_usamap_yr_str(t_vals, tt, is_year_axis));
else
    s = sprintf('mean(%s)', char(color_col));
end
end


function s = de_usamap_yr_str(t_vals, tt, is_year_axis)
if is_year_axis
    s = sprintf('%g', t_vals(tt));
else
    s = char(datetime(t_vals(tt), 'Format', 'MMM yyyy'));
end
end


function fc = de_usamap_val2color(val, vmin, vmax, cmap, has_choro)
if ~has_choro || isnan(val) || isnan(vmin) || vmin == vmax
    fc = [0.85 0.85 0.85];
else
    norm = max(0, min(1, (val - vmin) / (vmax - vmin)));
    ci   = max(1, min(size(cmap,1), floor(norm * size(cmap,1)) + 1));
    fc   = cmap(ci,:);
end
end


function cmap = de_usamap_cmap(spec)
if ischar(spec) || isstring(spec)
    cmap = feval(char(spec), 256);
else
    cmap = spec;
end
end


function de_usamap_update(sld, patch_h, label_h, label_codes, ...  %#ok<DEFNU>
        Heat, vmin, vmax, cmap, t_vals, is_year_axis, title_h, lbl_ctrl, ...
        color_col, has_time, has_choro)
tt = round(sld.Value); sld.Value = tt;
for si = 1:numel(patch_h)
    fc = de_usamap_val2color(Heat(si,tt), vmin, vmax, cmap, has_choro);
    if iscell(patch_h{si})
        for hk = 1:numel(patch_h{si}), set(patch_h{si}{hk}, 'FaceColor', fc); end
    else
        set(patch_h{si}, 'FaceColor', fc);
    end
    if ~isempty(label_h{si}) && isgraphics(label_h{si}) && ~isempty(label_codes{si})
        label_h{si}.String = de_usamap_label_str(label_codes{si}, Heat(si,tt), has_choro);
    end
end
title_h.String = de_usamap_title_str(color_col, t_vals, tt, is_year_axis, has_choro, has_time);
if ~isempty(lbl_ctrl) && isgraphics(lbl_ctrl)
    lbl_ctrl.String = de_usamap_yr_str(t_vals, tt, is_year_axis);
end
end


function txt = de_usamap_datatip(ev, Heat, N_obs, color_col, sld)
ud = ev.Target.UserData;
if ~isstruct(ud) || ~isfield(ud, 'state_idx')
    txt = ''; return
end
si = ud.state_idx;
tt = 1;
if ~isempty(sld) && isgraphics(sld), tt = round(sld.Value); end
val = Heat(si, tt); n = N_obs(si, tt);
if isnan(val)
    txt = {ud.state_name, sprintf('%s: N/A', color_col)};
else
    txt = {ud.state_name, sprintf('%s: %.4g  (n=%d)', color_col, val, n)};
end
end
