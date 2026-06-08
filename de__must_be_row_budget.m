function de__must_be_row_budget(x)
%DE__MUST_BE_ROW_BUDGET  Validate a MaxRows-style row budget.
%   Valid: a positive row count, or Inf for "no limit".  Rejects 0 and negatives
%   — the common mistake is MaxRows=0 meaning "unlimited"; the sentinel is Inf.
%   Used as an arguments-block validator: options.MaxRows (1,1) double {de__must_be_row_budget} = Inf
    if ~(isscalar(x) && x > 0)
        error('DataExplorer:badMaxRows', ...
            'MaxRows must be a positive row count, or Inf for no limit (got %g).', x);
    end
end
