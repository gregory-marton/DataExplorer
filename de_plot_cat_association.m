function de_plot_cat_association(T, prof)
%DE_PLOT_CAT_ASSOCIATION  Visualise pairwise associations between categorical columns.
arguments
    T     table
    prof  struct
end

cat_mask = (prof.type == "categorical" | prof.type == "logical") & ~prof.skip;
cat_idx  = find(cat_mask);
if numel(cat_idx) < 2, return; end
names = prof.name(cat_idx);
nc    = numel(cat_idx);

V_mat = zeros(nc, nc);
for i = 1:nc
    for j = i+1:nc
        v = de_cramer_v(T.(names{i}), T.(names{j}));
        V_mat(i,j) = v;
        V_mat(j,i) = v;
    end
end

src = ca_source_prefix(prof);
ca_plot_v_matrix(V_mat, names, src);

MAX_PAIRS = 3;
V_THRESH  = 0.10;
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
        names{pairs(k,1)}, names{pairs(k,2)}, pairs(k,3), src);
end
end


function ca_plot_v_matrix(V_mat, names, src)
nc  = numel(names);
fig = figure('Name', ca_fig_name("Categorical associations", src));
ax  = axes(fig);
imagesc(ax, V_mat, [0 1]);
blues = interp1([0 1], [1 1 1; 0.13 0.44 0.71], linspace(0,1,64));
colormap(ax, blues);
cb = colorbar(ax);
cb.Label.String = "Cramer's V";
short = cellfun(@(s) ca_trunc(s,18), names, 'UniformOutput', false);
set(ax, 'XTick', 1:nc, 'YTick', 1:nc, ...
    'XTickLabel', short, 'YTickLabel', short, ...
    'XTickLabelRotation', 40, 'FontSize', 8, 'TickLength', [0 0]);
title(ax, "Categorical associations (Cramer's V)", 'FontSize', 10);
for i = 1:nc
    for j = 1:nc
        if i ~= j && V_mat(i,j) >= 0.05
            text(ax, j, i, sprintf('%.2f', V_mat(i,j)), ...
                'HorizontalAlignment', 'center', 'FontSize', 7, ...
                'Color', ca_label_color(V_mat(i,j)));
        end
    end
end
end


function ca_plot_pair(x, y, xname, yname, V, src)
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
ftitle = sprintf('%s x %s  (V = %.2f)', ca_trunc(gname,24), ca_trunc(vname,24), V);
fig    = figure('Name', ca_fig_name(ftitle, src));
if ng <= 6
    ca_pareto_multiples(fig, grp, gname, gcats, val, ftitle);
elseif ng <= 15
    ca_stacked_bars(fig, grp, gname, gcats, val, vcats, ftitle);
else
    ca_cond_heatmap(fig, grp, gname, gcats, val, vname, vcats, ftitle);
end
end


function ca_pareto_multiples(fig, grp, gname, gcats, val, ftitle)
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
        cp = [cs(1:ns); sum(cs(ns+1:end))];
        lp = [cellfun(@(s) ca_trunc(s,14), ls(1:ns), 'UniformOutput', false); ...
              {sprintf('Other (%d)', no)}];
    else
        cp = cs(1:ns);
        lp = cellfun(@(s) ca_trunc(s,14), ls(1:ns), 'UniformOutput', false);
    end
    tot = sum(cp);
    pct = 100 * cp / tot;
    cum = cumsum(pct);
    ax  = subplot(nrow, ncol, k, 'Parent', fig);
    bar(ax, 1:numel(cp), pct, 'FaceColor', [0.25 0.55 0.80], 'EdgeColor', 'none');
    hold(ax, 'on');
    yyaxis(ax, 'right');
    plot(ax, 1:numel(cum), cum, 'r-o', 'MarkerSize', 4);
    ylim(ax, [0 100]);
    ylabel(ax, 'Cum %', 'FontSize', 7);
    yyaxis(ax, 'left');
    ylabel(ax, '%', 'FontSize', 7);
    set(ax, 'XTick', 1:numel(cp), 'XTickLabel', lp, ...
        'XTickLabelRotation', 40, 'FontSize', 7, 'TickLength', [0 0]);
    title(ax, sprintf('%s = %s  (n=%d)', ca_trunc(gname,12), ca_trunc(gcats{k},12), tot), ...
        'FontSize', 8, 'Interpreter', 'none');
    box(ax, 'off');
end
end


function ca_stacked_bars(fig, grp, gname, gcats, val, vcats, ftitle)
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
slabs = cellfun(@(s) ca_trunc(s,16), top_v, 'UniformOutput', false);
if n_oth > 0, slabs{end+1} = sprintf('Other (%d)', n_oth); end
gn = arrayfun(@(c) sum(grp == c{1}), gcats);
[~,gord] = sort(gn, 'descend');
ax = axes(fig);
bh = barh(ax, 1:ng, P(gord,:), 'stacked');
colors = ca_qualitative_colors(numel(top_v));
if n_oth > 0, colors(end+1,:) = [0.70 0.70 0.70]; end
for vi = 1:numel(bh)
    bh(vi).FaceColor = colors(vi,:);
    bh(vi).EdgeColor = 'none';
end
set(ax, 'YTick', 1:ng, ...
    'YTickLabel', cellfun(@(s) ca_trunc(s,18), gcats(gord), 'UniformOutput', false), ...
    'FontSize', 8, 'TickLength', [0 0]);
ylabel(ax, ca_trunc(gname, 24), 'FontSize', 9);
xlabel(ax, 'Proportion', 'FontSize', 9);
title(ax, ftitle, 'FontSize', 10, 'Interpreter', 'none');
legend(ax, slabs, 'Location', 'eastoutside', 'FontSize', 7, 'Interpreter', 'none');
xlim(ax, [0 1]);
box(ax, 'off');
end


function ca_cond_heatmap(fig, grp, gname, gcats, val, vname, vcats, ftitle)
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
cb.Label.String = sprintf('P(%s|%s)', ca_trunc(gname,16), ca_trunc(vname,16));
set(ax, 'XTick', 1:nc, 'YTick', 1:nr, ...
    'XTickLabel', cellfun(@(s) ca_trunc(s,14), show_v, 'UniformOutput', false), ...
    'YTickLabel', cellfun(@(s) ca_trunc(s,14), show_g, 'UniformOutput', false), ...
    'XTickLabelRotation', 40, 'FontSize', 7, 'TickLength', [0 0]);
if numel(gcats) > MAX_S || numel(vcats) > MAX_S
    sub = sprintf('(top %d of %d x top %d of %d)', nr,numel(gcats),nc,numel(vcats));
else
    sub = '';
end
title(ax, {ftitle, sub}, 'FontSize', 9, 'Interpreter', 'none');
box(ax, 'off');
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
