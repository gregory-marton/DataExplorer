function de__must_be_range(x)
%DE__MUST_BE_RANGE  Validate a [lo hi] limit pair: lo <= hi, or [NaN NaN] for auto.
%   Accepts the unset/auto sentinel ([NaN NaN]) and infinite bounds; rejects a
%   reversed pair.  Used as an arguments-block validator:
%   options.CLim (1,2) double {de__must_be_range} = [NaN NaN]
    if all(~isnan(x)) && x(1) > x(2)
        error('DataExplorer:badRange', ...
            'Range must be [lo hi] with lo <= hi (or [NaN NaN] for auto); got [%g %g].', x(1), x(2));
    end
end
