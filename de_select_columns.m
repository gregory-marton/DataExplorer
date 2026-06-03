function sel = de_select_columns(T, prof, maxv, families)
%DE_SELECT_COLUMNS  Pick the most informative, non-redundant columns to plot.
%
%   Numeric columns are scored by spread (std/range) and then pruned
%   greedily so that no two selected columns have |r| > CORR_THRESH.
%   Categorical columns are scored by Shannon entropy of their value
%   distribution (uniform = high entropy = informative; near-constant = 0).
%   The final selection interleaves: fill numeric slots first, then
%   categorical, up to maxv total.
%
%   Optional 4th argument: families — cell array from de_corr_families.
%   When supplied, only the first (highest-variance) member of each family
%   is eligible; all other family members are excluded before scoring.

if nargin < 4, families = {}; end

CORR_THRESH  = 0.92;
MAX_NUM_FRAC = 0.75;
MIN_CORR_N   = 10;   % min valid rows needed to compute correlation

not_skip = find(~prof.skip);

cat_idx = not_skip(prof.type(not_skip) == "categorical" | ...
                   prof.type(not_skip) == "logical");

num_idx = not_skip(prof.type(not_skip) == "numeric");

% Exclude lat/lon coordinate columns — they belong in the geo scatter, not pairplot.
LAT_LON_NAMES = ["lat","latitude","lat_","latitude_dd","decimallatitude", ...
                  "lon","long","longitude","lon_","longitude_dd","decimallongitude"];
names_lower = lower(string(prof.name));
is_coord    = ismember(names_lower, LAT_LON_NAMES);
num_idx     = num_idx(~is_coord(num_idx));

% Exclude non-representative family members: keep only fam(1) (highest-variance
% seed from de_corr_families); drop fam(2:end) so families show as one column.
if ~isempty(families)
    all_non_rep = cell2mat(cellfun(@(f) f(2:end), families, 'UniformOutput', false));
    num_idx = num_idx(~ismember(num_idx, all_non_rep));
end

num_scores = zeros(1, numel(num_idx));
for k = 1:numel(num_idx)
    col = T.(prof.name{num_idx(k)});
    col = double(col(~isnan(col)));
    if numel(col) < 2
        num_scores(k) = 0;
        continue
    end
    r = range(col);
    if r == 0
        num_scores(k) = 0;
    else
        num_scores(k) = std(col) / r;
    end
end

[~, num_ord] = sort(num_scores, 'descend');
num_ranked   = num_idx(num_ord);

num_sel = zeros(1, numel(num_ranked));
nsel = 0;
for k = 1:numel(num_ranked)
    candidate = num_ranked(k);
    if num_scores(num_ord(k)) == 0, continue; end

    if nsel == 0
        nsel = nsel + 1;
        num_sel(nsel) = candidate;
    else
        cand_col = T.(prof.name{candidate});

        valid = ~isnan(cand_col);
        for s = num_sel(1:nsel)
            valid = valid & ~isnan(T.(prof.name{s}));
        end

        if sum(valid) < MIN_CORR_N
            nsel = nsel + 1;
            num_sel(nsel) = candidate;
        else
            existing = cell2mat(arrayfun(@(s) T.(prof.name{s})(valid), ...
                num_sel(1:nsel), 'UniformOutput', false));
            r_vals = abs(corr(double(cand_col(valid)), double(existing)));
            if max(r_vals) < CORR_THRESH
                nsel = nsel + 1;
                num_sel(nsel) = candidate;
            end
        end
    end

    if nsel >= floor(maxv * MAX_NUM_FRAC) && ~isempty(cat_idx)
        break
    end
    if nsel >= maxv
        break
    end
end
num_sel = num_sel(1:nsel);

cat_scores = zeros(1, numel(cat_idx));
for k = 1:numel(cat_idx)
    col = T.(prof.name{cat_idx(k)});
    if islogical(col)
        p = [mean(col), 1-mean(col)];
        p = p(p > 0);
    else
        col = col(~isundefined(col));
        if isempty(col), continue; end
        counts = histcounts(col);
        p = counts(counts > 0) / numel(col);
    end
    cat_scores(k) = -sum(p .* log2(p));
end

[~, cat_ord] = sort(cat_scores, 'descend');
cat_sel = cat_idx(cat_ord);

remaining = maxv - numel(num_sel);
cat_sel   = cat_sel(1 : min(end, remaining));
sel       = [num_sel, cat_sel];
end
