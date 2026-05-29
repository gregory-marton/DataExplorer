function de_plot_pairplot(T, prof, sel)
%DE_PLOT_PAIRPLOT  Scatter matrix with type-aware dispatch per cell.
%
%   de_plot_pairplot(T, prof, sel)
%
%   T    — table (already profiled)
%   prof — struct from de_profile(T)
%   sel  — column indices to include (row vector); use de_select_columns to pick
%
%   Produces one figure: an np×np grid where each cell uses the best plot type
%   for its pair of variable types:
%     numeric × numeric   → scatter + least-squares line + Pearson r
%     numeric × cat       → box plot (≤5 cats) or ranked median dot plot
%     cat × cat           → co-occurrence heatmap (top-10 × top-10)
%     datetime × numeric  → scatter ordered by time
%     diagonal            → histogram (numeric), bar chart (categorical), or
%                           datetime histogram

if isempty(sel), return; end

np = numel(sel);

src = char(prof.source_name);
fig = figure('Name', pp_fig_name('Pairplot', src), ...
    'Color', [0.97 0.97 0.97], 'NumberTitle', 'off');
pp_stamp_source(fig, src);
tl = tiledlayout(fig, np, np, 'TileSpacing', 'tight', 'Padding', 'compact');

n = height(T);

for r = 1:np
    for c = 1:np
        ax = nexttile(tl);
        ri = sel(r);
        ci = sel(c);

        rtype = prof.type(ri);
        ctype = prof.type(ci);

        xdata = T.(prof.name{ci});
        ydata = T.(prof.name{ri});
        xname = prof.name{ci};
        yname = prof.name{ri};

        if r == c
            switch rtype
                case "numeric"
                    pp_num_diag(ax, xdata, xname, prof.nmissing(ci), n);
                case {"categorical", "logical"}
                    pp_cat_diag(ax, xdata, xname, prof.nmissing(ci), n);
                case "datetime"
                    pp_time_diag(ax, xdata, xname);
                otherwise
                    axis(ax, 'off');
                    text(ax, 0.5, 0.5, char(rtype), ...
                        'HorizontalAlignment', 'center', 'Units', 'normalized');
            end

        elseif rtype == "numeric" && ctype == "numeric"
            pp_num_num(ax, xdata, ydata);

        elseif rtype == "numeric" && ismember(ctype, ["categorical","logical"])
            pp_num_cat(ax, xdata, ydata);

        elseif ismember(rtype, ["categorical","logical"]) && ctype == "numeric"
            pp_num_cat(ax, ydata, xdata);

        elseif ismember(rtype, ["categorical","logical"]) && ...
               ismember(ctype, ["categorical","logical"])
            pp_cat_cat(ax, xdata, ydata);

        elseif rtype == "datetime" || ctype == "datetime"
            pp_time_pair(ax, xdata, ydata, rtype, ctype);

        else
            axis(ax, 'off');
        end

        set(ax, 'XTick', [], 'YTick', []);
        xlabel(ax, '');
        ylabel(ax, '');

        if r == 1
            if ismember(ctype, ["categorical","logical"]) && prof.nunique(ci) > 15
                col_title = {pp_wrapped(xname), ...
                    sprintf('\\rm\\fontsize{6}top 10 of %d groups', prof.nunique(ci))};
            else
                col_title = pp_wrapped(xname);
            end
            title(ax, col_title, 'FontSize', 8, 'FontWeight', 'bold', 'Interpreter', 'tex');
        end
        if r == c && r > 1
            title(ax, pp_wrapped(yname), 'FontSize', 8, 'FontWeight', 'bold', ...
                'Interpreter', 'none');
        end
        if c == 1
            yl = ylabel(ax, pp_wrapped(yname), 'FontSize', 6, 'Interpreter', 'none');
            set(yl, 'Rotation', 0, 'HorizontalAlignment', 'right');
        end
    end
end

if n == 0
    title_str = 'no rows';
else
    title_str = sprintf('n = %d', n);
end
title(tl, title_str, 'FontSize', 11, 'Interpreter', 'none');
end


% ── Diagonal helpers ─────────────────────────────────────────────────────────

function pp_num_diag(ax, x, varname, nmissing, n)
x = double(x);
valid = x(~isnan(x));
if isempty(valid)
    axis(ax, 'off');
    text(ax, 0.5, 0.5, 'all missing', 'HorizontalAlignment', 'center', ...
        'Units', 'normalized', 'Color', [0.6 0.6 0.6]);
    return
end
h = histogram(ax, valid, 'FaceColor', [0.35 0.55 0.75], 'EdgeColor', 'none', 'FaceAlpha', 0.8);
h.DataTipTemplate.DataTipRows(1).Label = char(varname);
lo = min(valid); hi = max(valid);
mu = mean(valid); sg = std(valid); md = median(valid);
text(ax, 0.98, 0.97, ...
    sprintf('μ = %.3g\nσ = %.3g\nm = %.3g\n[%.3g, %.3g]', mu, sg, md, lo, hi), ...
    'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'FontSize', 6.5, 'Color', [0.2 0.2 0.2]);
if nmissing > 0
    text(ax, 0.02, 0.97, sprintf('%d missing (%.0f%%)', nmissing, 100*nmissing/n), ...
        'Units', 'normalized', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontSize', 6.5, 'Color', [0.6 0.3 0.3]);
end
set(ax, 'FontSize', 7); box(ax, 'off');
end


function pp_cat_diag(ax, x, varname, nmissing, n)
MAX_K = 15;
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
n_shown = numel(counts_s);
b = barh(ax, n_shown:-1:1, counts_s, 'FaceColor', [0.45 0.70 0.55], 'EdgeColor', 'none');
b.DataTipTemplate.DataTipRows(1).Label = 'Count';
b.DataTipTemplate.DataTipRows(2).Label = 'Category';
b.DataTipTemplate.DataTipRows(2).Value = cats_s;
b.DataTipTemplate.DataTipRows(end+1) = ...
    dataTipTextRow('Variable', repmat({char(varname)}, n_shown, 1));
cats_lbl = cats_s;
for ki = 1:n_shown
    if ~strncmp(cats_s{ki}, 'Other (', 7)
        cats_lbl{ki} = [pp_trunc(cats_s{ki}, 9) sprintf(' (%d)', counts_s(ki))];
    end
end
yticks(ax, 1:n_shown);
yticklabels(ax, flip(cats_lbl));
set(ax, 'XTick', [], 'FontSize', 6.5, 'TickDir', 'out');
if nmissing > 0
    text(ax, 0.98, 0.97, sprintf('%d undef. (%.0f%%)', nmissing, 100*nmissing/n), ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
        'FontSize', 6.5, 'Color', [0.6 0.3 0.3]);
end
box(ax, 'off');
end


function pp_time_diag(ax, x, varname)
if isduration(x), x = datetime(0,0,0) + x; end
valid = x(~isnat(x));
if isempty(valid), axis(ax,'off'); return; end
span_yrs = years(max(valid) - min(valid));
if span_yrs < 2
    h = histogram(ax, month(valid), 1:13, 'FaceColor', [0.65 0.50 0.75], 'EdgeColor', 'none');
    text(ax, 0.98, 0.97, sprintf('%d months', round(span_yrs*12)), ...
        'Units','normalized','HorizontalAlignment','right', ...
        'VerticalAlignment','top','FontSize',6.5,'Color',[0.2 0.2 0.2]);
else
    h = histogram(ax, year(valid), 'FaceColor', [0.65 0.50 0.75], 'EdgeColor', 'none');
    text(ax, 0.98, 0.97, sprintf('%d–%d', year(min(valid)), year(max(valid))), ...
        'Units','normalized','HorizontalAlignment','right', ...
        'VerticalAlignment','top','FontSize',6.5,'Color',[0.2 0.2 0.2]);
end
h.DataTipTemplate.DataTipRows(1).Label = char(varname);
set(ax, 'YTick', [], 'FontSize', 7); box(ax, 'off');
end


% ── Off-diagonal helpers ─────────────────────────────────────────────────────

function pp_num_num(ax, x, y)
valid = ~isnan(x) & ~isnan(y);
xv = double(x(valid));
yv = double(y(valid));
if isempty(xv), axis(ax,'off'); return; end

if pp_is_discrete(xv) && ~pp_is_discrete(yv)
    pp_boxchart(ax, xv, yv); return
elseif pp_is_discrete(yv) && ~pp_is_discrete(xv)
    pp_boxchart(ax, yv, xv); return
end

MAX_PTS = 5000;
if numel(xv) > MAX_PTS
    idx = randperm(numel(xv), MAX_PTS);
    xv = xv(idx); yv = yv(idx);
end
scatter(ax, xv, yv, 8, [0.25 0.45 0.70], 'filled', ...
    'MarkerFaceAlpha', min(1, 500/numel(xv)));
hold(ax, 'on');
prev_warn = warning('off', 'MATLAB:polyfit:RepeatedPointsOrRescale');
lastwarn('');
p = polyfit(xv, yv, 1);
[~, wid] = lastwarn();
warning(prev_warn);
if isempty(wid)
    xl = xlim(ax);
    plot(ax, xl, polyval(p, xl), 'r-', 'LineWidth', 1.2);
end
r = corr(xv, yv, 'rows', 'complete');
if isnan(r), r_str = 'r = ?'; else, r_str = sprintf('r = %.2f', r); end
text(ax, 0.03, 0.97, r_str, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
    'FontSize', 7.5, 'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.7], 'Margin', 1);
hold(ax, 'off'); box(ax, 'off');
end


function pp_num_cat(ax, catdata, numdata)
MAX_BOX  = 5;
MAX_DOTS = 15;
if iscategorical(catdata)
    cats  = categories(catdata);
    valid = ~isundefined(catdata) & ~isnan(numdata);
elseif islogical(catdata)
    cats    = {'false','true'};
    catdata = categorical(double(catdata), [0 1], {'false','true'});
    valid   = ~isnan(numdata);
else
    axis(ax, 'off'); return
end
catdata = catdata(valid);
numdata = numdata(valid);
if isempty(numdata), axis(ax, 'off'); return; end

if numel(cats) <= MAX_BOX
    nc = numel(cats); xpos = double(catdata);
    hold(ax, 'on');
    for ki = 1:nc
        mask = xpos == ki;
        if ~any(mask), continue; end
        vals = numdata(mask);
        q    = quantile(vals, [0.25 0.5 0.75]);
        iqr_ = q(3) - q(1);
        wlo  = max(min(vals), q(1) - 1.5*iqr_);
        whi  = min(max(vals), q(3) + 1.5*iqr_);
        patch(ax, ki + [-0.3 0.3 0.3 -0.3], [q(1) q(1) q(3) q(3)], ...
            [0.35 0.55 0.75], 'EdgeColor', [0.2 0.2 0.2], 'LineWidth', 0.8);
        plot(ax, ki + [-0.3 0.3], [q(2) q(2)], '-', 'Color', [0.1 0.1 0.1], 'LineWidth', 1.5);
        plot(ax, [ki ki], [wlo q(1)], '-', 'Color', [0.2 0.2 0.2]);
        plot(ax, [ki ki], [q(3) whi], '-', 'Color', [0.2 0.2 0.2]);
    end
    hold(ax, 'off');
else
    all_cats = categories(catdata);
    n_cats   = numel(all_cats);
    med_vals = NaN(n_cats, 1);
    iqr_vals = NaN(n_cats, 1);
    for ki = 1:n_cats
        vals = numdata(catdata == all_cats{ki});
        if ~isempty(vals)
            med_vals(ki) = median(vals, 'omitnan');
            iqr_vals(ki) = iqr(vals);
        end
    end
    valid_med = find(~isnan(med_vals));
    [~, sort_ord] = sort(med_vals(valid_med));
    valid_med = valid_med(sort_ord);
    if numel(valid_med) <= MAX_DOTS
        sel = valid_med;
    else
        pick_pos = unique(round(linspace(1, numel(valid_med), MAX_DOTS)));
        sel = valid_med(pick_pos);
    end
    not_sel = setdiff(valid_med, sel);
    [~, disp_ord] = sort(med_vals(sel), 'ascend');
    sel = sel(disp_ord);
    other_med = NaN; other_iqr = 0;
    if ~isempty(not_sel)
        ov = numdata(ismember(catdata, all_cats(not_sel)));
        ov = ov(~isnan(ov));
        if ~isempty(ov), other_med = median(ov); other_iqr = iqr(ov); end
    end
    hold(ax, 'on');
    for ki = 1:numel(sel)
        oi = sel(ki); med = med_vals(oi);
        if isnan(med), continue; end
        half_iqr = iqr_vals(oi)/2;
        plot(ax, [med-half_iqr, med+half_iqr], [ki ki], '-', 'Color', [0.6 0.7 0.8], 'LineWidth', 1.5);
        plot(ax, med, ki, 'o', 'MarkerSize', 5, 'MarkerFaceColor', [0.22 0.44 0.69], 'MarkerEdgeColor', 'none');
    end
    if ~isnan(other_med)
        y_oth = numel(sel)+1; half_iqr = other_iqr/2;
        plot(ax, [other_med-half_iqr, other_med+half_iqr], [y_oth y_oth], '-', 'Color', [0.72 0.72 0.72], 'LineWidth', 1.5);
        plot(ax, other_med, y_oth, 'o', 'MarkerSize', 5, 'MarkerFaceColor', [0.55 0.55 0.55], 'MarkerEdgeColor', 'none');
    end
    hold(ax, 'off');
end
set(ax, 'XTick', [], 'YTick', []); box(ax, 'off');
end


function pp_cat_cat(ax, x, y)
MAX_CATS = 10;
if ~iscategorical(x), x = categorical(x); end
if ~iscategorical(y), y = categorical(y); end
valid = ~isundefined(x) & ~isundefined(y);
x = x(valid); y = y(valid);
if isempty(x), axis(ax, 'off'); return; end
cx = pp_top_cats(x, MAX_CATS);
cy = pp_top_cats(y, MAX_CATS);
keep = ismember(x, cx) & ismember(y, cy);
x = x(keep); y = y(keep);
if isempty(x), axis(ax, 'off'); return; end
M = zeros(numel(cy), numel(cx));
for ri = 1:numel(cy)
    for ci = 1:numel(cx)
        M(ri,ci) = sum(x == cx{ci} & y == cy{ri});
    end
end
imagesc(ax, M);
blues = interp1([0 1], [1 1 1; 0.13 0.44 0.71], linspace(0,1,64));
colormap(ax, blues);
set(ax, 'XTick', [], 'YTick', []);
if numel(cx) <= 2 && numel(cy) <= 2
    set(ax, 'XTick', 1:numel(cx), 'YTick', 1:numel(cy), ...
        'XTickLabel', cellfun(@(s) pp_trunc(s,6), cx, 'UniformOutput', false), ...
        'YTickLabel', cellfun(@(s) pp_trunc(s,6), cy, 'UniformOutput', false), ...
        'FontSize', 6, 'TickLength', [0 0]);
end
box(ax, 'off');
end


function pp_time_pair(ax, x, y, rtype, ctype)
if rtype == "datetime" && ctype == "numeric"
    tdata = x; ndata = y;
elseif ctype == "datetime" && rtype == "numeric"
    tdata = y; ndata = x;
else
    axis(ax, 'off'); return
end
valid = ~isnat(tdata) & ~isnan(ndata);
if ~any(valid), axis(ax,'off'); return; end
[ts, ord] = sort(tdata(valid));
ns = ndata(valid); ns = ns(ord);
plot(ax, ts, ns, '.', 'Color', [0.35 0.55 0.75], 'MarkerSize', 4);
box(ax, 'off');
end


% ── Utility helpers ──────────────────────────────────────────────────────────

function tf = pp_is_discrete(v)
tf = numel(unique(v)) <= 25 && max(abs(v - round(v))) < 0.01;
end


function pp_boxchart(ax, grp, vals)
grp_cat = categorical(grp);
try
    boxchart(ax, grp_cat, vals, 'BoxFaceColor', [0.25 0.45 0.70], ...
        'WhiskerLineColor', [0.25 0.45 0.70], 'MarkerColor', [0.25 0.45 0.70], ...
        'MarkerStyle', '.', 'BoxWidth', 0.6);
    xtickangle(ax, 45);
    ax.XAxis.FontSize = 6;
catch
    scatter(ax, double(grp_cat), vals, 8, [0.25 0.45 0.70], 'filled', ...
        'MarkerFaceAlpha', min(1, 500/numel(vals)));
end
box(ax, 'off');
end


function cats = pp_top_cats(x, k)
all_cats = categories(x);
counts   = histcounts(x);
[~, ord] = sort(counts, 'descend');
cats     = all_cats(ord(1:min(k, end)));
end


function s = pp_trunc(str, maxlen)
if numel(str) > maxlen
    s = [str(1:maxlen-1), '…'];
else
    s = str;
end
end


function s = pp_wrapped(name)
MAX_LINE = 16;
if numel(name) <= MAX_LINE, s = name; return; end
parts = regexp(name, '[^_ ]+', 'match');
if isempty(parts), s = name; return; end
lines_ = cell(1, numel(parts));
nl = 0; cur = parts{1};
for k = 2:numel(parts)
    cand = [cur '_' parts{k}];
    if numel(cand) <= MAX_LINE
        cur = cand;
    else
        nl = nl + 1; lines_{nl} = cur;
        cur = parts{k};
    end
end
nl = nl + 1; lines_{nl} = cur;
s = strjoin(lines_(1:nl), newline);
end


function s = pp_fig_name(label, source_name)
m = regexp(char(source_name), '\[([^\]]+)\]\s*$', 'tokens', 'once');
if ~isempty(m)
    s = sprintf('%s: %s', label, strtrim(m{1}));
else
    s = label;
end
end


function pp_stamp_source(fig, source_name)
if isempty(source_name) || strcmp(source_name, 'table input'), return; end
annotation(fig, 'textbox', [0.0, 0.0, 1.0, 0.022], 'String', source_name, ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontSize', 7, 'Color', [0.55 0.55 0.55], 'Interpreter', 'none', 'FitBoxToText', 'off');
end
