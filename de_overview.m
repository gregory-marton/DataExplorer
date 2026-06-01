function de_overview(T, prof, options)
%DE_OVERVIEW  Per-variable diagnostic tiles in a paginated 5×3 grid.
%
%   de_overview(T, prof)
%   de_overview(T, prof, MaxVars=N)     % stop after N variables
%   de_overview(T, prof, FontSize=sz)   % base font size (default 7)
%
%   T     — MATLAB table (already profiled)
%   prof  — struct from de_profile(T); uses fields: name, type, nmissing, skip,
%           source_name, sampling_note
%
%   Creates one or more figures (one per page, 15 tiles each).
%   Requires no toolboxes.

arguments
    T     table
    prof  struct
    options.MaxVars  (1,1) double {mustBePositive} = Inf
    options.FontSize (1,1) double {mustBePositive} = 7
end

NCOLS    = 5;
NROWS    = 3;
PER_PAGE = NCOLS * NROWS;
F       = de__font_sizes(options.FontSize);
fsz     = F.base;       % passed to per-tile helpers
BG_GRAY = [0.97 0.97 0.97];
CLR_SRC = [0.55 0.55 0.55];

all_idx = 1:numel(prof.name);
if isfinite(options.MaxVars)
    all_idx = all_idx(1:min(options.MaxVars, numel(all_idx)));
end

nv = numel(all_idx);
if nv == 0, return; end

n        = height(T);
n_pages  = ceil(nv / PER_PAGE);
src      = char(prof.source_name);
is_anon  = isempty(src) || strcmp(src, 'table input');

for pg = 1:n_pages
    idx_range = (pg-1)*PER_PAGE+1 : min(pg*PER_PAGE, nv);
    n_this    = numel(idx_range);

    if n_pages == 1
        page_tag = 'Overview';
    else
        page_tag = sprintf('Overview %d/%d', pg, n_pages);
    end
    fig_name = ov_fig_name(page_tag, src);

    fig = figure('Name', fig_name, 'Color', BG_GRAY, ...
        'NumberTitle', 'off');
    tl = tiledlayout(fig, NROWS, NCOLS, 'TileSpacing', 'tight', 'Padding', 'compact');

    if n_pages == 1
        body = sprintf('all %d variables', nv);
    else
        body = sprintf('variables %d–%d of %d  (page %d/%d)', ...
            idx_range(1), idx_range(end), nv, pg, n_pages);
    end
    title(tl, body, 'FontSize', F.page, 'Interpreter', 'none');

    if isfield(prof, 'sampling_note') && strlength(string(prof.sampling_note)) > 0
        subtitle(tl, char(prof.sampling_note), 'FontSize', F.tiny, ...
            'FontWeight', 'bold', 'Color', 'k', 'Interpreter', 'none');
    end

    if ~is_anon
        annotation(fig, 'textbox', [0, 0, 1, 0.022], 'String', src, ...
            'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', F.tiny, ...
            'Color', CLR_SRC, 'Interpreter', 'none', ...
            'FitBoxToText', 'off');
    end

    for k = 1:n_this
        ci = all_idx(idx_range(k));
        ax = nexttile(tl);
        switch string(prof.type(ci))
            case 'numeric'
                ov_num_tile(ax, double(T.(prof.name{ci})), prof.nmissing(ci), n, fsz);
            case {'categorical', 'logical'}
                ov_cat_tile(ax, T.(prof.name{ci}), prof.nmissing(ci), n, fsz);
            case {'datetime', 'duration'}
                ov_time_tile(ax, T.(prof.name{ci}), fsz);
            otherwise
                axis(ax, 'off');
        end
        title(ax, ov_wrap(prof.name{ci}), 'FontSize', fsz, ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    end

    for k = n_this+1:PER_PAGE
        nexttile(tl);
        axis off;
    end
end
end


% ── helpers ──────────────────────────────────────────────────────────────────

function s = ov_fig_name(label, source_name)
m = regexp(source_name, '\[([^\]]+)\]\s*$', 'tokens', 'once');
if ~isempty(m)
    s = sprintf('%s: %s', label, strtrim(m{1}));
else
    s = label;
end
end


function ov_num_tile(ax, x, nmissing, n, fsz)
DATA_BLUE  = [0.35 0.55 0.75];
BAR_ALPHA  = 0.8;
CLR_DARK   = [0.2 0.2 0.2];
MISS_RED   = [0.6 0.3 0.3];
CLR_NODATA = [0.6 0.6 0.6];

valid = x(~isnan(x));
if isempty(valid)
    axis(ax, 'off');
    text(ax, 0.5, 0.5, 'all missing', 'HorizontalAlignment', 'center', ...
        'Units', 'normalized', 'Color', CLR_NODATA, 'FontSize', fsz);
    return
end
histogram(ax, valid, 'FaceColor', DATA_BLUE, 'EdgeColor', 'none', 'FaceAlpha', BAR_ALPHA);
mu = mean(valid);  sg = std(valid);
text(ax, 0.98, 0.97, sprintf('μ=%.3g  σ=%.3g', mu, sg), ...
    'Units', 'normalized', 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'top', 'FontSize', fsz, 'Color', CLR_DARK);
if nmissing > 0
    text(ax, 0.02, 0.97, sprintf('%d missing (%.0f%%)', nmissing, 100*nmissing/n), ...
        'Units', 'normalized', 'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'top', 'FontSize', fsz, 'Color', MISS_RED);
end
set(ax, 'FontSize', fsz); box(ax, 'off');
end


function ov_cat_tile(ax, x, nmissing, n, fsz)
MAX_K         = 15;
MAX_CAT_CHARS = 9;   % truncate category labels longer than this
CAT_GREEN     = [0.45 0.70 0.55];
MISS_RED      = [0.6 0.3 0.3];
if iscategorical(x)
    cats   = categories(x);
    counts = histcounts(x);
elseif islogical(x)
    cats   = {'false','true'};
    counts = [sum(~x), sum(x)];
else
    axis(ax, 'off'); return
end

[counts_s, ord] = sort(counts(:), 'descend');
cats_s = cats(ord);
nc = numel(cats_s);
if nc > MAX_K
    n_top    = MAX_K - 1;
    rest_cnt = sum(counts_s(n_top+1:end));
    counts_s = [counts_s(1:n_top); rest_cnt];
    cats_s   = [cats_s(1:n_top); {sprintf('Other (%d, n=%d)', nc-n_top, rest_cnt)}];
end
ns = numel(counts_s);

barh(ax, ns:-1:1, counts_s, 'FaceColor', CAT_GREEN, 'EdgeColor', 'none');

cats_lbl = cats_s;
for ki = 1:ns
    if ~strncmp(cats_s{ki}, 'Other (', 7)
        lbl = cats_s{ki};
        if numel(lbl) > MAX_CAT_CHARS, lbl = [lbl(1:MAX_CAT_CHARS-1) '…']; end
        cats_lbl{ki} = sprintf('%s (%d)', lbl, counts_s(ki));
    end
end
yticks(ax, 1:ns);
yticklabels(ax, flip(cats_lbl));
set(ax, 'XTick', [], 'FontSize', fsz); box(ax, 'off');

if nmissing > 0
    text(ax, 0.98, 0.97, sprintf('%d undef. (%.0f%%)', nmissing, 100*nmissing/n), ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', 'FontSize', fsz, 'Color', MISS_RED);
end
end


function ov_time_tile(ax, x, fsz)
TIME_PURPLE  = [0.65 0.50 0.75];
CLR_DARK     = [0.2 0.2 0.2];
YR_SPAN_THRESH = 2;   % spans < this many years → show months histogram

if isduration(x)
    x = datetime(0,0,0) + x;
end
valid = x(~isnat(x));
if isempty(valid), axis(ax, 'off'); return; end
span_yrs = years(max(valid) - min(valid));
if span_yrs < YR_SPAN_THRESH
    histogram(ax, month(valid), 1:13, 'FaceColor', TIME_PURPLE, 'EdgeColor', 'none');
    text(ax, 0.98, 0.97, sprintf('%d months', round(span_yrs*12)), ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', 'FontSize', fsz, 'Color', CLR_DARK);
else
    histogram(ax, year(valid), 'FaceColor', TIME_PURPLE, 'EdgeColor', 'none');
    text(ax, 0.98, 0.97, sprintf('%d–%d', year(min(valid)), year(max(valid))), ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', 'FontSize', fsz, 'Color', CLR_DARK);
end
set(ax, 'YTick', [], 'FontSize', fsz); box(ax, 'off');
end


function s = ov_wrap(name)
MAX_LINE       = 16;
MAX_WRAP_LINES = 3;
if numel(name) <= MAX_LINE
    s = name; return
end
parts = regexp(name, '[^_ ]+', 'match');
np = numel(parts);
lines_   = cell(1, np);   % one entry per output line (at most np lines)
wbuf     = cell(1, np);   % word buffer for current line
nl = 0;  nw = 0;  line_len = 0;
for k = 1:np
    p = parts{k};
    needed = numel(p) + (nw > 0);   % +1 for '_' separator
    if line_len + needed <= MAX_LINE
        nw = nw + 1;
        wbuf{nw} = p;
        line_len = line_len + needed;
    else
        nl = nl + 1;
        lines_{nl} = strjoin(wbuf(1:nw), '_');
        nw = 1;  wbuf{1} = p;  line_len = numel(p);
    end
end
if nw > 0
    nl = nl + 1;
    lines_{nl} = strjoin(wbuf(1:nw), '_');
end
lines_ = lines_(1:nl);
if isscalar(lines_)
    s = lines_{1};
else
    s = strjoin(lines_(1:min(MAX_WRAP_LINES,end)), newline);
end
end
