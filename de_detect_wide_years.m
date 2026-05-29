function [yr_idxs, yr_vals] = de_detect_wide_years(prof)
%DE_DETECT_WIDE_YEARS  Find non-skip numeric columns named x#### (year 1900–2100).
%   Returns empty arrays if fewer than 3 such columns exist.
n_cols = numel(prof.name);
yr_idxs = zeros(1, n_cols);
yr_vals = zeros(1, n_cols);
ny = 0;
for i = 1:n_cols
    if prof.skip(i) || prof.type(i) ~= "numeric", continue; end
    tok = regexp(prof.name{i}, '^x(\d{4})$', 'tokens', 'once');
    if isempty(tok), continue; end
    yr = str2double(tok{1});
    if yr >= 1900 && yr <= 2100
        ny = ny + 1;
        yr_idxs(ny) = i;
        yr_vals(ny) = yr;
    end
end
yr_idxs = yr_idxs(1:ny);
yr_vals  = yr_vals(1:ny);
if ny < 3, yr_idxs = []; yr_vals = []; end
end
