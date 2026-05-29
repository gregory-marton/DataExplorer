function de_plot_panel_totals(T, prof, panel)
%DE_PLOT_PANEL_TOTALS  100%-stacked area per categorical for wide-year panel data.
%
%   de_plot_panel_totals(T, prof, panel)
%
%   T     — table (as returned by de_profile)
%   prof  — profile struct (as returned by de_profile)
%   panel — panel struct (prof.panel, as computed by de_profile)
%
%   Produces two stacked-area figures per grouping categorical:
%     1. Absolute totals over time
%     2. 100% share over time
%
%   Rows whose categorical columns contain aggregate "total" labels are
%   excluded before plotting so the stacks reflect only the components.

wide_yr_idxs = panel.wide_yr_idxs;
wide_yr_vals = panel.wide_yr_vals;

% Exclude rows where any categorical column has a total-like value
T_notot = T;
for vn = string(T.Properties.VariableNames)
    col_v = T_notot.(char(vn));
    if ~iscategorical(col_v) && ~isstring(col_v) && ~iscellstr(col_v), continue; end
    levs_v = unique(string(col_v));
    levs_v = levs_v(~ismissing(levs_v));
    tot_v  = levs_v(arrayfun(@(l) is_total_level(char(l)), levs_v));
    if ~isempty(tot_v)
        T_notot = T_notot(~ismember(string(col_v), tot_v), :);
    end
end

% 100% stacked area by each grouping categorical (state share, MSN share, …)
for k = 1:numel(panel.grouping_idxs)
    plot_pct_area_by_cat(T_notot, prof, panel.grouping_idxs(k), ...
        wide_yr_idxs, wide_yr_vals);
end
end


% ── Local helpers ─────────────────────────────────────────────────────────────

function plot_pct_area_by_cat(T, prof, cat_idx, yr_idxs, yr_vals)
TOP_AREA = 20;

catname = prof.name{cat_idx};
cat_col = T.(catname);
if ~iscategorical(cat_col), return; end

levels_all = cellstr(categories(cat_col));
cnt_all    = countcats(cat_col);
levels     = levels_all(cnt_all > 0);
n_lv       = numel(levels);
if n_lv < 2, return; end

[yr_sorted, sort_ord] = sort(yr_vals);
yr_names = string(prof.name(yr_idxs(sort_ord)));
n_yr     = numel(yr_sorted);

sum_mat = NaN(n_lv, n_yr);
for t = 1:n_yr
    col_vals = double(T.(char(yr_names(t))));
    for li = 1:n_lv
        v = col_vals(cat_col == levels{li});
        v = v(~isnan(v));
        if ~isempty(v), sum_mat(li, t) = sum(v); end
    end
end

[~, ord] = sort(mean(sum_mat, 2, 'omitnan'), 'descend');

if n_lv > TOP_AREA
    top_idx  = ord(1:TOP_AREA);
    rest_sum = sum(sum_mat(ord(TOP_AREA+1:end), :), 1, 'omitnan');
    sum_mat  = [sum_mat(top_idx, :); rest_sum];
    levels   = [levels(top_idx); {sprintf('Other (%d)', n_lv - TOP_AREA)}];
else
    sum_mat = sum_mat(ord, :);
    levels  = levels(ord);
end

yr_totals = sum(sum_mat, 1, 'omitnan');
pct_mat   = sum_mat ./ yr_totals * 100;
pct_mat(isnan(pct_mat)) = 0;
abs_mat   = sum_mat;
abs_mat(isnan(abs_mat)) = 0;
n_shown = size(sum_mat, 1);
cmap    = lines(n_shown);

fig1 = figure('Name', fig_title( ...
    sprintf('Total by %s over time', catname), prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
ax1 = axes(fig1);
hold(ax1, 'on');
ax1.ColorOrder = cmap;
area(ax1, yr_sorted(:), abs_mat');
hold(ax1, 'off');
legend(ax1, levels, 'Location', 'eastoutside', 'FontSize', 5, 'Interpreter', 'none');
xlabel(ax1, 'Year', 'FontSize', 9);
ylabel(ax1, 'Total', 'FontSize', 8);
title(ax1, src_prefix(prof.source_name, sprintf('Total over time by %s', catname)), ...
    'FontSize', 9, 'Interpreter', 'none');
box(ax1, 'off');

fig2 = figure('Name', fig_title( ...
    sprintf('Share by %s over time', catname), prof.source_name), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
ax2 = axes(fig2);
hold(ax2, 'on');
ax2.ColorOrder = cmap;
area(ax2, yr_sorted(:), pct_mat');
hold(ax2, 'off');
legend(ax2, levels, 'Location', 'eastoutside', 'FontSize', 5, 'Interpreter', 'none');
xlabel(ax2, 'Year', 'FontSize', 9);
ylabel(ax2, '% share', 'FontSize', 8);
ylim(ax2, [0 105]);
title(ax2, src_prefix(prof.source_name, sprintf('Share over time by %s', catname)), ...
    'FontSize', 9, 'Interpreter', 'none');
box(ax2, 'off');
end


function tf = is_total_level(lv)
tf = ~isempty(regexpi(strtrim(char(lv)), '\btotal\b', 'once'));
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
