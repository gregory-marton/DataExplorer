function de_plot_cat_association(T, prof, options)
%DE_PLOT_CAT_ASSOCIATION  Visualise pairwise associations between categorical columns.
%
%   de_plot_cat_association(T, prof)
%   de_plot_cat_association(T, prof, MaxPairs=5, VThresh=0.05)
%   de_plot_cat_association(T, prof, Figure="vmatrix")
%   de_plot_cat_association(T, prof, Figure="pair", Columns=["ColA" "ColB"])
%
%   Name-value options
%   ------------------
%   MaxPairs   Max number of full-page pair figures to produce (default 3)
%   VThresh    Min Cramer's V to qualify for a pair figure (default 0.10)
%   Figure     "all" | "vmatrix" | "pair"  (default "all")
%   Columns    [colA colB] string array — required when Figure="pair"
arguments
    T     table
    prof  struct
    options.MaxPairs  (1,1) double = 3
    options.VThresh   (1,1) double = 0.10
    options.Figure    (1,1) string = "all"
    options.Columns   (1,:) string = string([])
    options.ForcePlot (1,1) string = "auto"
end

MAX_LABEL          = 25;
MAX_PAIRS          = options.MaxPairs;
V_THRESH           = options.VThresh;
PARETO_MAX_GROUPS  = 6;
STACKED_MAX_GROUPS = 15;
V_ANNOTATE_THRESH  = 0.05;
GLYPH_MAX_COLS     = 10;
src = ca_source_prefix(prof);

if options.Figure == "pair"
    if numel(options.Columns) ~= 2
        error('de_plot_cat_association: Figure="pair" requires Columns=[colA colB].');
    end
    col_a = options.Columns(1); col_b = options.Columns(2);
    v = de_cramer_v(T.(col_a), T.(col_b));
    ca_plot_pair(T.(col_a), T.(col_b), col_a, col_b, v, src, MAX_LABEL, ...
        PARETO_MAX_GROUPS, STACKED_MAX_GROUPS, char(options.ForcePlot));
    return
end

cat_mask = (prof.type == "categorical" | prof.type == "logical") & ~prof.skip;
cat_idx  = find(cat_mask);
if numel(cat_idx) < 2, return; end
names = prof.name(cat_idx);
nc    = numel(cat_idx);

col_coverage = zeros(nc, 1);
for k = 1:nc
    xk = categorical(T.(names{k}));
    col_coverage(k) = sum(~isundefined(xk)) / height(T);
end

V_mat = zeros(nc, nc);
P_mat = ones(nc, nc);
U_mat = zeros(nc, nc);
for i = 1:nc
    for j = i+1:nc
        [v, p] = de_cramer_v(T.(names{i}), T.(names{j}));
        V_mat(i,j) = v; V_mat(j,i) = v;
        P_mat(i,j) = p; P_mat(j,i) = p;
        [U_mat(i,j), U_mat(j,i)] = ca_theil_u(T.(names{i}), T.(names{j}));
    end
end

ca_plot_v_matrix(V_mat, P_mat, U_mat, col_coverage, names, src, MAX_LABEL, V_ANNOTATE_THRESH, GLYPH_MAX_COLS);

if options.Figure == "vmatrix", return; end

pairs = zeros(nc*(nc-1)/2, 3);
np = 0;
for i = 1:nc
    for j = i+1:nc
        if V_mat(i,j) >= V_THRESH
            np = np + 1;
            pairs(np,:) = [i, j, V_mat(i,j)];
        end
    end
end
pairs = pairs(1:np,:);
if isempty(pairs), return; end
[~, ord] = sort(pairs(:,3), 'descend');
pairs = pairs(ord(1:min(MAX_PAIRS,end)), :);
for k = 1:size(pairs,1)
    ca_plot_pair(T.(names{pairs(k,1)}), T.(names{pairs(k,2)}), ...
        names{pairs(k,1)}, names{pairs(k,2)}, pairs(k,3), src, MAX_LABEL, ...
        PARETO_MAX_GROUPS, STACKED_MAX_GROUPS, 'auto');
end
end


function ca_plot_v_matrix(V_mat, P_mat, U_mat, col_cov, names, src, max_lbl, v_annotate, glyph_max_cols)
FONT_BASE = 9;
nc  = numel(names);
fig = figure('Name', ca_fig_name("Association Strength", src));
ax  = axes(fig);
imagesc(ax, V_mat, [0 1]);
blues = interp1([0 1], [1 1 1; 0.13 0.44 0.71], linspace(0,1,64));
colormap(ax, blues);
cb = colorbar(ax);
cb.Label.String = "Cramer's V  (0=independent, 1=fully associated)";
short = cellfun(@(s) ca_trunc(s,max_lbl), names, 'UniformOutput', false);
set(ax, 'XTick', 1:nc, 'YTick', 1:nc, ...
    'XTickLabel', short, 'YTickLabel', short, ...
    'XTickLabelRotation', 40, 'FontSize', FONT_BASE-1, 'TickLength', [0 0]);
sub = "Bias-Corrected Cramer's V";
if ~isempty(src), sub = sub + "  |  " + src; end
title(ax, {"Association Strength", sub}, 'FontSize', FONT_BASE+1);
draw_glyphs = nc <= glyph_max_cols;
for i = 1:nc
    for j = 1:nc
        if i == j, continue; end
        if i < j
            if V_mat(i,j) >= v_annotate
                text(ax, j, i, {sprintf('%.2f', V_mat(i,j)), ca_fmt_p(P_mat(i,j))}, ...
                    'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, ...
                    'Color', ca_label_color(V_mat(i,j)));
            end
        elseif draw_glyphs
            fh = col_cov(j);
            fv = col_cov(i);
            xl = j-0.5; yt = i-0.5; ym = i+0.5-fv;
            ca_fill_rect(ax, xl, yt, 1, 1, [0.75 0.75 0.75], 0.75);
            if fh > 0 && fv > 0
                ca_fill_rect(ax, xl, ym, fh, fv, [0.88 0.58 0.75], 0.60);
            end
            patch(ax, [xl xl+1 xl+1 xl xl], [yt yt yt+1 yt+1 yt], 'w', ...
                'FaceColor', 'none', 'EdgeColor', [0.20 0.20 0.20], 'LineWidth', 0.8);
            ca_draw_arrow(ax, j, i, U_mat(j,i) - U_mat(i,j));
        end
    end
end
gclr = [0.20 0.20 0.20];
for k = 0.5:nc+0.5
    line(ax, [0.5 nc+0.5], [k k], 'Color', gclr, 'LineWidth', 0.5);
    line(ax, [k k], [0.5 nc+0.5], 'Color', gclr, 'LineWidth', 0.5);
end
nm_dc = names; vm_dc = V_mat;
dcm = datacursormode(fig);
dcm.UpdateFcn = @(~,ev) ca_vmat_tip(ev, nm_dc, vm_dc);
end


function ca_plot_pair(x, y, xname, yname, V, src, max_lbl, pareto_max_grp, stacked_max_grp, force_plot)
if ~iscategorical(x), x = categorical(x); end
if ~iscategorical(y), y = categorical(y); end
valid = ~isundefined(x) & ~isundefined(y);
x = x(valid); y = y(valid);
cx = categories(x); nx = numel(cx);
cy = categories(y); ny = numel(cy);
if nx <= ny
    grp = x; gname = xname; gcats = cx; ng = nx;
    val = y; vname = yname; vcats = cy;
else
    grp = y; gname = yname; gcats = cy; ng = ny;
    val = x; vname = xname; vcats = cx;
end
ftitle = sprintf('%s x %s  (V = %.2f)', ca_trunc(gname,max_lbl), ca_trunc(vname,max_lbl), V);
fig    = figure('Name', ca_fig_name(ftitle, src));
if strcmp(force_plot,'pareto') || (strcmp(force_plot,'auto') && ng <= pareto_max_grp)
    ca_pareto_multiples(fig, grp, gname, gcats, val, ftitle, max_lbl);
elseif strcmp(force_plot,'stacked') || (strcmp(force_plot,'auto') && ng <= stacked_max_grp)
    ca_stacked_bars(fig, grp, gname, gcats, val, vcats, ftitle, max_lbl);
else
    ca_cond_heatmap(fig, grp, gname, gcats, val, vname, vcats, ftitle, max_lbl);
end
end


function ca_pareto_multiples(fig, grp, gname, gcats, val, ftitle, max_lbl)
MAX_B     = 15;
FONT_BASE = 9;
ng     = numel(gcats);
ncol   = min(ng, 3);
nrow   = ceil(ng / ncol);

% Layout constants
PAD_L  = 0.09;
PAD_R  = 0.04;
PAD_T  = 0.12;
PAD_B  = 0.14;
GAP_H  = 0.08;
GAP_V  = 0.16;
plot_h = (1 - PAD_T - PAD_B - (nrow-1)*GAP_V) / nrow;

% Global top-MAX_B val categories by total count across all groups.
% Each subplot shows whichever of these appear in its group (non-zero),
% sorted descending, plus a local "Other" bar for the remaining tail.
% bars_k(k) drives subplot width so real-estate reflects data density.
vcats_all = categories(val);
all_cn    = arrayfun(@(c) sum(val == c{1}), vcats_all);
[~, global_ord] = sort(all_cn, 'descend');
ns_global   = min(MAX_B, sum(all_cn > 0));
global_cats = vcats_all(global_ord(1:ns_global));
gc_str      = string(global_cats);

bars_k = ones(ng, 1);
for k = 1:ng
    sv_k      = val(grp == gcats{k});
    cn_k      = arrayfun(@(c) sum(sv_k == c{1}), global_cats);
    has_oth_k = any(~ismember(string(sv_k), gc_str));
    bars_k(k) = max(1, sum(cn_k > 0) + has_oth_k);
end

sgtitle(fig, ftitle, 'FontSize', FONT_BASE+1, 'Interpreter', 'none');

axs     = gobjects(ng, 1);
cp_list = cell(ng, 1);
ci_list = cell(ng, 1);
max_cnt = 0;

for k = 1:ng
    mask = (grp == gcats{k});
    sv   = val(mask);
    if isempty(sv), continue; end
    % Show globally-selected categories present in this group, sorted desc
    cn_k  = arrayfun(@(c) sum(sv == c{1}), global_cats);
    keep  = cn_k > 0;
    ls    = global_cats(keep);
    cn    = cn_k(keep);
    [cs, ord] = sort(cn, 'descend');
    ls    = ls(ord);
    % Other = local observations outside the global top-MAX_B
    sv_str    = string(sv);
    in_global = ismember(sv_str, gc_str);
    other_cnt = sum(~in_global);
    other_n_t = numel(unique(sv_str(~in_global)));
    if other_cnt > 0
        cp      = [cs; other_cnt];
        lp      = [cellfun(@(s) ca_trunc(s,max_lbl), ls, 'UniformOutput', false); ...
                   {sprintf('Other (%d)', other_n_t)}];
        full_lp = [ls; {sprintf('Other (%d categories)', other_n_t)}];
    else
        cp      = cs;
        lp      = cellfun(@(s) ca_trunc(s,max_lbl), ls, 'UniformOutput', false);
        full_lp = ls;
    end
    tot = sum(cp);
    cum = cumsum(100 * cp / tot);

    % Variable-width position within row
    ri      = floor((k-1) / ncol);
    ci      = mod(k-1, ncol);
    r_start = ri * ncol + 1;
    r_end   = min((ri+1)*ncol, ng);
    r_idxs  = r_start:r_end;
    local_j = ci + 1;
    frac_w  = bars_k(r_idxs) / sum(bars_k(r_idxs));
    avail_w = 1 - PAD_L - PAD_R - (numel(r_idxs)-1)*GAP_H;
    w_k     = frac_w(local_j) * avail_w;
    left_k  = PAD_L + sum(frac_w(1:local_j-1)) * avail_w + (local_j-1)*GAP_H;
    bot_k   = 1 - PAD_T - (ri+1)*plot_h - ri*GAP_V;
    ax      = axes('Parent', fig, 'Position', [left_k, bot_k, w_k, plot_h]);

    % Bars: raw counts
    b = bar(ax, 1:numel(cp), cp, 'FaceColor', [0 0.4470 0.7410], 'EdgeColor', 'none');
    b.DataTipTemplate.DataTipRows = [
        dataTipTextRow('Category', full_lp)
        dataTipTextRow('Count',    num2cell(double(cp)))
    ];

    % CI bars in count space (binomial SE); caps may exceed ylim — intentional
    p_hat    = cp / tot;
    ci_hw_ct = 1.96 * sqrt(tot .* p_hat .* (1 - p_hat));
    hold(ax, 'on');
    errorbar(ax, 1:numel(cp), cp, ci_hw_ct, ci_hw_ct, ...
        'LineStyle', 'none', 'Color', [0.25 0.25 0.25], ...
        'CapSize', 3, 'LineWidth', 0.7);

    % Right axis: cumulative %
    yyaxis(ax, 'right');
    plot(ax, 1:numel(cum), cum, '-o', 'Color', [0.55 0.10 0.20], 'MarkerSize', 4);
    ylim(ax, [0 100]);
    ylabel(ax, 'Cumulative %', 'FontSize', FONT_BASE);
    ax.YAxis(2).Color = [0.55 0.10 0.20];

    % Left axis: count, bold
    yyaxis(ax, 'left');
    set(ax, 'XTick', 1:numel(cp), 'XTickLabel', lp, ...
        'XTickLabelRotation', 40, 'FontSize', FONT_BASE, 'TickLength', [0 0]);
    ylabel(ax, 'Count', 'FontSize', FONT_BASE+2, 'FontWeight', 'bold');
    ax.YAxis(1).FontSize   = FONT_BASE+1;
    ax.YAxis(1).FontWeight = 'bold';

    title(ax, sprintf('%s = %s  (n=%d)', ca_trunc(gname,max_lbl), ca_trunc(gcats{k},max_lbl), tot), ...
        'FontSize', FONT_BASE+1, 'Interpreter', 'none');
    box(ax, 'off');

    max_cnt    = max(max_cnt, max(cp));
    axs(k)     = ax;
    cp_list{k} = cp;
    ci_list{k} = ci_hw_ct;
end

% Post-hoc A: shared count ylim across all subplots
shared_ylim = max_cnt * 1.1;
half_ylim   = shared_ylim / 2;
for k = 1:ng
    if ~isvalid(axs(k)), continue; end
    yyaxis(axs(k), 'left');
    ylim(axs(k), [0, shared_ylim]);
end

% Post-hoc B: count labels — inside (white) for tall bars, above CI cap for short
for k = 1:ng
    if ~isvalid(axs(k)) || isempty(cp_list{k}), continue; end
    yyaxis(axs(k), 'left');
    cp = cp_list{k};
    ci = ci_list{k};
    for bi = 1:numel(cp)
        if cp(bi) >= half_ylim
            text(axs(k), bi, cp(bi), ca_fmt_n(cp(bi)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
                'FontSize', 9, 'Color', [1 1 1]);
        else
            text(axs(k), bi, cp(bi) + ci(bi), ca_fmt_n(cp(bi)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontSize', 9, 'Color', [0.20 0.20 0.20]);
        end
    end
end
end


function ca_stacked_bars(fig, grp, gname, gcats, val, vcats, ftitle, max_lbl)
THRESH    = 0.03;   % include a val category if ≥3% of any major group
FONT_BASE = 9;
ng = numel(gcats);

gn = arrayfun(@(c) sum(grp == c{1}), gcats);
[~, gord] = sort(gn, 'descend');

ax = axes(fig);
hold(ax, 'on');

% Each row independently: show val categories ≥THRESH of that row's n;
% the rest become "Other" for that row. Colors are assigned per-row.
for row = 1:ng
    gi = gord(row);
    if gn(gi) == 0, continue; end
    sv = val(grp == gcats{gi});

    cn   = arrayfun(@(c) sum(sv == c{1}), vcats);
    show = cn / gn(gi) >= THRESH;
    if ~any(show), show(cn == max(cn)) = true; end  % fallback: show top-1
    ls   = vcats(show);
    cs   = cn(show);
    [cs, ord] = sort(cs, 'descend');
    ls   = ls(ord);

    other_cnt = gn(gi) - sum(cs);
    other_n_t = sum(~show & cn > 0);
    n_named = numel(ls);
    if n_named > 0
        named_clrs = ca_qualitative_colors(n_named);
    else
        named_clrs = zeros(0, 3);
    end
    if other_cnt > 0
        cp        = [cs; other_cnt];
        cat_names = [ls; {sprintf('Other (%d cats, n=%d)', other_n_t, other_cnt)}];
        clrs      = [named_clrs; 0.70 0.70 0.70];
    else
        cp        = cs;
        cat_names = ls;
        clrs      = named_clrs;
    end

    P_row = cp / gn(gi);
    x = 0;
    for si = 1:numel(cp)
        seg_w = P_row(si);
        if seg_w <= 0, x = x + seg_w; continue; end

        patch(ax, x + [0 seg_w seg_w 0], row + [-0.4 -0.4 0.4 0.4], ...
              clrs(si,:), 'EdgeColor', 'none');

        max_ch = floor(seg_w * 75);
        if max_ch >= 4
            cat_name = cat_names{si};
            if startsWith(cat_name, 'Other')
                full_lbl = cat_name;
            else
                full_lbl = [cat_name sprintf(' (%d)', cp(si))];
            end
            if max_ch >= length(full_lbl)
                lbl = full_lbl;
            elseif max_ch >= length(cat_name)
                lbl = cat_name;
            else
                lbl = ca_trunc(cat_name, max_ch);
            end
            lum     = 0.299*clrs(si,1) + 0.587*clrs(si,2) + 0.114*clrs(si,3);
            txt_clr = [1 1 1] * double(lum < 0.5);
            text(ax, x + seg_w/2, row, lbl, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontSize', FONT_BASE, 'Interpreter', 'none', 'Clipping', 'on', ...
                'Color', txt_clr);
        end
        x = x + seg_w;
    end
end

ylabels = cell(ng, 1);
for yi = 1:ng
    ylabels{yi} = sprintf('%s  (n=%d)', ca_trunc(gcats{gord(yi)}, max_lbl), gn(gord(yi)));
end
set(ax, 'YTick', 1:ng, 'YTickLabel', ylabels, ...
    'FontSize', FONT_BASE+1, 'TickLength', [0 0]);
ylabel(ax, ca_trunc(gname, max_lbl), 'FontSize', FONT_BASE+2);
xlabel(ax, 'Proportion', 'FontSize', FONT_BASE+2);
title(ax, ftitle, 'FontSize', FONT_BASE+3, 'Interpreter', 'none');
xlim(ax, [0 1]);
ylim(ax, [0.5, ng + 0.5]);
box(ax, 'off');
end


function ca_cond_heatmap(fig, grp, gname, gcats, val, vname, vcats, ftitle, max_lbl)
FONT_BASE  = 9;
MAX_S      = 20;
CLR_OTHER  = [0.82 0.82 0.82];
CLR_MARG   = [1.00 0.97 0.75];
CLR_CORNER = [0.72 0.72 0.72];

gn = arrayfun(@(c) sum(grp == c{1}), gcats);
[~,gord] = sort(gn,'descend');
show_g = gcats(gord(1:min(MAX_S,numel(gord))));
vn = arrayfun(@(c) sum(val == c{1}), vcats);
[~,vord] = sort(vn,'descend');
show_v = vcats(vord(1:min(MAX_S,numel(vord))));
nr = numel(show_g); nc = numel(show_v);

P         = zeros(nr, nc);
N         = zeros(nr, nc);
nri_total = arrayfun(@(c) sum(grp == c{1}), show_g)';
nci_total = arrayfun(@(c) sum(val == c{1}), show_v);
for ci = 1:nc
    mc  = (val == show_v{ci});
    nci = sum(mc);
    if nci == 0, continue; end
    for ri = 1:nr
        n_rc     = sum(grp(mc) == show_g{ri});
        N(ri,ci) = n_rc;
        P(ri,ci) = n_rc / nci;
    end
end
if nr > 3
    [U,~,~]   = svd(P,'econ');
    [~,rord]  = sort(U(:,1));
    P         = P(rord,:);
    N         = N(rord,:);
    show_g    = show_g(rord);
    nri_total = nri_total(rord);
end

has_oth_row = numel(gcats) > MAX_S;
has_oth_col = numel(vcats) > MAX_S;
n_oth_g     = numel(gcats) - nr;
n_oth_v     = numel(vcats) - nc;
nc_full     = nc + has_oth_col + 1;
nr_full     = nr + has_oth_row + 1;
oth_col_x   = nc + 1;
marg_col_x  = nc_full;
oth_row_y   = nr + 1;
marg_row_y  = nr_full;

N_oth_val = nri_total - sum(N, 2);
N_oth_grp = nci_total - sum(N, 1);
N_valid   = numel(grp);

P_full = NaN(nr_full, nc_full);
P_full(1:nr, 1:nc) = P;

ax = axes(fig);
imagesc(ax, P_full, [0 1]);
blues = interp1([0 1], [1 1 1; 0.13 0.44 0.71], linspace(0,1,64));
colormap(ax, blues);
cb = colorbar(ax);
cb.Label.String = sprintf('P(%s|%s)', ca_trunc(gname,max_lbl), ca_trunc(vname,max_lbl));

n_xticks = nc + has_oth_col + 1;
n_yticks = nr + has_oth_row + 1;
x_ticks  = zeros(1, n_xticks);
x_labels = cell(1, n_xticks);
y_ticks  = zeros(1, n_yticks);
y_labels = cell(1, n_yticks);
x_ticks(1:nc)  = 1:nc;
x_labels(1:nc) = cellfun(@(s) ca_trunc(s,max_lbl), show_v, 'UniformOutput', false);
y_ticks(1:nr)  = 1:nr;
y_labels(1:nr) = cellfun(@(s) ca_trunc(s,max_lbl), show_g, 'UniformOutput', false);
xi = nc + 1;
if has_oth_col
    x_ticks(xi)  = oth_col_x;
    x_labels{xi} = sprintf('Other (%d)', n_oth_v);
    xi = xi + 1;
end
x_ticks(xi)  = marg_col_x;
x_labels{xi} = 'Total';
yi = nr + 1;
if has_oth_row
    y_ticks(yi)  = oth_row_y;
    y_labels{yi} = sprintf('Other (%d)', n_oth_g);
    yi = yi + 1;
end
y_ticks(yi)  = marg_row_y;
y_labels{yi} = 'Total';

set(ax, 'XTick', x_ticks, 'YTick', y_ticks, ...
    'XTickLabel', x_labels, 'YTickLabel', y_labels, ...
    'XTickLabelRotation', 40, 'FontSize', FONT_BASE-2, 'TickLength', [0 0]);
if numel(gcats) > MAX_S || numel(vcats) > MAX_S
    sub = sprintf('(top %d of %d x top %d of %d)', nr,numel(gcats),nc,numel(vcats));
else
    sub = '';
end
title(ax, {ftitle, sub}, 'FontSize', FONT_BASE, 'Interpreter', 'none');
box(ax, 'off');

dark_txt = [0.15 0.15 0.15];

if has_oth_col
    for ri = 1:nr
        patch(ax, oth_col_x+[-0.5 0.5 0.5 -0.5 -0.5], ri+[-0.5 -0.5 0.5 0.5 -0.5], ...
            CLR_OTHER, 'EdgeColor', 'none');
        if N_oth_val(ri) > 0
            text(ax, oth_col_x, ri, ca_fmt_n(N_oth_val(ri)), ...
                'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);
        end
    end
end

if has_oth_row
    for ci = 1:nc
        patch(ax, ci+[-0.5 0.5 0.5 -0.5 -0.5], oth_row_y+[-0.5 -0.5 0.5 0.5 -0.5], ...
            CLR_OTHER, 'EdgeColor', 'none');
        if N_oth_grp(ci) > 0
            text(ax, ci, oth_row_y, ca_fmt_n(N_oth_grp(ci)), ...
                'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);
        end
    end
end

for ri = 1:nr
    patch(ax, marg_col_x+[-0.5 0.5 0.5 -0.5 -0.5], ri+[-0.5 -0.5 0.5 0.5 -0.5], ...
        CLR_MARG, 'EdgeColor', 'none');
    text(ax, marg_col_x, ri, ca_fmt_n(nri_total(ri)), ...
        'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);
end

for ci = 1:nc
    patch(ax, ci+[-0.5 0.5 0.5 -0.5 -0.5], marg_row_y+[-0.5 -0.5 0.5 0.5 -0.5], ...
        CLR_MARG, 'EdgeColor', 'none');
    text(ax, ci, marg_row_y, ca_fmt_n(nci_total(ci)), ...
        'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);
end

if has_oth_col && has_oth_row
    N_oth_oth = N_valid - sum(nri_total) - sum(nci_total) + sum(N(:));
    patch(ax, oth_col_x+[-0.5 0.5 0.5 -0.5 -0.5], oth_row_y+[-0.5 -0.5 0.5 0.5 -0.5], ...
        CLR_CORNER, 'EdgeColor', 'none');
    if N_oth_oth > 0
        text(ax, oth_col_x, oth_row_y, ca_fmt_n(N_oth_oth), ...
            'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);
    end
end
if has_oth_col
    N_val_oth_total = N_valid - sum(nci_total);
    patch(ax, oth_col_x+[-0.5 0.5 0.5 -0.5 -0.5], marg_row_y+[-0.5 -0.5 0.5 0.5 -0.5], ...
        CLR_CORNER, 'EdgeColor', 'none');
    text(ax, oth_col_x, marg_row_y, ca_fmt_n(N_val_oth_total), ...
        'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);
end
if has_oth_row
    N_grp_oth_total = N_valid - sum(nri_total);
    patch(ax, marg_col_x+[-0.5 0.5 0.5 -0.5 -0.5], oth_row_y+[-0.5 -0.5 0.5 0.5 -0.5], ...
        CLR_CORNER, 'EdgeColor', 'none');
    text(ax, marg_col_x, oth_row_y, ca_fmt_n(N_grp_oth_total), ...
        'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);
end
patch(ax, marg_col_x+[-0.5 0.5 0.5 -0.5 -0.5], marg_row_y+[-0.5 -0.5 0.5 0.5 -0.5], ...
    CLR_CORNER, 'EdgeColor', 'none');
text(ax, marg_col_x, marg_row_y, ca_fmt_n(N_valid), ...
    'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, 'Color', dark_txt);

for ri = 1:nr
    for ci = 1:nc
        if N(ri,ci) > 0
            text(ax, ci, ri, ca_fmt_count(N(ri,ci)), ...
                'HorizontalAlignment', 'center', 'FontSize', FONT_BASE-2, ...
                'Color', ca_label_color(P(ri,ci)));
        end
    end
end

sg_dc = show_g; sv_dc = show_v; p_dc = P;
dcm = datacursormode(fig);
dcm.UpdateFcn = @(~,ev) ca_heatmap_tip(ev, sg_dc, sv_dc, p_dc);
end


function txt = ca_vmat_tip(ev, names, V_mat)
pos = ev.Position;
ci = max(1, min(numel(names), round(pos(1))));
ri = max(1, min(numel(names), round(pos(2))));
if ri == ci
    txt = {names{ri}, 'Same column'};
else
    txt = {names{ri}, names{ci}, sprintf('V = %.3f', V_mat(ri,ci))};
end
end

function txt = ca_heatmap_tip(ev, row_names, col_names, P)
pos = ev.Position;
ci = max(1, min(numel(col_names), round(pos(1))));
ri = max(1, min(numel(row_names), round(pos(2))));
txt = {col_names{ci}, row_names{ri}, sprintf('P = %.3f', P(ri,ci))};
end

function s = ca_fmt_count(n)
if n >= 1000, s = sprintf('%.3gk', n/1000); else, s = sprintf('%d', n); end
end

function s = ca_fmt_p(p)
if p < 0.001
    s = 'p<.001';
else
    s = strrep(sprintf('p=%.3f', p), '0.', '.');
end
end

function ca_fill_rect(ax, xl, yt, w, h, clr, alp)
if w <= 0 || h <= 0, return; end
patch(ax, xl+[0 w w 0 0], yt+[0 0 h h 0], clr, 'FaceAlpha', alp, 'EdgeColor', 'none');
end

function s = ca_trunc(s, n)
if numel(s) > n, s = [s(1:n-1) '~']; end
end

function name = ca_fig_name(label, src)
if isempty(src), name = label; else, name = sprintf('%s: %s', src, label); end
end

function prefix = ca_source_prefix(prof)
prefix = '';
if ~isfield(prof, 'source_name'), return; end
sn = char(prof.source_name);
if isempty(sn), return; end
m = regexp(sn, '\[([^\]]+)\]', 'tokens', 'once');
if ~isempty(m), prefix = strtrim(m{1}); end
end

function clr = ca_label_color(v)
if v > 0.6, clr = [1 1 1]; else, clr = [0.15 0.15 0.15]; end
end

function colors = ca_qualitative_colors(n)
tab10 = [
    0.122 0.467 0.706; 1.000 0.498 0.055; 0.173 0.627 0.173
    0.839 0.153 0.157; 0.580 0.404 0.741; 0.549 0.337 0.294
    0.890 0.467 0.761; 0.498 0.498 0.498; 0.737 0.741 0.133
    0.090 0.745 0.812
];
colors = tab10(mod((0:n-1)', 10) + 1, :);
end


function [u_ba, u_ab] = ca_theil_u(x, y)
% u_ba = U(y|x): fraction of y's entropy explained by x
% u_ab = U(x|y): fraction of x's entropy explained by y
if ~iscategorical(x), x = categorical(x); end
if ~iscategorical(y), y = categorical(y); end
valid = ~isundefined(x) & ~isundefined(y);
x = x(valid); y = y(valid);
N = numel(x);
cx = categories(x); rx = numel(cx);
cy = categories(y); ry = numel(cy);
if N < 2 || rx < 2 || ry < 2
    u_ba = 0; u_ab = 0; return
end
xi = zeros(N, 1);
for ri = 1:rx, xi(x == cx{ri}) = ri; end
yi = zeros(N, 1);
for ci = 1:ry, yi(y == cy{ci}) = ci; end
O  = accumarray([xi yi], 1, [rx ry]);
hy = ca_entropy(sum(O, 1) / N);
hx = ca_entropy(sum(O, 2)' / N);
if hy < eps
    u_ba = 0;
else
    hyx = 0;
    for ri = 1:rx
        rs = sum(O(ri,:));
        if rs == 0, continue; end
        hyx = hyx + (rs/N) * ca_entropy(O(ri,:) / rs);
    end
    u_ba = max(0, (hy - hyx) / hy);
end
if hx < eps
    u_ab = 0;
else
    hxy = 0;
    for ci = 1:ry
        cs = sum(O(:,ci));
        if cs == 0, continue; end
        hxy = hxy + (cs/N) * ca_entropy(O(:,ci)' / cs);
    end
    u_ab = max(0, (hx - hxy) / hx);
end
end


function s = ca_fmt_n(n)
if n < 1000
    s = sprintf('%d', round(n));
else
    s = regexprep(sprintf('%.1e', n), 'e\+0*(\d+)', 'e$1');
end
end


function h = ca_entropy(p)
p = p(p > 0);
h = -sum(p .* log2(p));
end


function ca_draw_arrow(ax, cx, cy, u_diff)
% Arrow in lower-triangle cell (cx,cy).
% u_diff > 0: col (x-axis) predicts row (y-axis) → arrow toward top-left
% u_diff < 0: row (y-axis) predicts col (x-axis) → arrow toward bottom-right
% |u_diff| < 0.05: small square (near-symmetric)
THRESH_SQ   = 0.05;
THRESH_HEAD = 0.15;
HEAD_W      = 0.09;
HEAD_H      = 0.11;
MAX_MAG     = 0.30;
CLR = [0.20 0.20 0.20];

if abs(u_diff) < THRESH_SQ
    sq = 0.07;
    patch(ax, cx+sq*[-1 1 1 -1 -1], cy+sq*[-1 -1 1 1 -1], CLR, 'EdgeColor', 'none');
    return
end

if u_diff > 0
    dir = [-1 -1] / sqrt(2);
else
    dir = [1 1] / sqrt(2);
end
perp = [-dir(2), dir(1)];
mag  = min(MAX_MAG, abs(u_diff) * 0.6);

tip = [cx + dir(1)*mag,                          cy + dir(2)*mag];
bl  = [cx + dir(1)*(mag-HEAD_H) + perp(1)*HEAD_W, cy + dir(2)*(mag-HEAD_H) + perp(2)*HEAD_W];
br  = [cx + dir(1)*(mag-HEAD_H) - perp(1)*HEAD_W, cy + dir(2)*(mag-HEAD_H) - perp(2)*HEAD_W];
patch(ax, [tip(1) bl(1) br(1) tip(1)], [tip(2) bl(2) br(2) tip(2)], CLR, 'EdgeColor', 'none');

if abs(u_diff) >= THRESH_HEAD
    tail = [cx - dir(1)*0.04, cy - dir(2)*0.04];
    base = [(bl(1)+br(1))/2, (bl(2)+br(2))/2];
    line(ax, [tail(1) base(1)], [tail(2) base(2)], 'Color', CLR, 'LineWidth', 1.0);
end
end
