function tf = de__is_total_level(lv)
%DE__IS_TOTAL_LEVEL  True when a category level name represents an aggregate total.
%   Matches any string containing 'total' as a whole word (case-insensitive).
%
%   Used to identify and exclude aggregate/total rows from per-level plots.
tf = ~isempty(regexpi(strtrim(char(lv)), '\btotal\b', 'once'));
end
