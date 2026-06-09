function families = de_corr_families(T, prof, options)
%DE_CORR_FAMILIES  Detect groups of strongly correlated numeric columns.
%
%   families = de_corr_families(T, prof)
%   families = de_corr_families(T, prof, Threshold=0.80, MinSize=3, Method="spearman")
%
%   Returns a cell array; each cell is a vector of column indices (into
%   prof.name) whose pairwise |correlation| >= Threshold under complete linkage.
%   Groups with fewer than MinSize members are discarded.
%
%   Method:
%     "spearman" (default) — rank correlation; ideal for monotonically related
%                            families such as percentiles / max-values / mean.
%     "pearson"            — linear correlation.
%   Both are computed toolbox-free (ranks + corrcoef), so no Statistics Toolbox.
%
%   Clustering: complete-linkage — a column joins a group only when it exceeds
%   the threshold with EVERY existing member.  Within each group the first element
%   is the MEDOID (the member with the highest mean |correlation| to the rest):
%   the most representative member, used as the family's representative downstream
%   since all other members are dropped from the pairplot/choropleths.

arguments
    T         table
    prof      struct
    options.Threshold (1,1) double {mustBeGreaterThanOrEqual(options.Threshold, 0), mustBeLessThanOrEqual(options.Threshold, 1)} = 0.80
    options.MinSize   (1,1) double {mustBePositive} = 3
    options.Method    (1,1) string {mustBeMember(options.Method, ["spearman","pearson"])} = "spearman"
end

LAT_LON = ["lat","latitude","lat_","latitude_dd","decimallatitude", ...
           "lon","long","longitude","lon_","longitude_dd","decimallongitude"];
names_lower = lower(string(prof.name));
is_coord    = ismember(names_lower, LAT_LON);

candidates = find(prof.type == "numeric" & ~prof.skip & ~is_coord);
m = numel(candidates);
families = {};
if m < options.MinSize
    return
end

% Build data matrix
X = NaN(height(T), m);
for k = 1:m
    X(:, k) = double(T.(prof.name{candidates(k)}));
end

use_rank = options.Method == "spearman";

% Pairwise |correlation| matrix, computed on each pair's shared valid rows.
MIN_VALID = 10;
R = eye(m);
for i = 1:m-1
    for j = i+1:m
        both = ~isnan(X(:,i)) & ~isnan(X(:,j));
        if sum(both) < MIN_VALID, continue; end
        a = X(both, i);  b = X(both, j);
        if use_rank
            a = de_rankavg(a);  b = de_rankavg(b);
        end
        if std(a) == 0 || std(b) == 0, continue; end
        c = corrcoef(a, b);
        r = abs(c(1, 2));
        if isnan(r), continue; end
        R(i, j) = r;
        R(j, i) = r;
    end
end

% Greedy complete-linkage clustering, seeded by descending variance.
col_var  = var(X, 0, 1, 'omitnan');
[~, ord] = sort(col_var, 'descend');
assigned = false(1, m);
thr      = options.Threshold;

families = cell(1, m);   % pre-allocate; trimmed at end
nfam     = 0;

for si = 1:m
    seed = ord(si);
    if assigned(seed), continue; end

    in_cluster = false(1, m);
    in_cluster(seed) = true;

    for j = 1:m
        if j == seed || assigned(j), continue; end
        if all(R(j, in_cluster) >= thr)
            in_cluster(j) = true;
        end
    end

    cluster_indices = find(in_cluster);
    if numel(cluster_indices) >= options.MinSize
        % Representative = medoid: the member with the highest mean |correlation|
        % to the rest of the family.  Since every other member is dropped from
        % downstream plots, the survivor should be the most representative of the
        % shared signal — not the most extreme (variance is scale-biased).
        sub  = R(cluster_indices, cluster_indices);
        nci  = numel(cluster_indices);
        ma   = (sum(sub, 2)' - 1) / max(nci - 1, 1);   % mean |r| to others (1×nci)
        [~, mo] = sort(ma, 'descend');
        cluster_indices = cluster_indices(mo);          % medoid first
        nfam           = nfam + 1;
        families{nfam} = candidates(cluster_indices);
        assigned(in_cluster) = true;
    end
end

families = families(1:nfam);
end


function rk = de_rankavg(v)
%DE_RANKAVG  Ranks with average-of-ties (toolbox-free tiedrank equivalent).
v  = v(:);
nn = numel(v);
[sv, ord] = sort(v);
rk_sorted = (1:nn)';
i = 1;
while i <= nn
    j = i;
    while j < nn && sv(j+1) == sv(i)
        j = j + 1;
    end
    if j > i
        rk_sorted(i:j) = mean(i:j);
    end
    i = j + 1;
end
rk = zeros(nn, 1);
rk(ord) = rk_sorted;
end
