function de_plot_categorical_drilldown(T, prof, sel)
%DE_PLOT_CATEGORICAL_DRILLDOWN  Grouped time series + scatter matrices by category.
%
%   de_plot_categorical_drilldown(T, prof, sel)
%
%   T    — table (as returned by de_profile)
%   prof — profile struct (as returned by de_profile; must include prof.geo_grid)
%   sel  — column indices to use for scatter matrix (e.g. from de_select_columns)
%
%   For each qualifying categorical (non-constant, ≤15 unique levels):
%     1. Grouped time series: one subplot per numeric variable, one line per level.
%     2. Scatter matrix: np×np grid of scatters colored by that categorical.
%   For geo-like categoricals (prof.geo_grid non-empty):
%     Bar charts of mean per state + state×time heatmap.

MAX_LEVELS = 15;

cat_all    = find(prof.type == "categorical" & ~prof.skip);
cat_useful = cat_all(prof.nunique(cat_all) > 1 & ...
                     prof.nunique(cat_all) <= MAX_LEVELS);
cat_big    = cat_all(prof.nunique(cat_all) > MAX_LEVELS);

[time_idx, is_year_axis] = de_find_time_axis(prof);
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);

% Numeric columns for scatter matrix: selected numerics excluding time axis
sel_num = sel(prof.type(sel) == "numeric");
if ~isempty(time_idx)
    sel_num = sel_num(sel_num ~= time_idx);
end
MAX_NP_DRILL = 6;
if numel(sel_num) > MAX_NP_DRILL
    sel_num = sel_num(1:MAX_NP_DRILL);
end

% All non-skip numerics excluding time axis and wide year columns for time series subplots
if ~isempty(time_idx)
    ts_num = find(prof.type == "numeric" & ~prof.skip);
    ts_num = ts_num(ts_num ~= time_idx);
    ts_num = setdiff(ts_num, wide_yr_idxs);
else
    ts_num = [];
end

if ~isempty(cat_useful)
    for k = 1:numel(cat_useful)
        ci = cat_useful(k);
        if ~isempty(time_idx) && ~isempty(ts_num)
            plot_grouped_timeseries(T, prof, ci, time_idx, ts_num, is_year_axis);
        elseif ~isempty(wide_yr_idxs)
            plot_grouped_timeseries_wide(T, prof, ci, wide_yr_idxs, wide_yr_vals);
        end
        if numel(sel_num) >= 2
            plot_scatter_by_cat(T, prof, ci, sel_num);
        end
    end
end

% High-cardinality categoricals: geo treatment OR top-K drill-down with Other
% Geo × categorical heatmap figures are recipe-only (cg_geo_multicategorical_code).
TOP_K = 8;
for k = 1:numel(cat_big)
    ci = cat_big(k);
    geo_grid = '';
    if isfield(prof, 'geo_grid') && numel(prof.geo_grid) >= ci
        geo_grid = prof.geo_grid{ci};
    end
    if ~isempty(geo_grid)
        plot_state_summary(T, prof, ci, sel_num, ts_num, time_idx, is_year_axis, geo_grid);
    else
        catname_k  = prof.name{ci};
        cat_col_k  = T.(catname_k);
        all_levels = cellstr(categories(cat_col_k));
        cnt        = countcats(cat_col_k);
        keep_k     = ~total_mask(all_levels);
        all_levels = all_levels(keep_k);
        cnt        = cnt(keep_k);
        if isempty(all_levels), continue; end
        [~, ord]   = sort(cnt, 'descend');
        n_show     = min(TOP_K, numel(all_levels));
        top_levels = all_levels(ord(1:n_show));
        n_other    = numel(all_levels) - n_show;

        top_counts = cnt(ord(1:n_show));
        top_labels = cellfun(@(lv, c) sprintf('%s (n=%d)', lv, c), ...
            top_levels, num2cell(top_counts), 'UniformOutput', false);

        if n_other > 0
            n_other_rows = sum(~ismember(cat_col_k, top_levels) & ~isundefined(cat_col_k));
            other_label  = sprintf('Other (%d classes, n=%d)', n_other, n_other_rows);
            cat_str = string(cat_col_k);
            for ti = 1:n_show
                cat_str(cat_col_k == top_levels{ti}) = top_labels{ti};
            end
            cat_str(~ismember(cat_col_k, top_levels) & ~isundefined(cat_col_k)) = other_label;
            cat_str(isundefined(cat_col_k)) = missing;
            T_sub = T;
            T_sub.(catname_k) = categorical(cat_str, [top_labels; {other_label}]);
            T_sub = T_sub(~isundefined(T_sub.(catname_k)), :);
        else
            cat_str = string(cat_col_k);
            for ti = 1:n_show
                cat_str(cat_col_k == top_levels{ti}) = top_labels{ti};
            end
            cat_str(isundefined(cat_col_k)) = missing;
            T_sub = T;
            T_sub.(catname_k) = categorical(cat_str, top_labels);
            T_sub = T_sub(~isundefined(T_sub.(catname_k)), :);
        end

        if ~isempty(time_idx) && ~isempty(ts_num)
            plot_grouped_timeseries(T_sub, prof, ci, time_idx, ts_num, is_year_axis);
        elseif ~isempty(wide_yr_idxs)
            plot_grouped_timeseries_wide(T, prof, ci, wide_yr_idxs, wide_yr_vals);
        end
        if numel(sel_num) >= 2
            plot_scatter_by_cat(T_sub, prof, ci, sel_num);
        end
    end
end

if isempty(cat_useful) && isempty(cat_big), return; end
end


% ─────────────────────────────────────────────────────────────────────────────
% Local plot functions
% ─────────────────────────────────────────────────────────────────────────────

function plot_grouped_timeseries(T, prof, cat_idx, time_idx, num_idxs, is_year_axis)
catname = prof.name{cat_idx};
cat_col = T.(catname);
levels  = cellstr(categories(cat_col));
present = cellfun(@(lv) sum(cat_col == lv) > 0, levels);
levels  = levels(present);
levels  = levels(~total_mask(levels));
if isempty(levels), return; end
[colors, plot_order] = level_colors(levels);
tdata   = T.(prof.name{time_idx});

lev_counts = arrayfun(@(lk) sum(cat_col == levels{lk}), 1:numel(levels));

n_num  = numel(num_idxs);

fig = figure( ...
    'Name',        fig_title(sprintf('By %s', catname), prof.source_name), ...
    'Color',       [0.97 0.97 0.97], ...
    'NumberTitle', 'off');
tl = tiledlayout(fig, n_num, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

B_CI = 500;
for j = 1:n_num
    ax = nexttile(tl);
    ncn   = prof.name{num_idxs(j)};
    ydata = T.(ncn);

    for lk = plot_order
        mask = cat_col == levels{lk};
        t_sub = tdata(mask);
        y_sub = ydata(mask);

        if is_year_axis
            valid = ~isnan(t_sub) & ~isnan(y_sub);
        else
            valid = ~isnat(t_sub) & ~isnan(y_sub);
        end
        if sum(valid) < 2, continue; end

        t_v = t_sub(valid);
        y_v = y_sub(valid);

        [t_u, ~, tidx] = unique(t_v);
        n_u = numel(t_u);
        y_agg = nan(n_u, 1);
        y_lo  = nan(n_u, 1);
        y_hi  = nan(n_u, 1);
        for tt = 1:n_u
            vals = y_v(tidx == tt);
            vals = vals(~isnan(vals));
            nv = numel(vals);
            if nv == 0, continue; end
            y_agg(tt) = mean(vals);
            if nv >= 2
                bm = mean(vals(randi(nv, nv, B_CI)), 1);
                bm = sort(bm);
                y_lo(tt) = bm(max(1, round(0.025*B_CI)));
                y_hi(tt) = bm(min(B_CI, round(0.975*B_CI)));
            else
                y_lo(tt) = vals; y_hi(tt) = vals;
            end
        end

        ok_ci = ~isnan(y_lo) & ~isnan(y_hi);
        if sum(ok_ci) >= 2
            hold(ax, 'on');
            t_ci = t_u(ok_ci);
            fill(ax, [t_ci; flipud(t_ci)], [y_hi(ok_ci); flipud(y_lo(ok_ci))], ...
                colors(lk,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
                'HandleVisibility', 'off');
        end

        h = plot(ax, t_u, y_agg, '-o', ...
            'Color',      colors(lk, :), ...
            'MarkerSize', 3, ...
            'LineWidth',  1.2, ...
            'DisplayName', sprintf('%s (n=%d)', levels{lk}, lev_counts(lk)));
        hold(ax, 'on');
        try
            h.DataTipTemplate.DataTipRows(end+1) = ...
                dataTipTextRow(catname, repmat(levels(lk), numel(t_u), 1));
        catch
        end
    end

    if j == n_num
        xlabel(ax, prof.name{time_idx}, 'FontSize', 8, 'Interpreter', 'none');
    end
    ylabel(ax, ncn, 'FontSize', 7, 'Interpreter', 'none');
    legend(ax, 'Location', 'bestoutside', 'FontSize', 6, 'Interpreter', 'none');
    box(ax, 'off');
end

title(tl, src_prefix(prof.source_name, sprintf('by %s', catname)), ...
    'FontSize', 10, 'Interpreter', 'none');
end


function plot_grouped_timeseries_wide(T, prof, cat_idx, yr_idxs, yr_vals)
TOP_K = 20;
B_CI  = 500;
catname = prof.name{cat_idx};
cat_col = T.(catname);

levels_all = cellstr(categories(cat_col));

[yr_sorted, sort_ord] = sort(yr_vals);
yr_sorted  = yr_sorted(:);
yr_names_s = string(prof.name(yr_idxs(sort_ord)));
n_yr = numel(yr_sorted);

n_rows_all   = zeros(numel(levels_all), 1);
overall_mean = NaN(numel(levels_all), 1);
for li = 1:numel(levels_all)
    m = cat_col == levels_all{li};
    n_rows_all(li) = sum(m);
    yr_means = NaN(n_yr, 1);
    for yi = 1:n_yr
        v = double(T.(char(yr_names_s(yi)))(m));
        v = v(~isnan(v));
        if ~isempty(v), yr_means(yi) = mean(v); end
    end
    overall_mean(li) = mean(yr_means, 'omitnan');
end

has_rows = n_rows_all > 0;
levels_all   = levels_all(has_rows);
n_rows_all   = n_rows_all(has_rows);
overall_mean = overall_mean(has_rows);
if isempty(levels_all), return; end

keep = ~total_mask(levels_all, overall_mean);
levels_all   = levels_all(keep);
n_rows_all   = n_rows_all(keep);
overall_mean = overall_mean(keep);
if isempty(levels_all), return; end

[~, ord]  = sort(overall_mean, 'descend', 'MissingPlacement', 'last');
n_show    = min(TOP_K, numel(levels_all));
top_idx   = ord(1:n_show);
other_idx = ord(n_show+1:end);
has_other = ~isempty(other_idx);

levels_show = levels_all(top_idx);
n_rows_show = n_rows_all(top_idx);
[colors, plot_order] = level_colors(levels_show);

fig = figure('Name', fig_title(sprintf('By %s over time', catname), prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
ax = axes(fig);
hold(ax, 'on');

if has_other
    n_other_cats = numel(other_idx);
    n_other_rows = sum(n_rows_all(other_idx));
    other_label  = sprintf('Other (%d classes, n=%d)', n_other_cats, n_other_rows);
    other_mask   = ismember(cat_col, levels_all(other_idx));
    GRAY = [0.55 0.55 0.55];
    y_o = NaN(n_yr,1);  lo_o = NaN(n_yr,1);  hi_o = NaN(n_yr,1);
    for yi = 1:n_yr
        v = double(T.(char(yr_names_s(yi)))(other_mask));
        v = v(~isnan(v));  nv = numel(v);
        if nv == 0, continue; end
        y_o(yi) = mean(v);
        if nv >= 2
            bm = sort(mean(v(randi(nv,nv,B_CI)),1));
            lo_o(yi) = bm(max(1, round(0.025*B_CI)));
            hi_o(yi) = bm(min(B_CI, round(0.975*B_CI)));
        else
            lo_o(yi) = v;  hi_o(yi) = v;
        end
    end
    ok_ci = ~isnan(lo_o) & ~isnan(hi_o);
    if sum(ok_ci) >= 2
        t_ci = yr_sorted(ok_ci);
        fill(ax, [t_ci; flipud(t_ci)], [hi_o(ok_ci); flipud(lo_o(ok_ci))], ...
            GRAY, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    h_o = plot(ax, yr_sorted, y_o, '--', 'Color', GRAY, 'LineWidth', 1.0, ...
        'DisplayName', other_label);
    h_o.DataTipTemplate.DataTipRows(1).Label = 'Year';
    h_o.DataTipTemplate.DataTipRows(2).Label = 'Mean value';
    h_o.DataTipTemplate.DataTipRows(end+1) = ...
        dataTipTextRow(catname, repmat({other_label}, numel(yr_sorted), 1));
end

for lk = plot_order
    lv_mask  = cat_col == levels_show{lk};
    disp_lbl = sprintf('%s (n=%d)', strrep(levels_show{lk},'_',' '), n_rows_show(lk));
    y_k = NaN(n_yr,1);  lo_k = NaN(n_yr,1);  hi_k = NaN(n_yr,1);
    for yi = 1:n_yr
        v = double(T.(char(yr_names_s(yi)))(lv_mask));
        v = v(~isnan(v));  nv = numel(v);
        if nv == 0, continue; end
        y_k(yi) = mean(v);
        if nv >= 2
            bm = sort(mean(v(randi(nv,nv,B_CI)),1));
            lo_k(yi) = bm(max(1, round(0.025*B_CI)));
            hi_k(yi) = bm(min(B_CI, round(0.975*B_CI)));
        else
            lo_k(yi) = v;  hi_k(yi) = v;
        end
    end
    ok_ci = ~isnan(lo_k) & ~isnan(hi_k);
    if sum(ok_ci) >= 2
        t_ci = yr_sorted(ok_ci);
        fill(ax, [t_ci; flipud(t_ci)], [hi_k(ok_ci); flipud(lo_k(ok_ci))], ...
            colors(lk,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    h_k = plot(ax, yr_sorted, y_k, '-', 'Color', colors(lk,:), ...
        'LineWidth', 1.2, 'DisplayName', disp_lbl);
    h_k.DataTipTemplate.DataTipRows(1).Label = 'Year';
    h_k.DataTipTemplate.DataTipRows(2).Label = 'Mean value';
    h_k.DataTipTemplate.DataTipRows(end+1) = ...
        dataTipTextRow(catname, repmat(levels_show(lk), numel(yr_sorted), 1));
end

hold(ax, 'off');
xlabel(ax, 'Year', 'FontSize', 9);
ylabel(ax, 'Mean value', 'FontSize', 8);
legend(ax, 'Location', 'bestoutside', 'FontSize', 7, 'Interpreter', 'none');
if has_other
    title_suf = sprintf(' — top %d + Other (of %d total)', n_show, numel(levels_all));
else
    title_suf = '';
end
title(ax, src_prefix(prof.source_name, sprintf('Trend by %s%s', catname, title_suf)), ...
    'FontSize', 10, 'Interpreter', 'none');
box(ax, 'off');
end


function plot_scatter_by_cat(T, prof, cat_idx, sel_num)
catname = prof.name{cat_idx};
cat_col = T.(catname);
levels  = cellstr(categories(cat_col));
n_lev   = numel(levels);
[colors, plot_order] = level_colors(levels);

MAX_NP = 6;
sel_num = sel_num(1:min(end, MAX_NP));
np = numel(sel_num);

fig = figure( ...
    'Name',        fig_title(catname, prof.source_name), ...
    'Color',       [0.97 0.97 0.97], ...
    'NumberTitle', 'off');
tl = tiledlayout(fig, np, np, 'TileSpacing', 'tight', 'Padding', 'compact');

n_total = height(T);
pt_alpha = max(0.1, min(0.7, 300 / max(n_total, 1)));

legend_handles = gobjects(n_lev, 1);

for r = 1:np
    for c = 1:np
        ax = nexttile(tl);
        ri    = sel_num(r);
        ci    = sel_num(c);
        xname = prof.name{ci};
        yname = prof.name{ri};
        xdata = T.(xname);
        ydata = T.(yname);

        if r == c
            for lk = plot_order
                mask = cat_col == levels{lk};
                x = xdata(mask);
                x = x(~isnan(x));
                if numel(x) < 2, continue; end
                h = histogram(ax, x, 15, ...
                    'Normalization', 'probability', ...
                    'FaceColor',     colors(lk, :), ...
                    'FaceAlpha',     0.45, ...
                    'EdgeColor',     'none', ...
                    'DisplayName',   levels{lk});
                hold(ax, 'on');
                h.DataTipTemplate.DataTipRows(1).Label = ...
                    sprintf('%s = %s', char(catname), char(levels{lk}));
                if ~isgraphics(legend_handles(lk))
                    legend_handles(lk) = h;
                end
            end
        else
            for lk = plot_order
                mask  = cat_col == levels{lk};
                x     = xdata(mask);
                y     = ydata(mask);
                valid = ~isnan(x) & ~isnan(y);
                if ~any(valid), continue; end
                xv = x(valid);  yv = y(valid);
                if numel(xv) >= 5
                    r_val = corr(xv, yv);
                    lbl   = sprintf('%s (r=%.2f)', levels{lk}, r_val);
                    [ci_lo, ci_hi, x_fit, y_fit] = de_bootstrap_poly_ci(xv, yv, 1, 0.95, 300);
                    if ~isempty(y_fit)
                        hold(ax, 'on');
                        x_poly = [x_fit; flipud(x_fit)];
                        y_poly = [ci_hi; flipud(ci_lo)];
                        h_fill = fill(ax, x_poly, y_poly, ...
                            colors(lk,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
                            'HandleVisibility', 'off');
                        if isprop(h_fill, 'DataTipTemplate') && ...
                                ~isempty(h_fill.DataTipTemplate.DataTipRows)
                            h_fill.DataTipTemplate.DataTipRows(1).Label = ...
                                sprintf('%s = %s (CI)', char(catname), char(levels{lk}));
                        end
                        h_line = plot(ax, x_fit, y_fit, '-', 'Color', colors(lk,:), ...
                            'LineWidth', 1.5, 'HandleVisibility', 'off');
                        try
                            h_line.DataTipTemplate.DataTipRows(end+1) = ...
                                dataTipTextRow(catname, repmat(levels(lk), numel(x_fit), 1));
                        catch
                        end
                    end
                else
                    lbl = levels{lk};
                end
                h = scatter(ax, xv, yv, 8, colors(lk, :), 'filled', ...
                    'MarkerFaceAlpha', pt_alpha, 'DisplayName', lbl);
                hold(ax, 'on');
                try
                    h.DataTipTemplate.DataTipRows(end+1) = ...
                        dataTipTextRow(catname, repmat(levels(lk), numel(xv), 1));
                catch
                end
                if ~isgraphics(legend_handles(lk))
                    legend_handles(lk) = h;
                end
            end
        end

        show_y = (c == 1 && r ~= c);
        show_x = (r == np && r ~= c);
        if np <= 5
            if show_y, set(ax, 'YTickMode', 'auto', 'FontSize', 6);
            else,       set(ax, 'YTick', []); end
            if show_x, set(ax, 'XTickMode', 'auto', 'FontSize', 6, 'XTickLabelRotation', 45);
            else,       set(ax, 'XTick', []); end
        else
            if show_y
                yl = ylim(ax);
                set(ax, 'YTick', [yl(1) yl(2)], 'FontSize', 5.5);
            else
                set(ax, 'YTick', []);
            end
            if show_x
                xl = xlim(ax);
                set(ax, 'XTick', [xl(1) xl(2)], 'FontSize', 5.5, 'XTickLabelRotation', 45);
            else
                set(ax, 'XTick', []);
            end
        end
        box(ax, 'off');

        name_fn = @(s) label_name(s, np >= 6);
        if r == 1
            title(ax, name_fn(xname), 'FontSize', 7, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
        end
        if r == c && r > 1
            title(ax, name_fn(yname), 'FontSize', 7, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
        end
        if c == 1
            yl = ylabel(ax, name_fn(yname), 'FontSize', 6, 'Interpreter', 'none');
            set(yl, 'Rotation', 0, 'HorizontalAlignment', 'right');
        end
    end
end

valid_mask   = isgraphics(legend_handles);
valid_h      = legend_handles(valid_mask);
valid_labels = levels(valid_mask);
if ~isempty(valid_h)
    lgd = legend(nexttile(tl, 1), valid_h, valid_labels, ...
        'FontSize', 6, 'Interpreter', 'none');
    lgd.Layout.Tile = 'east';
end

title(tl, src_prefix(prof.source_name, sprintf('colored by %s', catname)), ...
    'FontSize', 10, 'Interpreter', 'none');
end


function plot_state_summary(T, prof, cat_idx, sel_num, ts_num, time_idx, is_year_axis, grid_name)
if nargin < 8 || isempty(grid_name), grid_name = 'us-states'; end

catname = prof.name{cat_idx};
cat_col = T.(catname);
states  = cellstr(unique(cat_col(~isundefined(cat_col))));
n_st    = numel(states);
if n_st == 0, return; end

TOTAL_CODES = {'US', 'ALL', 'TOTAL', 'GRAND TOTAL'};
states_plot = states(~ismember(upper(states), TOTAL_CODES));
if isempty(states_plot), states_plot = states; end
n_st_plot = numel(states_plot);

num_idxs = unique([sel_num, ts_num(:)']);
num_idxs = num_idxs(prof.type(num_idxs) == "numeric");
if ~isempty(time_idx)
    num_idxs = num_idxs(num_idxs ~= time_idx);
end
n_num = numel(num_idxs);
if n_num == 0, return; end

fprintf('  State summary: %d states × %d variables.\n', n_st_plot, n_num);

n_cols = min(n_num, 3);
n_rows = ceil(n_num / n_cols);

fig = figure('Name', fig_title(sprintf('By %s', catname), prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
tl = tiledlayout(fig, n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');

for j = 1:n_num
    ax = nexttile(tl);
    ncn   = prof.name{num_idxs(j)};
    ydata = T.(ncn);
    means = NaN(n_st_plot, 1);
    for s = 1:n_st_plot
        vals = ydata(cat_col == states_plot{s});
        vals = vals(~isnan(vals));
        if ~isempty(vals), means(s) = mean(vals); end
    end
    [means_s, sord] = sort(means, 'descend', 'MissingPlacement', 'last');
    states_s = states_plot(sord);
    barh(ax, 1:n_st_plot, means_s, 'FaceColor', [0.3 0.5 0.8], 'EdgeColor', 'none');
    set(ax, 'YTick', 1:n_st_plot, 'YTickLabel', states_s, 'FontSize', 5, ...
        'YDir', 'reverse');
    title(ax, wrapped_name(ncn), 'FontSize', 8, 'Interpreter', 'none');
    box(ax, 'off');
end
title(tl, src_prefix(prof.source_name, sprintf('mean by %s', catname)), ...
    'FontSize', 10, 'Interpreter', 'none');

plot_state_choropleth(T, prof, cat_idx, num_idxs, time_idx, is_year_axis, grid_name);

[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
TOTAL_CODES_ST = {'US', 'ALL', 'TOTAL', 'GRAND TOTAL'};
total_code_found = '';
for tc__ = TOTAL_CODES_ST
    if any(ismember(upper(states), tc__{1}))
        total_code_found = tc__{1};
        break;
    end
end
if ~isempty(total_code_found) && ~isempty(wide_yr_idxs)
    plot_state_pct_area(T, prof, cat_idx, total_code_found, states_plot, ...
        wide_yr_idxs, wide_yr_vals);
end

if isempty(time_idx) && isempty(wide_yr_idxs), return; end

if ~isempty(wide_yr_idxs)
    [t_vals, sort_ord] = sort(wide_yr_vals);
    yr_names_s = string(prof.name(wide_yr_idxs(sort_ord)));
    n_t = numel(t_vals);

    fig2 = figure('Name', fig_title(sprintf('%s × year', catname), prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    ax = axes(fig2);

    Heat = NaN(n_st_plot, n_t);
    for s = 1:n_st_plot
        s_mask = cat_col == states_plot{s};
        for t = 1:n_t
            vals = double(T.(char(yr_names_s(t)))(s_mask));
            vals = vals(~isnan(vals));
            if ~isempty(vals), Heat(s, t) = mean(vals); end
        end
    end
    imagesc(ax, Heat);
    colorbar(ax);
    step = max(1, floor(n_t / 8));
    set(ax, 'XTick', 1:step:n_t, 'XTickLabel', t_vals(1:step:n_t), ...
        'XTickLabelRotation', 45, 'YTick', 1:n_st_plot, ...
        'YTickLabel', states_plot, 'FontSize', 5);
    xlabel(ax, 'Year', 'FontSize', 8);
    title(ax, src_prefix(prof.source_name, sprintf('by %s over time', catname)), ...
        'FontSize', 9, 'Interpreter', 'none');
    box(ax, 'off');
else
    tdata = T.(prof.name{time_idx});
    if is_year_axis
        valid_t = ~isnan(tdata);
    else
        valid_t = ~isnat(tdata);
    end
    t_vals = unique(tdata(valid_t));
    n_t    = numel(t_vals);
    if n_t < 2, return; end

    fig2 = figure('Name', fig_title(sprintf('%s × time', catname), prof.source_name), ...
        'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
    tl2 = tiledlayout(fig2, n_rows, n_cols, 'TileSpacing', 'compact', 'Padding', 'compact');

    for j = 1:n_num
        ax = nexttile(tl2);
        ncn   = prof.name{num_idxs(j)};
        ydata = T.(ncn);
        Heat  = NaN(n_st_plot, n_t);
        for s = 1:n_st_plot
            s_mask = cat_col == states_plot{s};
            for tt = 1:n_t
                mask = s_mask & (tdata == t_vals(tt));
                vals = ydata(mask);
                vals = vals(~isnan(vals));
                if ~isempty(vals), Heat(s, tt) = mean(vals); end
            end
        end
        imagesc(ax, Heat);
        colorbar(ax);
        if is_year_axis
            step = max(1, floor(n_t / 8));
            set(ax, 'XTick', 1:step:n_t, ...
                'XTickLabel', t_vals(1:step:n_t), ...
                'XTickLabelRotation', 45);
        else
            set(ax, 'XTick', []);
        end
        set(ax, 'YTick', 1:n_st_plot, 'YTickLabel', states_plot, 'FontSize', 5);
        title(ax, wrapped_name(ncn), 'FontSize', 8, 'Interpreter', 'none');
        box(ax, 'off');
    end
    title(tl2, src_prefix(prof.source_name, sprintf('Time %s %s', char(215), catname)), ...
        'FontSize', 10, 'Interpreter', 'none');
end
end


function plot_state_choropleth(T, prof, cat_idx, num_idxs, time_idx, ~, grid_name)
if nargin < 7 || isempty(grid_name), grid_name = 'us-states'; end
catname = prof.name{cat_idx};
tcn     = '';
if ~isempty(time_idx), tcn = prof.name{time_idx}; end

[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
if ~isempty(wide_yr_idxs) && isempty(time_idx)
    fig_title_str = fig_title(sprintf('Choropleth: %s', catname), prof.source_name);
    T_long = pivot_wide_to_long(T, prof, wide_yr_idxs, wide_yr_vals);
    de_geobins(T_long, 'GeoCol', catname, 'Grid', grid_name, 'ColorCol', 'Value', ...
        'TimeCol', 'Year', 'Title', fig_title_str);
    num_idxs = num_idxs(~ismember(num_idxs, wide_yr_idxs));

    skip_cols = [string(catname), "Year", "Value"];
    sub_cats  = string(T_long.Properties.VariableNames);
    sub_cats  = sub_cats(~ismember(sub_cats, skip_cols));
    for sci = 1:numel(sub_cats)
        sc     = char(sub_cats(sci));
        sc_col = T_long.(sc);
        if ~iscategorical(sc_col) && ~isstring(sc_col), continue; end
        if iscategorical(sc_col)
            lv_cnt = countcats(sc_col);
            n_lv   = sum(lv_cnt > 0);
        else
            n_lv = numel(unique(sc_col(~ismissing(sc_col))));
        end
        if n_lv < 2, continue; end
        hm_title = fig_title( ...
            sprintf('Choropleth: %s × %s × year', catname, sc), prof.source_name);
        fprintf('  State heatmap choropleth: %s x %s (%d levels).\n', catname, sc, n_lv);
        de_geobins(T_long, 'GeoCol', catname, 'Grid', grid_name, ...
            'CellRenderer', 'heatmap_cat', ...
            'CatCol',  sc,      'ColorCol', 'Value', ...
            'TimeCol', 'Year',  'TopK',     min(n_lv, 5), ...
            'Title',   hm_title);
    end
end

for j = 1:numel(num_idxs)
    ncn        = prof.name{num_idxs(j)};
    fig_title_str = fig_title(sprintf('Choropleth: %s', ncn), prof.source_name);
    if isempty(tcn)
        de_geobins(T, 'GeoCol', catname, 'Grid', grid_name, 'ColorCol', ncn, ...
            'Title', fig_title_str);
    else
        de_geobins(T, 'GeoCol', catname, 'Grid', grid_name, 'ColorCol', ncn, ...
            'TimeCol', tcn, 'Title', fig_title_str);
    end
end
end


function plot_state_pct_area(T, prof, cat_idx, total_code, states_plot, yr_idxs, yr_vals)
catname = prof.name{cat_idx};
cat_col = T.(catname);

[yr_sorted, sort_ord] = sort(yr_vals);
yr_names_s = string(prof.name(yr_idxs(sort_ord)));
n_yrs = numel(yr_sorted);
n_st  = numel(states_plot);

pct_mat = NaN(n_st, n_yrs);
us_mask = upper(string(cat_col)) == total_code;
for t = 1:n_yrs
    col_vals = double(T.(char(yr_names_s(t))));
    us_total = sum(col_vals(us_mask), 'omitnan');
    if isnan(us_total) || us_total == 0, continue; end
    for s = 1:n_st
        st_sum = sum(col_vals(cat_col == states_plot{s}), 'omitnan');
        pct_mat(s, t) = st_sum / us_total * 100;
    end
end

valid = any(~isnan(pct_mat), 2);
if ~any(valid), return; end
pct_mat = pct_mat(valid, :);
st_labels = states_plot(valid);

[~, ord] = sort(mean(pct_mat, 2, 'omitnan'), 'descend');
pct_mat  = pct_mat(ord, :);
st_labels = st_labels(ord);
pct_mat(isnan(pct_mat)) = 0;

fig = figure('Name', fig_title( ...
    sprintf('%% of %s total by %s', total_code, catname), prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
ax = axes(fig);
n_shown = size(pct_mat, 1);
hold(ax, 'on');
ax.ColorOrder = lines(n_shown);
area(ax, yr_sorted(:), pct_mat');
hold(ax, 'off');
legend(ax, st_labels, 'Location', 'eastoutside', 'FontSize', 5, 'Interpreter', 'none');
xlabel(ax, 'Year', 'FontSize', 9);
ylabel(ax, sprintf('%% of %s total', total_code), 'FontSize', 8);
ylim(ax, [0 max(sum(pct_mat, 1), [], 'omitnan') * 1.05]);
title(ax, src_prefix(prof.source_name, ...
    sprintf('State share of %s total (sum across energy types)', total_code)), ...
    'FontSize', 9, 'Interpreter', 'none');
box(ax, 'off');
end


function T_long = pivot_wide_to_long(T, prof, wide_yr_idxs, wide_yr_vals)
yr_names  = string(prof.name(wide_yr_idxs));
all_cols  = string(T.Properties.VariableNames);
keep_cols = cellstr(all_cols(~ismember(all_cols, yr_names)));

[yr_sorted, yr_ord] = sort(wide_yr_vals);
yr_names_s = yr_names(yr_ord);

n_rows = height(T);
n_t    = numel(yr_sorted);

T_long       = repmat(T(:, keep_cols), n_t, 1);
T_long.Year  = repelem(yr_sorted(:), n_rows);
value_col    = cell2mat(arrayfun(@(ti) double(T.(yr_names_s(ti))), ...
                   (1:n_t)', 'UniformOutput', false));
T_long.Value = value_col;
end


% ─────────────────────────────────────────────────────────────────────────────
% Small utilities
% ─────────────────────────────────────────────────────────────────────────────

function mask = total_mask(levels, means)
n = numel(levels);
mask = false(n, 1);
for li = 1:n
    if is_total_level(levels{li}), mask(li) = true; end
end
if nargin < 2 || isempty(means), return; end
valid = ~isnan(means) & means > 0 & ~mask;
if sum(valid) < 4, return; end
for li = 1:n
    if mask(li) || isnan(means(li)) || means(li) <= 0, continue; end
    others = valid;  others(li) = false;
    sum_oth = sum(means(others));
    if sum_oth > 0 && abs(means(li)/sum_oth - 1) < 0.30
        mask(li) = true;
    end
end
end


function tf = is_total_level(lv)
tf = ~isempty(regexpi(strtrim(char(lv)), '\btotal\b', 'once'));
end


function [colors, plot_order] = level_colors(levels)
n = numel(levels);
colors = lines(n);
is_other = n > 0 && strncmp(levels{n}, 'Other (', 7);
if is_other
    colors(n, :) = [0.78 0.78 0.78];
    plot_order = [n, 1:n-1];
else
    plot_order = 1:n;
end
end


function s = fig_title(label, source_name)
m = regexp(char(source_name), '\[([^\]]+)\]\s*$', 'tokens', 'once');
if ~isempty(m)
    s = sprintf('%s: %s', label, strtrim(m{1}));
else
    s = label;
end
end


function s = src_prefix(~, rest)
s = rest;
end


function s = label_name(name, compact)
if compact
    s = short_name(name);
else
    s = wrapped_name(name);
end
end


function s = short_name(name)
MAX = 18;
if numel(name) > MAX
    s = [name(1:MAX-1) '…'];
else
    s = name;
end
end


function s = wrapped_name(name)
MAX_LINE = 16;
if numel(name) <= MAX_LINE
    s = name;
    return
end
parts = regexp(name, '[^_ ]+', 'match');
if isempty(parts)
    s = name;
    return
end
lns    = cell(1, numel(parts));
nl = 0;
cur_line = parts{1};
for k = 2:numel(parts)
    candidate = [cur_line '_' parts{k}];
    if numel(candidate) <= MAX_LINE
        cur_line = candidate;
    else
        nl = nl + 1;
        lns{nl} = cur_line;
        cur_line = parts{k};
    end
end
nl = nl + 1;
lns{nl} = cur_line;
lns = lns(1:nl);
s = strjoin(lns, newline);
end
