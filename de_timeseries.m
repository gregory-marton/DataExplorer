function de_timeseries(T, time_col, value_cols, options)
%DE_TIMESERIES  Overlaid multi-series time series (and stacked area if compositional).
%
%   de_timeseries(T, time_col, value_cols)
%   de_timeseries(T, time_col, value_cols, Compositional="on"|"off"|"auto", ...)
%
%   T          — table
%   time_col   — name of a datetime or numeric (year-like) time column
%   value_cols — string array of numeric column names to plot
%
%   Rows sharing a time value are aggregated to their mean.  When the series are
%   compositional (parts of a near-constant whole) an extra dashed Total line is
%   added and a stacked-area figure is produced.
%
%   Name-value options
%     Compositional  "auto" (default; nonneg + low row-sum CV), "on", or "off"
%     TitlePrefix    string prepended to the figure window names ("")
%     FontSize       base font size (8)
%
%   Requires no toolboxes.

arguments
    T          table
    time_col   (1,1) string
    value_cols (1,:) string
    options.Compositional (1,1) string = "auto"
    options.TitlePrefix   (1,1) string = ""
    options.FontSize      (1,1) double = 8
end

if ~ismember(time_col, string(T.Properties.VariableNames)), return; end
value_cols = value_cols(ismember(value_cols, string(T.Properties.VariableNames)));
n_s = numel(value_cols);
if n_s == 0, return; end

t_col = T.(char(time_col));
if isdatetime(t_col)
    valid_t = ~isnat(t_col);
elseif isnumeric(t_col)
    valid_t = ~isnan(t_col);
else
    return
end

t_u = unique(t_col(valid_t));
n_u = numel(t_u);
if n_u < 2, return; end

% Aggregate each series to per-time-point means
Y = NaN(n_u, n_s);
for k = 1:n_s
    col = double(T.(char(value_cols(k))));
    for i = 1:n_u
        v = col(t_col == t_u(i));
        v = v(~isnan(v));
        if ~isempty(v), Y(i, k) = mean(v); end
    end
end

% Decide compositional
switch lower(options.Compositional)
    case "on",  is_comp = true;
    case "off", is_comp = false;
    otherwise   % auto: all-nonneg and row sums near-constant (low CV)
        Yc = Y(all(~isnan(Y), 2), :);
        if isempty(Yc) || size(Yc,1) < 2 || size(Yc,2) < 2 || any(Yc(:) < 0)
            is_comp = false;
        else
            rs = sum(Yc, 2);
            is_comp = std(rs) / max(abs(mean(rs)), eps) < 0.05;
        end
end

pfx     = char(options.TitlePrefix);
fsz     = options.FontSize;
labels  = cellstr(value_cols);
n_rows  = height(T);

%% ── Overlaid lines (+ Total when compositional) ──────────────────────────────
figure('Name', [pfx 'time series (overlaid)'], 'NumberTitle', 'off', 'Color', [1 1 1]);
ax = gca; hold(ax, 'on'); colors_ts = lines(n_s);
for k = 1:n_s
    plot(ax, t_u, Y(:,k), '-', 'Color', colors_ts(k,:), 'LineWidth', 1.5, ...
        'DisplayName', labels{k});
end
if is_comp
    Y_total = sum(Y, 2, 'omitnan');
    plot(ax, t_u, Y_total, '--', 'Color', [0.10 0.10 0.10], 'LineWidth', 2, ...
        'DisplayName', 'Total');
    legend(ax, [labels {'Total'}], 'Location', 'bestoutside', 'Interpreter', 'none', 'FontSize', fsz);
else
    legend(ax, labels, 'Location', 'bestoutside', 'Interpreter', 'none', 'FontSize', fsz);
end
xlabel(ax, char(time_col), 'Interpreter', 'none'); ylabel(ax, 'Value');
box(ax, 'off'); hold(ax, 'off');
title(ax, sprintf('time series, overlaid lines  (n = %d, %d series)', n_rows, n_s), ...
    'FontSize', fsz + 3, 'Interpreter', 'none');

%% ── Stacked area (compositional only) ────────────────────────────────────────
if is_comp
    figure('Name', [pfx 'time series (stacked)'], 'NumberTitle', 'off', 'Color', [1 1 1]);
    ax = gca; Y_plot = Y; Y_plot(isnan(Y_plot)) = 0;
    [~, sord] = sort(mean(Y_plot, 1), 'descend');
    area(ax, t_u, Y_plot(:, sord), 'LineStyle', 'none', 'FaceAlpha', 0.85);
    legend(ax, labels(sord), 'Location', 'bestoutside', 'Interpreter', 'none', 'FontSize', fsz);
    xlabel(ax, char(time_col), 'Interpreter', 'none'); ylabel(ax, 'Value (stacked)');
    box(ax, 'off');
    title(ax, sprintf('time series, stacked area  (n = %d, %d series)', n_rows, n_s), ...
        'FontSize', fsz + 3, 'Interpreter', 'none');
end
end
