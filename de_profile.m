function [T, prof] = de_profile(T, missingStrings)
%DE_PROFILE  Profile a table: classify columns, recode missing, convert types.
%
%   [T, prof] = de_profile(T)
%   [T, prof] = de_profile(T, missingStrings)
%
%   Returns the cleaned table T and a profile struct with fields:
%     prof.name        cell array of column names
%     prof.source_name string label (empty unless set by caller)
%     prof.type        string array: "numeric","categorical","datetime","logical","unknown"
%     prof.nmissing    missing-value count per column
%     prof.nunique     unique-value count per column
%     prof.skip        logical: true for ID-like or >80%-missing columns
%     prof.skip_reason string reason for skip flag
%     prof.orig_class  MATLAB class before conversion ("text" if originally string)
%
%   String columns ≥70% parseable as numbers are converted to double.
%   Values matching missingStrings are recoded as NaN / <undefined>.
%   Requires no toolboxes.

DEFAULT_MISSING = ["Suppressed","N/A","NA","n/a","--","-","None","none", ...
    "null","NULL","missing","Missing","?","Unknown","unknown","*"];
if nargin < 2
    missingStrings = DEFAULT_MISSING;
end

n    = height(T);
ncol = width(T);

prof.name        = T.Properties.VariableNames;
prof.source_name = '';
prof.skip        = false(1, ncol);
prof.skip_reason = repmat("", 1, ncol);
prof.type        = repmat("unknown", 1, ncol);
prof.orig_class  = repmat("", 1, ncol);
prof.nmissing    = zeros(1, ncol);
prof.nunique     = zeros(1, ncol);

for k = 1:ncol
    col   = T.(prof.name{k});
    cname = prof.name{k};

    % Record original class before any conversions
    if ischar(col) || iscellstr(col) || (isstring(col) && ~isscalar(col))
        prof.orig_class(k) = "text";
    else
        prof.orig_class(k) = string(class(col));
    end

    % String/char/cellstr: try numeric conversion, else categorical
    if ischar(col) || iscellstr(col) || (isstring(col) && ~isscalar(col))
        col = string(col);
        col(ismember(col, missingStrings)) = missing;
        numvals     = str2double(col);
        pct_numeric = sum(~isnan(numvals)) / n;
        if pct_numeric >= 0.70
            col = numvals;
        else
            col = categorical(col);
        end
        T.(cname) = col;
    end

    % Re-fetch after possible conversion
    col = T.(cname);

    if isnumeric(col) || islogical(col)
        if islogical(col)
            prof.type(k)     = "logical";
            nmiss            = 0;
        else
            prof.type(k)     = "numeric";
            nmiss            = sum(isnan(col));
        end
        prof.nmissing(k) = nmiss;
        prof.nunique(k)  = numel(unique(col(~isnan(col))));

    elseif iscategorical(col)
        bad_cats = intersect(categories(col), cellstr(missingStrings));
        if ~isempty(bad_cats)
            col = setcats(col, setdiff(categories(col), bad_cats));
            T.(cname) = col;
        end
        prof.type(k)     = "categorical";
        prof.nmissing(k) = sum(isundefined(col));
        prof.nunique(k)  = numel(categories(col));

    elseif isdatetime(col)
        prof.type(k)     = "datetime";
        prof.nmissing(k) = sum(isnat(col));
        valid            = col(~isnat(col));
        prof.nunique(k)  = numel(unique(valid));

    elseif isduration(col)
        prof.type(k)     = "datetime";
        prof.nmissing(k) = sum(isnan(seconds(col)));
        valid            = col(~isnan(seconds(col)));
        prof.nunique(k)  = numel(unique(valid));

    else
        prof.type(k) = "other";
    end

    % Flag columns >80% missing
    if prof.nmissing(k) / n > 0.80
        prof.skip(k)        = true;
        prof.skip_reason(k) = "mostly missing";
    end

    % Flag ID-like categorical columns (every non-missing value is unique)
    n_present = n - prof.nmissing(k);
    if n_present > 1 && prof.nunique(k) == n_present && prof.type(k) == "categorical"
        prof.skip(k)        = true;
        prof.skip_reason(k) = "all values unique (ID column)";
    end
end
end
