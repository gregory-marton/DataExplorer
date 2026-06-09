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
%   Name-value options (see the arguments block for the full set)
%   ──────────────────
%   ColorCol          numeric column for tile fill
%   TimeCol           time axis — drawn as a per-tile heatmap x-axis or sparkline
%                     (never a slider)
%   CellRenderer      'color' (default) | 'heatmap_cat' | 'scatter_cat' | 'value_ladder'
%   CatCol            categorical for heatmap_cat / scatter_cat
%   ValueCols         value_ladder: numeric columns drawn as per-tile bars
%   Scale             'auto' | 'log' | 'linear' — color / bar quantitative axis
%   ConfoundNote      small red caveat drawn in the figure body
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
    options.CellRenderer      (1,1) string {mustBeMember(options.CellRenderer, ["color","heatmap_cat","scatter_cat","value_ladder"])} = "color"
    options.CatCol            (1,1) string  = ""
    options.TopK              (1,1) double {mustBePositive} = 5
    options.SharedYLim        (1,2) double {de__must_be_range} = [NaN NaN]
    options.CatColors                       = []
    options.XCol              (1,1) string  = ""
    options.YCol              (1,1) string  = ""
    options.SharedXLim        (1,2) double {de__must_be_range} = [NaN NaN]
    options.CLim              (1,2) double {de__must_be_range} = [NaN NaN]
    options.ValueCols         (1,:) string  = string([])  % CellRenderer="value_ladder"
    options.LegendNote        (1,1) string  = ""
    options.ConfoundNote      (1,1) string  = ""      % small red in-figure caveat
    options.Scale             (1,1) string {mustBeMember(options.Scale, ["auto","log","linear"])} = "auto"   % color axis (choropleth) or bar axis (value_ladder)
    options.ColorMethod       (1,1) string {mustBeMember(options.ColorMethod, ["mean","count","median","sum"])} = "mean"   % per-tile aggregation
end

F                 = de__font_sizes(options.FontSize);  % F.subtitle=cbar, F.axlabel=overflow, F.page=title
mname             = char(options.ColorMethod);         % per-tile aggregation (mean/count/median/sum)
TILE_PX           = 36;
FIG_W_MIN         = 500;   FIG_W_MAX = 1600;
FIG_H_MIN         = 380;   FIG_H_MAX = 1000;
CBAR_X            = 0.86;  CBAR_W   = 0.03;
FSZ_LEGEND        = 6.5;   FSZ_CATLEGEND = 5.5;  % non-integer; stay local
LBL_Y_SPARK       = 0.12;  LBL_Y_CAT = 0.10;   % label near the top; data fills below
CLR_LEGEND_BG     = [0.91 0.91 0.91];
CLR_LEGEND_BORDER = [0.55 0.55 0.55];
BG_GRAY           = [0.97 0.97 0.97];

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
val_cols       = options.ValueCols(ismember(options.ValueCols, varnames));
is_value_ladder = options.CellRenderer == "value_ladder" && ...
    numel(val_cols) >= 2 && numel(normed) == height(T) && height(T) > 0;

%% ── Complain about options the active renderer can't use (Plan A) ─────────────
% A typo'd / invalid value is already rejected by the arguments block (Plan D);
% here we warn when a *valid* option simply isn't used by the active renderer, or
% when value_ladder silently falls back for lack of columns.
if options.CellRenderer == "value_ladder" && ~is_value_ladder
    warning('de_tilegrid:valueLadderNeeds2', ...
        ['CellRenderer="value_ladder" needs >=2 ValueCols present in the table ' ...
         '(got %d); drawing a plain map instead.'], numel(val_cols));
else
    if is_value_ladder
        tg_active = "value_ladder"; tg_consumed = ["ValueCols", "SharedYLim", "ColorCol"];
    elseif is_heatmap_cat
        tg_active = "heatmap_cat";  tg_consumed = ["CatCol", "ColorCol", "TimeCol", "SharedYLim"];
    elseif is_scatter_cat
        tg_active = "scatter_cat";  tg_consumed = ["CatCol", "XCol", "YCol", "SharedXLim", "SharedYLim", "CatColors"];
    else
        tg_active = "color";        tg_consumed = ["ColorCol", "TimeCol"];
    end
    tg_ig = tg_ignored_options(options, tg_consumed);
    if ~isempty(tg_ig)
        warning('de_tilegrid:ignoredOptions', 'CellRenderer="%s" ignores: %s', ...
            tg_active, strjoin(cellstr(tg_ig), ', '));
    end
end

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
                Heat(ti, tt)  = tg_agg(vals, mname);
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
if is_heatmap_cat || is_scatter_cat, has_choro = false; end   % value_ladder may keep a ColorCol tile fill (B2)

% Log color scale.  Policy: callers (the recipe) pass Scale "log"/"linear" based on
% the column's profiled skewness; "auto" falls back to a skewness test on the tile
% values.  Mechanism: non-negative data with zeros is supported by flooring zeros a
% decade below the smallest positive value, so counts (which have zero means) still
% render on a log scale instead of being blocked.
use_log_color = false;
if has_choro && any(isnan(options.CLim))
    hv  = Heat(~IS_OVERFLOW, :);
    hv  = hv(isfinite(hv));
    pos = hv(hv > 0);
    nonneg = ~isempty(hv) && all(hv >= 0) && ~isempty(pos);
    switch lower(options.Scale)
        case "log",    use_log_color = nonneg;
        case "linear", use_log_color = false;
        otherwise   % "auto"
            use_log_color = nonneg && ...
                (max(pos)/min(pos) > 100 || (tg_skewness(hv) > 1.5 && max(pos)/min(pos) > 5));
    end
end
if use_log_color
    floor_v = min(pos) / 10;        % zeros / non-positives map a decade below
    Heat(Heat <= 0) = floor_v;
    Heat = log10(Heat);
    vmin = log10(floor_v);
    vmax = log10(max(pos));
end

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
                if ~isempty(v_ki), multi_heat(ti,tt,ki) = tg_agg(v_ki, mname); end
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

%% ── Value-ladder data (CellRenderer='value_ladder') ──────────────────────────
% Per tile: mean of each family member, drawn as a sparkline across the members
% on a y-scale shared by every tile (so heights compare across patches).
ladder = []; lad_lo = NaN; lad_hi = NaN; K_lad = 0; use_log_ladder = false;
if is_value_ladder
    K_lad  = numel(val_cols);
    ladder = NaN(n_tiles, K_lad);
    for ti = 1:n_tiles
        s_mask = normed == CODES{ti};
        if ~any(s_mask), continue; end
        for ki = 1:K_lad
            v = double(T.(char(val_cols(ki))));
            v = v(s_mask); v = v(~isnan(v));
            if ~isempty(v), ladder(ti, ki) = tg_agg(v, mname); end
        end
    end
    non_ov_lad = ladder(~IS_OVERFLOW, :);
    if all(isnan(options.SharedYLim))
        lad_lo = min(non_ov_lad(:), [], 'omitnan');
        lad_hi = max(non_ov_lad(:), [], 'omitnan');
        % Scale: "log" forces it, "linear" forbids it, "auto" logs when values
        % are non-negative and right-skewed (one outlier would otherwise flatten
        % every other tile).  Log requires non-negative data with positives.
        posl = non_ov_lad(non_ov_lad > 0 & isfinite(non_ov_lad));
        finl = non_ov_lad(isfinite(non_ov_lad));
        nonneg_ok = ~isempty(posl) && all(finl >= 0);
        switch lower(options.Scale)
            case "log",    want_log = nonneg_ok;
            case "linear", want_log = false;
            otherwise,     want_log = nonneg_ok && ...
                (max(posl)/min(posl) > 100 || (tg_skewness(finl) > 1.5 && max(posl)/min(posl) > 5));
        end
        if want_log
            use_log_ladder = true;
            lad_floor = min(posl) / 10;        % zeros / tiny values floored a decade below
            ladder(ladder <= 0) = lad_floor;
            ladder = log10(ladder);
            lad_lo = log10(lad_floor);
            lad_hi = log10(max(posl));
        end
    else
        lad_lo = options.SharedYLim(1);
        lad_hi = options.SharedYLim(2);
    end
end

%% ── Figure and axes ──────────────────────────────────────────────────────────
has_spark = has_time && n_t > 1;

max_col = max(COLS);
max_row = max(ROWS);
needs_cbar = has_choro || is_heatmap_cat;
fig_w   = min(FIG_W_MAX, max(FIG_W_MIN, round((max_col + 2) * TILE_PX) + 100 * double(needs_cbar)));
fig_h   = min(FIG_H_MAX, max(FIG_H_MIN, round((max_row + 2) * TILE_PX)));
fig = figure('Color', BG_GRAY, 'NumberTitle', 'off');
if ~strcmp(fig.WindowStyle, 'docked')
    fig.Position(3:4) = [fig_w, fig_h];
end
if options.Title ~= "", fig.Name = char(options.Title); end

ax_right = 0.82 + 0.10 * double(~needs_cbar);
ax = axes(fig, 'Units', 'normalized', ...
    'Position', [0.02, 0.04, ax_right, 0.92], ...
    'Color', BG_GRAY, 'XColor', 'none', 'YColor', 'none', 'Box', 'off');
hold(ax, 'on');

MARGIN = 0.5;
set(ax, 'XLim', [-MARGIN, double(max_col)+1+MARGIN], ...
        'YLim', [-MARGIN, double(max_row)+1+MARGIN], 'YDir', 'reverse');

%% ── Draw tiles ───────────────────────────────────────────────────────────────
GAP = 0.06;
fs  = F.base;
patch_h = cell(n_tiles, 1);
label_h = cell(n_tiles, 1);

% When sparklines are drawn, background = mean over all time steps.
if has_spark
    Heat_bg = mean(Heat, 2, 'omitnan');
else
    Heat_bg = Heat(:, 1);
end
lbl_y_frac = 0.50;
if has_spark, lbl_y_frac = LBL_Y_SPARK; end
if is_heatmap_cat, lbl_y_frac = LBL_Y_CAT; end
if is_value_ladder, lbl_y_frac = LBL_Y_SPARK; end

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
    text(ax, -0.3, ov_row+0.5, '?', 'FontSize', F.axlabel, 'FontWeight', 'bold', ...
        'Color', options.OverflowEdgeColor, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end

%% ── Colorbar ─────────────────────────────────────────────────────────────────
if has_choro
    colormap(ax, cmap_ch);
    clim(ax, [vmin vmax]);
    cb = colorbar(ax, 'Position', [CBAR_X, 0.04, CBAR_W, 0.92]);
    lbl = strrep(char(options.ColorCol), '_', ' ');
    if has_spark
        t1s_cb = tg_yr_str(t_vals, 1, is_year_axis);
        tns_cb = tg_yr_str(t_vals, numel(t_vals), is_year_axis);
        lbl = sprintf('%s(%s, %s – %s)', mname, lbl, t1s_cb, tns_cb);
    else
        lbl = sprintf('%s(%s)', mname, lbl);
    end
    if use_log_color
        lbl = [lbl ' (log scale)'];
        % Set tick labels at round powers of 10 within [vmin, vmax]
        pow10 = ceil(vmin):floor(vmax);
        if numel(pow10) >= 2
            cb.Ticks     = pow10;
            cb.TickLabels = arrayfun(@(p) num2str(10^p,'%.4g'), pow10, ...
                'UniformOutput', false);
        end
    end
    cb.Label.String = lbl;
    cb.FontSize = F.subtitle;
end

%% ── Title ────────────────────────────────────────────────────────────────────
title(ax, tg_title_str(mname, options.ColorCol, options.MapLabel, ...
    t_vals, is_year_axis, has_choro, has_spark), ...
    'FontSize', F.page, 'Interpreter', 'none');

% Confound caveat: small red note in the bottom margin (the plot is still shown;
% it just warns that a per-region mean mixes sub-populations).
if strlength(options.ConfoundNote) > 0
    annotation(fig, 'textbox', [0.02 0.005 0.96 0.045], ...
        'String', "! " + options.ConfoundNote, ...
        'Color', [0.75 0 0], 'FontSize', F.subtitle, 'FontWeight', 'bold', ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', 'Interpreter', 'none', 'Tag', 'confound_note', ...
        'FitBoxToText', 'off');
end

%% ── Sparklines (per-tile time series) ───────────────────────────────────────
if has_spark && has_choro && ~is_heatmap_cat && ~is_value_ladder
    tile_h   = 1 - 2*GAP;
    SPARK_MX = 0.10;
    x_ticks  = linspace(0, 1, n_t);
    for ti = 1:n_tiles
        if all(isnan(Heat(ti,:))), continue; end
        r = ROWS(ti);  c = COLS(ti);
        spark_y_top = r + lbl_y_frac + 0.06;   % fill up to just below the label
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
if has_spark && has_choro && ~is_heatmap_cat && ~is_value_ladder
    t1s = tg_yr_str(t_vals, 1, is_year_axis);
    tns = tg_yr_str(t_vals, numel(t_vals), is_year_axis);
    tcn = strrep(char(options.TimeCol), '_', ' ');
    key_str = ['color: ' mname '  |  spark x = ' tcn ': ' t1s char(8594) tns];
    text(ax, -MARGIN + 0.05, -MARGIN + 0.05, key_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontSize', FSZ_LEGEND, 'Interpreter', 'none', 'Tag', 'legend_key', ...
        'BackgroundColor', CLR_LEGEND_BG, 'EdgeColor', CLR_LEGEND_BORDER, ...
        'Margin', 3, 'LineWidth', 0.5);
end

%% ── Value ladder (CellRenderer='value_ladder': per-tile colored bars per member)
if is_value_ladder && K_lad > 0 && ~isnan(lad_lo) && lad_hi > lad_lo
    tile_h  = 1 - 2*GAP;
    BAR_MX  = 0.08;
    cmap_lad = lines(K_lad);
    inner_w = tile_h - 2*BAR_MX;
    bw      = inner_w / K_lad;
    if use_log_ladder
        base_lo = lad_lo;                     % log scale: baseline at the floor
    else
        base_lo = min(lad_lo, 0);             % linear: bars grow from 0 (or below if neg)
    end
    leg_h   = gobjects(1, K_lad);             % one handle per member for the legend
    for ti = 1:n_tiles
        if all(isnan(ladder(ti,:))), continue; end
        r = ROWS(ti);  c = COLS(ti);
        bar_top = r + lbl_y_frac + 0.06;   % full bars rise to just under the label
        bar_bot = r + 1 - GAP - 0.01;      % baseline near the bottom of the tile
        for ki = 1:K_lad
            v = ladder(ti, ki);
            if isnan(v), continue; end
            norm_h = (v - base_lo) / (lad_hi - base_lo);
            norm_h = max(0, min(1, norm_h));
            x0 = c + GAP + BAR_MX + (ki-1)*bw;
            y_top = bar_bot - norm_h * (bar_bot - bar_top);
            ph = patch(ax, [x0 x0+bw*0.85 x0+bw*0.85 x0], ...
                [bar_bot bar_bot y_top y_top], cmap_lad(ki,:), ...
                'EdgeColor', 'none', 'Tag', 'value_ladder');
            if ~isgraphics(leg_h(ki)), leg_h(ki) = ph; end
        end
    end

    % Vertical scale: a labeled y-axis on each leftmost-column tile, aligned with
    % the bars (the scale is shared across all tiles).  Ticks/labels sit in the
    % left margin (nothing is left of the leftmost column).
    min_col = min(COLS(~IS_OVERFLOW));
    if use_log_ladder
        p0 = ceil(lad_lo);  p1 = floor(lad_hi);
        if p1 >= p0, tick_t = p0:p1; else, tick_t = [lad_lo, lad_hi]; end
        tick_v = 10 .^ tick_t;
    else
        tick_t = linspace(base_lo, lad_hi, 3);
        tick_v = tick_t;
    end
    for ti = 1:n_tiles
        if IS_OVERFLOW(ti) || COLS(ti) ~= min_col || all(isnan(ladder(ti,:))), continue; end
        r = ROWS(ti);
        bar_top = r + lbl_y_frac + 0.06;
        bar_bot = r + 1 - GAP - 0.01;
        ax_x    = min_col + GAP;          % left edge of the tile interior
        line(ax, [ax_x ax_x], [bar_bot bar_top], 'Color', [0.4 0.4 0.4], ...
            'LineWidth', 0.5, 'Tag', 'ladder_axis');
        for tk = 1:numel(tick_t)
            nh = (tick_t(tk) - base_lo) / (lad_hi - base_lo);
            if nh < -1e-3 || nh > 1 + 1e-3, continue; end
            yt = bar_bot - nh * (bar_bot - bar_top);
            line(ax, [ax_x-0.05 ax_x], [yt yt], 'Color', [0.4 0.4 0.4], ...
                'LineWidth', 0.5, 'Tag', 'ladder_axis');
            text(ax, ax_x-0.07, yt, tg_fmt_tick(tick_v(tk)), ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
                'FontSize', FSZ_LEGEND, 'Color', [0.3 0.3 0.3], 'Tag', 'ladder_axis');
        end
    end

    % Color legend (member → color), at subtitle font size
    valid = isgraphics(leg_h);
    if any(valid)
        lg = legend(ax, leg_h(valid), cellstr(val_cols(valid)), ...
            'Location', 'eastoutside', 'FontSize', F.subtitle, ...
            'Interpreter', 'none', 'Box', 'off');
        % Legend title doubles as the vertical scale: the value range a full bar
        % spans (un-logged), plus log/omission notes.
        if use_log_ladder
            note = sprintf('bar height: %.3g to %.3g (log)', 10^base_lo, 10^lad_hi);
        else
            note = sprintf('bar height: %.3g to %.3g', base_lo, lad_hi);
        end
        if options.LegendNote ~= ""
            note = note + "  |  " + options.LegendNote;
        end
        lg.Title.String = char(note);
        lg.Title.FontSize = FSZ_LEGEND;
    end
end

%% ── Category heatmap (CellRenderer='heatmap_cat': x=time, y=category, color=value)
if is_heatmap_cat && K > 0 && ~isnan(sh_lo) && sh_lo < sh_hi
    heat_top = lbl_y_frac + 0.08;   % fill up to just below the label
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
        cb = colorbar(ax, 'Position', [CBAR_X, 0.04, CBAR_W, 0.92]);
        val_lbl = strrep(char(options.ColorCol), '_', ' ');
        if n_t > 1
            cb.Label.String = sprintf('%s(%s, %s%s%s)', mname, val_lbl, ...
                tg_yr_str(t_vals, 1, is_year_axis), char(8211), ...
                tg_yr_str(t_vals, numel(t_vals), is_year_axis));
        else
            cb.Label.String = val_lbl;
        end
        cb.FontSize = F.subtitle;
        key_lines = [{'rows:'}, arrayfun(@(k) sprintf('%d  %s', k, top_cat_levels{k}), ...
            (1:K)', 'UniformOutput', false)'];
        % Name the x-axis: it is the (auto-picked) TimeCol, which may be an
        % arbitrary datetime — say which column it is and its span so a viewer
        % isn't left guessing whether it is a meaningful timeline.
        if has_time && n_t > 1
            tcn    = strrep(char(options.TimeCol), '_', ' ');
            x_line = sprintf('x = %s: %s%s%s', tcn, ...
                tg_yr_str(t_vals, 1, is_year_axis), char(8594), ...
                tg_yr_str(t_vals, numel(t_vals), is_year_axis));
            key_lines = [{x_line}, key_lines];
        end
        cat_key = strjoin(key_lines, newline);
        text(ax, -MARGIN+0.05, -MARGIN+0.1, cat_key, ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
            'FontSize', FSZ_CATLEGEND, 'Interpreter', 'none', 'Tag', 'cat_legend', ...
            'BackgroundColor', CLR_LEGEND_BG, 'EdgeColor', CLR_LEGEND_BORDER, ...
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
    legend(leg_h2, 'Location','southeast', 'FontSize', F.tiny, 'Interpreter','none');
end

%% ── Datacursor ───────────────────────────────────────────────────────────────
dcm = datacursormode(fig);
Heat_dc=Heat; N_dc=N_obs; cn_dc=char(options.ColorCol); hs_dc=has_spark;
dcm.UpdateFcn = @(~,ev) tg_datatip(ev, Heat_dc, N_dc, cn_dc, hs_dc, code_map);

end % de_tilegrid


%% ── Local helpers ────────────────────────────────────────────────────────────

function cmap = tg_cmap(spec)
CMAP_N = 256;
if ischar(spec) || isstring(spec), cmap = feval(char(spec), CMAP_N);
else, cmap = spec; end
end

function v = tg_agg(x, method)
%TG_AGG  Aggregate a vector by the chosen ColorMethod (default mean).
switch method
    case 'count',  v = numel(x);
    case 'median', v = median(x);
    case 'sum',    v = sum(x);
    otherwise,     v = mean(x);
end
end

function ig = tg_ignored_options(options, consumed)
%TG_IGNORED_OPTIONS  Non-default discriminating options not used by the active renderer.
names = ["ColorCol", "TimeCol", "CatCol", "ValueCols", "XCol", "YCol", ...
         "SharedYLim", "SharedXLim", "CatColors"];
isset = [ options.ColorCol ~= "", options.TimeCol ~= "", options.CatCol ~= "", ...
          ~isempty(options.ValueCols), options.XCol ~= "", options.YCol ~= "", ...
          ~all(isnan(options.SharedYLim)), ~all(isnan(options.SharedXLim)), ...
          ~isempty(options.CatColors) ];
ig = names(isset & ~ismember(names, consumed));
end

function s = tg_fmt_tick(v)
% Compact axis-tick label: 0, 12, 3k, 4M, 0.04.
if v == 0
    s = '0';
elseif abs(v) >= 1e6
    s = sprintf('%.0fM', v/1e6);
elseif abs(v) >= 1e3
    s = sprintf('%.0fk', v/1e3);
elseif abs(v) >= 1
    s = sprintf('%.0f', v);
else
    s = sprintf('%.2g', v);
end
end

function sk = tg_skewness(v)
% Sample skewness of a vector (toolbox-free). Returns 0 if undefined.
v = v(:);
v = v(~isnan(v));
sk = 0;
if numel(v) > 2
    s = std(v);
    if s > 0
        sk = mean(((v - mean(v)) / s) .^ 3);
    end
end
end

function fc = tg_val2color(val, vmin, vmax, cmap, has_choro)
CLR_NODATA = [0.88 0.88 0.88];
if ~has_choro || isnan(val)
    fc = CLR_NODATA;
else
    norm = max(0, min(1, (val-vmin)/(vmax-vmin)));
    ci   = max(1, min(size(cmap,1), floor(norm*size(cmap,1))+1));
    fc   = cmap(ci,:);
end
end

function tc = tg_text_color(bgc)
LUM_THRESH = 0.45;
lum = 0.299*bgc(1) + 0.587*bgc(2) + 0.114*bgc(3);
if lum < LUM_THRESH, tc = [1 1 1];
else, tc = [0.08 0.08 0.08]; end
end

function s = tg_label(code, val, has_choro)
if ~has_choro || isnan(val), s = code;
else, s = sprintf('%s\n%.3g', code, val); end
end

function s = tg_title_str(method, color_col, map_label, t_vals, is_year_axis, has_choro, has_spark)
if ~has_choro, s = char(map_label); return; end
if has_spark && numel(t_vals) >= 2
    t1 = tg_yr_str(t_vals, 1, is_year_axis);
    tn = tg_yr_str(t_vals, numel(t_vals), is_year_axis);
    s = sprintf('%s(%s)  —  %s to %s', method, char(color_col), t1, tn);
else
    s = sprintf('%s(%s)', method, char(color_col));
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
