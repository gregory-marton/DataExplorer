function de_histogram(varargin)
%DE_HISTOGRAM  Annotated histogram: auto-bins, missing-count in title.
%
%   de_histogram(x, name)                    — creates a new figure
%   de_histogram(ax, x, name)                — plots into existing axes
%   de_histogram(ax, x, name, XLim=[lo,hi])  — fix x-axis for comparison
%
%   x     numeric vector  (NaN values are dropped and counted)
%   name  label used for x-axis title and figure name
%
%   Optional name-value arguments (append after positional args)
%   ─────────────────────────────────────────────────────────────
%   XLim   [lo, hi]   Fix x-axis limits.  Useful for comparing
%                     distributions of the same variable across subsets.
%
%   Requires no toolboxes.

% Parse positional args, then collect any trailing name-value pairs.
if nargin >= 3 && isgraphics(varargin{1}, 'axes')
    ax      = varargin{1};
    x       = varargin{2};
    name    = char(varargin{3});
    nv_args = varargin(4:end);
    new_fig = false;
else
    x       = varargin{1};
    name    = char(varargin{2});
    nv_args = varargin(3:end);
    new_fig = true;
end

p = inputParser;
addParameter(p, 'XLim', [NaN NaN]);
parse(p, nv_args{:});
xlim_opt = p.Results.XLim;

if new_fig
    fig = figure('Color', [1 1 1], 'NumberTitle', 'off', ...
        'Name', sprintf('Histogram — %s', name));
    ax = axes(fig);
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
if ~any(isnan(xlim_opt))
    xlim(ax, xlim_opt);
end
box(ax, 'off');
end
