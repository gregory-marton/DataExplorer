function [fig, ax] = de_geoscatter(lon, lat, color_data, size_data, options)
%DE_GEOSCATTER  Geographic scatter: color encodes one numeric variable, size another.
%   No Mapping Toolbox required.
%
%   Usage
%   ─────
%   de_geoscatter(lon, lat, time_vals, prcp_vals)
%   de_geoscatter(lon, lat, time_vals, prcp_vals, ColorLabel="Month", SizeLabel="prcp")
%   [fig, ax] = de_geoscatter(...)
%
%   % Embed in a tiledlayout or subplot:
%   tl = tiledlayout(1, 3);
%   de_geoscatter(lon, lat, tmax, std_tmax, Parent=nexttile(tl), Title="tmax")
%
%   All four vector arguments must have the same length.
%   color_data is mapped linearly to parula(256).
%   size_data  is mapped linearly to marker area [MinSize, MaxSize] pt².
%   Negative values in size_data are fine — the full range is normalised.
%   A size legend is drawn in the lower-right corner when no Parent is given.
%
%   Optional arguments
%   ──────────────────
%   ColorLabel  ("Color")       Colorbar label.
%   SizeLabel   ("Size")        Size-legend title.
%   Title       ("")            Variable name — used in window title and axes title.
%   Source      ("")            Dataset name — appended to axes title only (not window title).
%   MinSize     (5)             Minimum marker area (pt²).
%   MaxSize     (200)           Maximum marker area (pt²).
%   ColorLim    ([NaN NaN])     Fix colorbar limits [lo, hi].  Useful for comparing
%                               multiple plots of the same variable on a common scale.
%   SizeLim     ([NaN NaN])     Fix the data range used for size normalization [lo, hi].
%                               Values outside the range are clamped to MinSize/MaxSize.
%                               Useful for comparing std or range across variables.
%   Colormap    ('parula')      Colormap name or Nx3 matrix.  Use a diverging map
%                               (e.g. 'rdbu') for anomaly or centered data.
%   FontSize    (NaN)           Base font size (pt) for axes labels, ticks, and title.
%                               NaN keeps MATLAB's default.
%   Parent      ([ ])           Axes handle to draw into.  When supplied, no new figure
%                               is created and the size legend is omitted (use a shared
%                               legend or colorbar at the layout level instead).

arguments
    lon        (:,1) double
    lat        (:,1) double
    color_data (:,1) double
    size_data  (:,1) double
    options.ColorLabel (1,1) string  = "Color"
    options.SizeLabel  (1,1) string  = "Size"
    options.Title      (1,1) string  = ""
    options.Source     (1,1) string  = ""
    options.MinSize    (1,1) double  = 5
    options.MaxSize    (1,1) double  = 200
    options.ColorLim   (1,2) double  = [NaN NaN]
    options.SizeLim    (1,2) double  = [NaN NaN]
    options.Colormap                 = 'parula'
    options.FontSize   (1,1) double  = NaN
    options.Parent                   = []
end

standalone = isempty(options.Parent);

%% ── Normalise size_data to [MinSize, MaxSize] ─────────────────────────────────
s_lo = min(size_data, [], 'omitnan');
s_hi = max(size_data, [], 'omitnan');
if ~any(isnan(options.SizeLim))
    s_lo = options.SizeLim(1);
    s_hi = options.SizeLim(2);
end
if s_hi > s_lo
    sz_norm = (size_data - s_lo) ./ (s_hi - s_lo);
    sz_norm = max(0, min(1, sz_norm));
else
    sz_norm = repmat(0.5, size(size_data));
end
sz_pts = options.MinSize + sz_norm .* (options.MaxSize - options.MinSize);

%% ── Figure / axes ────────────────────────────────────────────────────────────
if standalone
    if strlength(options.Title) > 0
        fig_name = sprintf('Geo Scatter: %s', char(options.Title));
    else
        fig_name = sprintf('Geo Scatter: %s', char(options.ColorLabel));
    end
    fig = figure('Color', 'w', 'Name', fig_name, 'NumberTitle', 'off');
    ax  = axes(fig, 'Position', [0.08 0.08 0.70 0.85]);
else
    ax  = options.Parent;
    fig = ancestor(ax, 'figure');
end

%% ── Main scatter ──────────────────────────────────────────────────────────────
sc = scatter(ax, lon, lat, sz_pts, color_data, 'filled', 'MarkerFaceAlpha', 0.5);
sc.DataTipTemplate.DataTipRows(1).Label = 'Longitude';
sc.DataTipTemplate.DataTipRows(2).Label = 'Latitude';
sc.DataTipTemplate.DataTipRows = [
    sc.DataTipTemplate.DataTipRows(1:2)
    dataTipTextRow(char(options.ColorLabel), color_data)
    dataTipTextRow(char(options.SizeLabel),  size_data)
];
colormap(ax, options.Colormap);
if ~any(isnan(options.ColorLim))
    clim(ax, options.ColorLim);
end
cb              = colorbar(ax);
cb.Label.String = char(options.ColorLabel);
if ~isnan(options.FontSize)
    ax.FontSize        = options.FontSize;
    cb.Label.FontSize  = options.FontSize;
end
xlabel(ax, 'Longitude');
ylabel(ax, 'Latitude');
if strlength(options.Title) > 0
    if strlength(options.Source) > 0
        ax_title = sprintf('%s  —  %s', char(options.Title), char(options.Source));
    else
        ax_title = char(options.Title);
    end
    title(ax, ax_title, 'Interpreter', 'none');
end
box(ax, 'on');
grid(ax, 'on');

%% ── Size legend (inset axes, lower-right corner — standalone only) ───────────
if standalone
    leg_ax = axes(fig, 'Position', [0.80 0.05 0.18 0.32]);
    axis(leg_ax, 'off');
    hold(leg_ax, 'on');

    rep_vals = [s_lo, (s_lo + s_hi) / 2, s_hi];
    rep_sz   = [options.MinSize, (options.MinSize + options.MaxSize) / 2, options.MaxSize];
    y_pos    = [2.6, 1.6, 0.6];
    for ki = 1:3
        scatter(leg_ax, 0.35, y_pos(ki), rep_sz(ki), [0.45 0.45 0.45], ...
            'filled', 'MarkerFaceAlpha', 0.6);
        text(leg_ax, 0.70, y_pos(ki), sprintf('%.3g', rep_vals(ki)), ...
            'VerticalAlignment', 'middle', 'FontSize', 7);
    end
    text(leg_ax, 0.35, 3.4, char(options.SizeLabel), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 8, ...
        'Interpreter', 'none');
    xlim(leg_ax, [0 1.3]);
    ylim(leg_ax, [0 3.8]);
end
end
