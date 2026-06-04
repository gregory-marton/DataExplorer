function eta2 = de_variance_explained(x, g)
%DE_VARIANCE_EXPLAINED  One-way ANOVA η² — fraction of a numeric's variance
%   explained by grouping it by a categorical.
%
%   eta2 = de_variance_explained(x, g)
%
%   x — numeric vector.
%   g — grouping vector the same length as x (categorical, string, cellstr, or
%       numeric).  Each distinct value of g is one group.
%
%   Returns η² = SS_between / SS_total in [0, 1]:
%     0  → grouping explains nothing (group means all ≈ grand mean).
%     1  → grouping explains everything (no within-group spread).
%
%   This is the domain-free measure of "how strongly does g stratify x".  A high
%   value means a per-group aggregate of x (e.g. a per-state mean) is confounded
%   by g's composition.  Toolbox-free (findgroups + accumarray are base MATLAB).
%
%   NaNs in x and missing values in g are dropped pairwise.  Returns 0 when
%   fewer than two groups remain or x is constant.

x = double(x(:));
g = g(:);

ok = ~isnan(x);
if iscategorical(g)
    ok = ok & ~isundefined(g);
elseif isstring(g)
    ok = ok & ~ismissing(g);
elseif isnumeric(g)
    ok = ok & ~isnan(g);
end
x = x(ok);
g = g(ok);

eta2 = 0;
if numel(x) < 2, return; end

gi = findgroups(g);
ng = max(gi);
if isempty(ng) || ng < 2, return; end

grand    = mean(x);
ss_total = sum((x - grand).^2);
if ss_total <= 0, return; end

n_i        = accumarray(gi, 1);
mean_i     = accumarray(gi, x) ./ n_i;
ss_between = sum(n_i .* (mean_i - grand).^2);

eta2 = max(0, min(1, ss_between / ss_total));
end
