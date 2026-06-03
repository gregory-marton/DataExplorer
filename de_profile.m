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

NUMERIC_FRAC   = 0.70;  % convert string col to numeric if ≥ this fraction parses
SKIP_MISS_FRAC = 0.80;  % flag col as skippable if > this fraction is missing

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
prof.skewness    = nan(1, ncol);
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

    % String/char/cellstr: try numeric conversion, else categorical.
    % Two heuristics prevent numeric conversion for identifier-like columns:
    %   1. Leading-zero detection: values like "01","003" are codes, not numbers.
    %   2. Name keyword check: split on CamelCase/snake_case; match id/code/num/number.
    if ischar(col) || iscellstr(col) || (isstring(col) && ~isscalar(col))
        col = string(col);
        col(ismember(col, missingStrings)) = missing;
        numvals     = str2double(col);
        pct_numeric = sum(~isnan(numvals)) / n;

        % Leading-zero check (e.g., FIPS codes "01","003","0010"): language-agnostic.
        valid_mask = ~isnan(numvals) & col ~= missing;
        if any(valid_mask)
            lz = valid_mask & startsWith(col, '0') & ~startsWith(col, '0.') & col ~= "0";
            pct_lz = sum(lz) / max(sum(valid_mask), 1);
        else
            pct_lz = 0;
        end

        % Name keyword check: tokenize (CamelCase/snake_case); match last word.
        % ("NumObsBelowMDL" → last word "mdl" → no match; "CountyCode" → "code" → match)
        toks       = de_name_tokens(cname);
        is_id_name = ismember(toks(end), ["code","id","num","number"]);

        if pct_numeric >= NUMERIC_FRAC && pct_lz <= 0.10 && ~is_id_name
            col = numvals;
        else
            % Try temporal parsing for date-like strings readtable left as text.
            dt = de_maybe_datetime(col);
            if ~isempty(dt)
                col = dt;
            else
                col = categorical(col);
            end
        end
        T.(cname) = col;
    end

    % Re-fetch after possible conversion
    col = T.(cname);

    % Reclassify pre-loaded integer columns whose name looks like an identifier.
    % readtable loads "State Code" as int/double 1..56 before profiling — the
    % string-conversion block above is never reached for those.  Check again here.
    if isnumeric(col) && ~islogical(col) && prof.orig_class(k) ~= "text"
        col_clean = col(~isnan(col));
        if ~isempty(col_clean) && all(col_clean == floor(col_clean))
            toks_k     = de_name_tokens(cname);
            is_id_k    = ismember(toks_k(end), ["code","id","num","number"]);
            if is_id_k
                col_str = string(col);
                col_str(strcmp(col_str, "NaN")) = missing;
                col = categorical(col_str);
                T.(cname) = col;
            end
        end
    end

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
        x = double(col(~isnan(col)));
        if numel(x) > 2
            s = std(x);
            if s > 0
                prof.skewness(k) = mean(((x - mean(x)) / s).^3);
            end
        end

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
    if prof.nmissing(k) / n > SKIP_MISS_FRAC
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

% ── High-cardinality categorical skip (after geo detection so geo cols exempt) ─
HIGH_CARD_THRESHOLD = 100;
for k = find(prof.type == "categorical" & ~prof.skip)
    if prof.nunique(k) > HIGH_CARD_THRESHOLD && isempty(prof.geo_grid{k})
        prof.skip(k)        = true;
        prof.skip_reason(k) = sprintf("high-cardinality (%d unique values)", prof.nunique(k));
    end
end

% ── Redundant categorical skip ────────────────────────────────────────────────
% When two categoricals are near-perfectly associated (Cramér's V ≈ 1) they carry
% the same information.  Keep one representative and skip the other (prefer
% dropping an identifier-named, non-geo, or higher-cardinality column).  The
% skipped column still shows in the overview — just not in analysis plots.
REDUNDANT_V = 0.95;
cat_live = find((prof.type == "categorical" | prof.type == "logical") & ~prof.skip);
for ii = 1:numel(cat_live)
    a = cat_live(ii);
    if prof.skip(a), continue; end
    for jj = ii+1:numel(cat_live)
        b = cat_live(jj);
        if prof.skip(b), continue; end
        v = de_cramer_v(T.(prof.name{a}), T.(prof.name{b}));
        if v >= REDUNDANT_V
            drop = de_redundant_pick(prof, a, b);
            keep = a + b - drop;
            prof.skip(drop)        = true;
            prof.skip_reason(drop) = sprintf("redundant (V=%.2f with %s)", v, prof.name{keep});
            if drop == a, break; end   % a is gone; advance to the next a
        end
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

% ── Semantic role per column (geographic / temporal / identifier) ─────────────
% A layer on top of prof.type: surfaces the meaning of a column beyond its
% storage type.  Empty string for plain measures/categories.
LAT_LON_NAMES = ["lat","latitude","lat_","latitude_dd","decimallatitude", ...
                 "lon","long","longitude","lon_","longitude_dd","decimallongitude"];
names_lower = lower(string(prof.name));
prof.role   = repmat("", 1, ncol);
for k = 1:ncol
    nm_toks   = de_name_tokens(prof.name{k});
    last_word = nm_toks(end);

    is_geo  = ~isempty(prof.geo_grid{k}) || ismember(names_lower(k), LAT_LON_NAMES);
    is_time = prof.type(k) == "datetime" ...
        || (prof.type(k) == "numeric" && ...
            any(ismember(nm_toks, ["year","month","day","date","time"]))) ...
        || ismember(k, panel.wide_yr_idxs);
    is_ident = prof.skip_reason(k) == "all values unique (ID column)" ...
        || ismember(last_word, ["code","id","num","number"]);

    if is_geo
        prof.role(k) = "geographic";
    elseif is_time
        prof.role(k) = "temporal";
    elseif is_ident
        prof.role(k) = "identifier";
    end
end
end


% ── de_maybe_datetime ─────────────────────────────────────────────────────────
function dt = de_maybe_datetime(s)
%DE_MAYBE_DATETIME  Parse a string column to datetime if it is clearly date-like.
%   Returns [] unless >= 70% of non-missing values both (a) match a date-like
%   pattern (digit groups with -/ separators, a month name, or a HH:MM time)
%   and (b) parse to a valid (non-NaT) datetime.  Conservative by design so
%   decimal/code strings are never misread as dates.
dt = [];
s  = string(s);
nonmiss = s(~ismissing(s));
if isempty(nonmiss), return; end

datelike = ~cellfun('isempty', regexp(cellstr(nonmiss), ...
    '\d{1,4}[-/]\d{1,2}|[A-Za-z]{3,}\s+\d{1,2}|\d{1,2}:\d{2}', 'once'));
if mean(datelike) < 0.70, return; end

try
    cand = datetime(s);
catch
    return
end
frac_ok = sum(~isnat(cand(~ismissing(s)))) / numel(nonmiss);
if frac_ok >= 0.70
    dt = cand;
end
end


% ── de_redundant_pick ─────────────────────────────────────────────────────────
function d = de_redundant_pick(prof, a, b)
%DE_REDUNDANT_PICK  Of two redundant categoricals, return the index to DROP,
%   keeping the more useful one: prefer dropping an identifier-named column, then
%   a non-geo column, then the higher-cardinality one, then the later index.
ida = de_tok_is_id(prof.name{a});
idb = de_tok_is_id(prof.name{b});
if ida ~= idb
    if ida, d = a; else, d = b; end
    return
end
ga = ~isempty(prof.geo_grid{a});
gb = ~isempty(prof.geo_grid{b});
if ga ~= gb
    if ga, d = b; else, d = a; end
    return
end
if prof.nunique(a) ~= prof.nunique(b)
    if prof.nunique(a) > prof.nunique(b), d = a; else, d = b; end
    return
end
d = max(a, b);
end


function tf = de_tok_is_id(name)
toks = de_name_tokens(name);
tf = ismember(toks(end), ["code","id","num","number"]);
end
