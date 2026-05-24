function [fig, ax] = de_tilegrid(T, grid, normed, options)
%DE_TILEGRID  Generic tile-grid choropleth — shared rendering engine.
%   Called by de_statebins and de_countrybins.  You can also call it
%   directly with a fully custom grid layout.
%
%   Usage
%   ─────
%   g.codes      = {'ME','NY','CA',...};
%   g.rows       = [0, 2, 4,...];           % 0-indexed row positions
%   g.cols       = [11, 9, 1,...];          % 0-indexed col positions
%   g.is_overflow = false(numel(g.codes),1); % true = orphan tiles
%   normed = string(T.StateCode);           % pre-normalised code column
%   de_tilegrid(T, g, normed, 'ColorCol','Value', 'TimeCol','Year')
%
%   Arguments
%   ─────────
%   T      table (height must match length of normed)
%   grid   struct with fields: codes (cell), rows, cols, is_overflow
%   normed (:,1) string — normalized tile codes, same length as T
%
%   Name-value options
%   ──────────────────
%   ColorCol          numeric column for tile fill
%   TimeCol           time axis → slider
%   Title             figure / window title
%   Colormap          colormap name or Nx3 matrix (default 'parula')
%   OverflowEdgeColor RGB for orphan tile border (default amber)
%   MapLabel          axes title when no color data (default 'Map')
%   FontSize          tile label font size (default 7)

arguments
    T      (:,:) table
    grid   (1,1) struct
    normed (:,1) string
    options.ColorCol          (1,1) string  = ""
    options.TimeCol           (1,1) string  = ""
    options.Title             (1,1) string  = ""
    options.Colormap                        = 'parula'
    options.OverflowEdgeColor (1,3) double  = [0.75 0.40 0.05]
    options.MapLabel          (1,1) string  = "Map"
    options.FontSize          (1,1) double  = 7
end

fig = []; ax = [];

CODES       = grid.codes(:);
ROWS        = double(grid.rows(:));
COLS        = double(grid.cols(:));
IS_OVERFLOW = logical(grid.is_overflow(:));
n_tiles     = numel(CODES);

code_map = containers.Map(CODES, num2cell(1:n_tiles));

%% ── Validate columns ─────────────────────────────────────────────────────────
varnames  = string(T.Properties.VariableNames);
has_color = options.ColorCol ~= "" && ismember(options.ColorCol, varnames);
has_time  = options.TimeCol  ~= "" && ismember(options.TimeCol,  varnames);
has_choro = has_color && numel(normed) == height(T) && height(T) > 0;

%% ── Time axis ────────────────────────────────────────────────────────────────
t_vals = []; n_t = 1; is_year_axis = false;
if has_time && has_choro
    tdata = T.(char(options.TimeCol));
    if isa(tdata, 'datetime')
        t_vals = unique(tdata(~isnat(tdata)));
    else
        t_vals = unique(double(tdata(~isnan(double(tdata)))));
        is_year_axis = true;
    end
    n_t = numel(t_vals);
    if n_t == 0, has_time = false; t_vals = []; n_t = 1; end
end

%% ── Build heat matrix ────────────────────────────────────────────────────────
cmap_ch = tg_cmap(options.Colormap);
Heat    = NaN(n_tiles, n_t);
N_obs   = zeros(n_tiles, n_t);

if has_choro
    ydata = double(T.(char(options.ColorCol)));
    tdata_col = [];
    if has_time
        tdata_col = T.(char(options.TimeCol));
        if ~isa(tdata_col, 'datetime'), tdata_col = double(tdata_col); end
    end
    for ti = 1:n_tiles
        s_mask = normed == CODES{ti};
        if ~any(s_mask), continue; end
        for tt = 1:n_t
            if has_time
                vals = ydata(s_mask & (tdata_col == t_vals(tt)));
            else
                vals = ydata(s_mask);
            end
            vals = vals(~isnan(vals));
            if ~isempty(vals)
                Heat(ti, tt)  = mean(vals);
                N_obs(ti, tt) = numel(vals);
            end
        end
    end
end

vmin = min(Heat(:), [], 'omitnan');
vmax = max(Heat(:), [], 'omitnan');
if isnan(vmin) || vmin == vmax, has_choro = false; end

%% ── Figure and axes ──────────────────────────────────────────────────────────
has_slider = has_time && n_t > 1;
sldr_lift  = 0.07 * double(has_slider);
BG = [0.97 0.97 0.97];

max_col = max(COLS);
max_row = max(ROWS);
aspect  = (max_col + 2) / (max_row + 2);
if aspect >= 1.2
    fig_pos = [0.02 0.04 0.96 0.90];
elseif aspect >= 0.8
    fig_pos = [0.05 0.05 0.88 0.85];
else
    fig_pos = [0.10 0.04 0.70 0.90];
end

fig = figure('Color', BG, 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', fig_pos);
if options.Title ~= "", fig.Name = char(options.Title); end

ax_right = 0.82 + 0.10 * double(~has_choro);
ax = axes(fig, 'Units', 'normalized', ...
    'Position', [0.02, 0.04+sldr_lift, ax_right, 0.92-sldr_lift], ...
    'Color', BG, 'XColor', 'none', 'YColor', 'none', 'Box', 'off');
hold(ax, 'on');

MARGIN = 0.5;
set(ax, 'XLim', [-MARGIN, double(max_col)+1+MARGIN], ...
        'YLim', [-MARGIN, double(max_row)+1+MARGIN], 'YDir', 'reverse');

%% ── Draw tiles ───────────────────────────────────────────────────────────────
GAP     = 0.06;
fs      = options.FontSize;
patch_h = cell(n_tiles, 1);
label_h = cell(n_tiles, 1);

for ti = 1:n_tiles
    r  = ROWS(ti);  c = COLS(ti);
    fc = tg_val2color(Heat(ti,1), vmin, vmax, cmap_ch, has_choro);
    if IS_OVERFLOW(ti)
        ec = options.OverflowEdgeColor;  lw = 1.5;
    else
        ec = 'none';  lw = 0.5;
    end

    xv = [c+GAP, c+1-GAP, c+1-GAP, c+GAP  ];
    yv = [r+GAP, r+GAP,   r+1-GAP, r+1-GAP];
    patch_h{ti} = patch(ax, xv, yv, fc, 'EdgeColor', ec, 'LineWidth', lw);

    tc  = tg_text_color(fc);
    lbl = tg_label(CODES{ti}, Heat(ti,1), has_choro);
    lh  = text(ax, c+0.5, r+0.5, lbl, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', fs, 'FontWeight', 'bold', 'Color', tc, ...
        'Interpreter', 'none', 'UserData', CODES{ti});
    label_h{ti} = lh;
end

n_ov = sum(IS_OVERFLOW);
if n_ov > 0
    ov_row = min(ROWS(IS_OVERFLOW));
    text(ax, -0.3, ov_row+0.5, '?', 'FontSize', 9, 'FontWeight', 'bold', ...
        'Color', options.OverflowEdgeColor, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end

%% ── Colorbar ─────────────────────────────────────────────────────────────────
if has_choro
    colormap(ax, cmap_ch);
    clim(ax, [vmin vmax]);
    cb = colorbar(ax, 'Position', [0.86, 0.04+sldr_lift, 0.03, 0.92-sldr_lift]);
    cb.Label.String = strrep(char(options.ColorCol), '_', ' ');
    cb.FontSize = 8;
end

%% ── Title ────────────────────────────────────────────────────────────────────
title(ax, tg_title_str(options.ColorCol, options.MapLabel, ...
    t_vals, 1, is_year_axis, has_choro, has_time), ...
    'FontSize', 11, 'Interpreter', 'none');

%% ── Slider ───────────────────────────────────────────────────────────────────
sld = []; lbl_ctrl = [];
if has_slider
    sld = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.08 0.01 0.76 0.04], ...
        'Min', 1, 'Max', n_t, 'Value', 1, ...
        'SliderStep', [1/max(n_t-1,1), max(0.1, 5/max(n_t-1,1))]);
    lbl_ctrl = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.85 0.01 0.13 0.04], ...
        'String', tg_yr_str(t_vals, 1, is_year_axis), ...
        'FontSize', 10, 'BackgroundColor', BG, 'HorizontalAlignment', 'left');

    ph_c=patch_h; lh_c=label_h; Heat_c=Heat;
    vmin_c=vmin; vmax_c=vmax; cmap_c=cmap_ch;
    tvals_c=t_vals; iyr_c=is_year_axis;
    th_c=ax.Title; cc_c=options.ColorCol;
    ht_c=has_time; hchoro_c=has_choro; ml_c=options.MapLabel;

    sld.Callback = @(src,~) tg_update(src, ph_c, lh_c, Heat_c, ...
        vmin_c, vmax_c, cmap_c, tvals_c, iyr_c, th_c, lbl_ctrl, ...
        cc_c, ht_c, hchoro_c, ml_c);
end

%% ── Datacursor ───────────────────────────────────────────────────────────────
dcm = datacursormode(fig);
Heat_dc=Heat; N_dc=N_obs; cn_dc=char(options.ColorCol); sld_dc=sld;
dcm.UpdateFcn = @(~,ev) tg_datatip(ev, Heat_dc, N_dc, cn_dc, sld_dc, code_map);

end % de_tilegrid


%% ── Local helpers ────────────────────────────────────────────────────────────

function cmap = tg_cmap(spec)
if ischar(spec) || isstring(spec), cmap = feval(char(spec), 256);
else, cmap = spec; end
end

function fc = tg_val2color(val, vmin, vmax, cmap, has_choro)
if ~has_choro || isnan(val)
    fc = [0.88 0.88 0.88];
else
    norm = max(0, min(1, (val-vmin)/(vmax-vmin)));
    ci   = max(1, min(size(cmap,1), floor(norm*size(cmap,1))+1));
    fc   = cmap(ci,:);
end
end

function tc = tg_text_color(bgc)
if 0.299*bgc(1)+0.587*bgc(2)+0.114*bgc(3) < 0.45, tc=[1 1 1];
else, tc=[0.08 0.08 0.08]; end
end

function s = tg_label(code, val, has_choro)
if ~has_choro || isnan(val), s = code;
else, s = sprintf('%s\n%.3g', code, val); end
end

function s = tg_title_str(color_col, map_label, t_vals, tt, is_year_axis, has_choro, has_time)
if ~has_choro, s = char(map_label); return; end
if has_time && ~isempty(t_vals)
    s = sprintf('mean(%s)  —  %s', char(color_col), tg_yr_str(t_vals, tt, is_year_axis));
else
    s = sprintf('mean(%s)', char(color_col));
end
end

function s = tg_yr_str(t_vals, tt, is_year_axis)
if is_year_axis, s = sprintf('%g', t_vals(tt));
else, s = char(datetime(t_vals(tt), 'Format', 'MMM yyyy')); end
end

function tg_update(sld, patch_h, label_h, Heat, vmin, vmax, cmap, ...
        t_vals, is_year_axis, title_h, lbl_ctrl, color_col, has_time, has_choro, map_label)
tt = round(sld.Value);  sld.Value = tt;
for ti = 1:numel(patch_h)
    if isempty(patch_h{ti}) || ~isgraphics(patch_h{ti}), continue; end
    fc = tg_val2color(Heat(ti,tt), vmin, vmax, cmap, has_choro);
    set(patch_h{ti}, 'FaceColor', fc);
    if ~isempty(label_h{ti}) && isgraphics(label_h{ti})
        label_h{ti}.String = tg_label(label_h{ti}.UserData, Heat(ti,tt), has_choro);
        label_h{ti}.Color  = tg_text_color(fc);
    end
end
title_h.String = tg_title_str(color_col, map_label, t_vals, tt, is_year_axis, has_choro, has_time);
if ~isempty(lbl_ctrl) && isgraphics(lbl_ctrl)
    lbl_ctrl.String = tg_yr_str(t_vals, tt, is_year_axis);
end
end

function txt = tg_datatip(ev, Heat, N_obs, color_col, sld, code_map)
ud = ev.Target.UserData;
if ~(ischar(ud) || isstring(ud)), txt = ''; return; end
code = char(ud);
if ~isKey(code_map, code), txt = code; return; end
ti = code_map(code);
tt = 1;
if ~isempty(sld) && isgraphics(sld), tt = round(sld.Value); end
val = Heat(ti,tt);  n = N_obs(ti,tt);
if isnan(val), txt = {code, sprintf('%s: N/A', color_col)};
else, txt = {code, sprintf('%s: %.4g  (n=%d)', color_col, val, n)}; end
end
