function T_long = de_pivot_wide_years(T, yr_cols)
%DE_PIVOT_WIDE_YEARS  Pivot wide year-columns to long format.
%
%   T_long = de_pivot_wide_years(T, yr_cols)
%
%   yr_cols  Cell array or string array of column names that encode years.
%            Year values are extracted by stripping a leading 'x' or 'X'
%            then parsing the remainder as a number ('x1960' → 1960;
%            '1960' also works).
%
%   Returns T_long with:
%     • All non-year columns repeated n_years times (block repetition)
%     • Year   — numeric year value  (double)
%     • Value  — stacked values from the year columns
%
%   Example
%   ───────
%   yr = T.Properties.VariableNames(startsWith(...,'x'));
%   T_long = de_pivot_wide_years(T, yr);
%   de_statebins(T_long, 'StateCol','StateCode', ...
%       'ColorCol','Value', 'TimeCol','Year', 'Title','Energy by state')

yr_cols = cellstr(yr_cols(:)');
yr_vals = cellfun(@(c) str2double(regexprep(c, '^[xX]', '')), yr_cols);
kp      = T.Properties.VariableNames(~ismember(T.Properties.VariableNames, yr_cols));
n_yr    = numel(yr_vals);
n_r     = height(T);
T_long        = repmat(T(:, kp), n_yr, 1);
T_long.Year   = repelem(yr_vals(:), n_r);
T_long.Value  = reshape( ...
    cell2mat(cellfun(@(c) double(T.(c)), yr_cols, 'UniformOutput', false).'), ...
    [], 1);
end
