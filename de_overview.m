function de_overview(T, prof, options)
%DE_OVERVIEW  Per-variable diagnostic tiles in a paginated 4×2 grid.
%
%   de_overview(T, prof)
%   de_overview(T, prof, MaxVars=N)     % stop after N variables
%   de_overview(T, prof, FontSize=sz)   % base font size (default 8)
%
%   T     — MATLAB table (already profiled)
%   prof  — struct from de_profile(T)
%
%   Creates one or more figures (one per page, 8 tiles each).
%   All profile metadata (type, n, unique, missing, skip, geo, panel, stats)
%   appears in the per-tile subtitle — never inside the chart area.
%   Requires no toolboxes.

arguments
    T     table
    prof  struct
    options.MaxVars  (1,1) double {mustBePositive} = Inf
    options.FontSize (1,1) double {mustBePositive} = 8
end

NCOLS    = 4;
NROWS    = 2;
PER_PAGE = NCOLS * NROWS;
F        = de__font_sizes(options.FontSize);
fsz      = F.base;
BG_GRAY  = [0.97 0.97 0.97];

all_idx = 1:numel(prof.name);
if isfinite(options.MaxVars)
    all_idx = all_idx(1:min(options.MaxVars, numel(all_idx)));
end

nv = numel(all_idx);
if nv == 0, return; end

n       = height(T);
n_total = n;
ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'n_orig') && ud.n_orig > n
    n_total = ud.n_orig;
end

n_pages = ceil(nv / PER_PAGE);
src     = char(prof.source_name);

for pg = 1:n_pages
    idx_range = (pg-1)*PER_PAGE+1 : min(pg*PER_PAGE, nv);
    n_this    = numel(idx_range);

    if n_pages == 1
        page_tag = 'Overview';
    else
        page_tag = sprintf('Overview %d/%d', pg, n_pages);
    end
    fig = figure('Name', de__fig_title(page_tag, src), 'Color', BG_GRAY, ...
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

    de__stamp_source(fig, src);

    for k = 1:n_this
        ci   = all_idx(idx_range(k));
        ax   = nexttile(tl);
        typ  = string(prof.type(ci));
        sk   = NaN;
        if isfield(prof, 'skewness'), sk = prof.skewness(ci); end

        % ── Draw chart (no text annotations inside) ───────────────────────
        mu = NaN;  sg = NaN;  scale_type = '';
        switch typ
            case 'numeric'
                x = double(T.(prof.name{ci}));
                valid_x = x(~isnan(x));
                if ~isempty(valid_x)
                    mu = mean(valid_x);
                    sg = std(valid_x);
                end
                scale_type = ov_num_tile(ax, x, fsz, sk, prof.skip(ci));

            case {'categorical', 'logical'}
                ov_cat_tile(ax, T.(prof.name{ci}), fsz, prof.skip(ci));

            case {'datetime', 'duration'}
                ov_time_tile(ax, T.(prof.name{ci}), fsz, prof.skip(ci));

            otherwise
                ov_unknown_tile(ax, fsz);
        end

        % ── Title: column name (bold) ──────────────────────────────────────
        title(ax, ov_col_title(prof.name{ci}), 'FontSize', fsz, ...
            'FontWeight', 'bold', 'Interpreter', 'none');

        % ── Subtitle: all profile metadata + chart stats (one item per line) ─
        meta = ov_meta_line(prof, ci, n, n_total, typ, mu, sg, sk, scale_type);
        subtitle(ax, meta, 'FontSize', fsz - 1, ...
            'FontWeight', 'normal', 'Color', [0.30 0.30 0.30], ...
            'Interpreter', 'none');
    end

    for k = n_this+1:PER_PAGE
        nexttile(tl);
        axis off;
    end
end
end


% ── Chart helpers (draw only — no text inside the axes) ──────────────────────

function scale_type = ov_num_tile(ax, x, fsz, skewness_val, is_skip)
DATA_BLUE   = [0.35 0.55 0.75];
CLR_SEMILOG = [0.93 0.55 0.15];   % orange — log x axis
CLR_LOGLOG  = [0.58 0.29 0.78];   % violet — both axes log
BAR_ALPHA   = 0.8;
CLR_NODATA  = [0.6 0.6 0.6];
scale_type  = '';

valid = x(~isnan(x));
if isempty(valid)
    axis(ax, 'off');
    text(ax, 0.5, 0.5, 'all missing', 'HorizontalAlignment', 'center', ...
        'Units', 'normalized', 'Color', CLR_NODATA, 'FontSize', fsz);
    return
end

% Choose log scale: three cases based on the sign mix.
has_pos   = any(valid > 0);
has_neg   = any(valid < 0);
pos_vals  = valid(valid > 0);
neg_mags  = -valid(valid < 0);   % magnitudes of negative values
is_skewed = ~isnan(skewness_val) && abs(skewness_val) > 2.5;

use_symlog = false;  use_logx = false;  pct_omit = 0;

if has_pos && has_neg && is_skewed
    span_pos = ~isempty(pos_vals)  && max(pos_vals)  / min(pos_vals)  > 100;
    span_neg = ~isempty(neg_mags)  && max(neg_mags)  / min(neg_mags)  > 100;
    use_symlog = span_pos || span_neg;
elseif is_skewed
    one_side = pos_vals;
    if isempty(one_side), one_side = neg_mags; end
    pct_one  = numel(one_side) / numel(valid);
    pct_omit = 1 - pct_one;
    use_logx = pct_one > 0.5 && ~isempty(one_side) && max(one_side)/min(one_side) > 100;
end

if use_symlog
    % Symmetric log: f(x) = sign(x) * log10(1 + |x|)
    x_trans = sign(valid) .* log10(1 + abs(valid));
    lo = min(x_trans);  hi = max(x_trans);
    histogram(ax, x_trans, linspace(lo, hi, 32), ...
        'EdgeColor', 'none', 'FaceAlpha', BAR_ALPHA, 'FaceColor', CLR_SEMILOG);
    % Tick marks at 0 and ±powers of 10 within data range
    max_abs  = max(abs(valid));
    max_exp  = max(0, floor(log10(max_abs + eps)));
    pow_list = 10.^(0:max_exp);
    pos_tks  = pow_list(has_pos & pow_list <=  max(valid) * 1.01);
    neg_tks  = pow_list(has_neg & pow_list <= -min(valid) * 1.01);
    tick_orig  = sort([0, pos_tks, -neg_tks]);
    tick_trans = sign(tick_orig) .* log10(1 + abs(tick_orig));
    xticks(ax, tick_trans);
    xticklabels(ax, arrayfun(@(v) num2str(v, '%g'), tick_orig, 'UniformOutput', false));
    scale_type = 'symlog';

elseif use_logx
    one_side = pos_vals;
    if isempty(one_side), one_side = neg_mags; end
    edges = logspace(log10(min(one_side)), log10(max(one_side)), 31);
    plot_vals = valid(valid > 0);
    if isempty(plot_vals), plot_vals = -valid(valid < 0); end
    h = histogram(ax, plot_vals, edges, 'EdgeColor', 'none', 'FaceAlpha', BAR_ALPHA);
    counts    = h.Values;
    pos_cnts  = counts(counts > 0);
    if ~isempty(pos_cnts) && max(counts) / min(pos_cnts) > 100
        set(ax, 'YScale', 'log');
        yl = ylim(ax);
        if yl(1) <= 0, yl(1) = 0.5; end
        if log10(yl(2)) - log10(yl(1)) < 1
            set(ax, 'YLim', [yl(1), yl(1) * 10]);
        end
        h.FaceColor = CLR_LOGLOG;
        scale_type  = 'log-log';
    else
        h.FaceColor = CLR_SEMILOG;
        if pct_omit > 0
            scale_type = sprintf('log x  (%.0f%% zeros omitted)', 100*pct_omit);
        else
            scale_type = 'log x';
        end
    end
    set(ax, 'XScale', 'log');
else
    histogram(ax, valid, 'FaceColor', DATA_BLUE, 'EdgeColor', 'none', 'FaceAlpha', BAR_ALPHA);
end

if is_skip
    set(ax, 'Color', [1.00 0.96 0.96]);
end
set(ax, 'FontSize', fsz); box(ax, 'off');
end


function ov_cat_tile(ax, x, fsz, is_skip)
MAX_K         = 12;
MAX_CAT_CHARS = 20;
CAT_GREEN     = [0.45 0.70 0.55];
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
        if numel(lbl) > MAX_CAT_CHARS, lbl = [lbl(1:MAX_CAT_CHARS-1) char(8230)]; end
        cats_lbl{ki} = sprintf('%s (%d)', lbl, counts_s(ki));
    end
end
yticks(ax, 1:ns);
yticklabels(ax, flip(cats_lbl));
set(ax, 'XTick', [], 'FontSize', fsz); box(ax, 'off');
if is_skip
    set(ax, 'Color', [1.00 0.96 0.96]);
end
end


function ov_time_tile(ax, x, fsz, is_skip)
TIME_PURPLE    = [0.65 0.50 0.75];
YR_SPAN_THRESH = 2;

if isduration(x)
    x = datetime(0,0,0) + x;
end
valid = x(~isnat(x));
if isempty(valid), axis(ax, 'off'); return; end
span_yrs = years(max(valid) - min(valid));
if span_yrs < YR_SPAN_THRESH
    histogram(ax, month(valid), 1:13, 'FaceColor', TIME_PURPLE, 'EdgeColor', 'none');
else
    histogram(ax, year(valid), 'FaceColor', TIME_PURPLE, 'EdgeColor', 'none');
end
set(ax, 'FontSize', fsz); box(ax, 'off');
if is_skip
    set(ax, 'Color', [1.00 0.96 0.96]);
end
end


function ov_unknown_tile(ax, fsz)
CLR_NODATA = [0.6 0.6 0.6];
axis(ax, 'off');
text(ax, 0.5, 0.5, 'unknown type', 'HorizontalAlignment', 'center', ...
    'Units', 'normalized', 'Color', CLR_NODATA, 'FontSize', fsz);
end


% ── Subtitle metadata builder ─────────────────────────────────────────────────

function s = ov_meta_line(prof, ci, n, n_total, typ, mu, sg, sk, scale_type)
lines = {};

% ── Row 1: semantic role — base type (+ conversion) ─────────────────────────
type_str = char(typ);
if isfield(prof, 'orig_class') && prof.orig_class(ci) == "text"
    type_str = [type_str '  ' char(8592) ' text'];
end
role = "";
if isfield(prof, 'role'), role = prof.role(ci); end
if role ~= ""
    role_label = char(role);
    if role == "geographic" && isfield(prof, 'geo_grid') && ~isempty(prof.geo_grid{ci})
        role_label = [role_label ' (' prof.geo_grid{ci} ')'];
    end
    type_str = sprintf('%s  %s  %s', role_label, char(8212), type_str);
end
lines{end+1} = type_str;

% ── Row 2: n, unique, missing ─────────────────────────────────────────────
if n_total > n
    n_str = sprintf('n=%s of %s', ov_kfmt(n), ov_kfmt(n_total));
else
    n_str = sprintf('n=%s', ov_kfmt(n));
end
uniq_str = sprintf('%s unique', ov_kfmt(prof.nunique(ci)));
if prof.nmissing(ci) > 0
    pct = 100 * prof.nmissing(ci) / max(n, 1);
    if pct < 0.1
        miss_str = sprintf('%d missing', prof.nmissing(ci));
    else
        miss_str = sprintf('%.1f%% missing', pct);
    end
    lines{end+1} = [n_str '   ' uniq_str '   ' miss_str];
else
    lines{end+1} = [n_str '   ' uniq_str];
end

% ── Row 3: numeric stats + scale ─────────────────────────────────────────
if ~isnan(mu) && ~isnan(sg)
    mu_sym = char(956);  sg_sym = char(963);
    if ~isnan(sk) && abs(sk) > 1
        stat_str = sprintf([mu_sym '=%.3g  ' sg_sym '=%.3g  sk=%.2g'], mu, sg, sk);
    else
        stat_str = sprintf([mu_sym '=%.3g  ' sg_sym '=%.3g'], mu, sg);
    end
    if ~isempty(scale_type)
        stat_str = [stat_str '  (' scale_type ')'];
    end
    lines{end+1} = stat_str;
elseif ~isempty(scale_type)
    lines{end+1} = scale_type;
end

% ── Row 4: geo / panel / skip ─────────────────────────────────────────────
extra = {};
if isfield(prof, 'geo_grid') && ~isempty(prof.geo_grid{ci})
    extra{end+1} = sprintf('geo: %s', prof.geo_grid{ci});
end
if isfield(prof, 'panel') && prof.panel.is_panel
    if ~isempty(prof.panel.geo_idx) && ci == prof.panel.geo_idx
        extra{end+1} = 'panel: geo';
    elseif ismember(ci, prof.panel.grouping_idxs)
        extra{end+1} = 'panel: grouping';
    elseif ismember(ci, prof.panel.wide_yr_idxs)
        extra{end+1} = 'panel: year col';
    end
end
if prof.skip(ci)
    extra{end+1} = sprintf('SKIP: %s', char(prof.skip_reason(ci)));
end
if ~isempty(extra)
    lines{end+1} = strjoin(extra, '   ');
end

s = strjoin(lines, newline);
end


function s = ov_kfmt(n)
n = double(n);
if n >= 1e6
    s = sprintf('%.1fM', n/1e6);
elseif n >= 10000
    s = sprintf('%.0fK', n/1000);
else
    s = sprintf('%d', round(n));
end
end


function s = ov_col_title(name)
MAX_LINE       = 22;
MAX_WRAP_LINES = 2;
if numel(name) <= MAX_LINE
    s = name; return
end
parts = regexp(name, '[^_ ]+', 'match');
np = numel(parts);
lines_   = cell(1, np);
wbuf     = cell(1, np);
nl = 0;  nw = 0;  line_len = 0;
for k = 1:np
    p = parts{k};
    needed = numel(p) + (nw > 0);
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
