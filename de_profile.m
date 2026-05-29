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
%     prof.geo_grid    1×ncol cell array — geo grid name string for geo-like
%                      categorical columns, '' everywhere else
%     prof.panel       struct — panel detection result (see de_detect_wide_years)
%                      fields: is_panel, grouping_idxs, geo_idx, non_geo_idxs,
%                              description, wide_yr_idxs, wide_yr_vals
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
prof.geo_grid    = repmat({''}, 1, ncol);

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

% ── Geo detection (per categorical column) ───────────────────────────────────
cat_cols = find(prof.type == "categorical" & ~prof.skip);
for k = cat_cols
    g = de_looks_like_geo(prof, k, T);
    if ~isempty(g)
        prof.geo_grid{k} = g;
    end
end

% ── Panel detection ───────────────────────────────────────────────────────────
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
panel.is_panel      = false;
panel.grouping_idxs = [];
panel.geo_idx       = [];
panel.non_geo_idxs  = [];
panel.description   = '';
panel.wide_yr_idxs  = wide_yr_idxs;
panel.wide_yr_vals  = wide_yr_vals;

cat_all = find(prof.type == "categorical" & ~prof.skip);
if ~isempty(wide_yr_idxs) && ~isempty(cat_all) && any(prof.nunique(cat_all) > 2)
    panel.is_panel      = true;
    panel.grouping_idxs = cat_all;

    for k = 1:numel(cat_all)
        if ~isempty(prof.geo_grid{cat_all(k)})
            panel.geo_idx = cat_all(k);
            break
        end
    end
    panel.non_geo_idxs = cat_all(~ismember(cat_all, panel.geo_idx));

    parts = cell(1, numel(cat_all)+1);
    for k = 1:numel(cat_all)
        ci = cat_all(k);
        parts{k} = sprintf('%s (%d levels)', prof.name{ci}, prof.nunique(ci));
    end
    yr_min = min(wide_yr_vals);  yr_max = max(wide_yr_vals);
    parts{end} = sprintf('%d years (%g%s%g)', numel(wide_yr_vals), yr_min, char(8211), yr_max);
    panel.description = strjoin(parts, [' ' char(215) ' ']);
end
prof.panel = panel;
end
