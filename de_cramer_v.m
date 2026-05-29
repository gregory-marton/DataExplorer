function V = de_cramer_v(x, y)
%DE_CRAMER_V  Cramer's V association measure between two categorical vectors.
%
%   V = de_cramer_v(x, y)
%
%   Returns V in [0, 1]: 0 = no association, 1 = perfect association.
%   Does not require any toolbox.  Missing (undefined) rows are excluded.
%
%   Uses the bias-corrected formula (Bergsma & Wicher 2013) which adjusts
%   for inflated V in small samples or high-cardinality tables.

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

% Bias-corrected Cramer's V (Bergsma & Wicher 2013)
phi2_bc = max(0, chi2/N - (r_eff-1)*(c_eff-1)/(N-1));
r_tilde = r_eff - (r_eff-1)^2/(N-1);
c_tilde = c_eff - (c_eff-1)^2/(N-1);
denom   = min(r_tilde - 1, c_tilde - 1);
if denom <= 0
    V = 0;
    return
end
V = min(sqrt(phi2_bc / denom), 1);
end
