function [fig, ax] = de_usamap(T, options)
%DE_USAMAP  U.S. state choropleth on a geographic map (Albers projection).
%   Uses a single usamap('conus') axes.  Alaska and Hawaii are placed in
%   the lower-left area using affine transforms in projected coordinates —
%   no separate axes, no frame-fill fights.
%
%   Requires: Mapping Toolbox.
%
%   This function is a teaching demo.  Key parameters are intentionally
%   exposed so students can see how the affine transform works:
%
%     % See AK at its true geographic size (it's enormous):
%     de_usamap(T, 'StateCol','State', 'ColorCol','Value', 'AKScale',1.0)
%
%     % Move AK to a custom position (projected metres):
%     de_usamap(T, ..., 'AKOffset',[-2.1e6, -1.0e6])
%
%   Usage
%   ─────
%   de_usamap(T, 'StateCol','State', 'ColorCol','Value')
%   de_usamap(T, 'StateCol','State', 'ColorCol','Value', 'TimeCol','Year')
%
%   Name-value arguments
%   ────────────────────
%   StateCol    column of 2-letter state codes or full state names
%   ColorCol    numeric column for fill color
%   TimeCol     time axis → activates slider
%   Title       figure / window title
%   Colormap    colormap (default 'parula')
%   AKScale     scale factor for Alaska (default 0.35; try 1.0 to see real size)
%   AKOffset    [cx, cy] target centre in projected metres ([] = auto)
%   HIOffset    [cx, cy] target centre in projected metres ([] = auto)
%
%   Returns
%   ───────
%   fig   Figure handle
%   ax    Axes handle (single map axes — all state patches are children of this)

arguments
    T (:,:) table
    options.StateCol  (1,1) string  = ""
    options.ColorCol  (1,1) string  = ""
    options.TimeCol   (1,1) string  = ""
    options.Title     (1,1) string  = ""
    options.Colormap                = 'parula'
    options.AKScale   (1,1) double  = 0.35
    options.AKOffset  (1,2) double  = [NaN NaN]
    options.HIOffset  (1,2) double  = [NaN NaN]
end

fig = []; ax = [];

if isempty(ver('map'))
    fprintf('  ℹ de_usamap: Mapping Toolbox not available.\n');
    return
end

%% ── State name ↔ 2-letter code lookup ───────────────────────────────────────
[US_NAMES, US_CODES] = um_us_lookup();
norm = containers.Map('KeyType','char','ValueType','char');
for i = 1:numel(US_CODES)
    k = char(US_CODES{i});
    if ~isKey(norm,k), norm(k) = k; end
end
for i = 1:numel(US_NAMES)
    k = char(US_NAMES{i});
    if ~isKey(norm,k), norm(k) = US_CODES{i}; end
end

%% ── Validate columns ─────────────────────────────────────────────────────────
varnames  = string(T.Properties.VariableNames);
has_state = options.StateCol ~= "" && ismember(options.StateCol, varnames);
has_color = options.ColorCol ~= "" && ismember(options.ColorCol, varnames);
has_time  = options.TimeCol  ~= "" && ismember(options.TimeCol,  varnames);
has_choro = has_state && has_color;

if ~has_choro
    fprintf('  ℹ de_usamap: need StateCol + ColorCol — nothing to plot.\n');
    return
end

%% ── Normalize state column ───────────────────────────────────────────────────
raw_st = upper(strtrim(string(T.(char(options.StateCol)))));
normed = raw_st;
for ri = 1:numel(raw_st)
    k = char(raw_st(ri));
    if isKey(norm,k), normed(ri) = string(norm(k)); end
end

%% ── Time axis ────────────────────────────────────────────────────────────────
t_vals = []; n_t = 1; is_year_axis = false;
if has_time
    tdata = T.(char(options.TimeCol));
    if isa(tdata,'datetime')
        t_vals = unique(tdata(~isnat(tdata)));
    else
        t_vals = unique(double(tdata(~isnan(double(tdata)))));
        is_year_axis = true;
    end
    n_t = numel(t_vals);
    if n_t == 0, has_time = false; t_vals = []; n_t = 1; end
end
has_slider = has_time && n_t > 1;

%% ── Build per-state heat matrix ──────────────────────────────────────────────
all_codes   = unique(US_CODES,'stable');   % 51 entries: 50 states + DC
n_st        = numel(all_codes);
code_to_idx = containers.Map(all_codes, num2cell(1:n_st));

cmap_ch = um_cmap(options.Colormap);
Heat    = NaN(n_st, n_t);
N_obs   = zeros(n_st, n_t);
ydata   = double(T.(char(options.ColorCol)));

tdata_col = [];
if has_time
    tdata_col = T.(char(options.TimeCol));
    if ~isa(tdata_col,'datetime'), tdata_col = double(tdata_col); end
end

for si = 1:n_st
    sc     = all_codes{si};
    s_mask = normed == sc;
    if ~any(s_mask), continue; end
    for tt = 1:n_t
        if has_time
            vals = ydata(s_mask & (tdata_col == t_vals(tt)));
        else
            vals = ydata(s_mask);
        end
        vals = vals(~isnan(vals));
        if ~isempty(vals)
            Heat(si,tt)  = mean(vals);
            N_obs(si,tt) = numel(vals);
        end
    end
end

vmin = min(Heat(:),[],'omitnan');
vmax = max(Heat(:),[],'omitnan');
if isnan(vmin) || vmin == vmax, has_choro = false; end

%% ── Figure ───────────────────────────────────────────────────────────────────
sldr_lift = 0.07 * double(has_slider);
BG = [0.97 0.97 0.97];

fig = figure('Color',BG,'NumberTitle','off', ...
    'Units','normalized','Position',[0.05 0.08 0.88 0.85]);
if options.Title ~= "", fig.Name = char(options.Title); end

%% ── Single map axes (usamap conus) ───────────────────────────────────────────
% usamap() creates its own map axes in the current figure.
% Make fig current, call usamap, then grab and reposition the axes.
ax_right = 0.82 + 0.10*double(~has_choro);
figure(fig);        % set as current figure so usamap draws into it
usamap('conus');
ax = gca;
set(ax, 'Units','normalized', ...
    'Position',[0.02, 0.05+sldr_lift, ax_right, 0.90-sldr_lift]);
mstruct = getm(ax);
setm(ax,'Grid','off','Frame','off', ...
    'MeridianLabel','off','ParallelLabel','off');

% Projected extents in metres; used to auto-place AK/HI insets.
xl = xlim(ax);  yl = ylim(ax);
xr = xl(2)-xl(1);  yr = yl(2)-yl(1);

% Default inset centres (lower-left, in the Pacific area off California).
if any(isnan(options.AKOffset))
    ak_cx = xl(1) + 0.13*xr;
    ak_cy = yl(1) + 0.17*yr;
else
    ak_cx = options.AKOffset(1);
    ak_cy = options.AKOffset(2);
end
if any(isnan(options.HIOffset))
    hi_cx = xl(1) + 0.29*xr;
    hi_cy = yl(1) + 0.10*yr;
else
    hi_cx = options.HIOffset(1);
    hi_cy = options.HIOffset(2);
end

%% ── Load shapes and draw patches ─────────────────────────────────────────────
states = shaperead('usastatelo','UseGeoCoords',true);

shape_lookup = containers.Map('KeyType','char','ValueType','char');
for i = 1:numel(US_NAMES)
    shape_lookup(US_NAMES{i}) = US_CODES{i};
end

hold(ax,'on');
patch_h = containers.Map('KeyType','char','ValueType','any');

for i = 1:numel(states)
    sname = upper(strtrim(states(i).Name));
    if ~isKey(shape_lookup,sname), continue; end
    scode = shape_lookup(sname);
    if ~isKey(code_to_idx,scode), continue; end
    si = code_to_idx(scode);
    fc = um_val2color(Heat(si,1), vmin, vmax, cmap_ch, has_choro);

    [x, y] = mfwdtran(mstruct, states(i).Lat, states(i).Lon);

    if strcmp(scode,'AK')
        % Affine: scale around centroid, shift to inset position.
        cx = mean(x(~isnan(x)));  cy = mean(y(~isnan(y)));
        s  = options.AKScale;
        x  = (x - cx)*s + ak_cx;
        y  = (y - cy)*s + ak_cy;
    elseif strcmp(scode,'HI')
        % Shift only — Hawaii is already a reasonable size.
        cx = mean(x(~isnan(x)));  cy = mean(y(~isnan(y)));
        x  = x - cx + hi_cx;
        y  = y - cy + hi_cy;
    end

    ph = patch(x, y, fc, 'Parent', ax, ...
        'EdgeColor', [0.45 0.45 0.45], 'LineWidth', 0.5, ...
        'UserData', scode);
    patch_h(scode) = ph;
end

%% ── Colorbar ─────────────────────────────────────────────────────────────────
if has_choro
    colormap(ax, cmap_ch);
    clim(ax, [vmin vmax]);
    cb = colorbar(ax,'Position',[0.86, 0.05+sldr_lift, 0.03, 0.90-sldr_lift]);
    cb.Label.String = strrep(char(options.ColorCol),'_',' ');
    cb.FontSize = 8;
end

%% ── Title ────────────────────────────────────────────────────────────────────
title(ax, um_title_str(options.ColorCol, t_vals, 1, is_year_axis, has_choro, has_time), ...
    'FontSize', 11, 'Interpreter','none');

%% ── Slider ───────────────────────────────────────────────────────────────────
sld = []; lbl_ctrl = [];
if has_slider
    sld = uicontrol(fig,'Style','slider','Units','normalized', ...
        'Position',[0.08 0.01 0.76 0.04], ...
        'Min',1,'Max',n_t,'Value',1, ...
        'SliderStep',[1/max(n_t-1,1), max(0.1,5/max(n_t-1,1))]);
    lbl_ctrl = uicontrol(fig,'Style','text','Units','normalized', ...
        'Position',[0.85 0.01 0.13 0.04], ...
        'String', um_yr_str(t_vals,1,is_year_axis), ...
        'FontSize',10,'BackgroundColor',BG,'HorizontalAlignment','left');

    ph_c=patch_h; Heat_c=Heat; vmin_c=vmin; vmax_c=vmax; cmap_c=cmap_ch;
    tvals_c=t_vals; iyr_c=is_year_axis; th_c=ax.Title; cc_c=options.ColorCol;
    ht_c=has_time; hchoro_c=has_choro; ctoi_c=code_to_idx;

    sld.Callback = @(src,~) um_update(src, ph_c, Heat_c, vmin_c, vmax_c, cmap_c, ...
        tvals_c, iyr_c, th_c, lbl_ctrl, cc_c, ht_c, hchoro_c, ctoi_c);
end

%% ── Datacursor ───────────────────────────────────────────────────────────────
dcm = datacursormode(fig);
Heat_dc=Heat; N_dc=N_obs; cn_dc=char(options.ColorCol); sld_dc=sld; ctoi_dc=code_to_idx;
dcm.UpdateFcn = @(~,ev) um_datatip(ev, Heat_dc, N_dc, cn_dc, sld_dc, ctoi_dc);

end % de_usamap


%% ── Local helpers ────────────────────────────────────────────────────────────

function [US_NAMES, US_CODES] = um_us_lookup()
US_NAMES = { ...
    'ALABAMA','ALASKA','ARIZONA','ARKANSAS','CALIFORNIA','COLORADO', ...
    'CONNECTICUT','DELAWARE','FLORIDA','GEORGIA','HAWAII','IDAHO', ...
    'ILLINOIS','INDIANA','IOWA','KANSAS','KENTUCKY','LOUISIANA','MAINE', ...
    'MARYLAND','MASSACHUSETTS','MICHIGAN','MINNESOTA','MISSISSIPPI', ...
    'MISSOURI','MONTANA','NEBRASKA','NEVADA','NEW HAMPSHIRE','NEW JERSEY', ...
    'NEW MEXICO','NEW YORK','NORTH CAROLINA','NORTH DAKOTA','OHIO', ...
    'OKLAHOMA','OREGON','PENNSYLVANIA','RHODE ISLAND','SOUTH CAROLINA', ...
    'SOUTH DAKOTA','TENNESSEE','TEXAS','UTAH','VERMONT','VIRGINIA', ...
    'WASHINGTON','WEST VIRGINIA','WISCONSIN','WYOMING','DISTRICT OF COLUMBIA'};
US_CODES = { ...
    'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN', ...
    'IA','KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV', ...
    'NH','NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN', ...
    'TX','UT','VT','VA','WA','WV','WI','WY','DC'};
end


function cmap = um_cmap(spec)
if ischar(spec) || isstring(spec), cmap = feval(char(spec), 256);
else, cmap = spec; end
end


function fc = um_val2color(val, vmin, vmax, cmap, has_choro)
if ~has_choro || isnan(val)
    fc = [0.88 0.88 0.88];
else
    norm = max(0, min(1, (val-vmin)/(vmax-vmin)));
    ci   = max(1, min(size(cmap,1), floor(norm*size(cmap,1))+1));
    fc   = cmap(ci,:);
end
end


function s = um_title_str(color_col, t_vals, tt, is_year_axis, has_choro, has_time)
if ~has_choro, s = 'U.S. map'; return; end
if has_time && ~isempty(t_vals)
    s = sprintf('mean(%s)  —  %s', char(color_col), um_yr_str(t_vals, tt, is_year_axis));
else
    s = sprintf('mean(%s)', char(color_col));
end
end


function s = um_yr_str(t_vals, tt, is_year_axis)
if is_year_axis, s = sprintf('%g', t_vals(tt));
else, s = char(datetime(t_vals(tt), 'Format','MMM yyyy')); end
end


function um_update(sld, patch_h, Heat, vmin, vmax, cmap, ...
        t_vals, is_year_axis, title_h, lbl_ctrl, color_col, has_time, has_choro, code_to_idx)
tt = round(sld.Value);  sld.Value = tt;
codes = keys(patch_h);
for i = 1:numel(codes)
    scode = codes{i};
    if ~isKey(code_to_idx,scode), continue; end
    si = code_to_idx(scode);
    ph = patch_h(scode);
    if ~isgraphics(ph), continue; end
    set(ph,'FaceColor', um_val2color(Heat(si,tt), vmin, vmax, cmap, has_choro));
end
title_h.String = um_title_str(color_col, t_vals, tt, is_year_axis, has_choro, has_time);
if ~isempty(lbl_ctrl) && isgraphics(lbl_ctrl)
    lbl_ctrl.String = um_yr_str(t_vals, tt, is_year_axis);
end
end


function txt = um_datatip(ev, Heat, N_obs, color_col, sld, code_to_idx)
ud = ev.Target.UserData;
if ~(ischar(ud) || isstring(ud)), txt = ''; return; end
scode = char(ud);
if ~isKey(code_to_idx,scode), txt = scode; return; end
si = code_to_idx(scode);
tt = 1;
if ~isempty(sld) && isgraphics(sld), tt = round(sld.Value); end
val = Heat(si,tt);  n = N_obs(si,tt);
if isnan(val), txt = {scode, sprintf('%s: N/A', color_col)};
else, txt = {scode, sprintf('%s: %.4g  (n=%d)', color_col, val, n)}; end
end
