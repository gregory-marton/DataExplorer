function [time_idx, is_year_axis] = de_find_time_axis(prof)
%DE_FIND_TIME_AXIS  Return index of the time axis column and whether it is a
%   year-named numeric (true) or a proper datetime column (false).
%   Returns time_idx=[] if no time axis is found.

dt_idx = find(prof.type == "datetime" & ~prof.skip, 1, 'first');
if ~isempty(dt_idx)
    time_idx    = dt_idx;
    is_year_axis = false;
    return
end

num_cols = find(prof.type == "numeric" & ~prof.skip);
year_candidates = num_cols(arrayfun(@(i) ...
    ~isempty(regexpi(prof.name{i}, 'year', 'once')), num_cols));
if isscalar(year_candidates)
    time_idx    = year_candidates;
    is_year_axis = true;
else
    time_idx    = [];
    is_year_axis = false;
end
end
