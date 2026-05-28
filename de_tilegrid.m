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
%   CLim              Fix color axis [lo, hi].  Useful for comparing maps
%                     of the same variable on a common scale.

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
    options.CellRenderer      (1,1) string  = "color"
    options.CatCol            (1,1) string  = ""
    options.TopK              (1,1) double  = 5
    options.SharedYLim        (1,2) double  = [NaN NaN]
    options.CatColors                       = []
    options.XCol              (1,1) string  = ""
    options.YCol              (1,1) string  = ""
    options.SharedXLim        (1,2) double  = [NaN NaN]
    options.CLim              (1,2) double  = [NaN NaN]
end

fig = []; ax = []; %#ok<NASGU>

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
is_heatmap_cat = options.CellRenderer == "heatmap_cat" && ...
    options.CatCol ~= "" && ismember(options.CatCol, varnames) && ...
    options.ColorCol ~= "" && ismember(options.ColorCol, varnames) && ...
    numel(normed) == height(T) && height(T) > 0;
is_scatter_cat = options.CellRenderer == "scatter_cat" && ...
    options.CatCol ~= "" && ismember(options.CatCol, varnames) && ...
    options.XCol ~= "" && ismember(options.XCol, varnames) && ...
    options.YCol ~= "" && ismember(options.YCol, varnames) && ...
    numel(normed) == height(T) && height(T) > 0;

%% ── Time axis ────────────────────────────────────────────────────────────────
t_vals = []; n_t = 1; is_year_axis = false;
if has_time && (has_choro || is_heatmap_cat)
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

non_ov_heat = Heat(~IS_OVERFLOW, :);
vmin = min(non_ov_heat(:), [], 'omitnan');
vmax = max(non_ov_heat(:), [], 'omitnan');
if ~any(isnan(options.CLim))
    vmin = options.CLim(1);
    vmax = options.CLim(2);
end
if isnan(vmin) || vmin == vmax, has_choro = false; end
if is_heatmap_cat || is_scatter_cat, has_choro = false; end

%% ── Multi-category sparkline data ────────────────────────────────────────────
multi_heat = []; top_cat_levels = {};
sh_lo = NaN; sh_hi = NaN; K = 0;
if is_heatmap_cat
    ydata_sc   = double(T.(char(options.ColorCol)));
    if has_time
        tdata_sc = T.(char(options.TimeCol));
        if ~isa(tdata_sc,'datetime'), tdata_sc = double(tdata_sc); end
    end
    cat_col_sc = categorical(string(T.(char(options.CatCol))));
    all_lv     = cellstr(categories(cat_col_sc));
    cnt_lv     = countcats(cat_col_sc);
    [~, ord_lv] = sort(cnt_lv,'descend');
    K           = min(options.TopK, numel(all_lv));
    top_cat_levels = all_lv(ord_lv(1:K));

    multi_heat = NaN(n_tiles, n_t, K);
    for ti = 1:n_tiles
        s_mask = normed == CODES{ti};
        if ~any(s_mask), continue; end
        for ki = 1:K
            k_mask = cat_col_sc == top_cat_levels{ki};
            for tt = 1:n_t
                if has_time
                    v_ki = ydata_sc(s_mask & k_mask & (tdata_sc == t_vals(tt)));
                else
                    v_ki = ydata_sc(s_mask & k_mask);
                end
                v_ki = v_ki(~isnan(v_ki));
                if ~isempty(v_ki), multi_heat(ti,tt,ki) = mean(v_ki); end
            end
        end
    end

    if all(isnan(options.SharedYLim))
        non_ov_mh = multi_heat(~IS_OVERFLOW,:,:);
        sh_lo = min(non_ov_mh(:), [], 'omitnan');
        sh_hi = max(non_ov_mh(:), [], 'omitnan');
    else
        sh_lo = options.SharedYLim(1);
        sh_hi = options.SharedYLim(2);
    end
end

%% ── Scatter cat data ─────────────────────────────────────────────────────────
xdata_sc2 = []; ydata_sc2 = []; cat_col_sc2 = categorical([]);
sh_xlim = [NaN NaN]; K2 = 0; top_cat_levels2 = {}; cat_colors_mat2 = [];
sh_lo2 = NaN; sh_hi2 = NaN;
if is_scatter_cat
    xdata_sc2   = double(T.(char(options.XCol)));
    ydata_sc2   = double(T.(char(options.YCol)));
    cat_col_sc2 = categorical(string(T.(char(options.CatCol))));
    all_lv2     = cellstr(categories(cat_col_sc2));
    cnt_lv2     = countcats(cat_col_sc2);
    [~, ord2]   = sort(cnt_lv2,'descend');
    K2          = min(options.TopK, numel(all_lv2));
    top_cat_levels2 = all_lv2(ord2(1:K2));
    if ~isempty(options.CatColors) && size(options.CatColors,1) >= K2
        cat_colors_mat2 = options.CatColors(1:K2,:);
    else
        cat_colors_mat2 = lines(K2);
    end
    if all(isnan(options.SharedXLim))
        sh_xlim = [min(xdata_sc2,[],'omitnan'), max(xdata_sc2,[],'omitnan')];
    else
        sh_xlim = options.SharedXLim;
    end
    if all(isnan(options.SharedYLim))
        sh_lo2 = min(ydata_sc2,[],'omitnan');
        sh_hi2 = max(ydata_sc2,[],'omitnan');
    else
        sh_lo2 = options.SharedYLim(1);
        sh_hi2 = options.SharedYLim(2);
    end
end

%% ── Figure and axes ──────────────────────────────────────────────────────────
has_spark = has_time && n_t > 1;
BG = [0.97 0.97 0.97];

max_col = max(COLS);
max_row = max(ROWS);
tile_px = 36;
needs_cbar = has_choro || is_heatmap_cat;
fig_w   = min(1600, max(500, round((max_col + 2) * tile_px) + 100 * double(needs_cbar)));
fig_h   = min(1000, max(380, round((max_row + 2) * tile_px)));
fig = figure('Color', BG, 'NumberTitle', 'off');
if ~strcmp(fig.WindowStyle, 'docked')
    fig.Position(3:4) = [fig_w, fig_h];
end
if options.Title ~= "", fig.Name = char(options.Title); end

ax_right = 0.82 + 0.10 * double(~needs_cbar);
ax = axes(fig, 'Units', 'normalized', ...
    'Position', [0.02, 0.04, ax_right, 0.92], ...
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

% When sparklines are drawn, background = mean over all time steps.
if has_spark
    Heat_bg = mean(Heat, 2, 'omitnan');
else
    Heat_bg = Heat(:, 1);
end
lbl_y_frac = 0.50;
if has_spark, lbl_y_frac = 0.28; end
if is_heatmap_cat, lbl_y_frac = 0.10; end

for ti = 1:n_tiles
    r  = ROWS(ti);  c = COLS(ti);
    fc = tg_val2color(Heat_bg(ti), vmin, vmax, cmap_ch, has_choro);
    if IS_OVERFLOW(ti)
        ec = options.OverflowEdgeColor;  lw = 1.5;
    else
        ec = 'none';  lw = 0.5;
    end

    xv = [c+GAP, c+1-GAP, c+1-GAP, c+GAP  ];
    yv = [r+GAP, r+GAP,   r+1-GAP, r+1-GAP];
    patch_h{ti} = patch(ax, xv, yv, fc, 'EdgeColor', ec, 'LineWidth', lw);
    if has_choro && ~isnan(Heat_bg(ti))
        ph = patch_h{ti};
        ph.DataTipTemplate.DataTipRows(1) = dataTipTextRow(char(options.MapLabel), CODES{ti});
        ph.DataTipTemplate.DataTipRows(2) = dataTipTextRow(char(options.ColorCol),  Heat_bg(ti));
        ph.DataTipTemplate.DataTipRows    = ph.DataTipTemplate.DataTipRows(1:2);
    end

    tc  = tg_text_color(fc);
    if has_spark
        lbl = CODES{ti};
    else
        lbl = tg_label(CODES{ti}, Heat(ti,1), has_choro);
    end
    lh  = text(ax, c+0.5, r+lbl_y_frac, lbl, ...
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
    cb = colorbar(ax, 'Position', [0.86, 0.04, 0.03, 0.92]);
    lbl = strrep(char(options.ColorCol), '_', ' ');
    if has_spark
        t1s_cb = tg_yr_str(t_vals, 1, is_year_axis);
        tns_cb = tg_yr_str(t_vals, numel(t_vals), is_year_axis);
        lbl = sprintf('mean(%s, %s – %s)', lbl, t1s_cb, tns_cb);
    end
    cb.Label.String = lbl;
    cb.FontSize = 8;
end

%% ── Title ────────────────────────────────────────────────────────────────────
title(ax, tg_title_str(options.ColorCol, options.MapLabel, ...
    t_vals, is_year_axis, has_choro, has_spark), ...
    'FontSize', 11, 'Interpreter', 'none');

%% ── Sparklines (per-tile time series) ───────────────────────────────────────
if has_spark && has_choro && ~is_heatmap_cat
    tile_h   = 1 - 2*GAP;
    SPARK_MX = 0.10;
    x_ticks  = linspace(0, 1, n_t);
    for ti = 1:n_tiles
        if all(isnan(Heat(ti,:))), continue; end
        r = ROWS(ti);  c = COLS(ti);
        spark_y_top = r + GAP + (1 - 0.28) * tile_h;
        spark_y_bot = r + 1 - GAP - 0.01;
        x_spark = c + GAP + SPARK_MX + x_ticks * (tile_h - 2*SPARK_MX);
        heat_row = Heat(ti, :);
        if vmax > vmin
            norm_h = (heat_row - vmin) / (vmax - vmin);
        else
            norm_h = 0.5 * ones(1, n_t);
        end
        y_spark = spark_y_bot - norm_h * (spark_y_bot - spark_y_top);
        y_spark(isnan(heat_row)) = NaN;
        fc = tg_val2color(Heat_bg(ti), vmin, vmax, cmap_ch, has_choro);
        tc = tg_text_color(fc);
        line(ax, x_spark, y_spark, 'Color', tc, 'LineWidth', 0.8, 'Tag', 'sparkline');
    end
end

%% ── Legend key ───────────────────────────────────────────────────────────────
if has_spark && has_choro && ~is_heatmap_cat
    t1s = tg_yr_str(t_vals, 1, is_year_axis);
    tns = tg_yr_str(t_vals, numel(t_vals), is_year_axis);
    key_str = ['color: mean  |  spark: ' t1s char(8594) tns];
    text(ax, -MARGIN + 0.05, -MARGIN + 0.05, key_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontSize', 6.5, 'Interpreter', 'none', 'Tag', 'legend_key', ...
        'BackgroundColor', [0.91 0.91 0.91], 'EdgeColor', [0.55 0.55 0.55], ...
        'Margin', 3, 'LineWidth', 0.5);
end

%% ── Category heatmap (CellRenderer='heatmap_cat': x=time, y=category, color=value)
if is_heatmap_cat && K > 0 && ~isnan(sh_lo) && sh_lo < sh_hi
    heat_top = GAP + 0.20;
    heat_bot = 1 - GAP;
    cell_h   = (heat_bot - heat_top) / K;
    cell_w   = (1 - 2*GAP) / n_t;
    % Pre-allocate patch arrays (upper bound = all cells)
    Xp = NaN(4, numel(multi_heat));
    Yp = NaN(4, numel(multi_heat));
    Cp = NaN(1, numel(multi_heat));
    idx = 0;
    for ti = 1:n_tiles
        if all(isnan(multi_heat(ti,:,:)), 'all'), continue; end
        r = ROWS(ti);  c = COLS(ti);
        for ki = 1:K
            for tt = 1:n_t
                v = multi_heat(ti, tt, ki);
                if isnan(v), continue; end
                idx = idx + 1;
                x0 = c + GAP + (tt-1)*cell_w;
                y0 = r + heat_top + (ki-1)*cell_h;
                Xp(:, idx) = [x0; x0+cell_w; x0+cell_w; x0];
                Yp(:, idx) = [y0; y0;         y0+cell_h; y0+cell_h];
                Cp(idx)    = v;
            end
        end
    end
    if idx > 0
        patch(ax, Xp(:,1:idx), Yp(:,1:idx), Cp(1:idx), ...
            'EdgeColor','none', 'FaceColor','flat', 'Tag','cat_heat');
        colormap(ax, cmap_ch);
        clim(ax, [sh_lo sh_hi]);
        cb = colorbar(ax, 'Position', [0.86, 0.04, 0.03, 0.92]);
        val_lbl = strrep(char(options.ColorCol), '_', ' ');
        if n_t > 1
            cb.Label.String = sprintf('mean(%s, %s%s%s)', val_lbl, ...
                tg_yr_str(t_vals, 1, is_year_axis), char(8211), ...
                tg_yr_str(t_vals, numel(t_vals), is_year_axis));
        else
            cb.Label.String = val_lbl;
        end
        cb.FontSize = 8;
        key_lines = [{'rows:'}, arrayfun(@(k) sprintf('%d  %s', k, top_cat_levels{k}), ...
            (1:K)', 'UniformOutput', false)'];
        cat_key = strjoin(key_lines, newline);
        text(ax, -MARGIN+0.05, -MARGIN+0.1, cat_key, ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
            'FontSize', 5.5, 'Interpreter', 'none', 'Tag', 'cat_legend', ...
            'BackgroundColor', [0.91 0.91 0.91], 'EdgeColor', [0.55 0.55 0.55], ...
            'Margin', 3, 'LineWidth', 0.5);
    end
end

%% ── Category scatter (CellRenderer='scatter_cat') ────────────────────────────
if is_scatter_cat && (K2 == 0 || isnan(sh_lo2) || sh_lo2 >= sh_hi2 || ...
        isnan(sh_xlim(1)) || sh_xlim(1) >= sh_xlim(2))
    fprintf('  ℹ de_tilegrid scatter_cat: skipped (constant or empty x/y range).\n');
end
if is_scatter_cat && K2 > 0 && ~isnan(sh_lo2) && sh_lo2 < sh_hi2 && ...
        ~isnan(sh_xlim(1)) && sh_xlim(1) < sh_xlim(2)
    tile_w = 1 - 2*GAP;
    for ti = 1:n_tiles
        s_mask = normed == CODES{ti};
        if ~any(s_mask), continue; end
        r = ROWS(ti);  c = COLS(ti);
        for ki = 1:K2
            k_mask = cat_col_sc2 == top_cat_levels2{ki};
            pts = s_mask & k_mask & ~isnan(xdata_sc2) & ~isnan(ydata_sc2);
            if ~any(pts), continue; end
            xn = (xdata_sc2(pts) - sh_xlim(1)) / (sh_xlim(2) - sh_xlim(1));
            yn = (ydata_sc2(pts) - sh_lo2)      / (sh_hi2 - sh_lo2);
            x_plot = c + GAP + xn * tile_w;
            y_plot = r + GAP + (1 - yn) * tile_w;
            line(ax, x_plot, y_plot, 'Color', cat_colors_mat2(ki,:), ...
                'LineStyle','none', 'Marker','.', 'MarkerSize', 4, ...
                'Tag', 'cat_scatter');
        end
    end
    leg_h2 = gobjects(K2,1);
    for ki = 1:K2
        leg_h2(ki) = line(nan, nan, 'Parent', ax, ...
            'Color', cat_colors_mat2(ki,:), 'LineWidth', 1.5, ...
            'DisplayName', top_cat_levels2{ki}, ...
            'LineStyle','none', 'Marker','.');
    end
    legend(leg_h2, 'Location','southeast', 'FontSize',6, 'Interpreter','none');
end

%% ── Datacursor ───────────────────────────────────────────────────────────────
dcm = datacursormode(fig);
Heat_dc=Heat; N_dc=N_obs; cn_dc=char(options.ColorCol); hs_dc=has_spark;
dcm.UpdateFcn = @(~,ev) tg_datatip(ev, Heat_dc, N_dc, cn_dc, hs_dc, code_map);

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

function s = tg_title_str(color_col, map_label, t_vals, is_year_axis, has_choro, has_spark)
if ~has_choro, s = char(map_label); return; end
if has_spark && numel(t_vals) >= 2
    t1 = tg_yr_str(t_vals, 1, is_year_axis);
    tn = tg_yr_str(t_vals, numel(t_vals), is_year_axis);
    s = sprintf('mean(%s)  —  %s to %s', char(color_col), t1, tn);
else
    s = sprintf('mean(%s)', char(color_col));
end
end

function s = tg_yr_str(t_vals, tt, is_year_axis)
if is_year_axis, s = sprintf('%g', t_vals(tt));
else, s = char(datetime(t_vals(tt), 'Format', 'MMM yyyy')); end
end

function txt = tg_datatip(ev, Heat, N_obs, color_col, has_spark, code_map)
ud = ev.Target.UserData;
if ~(ischar(ud) || isstring(ud)), txt = ''; return; end
code = char(ud);
if ~isKey(code_map, code), txt = code; return; end
ti = code_map(code);
if has_spark
    val = mean(Heat(ti,:), 'omitnan');
    n   = sum(N_obs(ti,:));
else
    val = Heat(ti,1);  n = N_obs(ti,1);
end
if isnan(val), txt = {code, sprintf('%s: N/A', color_col)};
else, txt = {code, sprintf('%s: %.4g  (n=%d)', color_col, val, n)}; end
end
