function V = de_cramer_v(x, y)
%DE_CRAMER_V  Cramer's V association measure between two categorical vectors.
%
%   V = de_cramer_v(x, y)
%
%   Returns V in [0, 1]: 0 = no association, 1 = perfect association.
%   Does not require any toolbox.  Missing (undefined) rows are excluded.
%
%   Formula: V = sqrt(chi2 / (N * min(r-1, c-1)))
%   where r, c are the number of levels in x, y respectively.

if ~iscategorical(x), x = categorical(x); end
if ~iscategorical(y), y = categorical(y); end

valid = ~isundefined(x) & ~isundefined(y);
x = x(valid);
y = y(valid);
N = numel(x);

if N < 2
    V = 0;
    return
end

cx = categories(x);
cy = categories(y);
r  = numel(cx);
c  = numel(cy);

if r < 2 || c < 2
    V = 0;
    return
end

% Build contingency table
O = zeros(r, c);
for ri = 1:r
    for ci = 1:c
        O(ri, ci) = sum(x == cx{ri} & y == cy{ci});
    end
end

row_sum = sum(O, 2);
col_sum = sum(O, 1);

% Remove empty rows/cols before computing chi-square
keep_r = row_sum > 0;
keep_c = col_sum > 0;
O = O(keep_r, keep_c);
row_sum = row_sum(keep_r);
col_sum = col_sum(keep_c);
r_eff = sum(keep_r);
c_eff = sum(keep_c);

if r_eff < 2 || c_eff < 2
    V = 0;
    return
end

E    = (row_sum * col_sum) / N;
chi2 = sum(sum((O - E).^2 ./ E));
V    = sqrt(chi2 / (N * (min(r_eff, c_eff) - 1)));
V    = min(V, 1);
end
