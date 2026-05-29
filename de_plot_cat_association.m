function de_plot_cat_association(T, prof, options)
%DE_PLOT_CAT_ASSOCIATION  Visualise pairwise associations between categorical columns.
%
%   de_plot_cat_association(T, prof)
%   de_plot_cat_association(T, prof, MaxPairs=5, VThresh=0.05)
%
%   Name-value options
%   ------------------
%   MaxPairs   Max number of full-page pair figures to produce (default 3)
%   VThresh    Min Cramer's V to qualify for a pair figure (default 0.10)
arguments
    T     table
    prof  struct
    options.MaxPairs  (1,1) double = 3
    options.VThresh   (1,1) double = 0.10
end

MAX_LABEL         = 25;
MAX_PAIRS         = options.MaxPairs;
V_THRESH          = options.VThresh;
PARETO_MAX_GROUPS = 6;
STACKED_MAX_GROUPS = 15;
V_ANNOTATE_THRESH = 0.05;

cat_mask = (prof.type == "categorical" | prof.type == "logical") & ~prof.skip;
cat_idx  = find(cat_mask);
if numel(cat_idx) < 2, return; end
names = prof.name(cat_idx);
nc    = numel(cat_idx);

V_mat = zeros(nc, nc);
P_mat = ones(nc, nc);
for i = 1:nc
    for j = i+1:nc
        [v, p] = de_cramer_v(T.(names{i}), T.(names{j}));
        V_mat(i,j) = v; V_mat(j,i) = v;
        P_mat(i,j) = p; P_mat(j,i) = p;
    end
end

src = ca_source_prefix(prof);
ca_plot_v_matrix(V_mat, P_mat, names, src, MAX_LABEL, V_ANNOTATE_THRESH);

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
        PARETO_MAX_GROUPS, STACKED_MAX_GROUPS);
end
end


function ca_plot_v_matrix(V_mat, P_mat, names, src, max_lbl, v_annotate)
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
    'XTickLabelRotation', 40, 'FontSize', 8, 'TickLength', [0 0]);
sub = "Bias-Corrected Cramer's V";
if ~isempty(src), sub = sub + "  |  " + src; end
title(ax, {"Association Strength", sub}, 'FontSize', 10);
for i = 1:nc
    for j = 1:nc
        if i == j, continue; end
        if i < j
            if V_mat(i,j) >= v_annotate
                text(ax, j, i, sprintf('%.2f', V_mat(i,j)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 7, ...
                    'Color', ca_label_color(V_mat(i,j)));
            end
        else
            stars = ca_sig_stars(P_mat(i,j));
            if ~isempty(stars)
                text(ax, j, i, stars, ...
                    'HorizontalAlignment', 'center', 'FontSize', 8, ...
                    'Color', ca_label_color(V_mat(i,j)));
            end
        end
    end
end
nm_dc = names; vm_dc = V_mat;
dcm = datacursormode(fig);
dcm.UpdateFcn = @(~,ev) ca_vmat_tip(ev, nm_dc, vm_dc);
end


function ca_plot_pair(x, y, xname, yname, V, src, max_lbl, pareto_max_grp, stacked_max_grp)
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
if ng <= pareto_max_grp
    ca_pareto_multiples(fig, grp, gname, gcats, val, ftitle, max_lbl);
elseif ng <= stacked_max_grp
    ca_stacked_bars(fig, grp, gname, gcats, val, vcats, ftitle, max_lbl);
else
    ca_cond_heatmap(fig, grp, gname, gcats, val, vname, vcats, ftitle, max_lbl);
end
end


function ca_pareto_multiples(fig, grp, gname, gcats, val, ftitle, max_lbl)
MAX_B = 15;
ng   = numel(gcats);
ncol = min(ng, 3);
nrow = ceil(ng / ncol);
sgtitle(fig, ftitle, 'FontSize', 10, 'Interpreter', 'none');
for k = 1:ng
    mask = (grp == gcats{k});
    sv   = val(mask);
    if isempty(sv), continue; end
    vc = categories(sv);
    cn = arrayfun(@(c) sum(sv == c{1}), vc);
    [cs, ord] = sort(cn, 'descend');
    ls = vc(ord);
    ns = min(MAX_B, numel(ls));
    no = numel(ls) - ns;
    if no > 0
        cp      = [cs(1:ns); sum(cs(ns+1:end))];
        lp      = [cellfun(@(s) ca_trunc(s,max_lbl), ls(1:ns), 'UniformOutput', false); ...
                   {sprintf('Other (%d)', no)}];
        full_lp = [ls(1:ns); {sprintf('Other (%d categories)', no)}];
    else
        cp      = cs(1:ns);
        lp      = cellfun(@(s) ca_trunc(s,max_lbl), ls(1:ns), 'UniformOutput', false);
        full_lp = ls(1:ns);
    end
    tot = sum(cp);
    pct = 100 * cp / tot;
    cum = cumsum(pct);
    ax  = subplot(nrow, ncol, k, 'Parent', fig);
    b   = bar(ax, 1:numel(cp), pct, 'FaceColor', [0.25 0.55 0.80], 'EdgeColor', 'none');
    b.DataTipTemplate.DataTipRows(1).Label = 'Category';
    b.DataTipTemplate.DataTipRows(1).Value = full_lp;
    b.DataTipTemplate.DataTipRows(2).Label = '%';
    hold(ax, 'on');
    yyaxis(ax, 'right');
    plot(ax, 1:numel(cum), cum, 'r-o', 'MarkerSize', 4);
    ylim(ax, [0 100]);
    ylabel(ax, 'Cumulative %', 'FontSize', 7);
    yyaxis(ax, 'left');
    ylabel(ax, '%', 'FontSize', 7);
    set(ax, 'XTick', 1:numel(cp), 'XTickLabel', lp, ...
        'XTickLabelRotation', 40, 'FontSize', 7, 'TickLength', [0 0]);
    title(ax, sprintf('%s = %s  (n=%d)', ca_trunc(gname,max_lbl), ca_trunc(gcats{k},max_lbl), tot), ...
        'FontSize', 8, 'Interpreter', 'none');
    box(ax, 'off');
end
end


function ca_stacked_bars(fig, grp, gname, gcats, val, vcats, ftitle, max_lbl)
MAX_S = 12;
ng = numel(gcats);
vn = arrayfun(@(c) sum(val == c{1}), vcats);
[~, vord] = sort(vn, 'descend');
top_v  = vcats(vord(1:min(MAX_S, numel(vord))));
n_oth  = numel(vcats) - numel(top_v);
nc_s   = numel(top_v) + (n_oth > 0);
P      = zeros(ng, nc_s);
for gi = 1:ng
    mask  = (grp == gcats{gi});
    n_grp = sum(mask);
    if n_grp == 0, continue; end
    sv = val(mask);
    for vi = 1:numel(top_v)
        P(gi,vi) = sum(sv == top_v{vi}) / n_grp;
    end
    if n_oth > 0
        P(gi,end) = max(0, 1 - sum(P(gi,1:end-1)));
    end
end
slabs = cellfun(@(s) ca_trunc(s,max_lbl), top_v, 'UniformOutput', false);
if n_oth > 0, slabs{end+1} = sprintf('Other (%d)', n_oth); end
gn = arrayfun(@(c) sum(grp == c{1}), gcats);
[~,gord] = sort(gn, 'descend');
ax = axes(fig);
bh = barh(ax, 1:ng, P(gord,:), 'stacked');
colors = ca_qualitative_colors(numel(top_v));
if n_oth > 0, colors(end+1,:) = [0.70 0.70 0.70]; end
full_gcats_s = gcats(gord);
full_slabs   = top_v;
if n_oth > 0, full_slabs{end+1} = sprintf('Other (%d categories)', n_oth); end
for vi = 1:numel(bh)
    bh(vi).FaceColor = colors(vi,:);
    bh(vi).EdgeColor = 'none';
    bh(vi).DataTipTemplate.DataTipRows(1).Label = full_slabs{vi};
    bh(vi).DataTipTemplate.DataTipRows(2).Label = 'Group';
    bh(vi).DataTipTemplate.DataTipRows(2).Value = full_gcats_s;
end
set(ax, 'YTick', 1:ng, ...
    'YTickLabel', cellfun(@(s) ca_trunc(s,max_lbl), gcats(gord), 'UniformOutput', false), ...
    'FontSize', 8, 'TickLength', [0 0]);
ylabel(ax, ca_trunc(gname, max_lbl), 'FontSize', 9);
xlabel(ax, 'Proportion', 'FontSize', 9);
title(ax, ftitle, 'FontSize', 10, 'Interpreter', 'none');
legend(ax, slabs, 'Location', 'eastoutside', 'FontSize', 7, 'Interpreter', 'none');
xlim(ax, [0 1]);
box(ax, 'off');
end


function ca_cond_heatmap(fig, grp, gname, gcats, val, vname, vcats, ftitle, max_lbl)
MAX_S = 20;
gn = arrayfun(@(c) sum(grp == c{1}), gcats);
[~,gord] = sort(gn,'descend');
show_g = gcats(gord(1:min(MAX_S,numel(gord))));
vn = arrayfun(@(c) sum(val == c{1}), vcats);
[~,vord] = sort(vn,'descend');
show_v = vcats(vord(1:min(MAX_S,numel(vord))));
nr = numel(show_g); nc = numel(show_v);
P  = zeros(nr, nc);
for ci = 1:nc
    mc  = (val == show_v{ci});
    nci = sum(mc);
    if nci == 0, continue; end
    for ri = 1:nr
        P(ri,ci) = sum(grp(mc) == show_g{ri}) / nci;
    end
end
if nr > 3
    [U,~,~] = svd(P,'econ');
    [~,rord] = sort(U(:,1));
    P        = P(rord,:);
    show_g   = show_g(rord);
end
ax = axes(fig);
imagesc(ax, P, [0 1]);
blues = interp1([0 1], [1 1 1; 0.13 0.44 0.71], linspace(0,1,64));
colormap(ax, blues);
cb = colorbar(ax);
cb.Label.String = sprintf('P(%s|%s)', ca_trunc(gname,max_lbl), ca_trunc(vname,max_lbl));
set(ax, 'XTick', 1:nc, 'YTick', 1:nr, ...
    'XTickLabel', cellfun(@(s) ca_trunc(s,max_lbl), show_v, 'UniformOutput', false), ...
    'YTickLabel', cellfun(@(s) ca_trunc(s,max_lbl), show_g, 'UniformOutput', false), ...
    'XTickLabelRotation', 40, 'FontSize', 7, 'TickLength', [0 0]);
if numel(gcats) > MAX_S || numel(vcats) > MAX_S
    sub = sprintf('(top %d of %d x top %d of %d)', nr,numel(gcats),nc,numel(vcats));
else
    sub = '';
end
title(ax, {ftitle, sub}, 'FontSize', 9, 'Interpreter', 'none');
box(ax, 'off');
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

function s = ca_sig_stars(p)
if p < 0.001, s = '***'; elseif p < 0.01, s = '**'; elseif p < 0.05, s = '*'; else, s = ''; end
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
