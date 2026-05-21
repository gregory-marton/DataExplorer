function de_histogram(varargin)
%DE_HISTOGRAM  Annotated histogram: auto-bins, missing-count in title.
%
%   de_histogram(x, name)       — creates a new figure
%   de_histogram(ax, x, name)   — plots into existing axes (for subplots)
%
%   x     numeric vector  (NaN values are dropped and counted)
%   name  label used for x-axis title and figure name
%
%   Requires no toolboxes.

if nargin >= 3 && isgraphics(varargin{1}, 'axes')
    ax   = varargin{1};
    x    = varargin{2};
    name = char(varargin{3});
else
    x    = varargin{1};
    name = char(varargin{2});
    fig  = figure('Color', [1 1 1], 'NumberTitle', 'off', ...
        'Name', sprintf('Histogram — %s', name));
    ax   = axes(fig);
end

x      = double(x(:));
n_tot  = numel(x);
x_ok   = x(~isnan(x));
n_miss = n_tot - numel(x_ok);
nbins  = min(50, max(10, round(sqrt(max(numel(x_ok), 1)))));
label  = strrep(name, '_', ' ');

histogram(ax, x_ok, nbins, 'FaceColor', [0.35 0.55 0.75], 'EdgeColor', 'none');
xlabel(ax, label, 'Interpreter', 'none');
ylabel(ax, 'Count');
if n_miss > 0
    title(ax, sprintf('%s  (n = %d, %d missing)', label, numel(x_ok), n_miss), ...
        'Interpreter', 'none');
else
    title(ax, sprintf('%s  (n = %d)', label, numel(x_ok)), 'Interpreter', 'none');
end
box(ax, 'off');
end
