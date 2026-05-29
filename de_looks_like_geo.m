function grid_name = de_looks_like_geo(prof, idx, T)
%DE_LOOKS_LIKE_GEO  Return the name of the best-matching geo grid, or ''.
%   Uses de_build_grids() (YAML→.mat cache) — any .yaml in data/grids/ is
%   automatically discovered.  Column name heuristics provide a fast path.

persistent GEO_GRIDS  % struct array: .name, .vocab (containers.Map, uppercase keys)
if isempty(GEO_GRIDS)
    grids = de_build_grids();
    GEO_GRIDS = struct('name', {}, 'vocab', {});
    for gi = 1:numel(grids)
        g     = grids(gi);
        vocab = containers.Map('KeyType','char','ValueType','logical');
        for ci = 1:numel(g.codes)
            k = char(g.codes{ci});
            if ~isKey(vocab, k), vocab(k) = true; end
        end
        for ki = 1:numel(g.alias_keys)
            k = char(g.alias_keys{ki});
            if ~isKey(vocab, k), vocab(k) = true; end
        end
        GEO_GRIDS(gi).name  = g.name;
        GEO_GRIDS(gi).vocab = vocab;
    end
end

catname   = prof.name{idx};
col_lower = lower(catname);

% Fast path: column name triggers for the two most common grids
if contains(col_lower, 'state')
    grid_name = 'us-states';  return
end
if any(contains(col_lower, {'country','nation','iso'}))
    grid_name = 'world';  return
end

% Code scan: check all loaded grids
cat_col = T.(catname);
all_levels = cellstr(upper(strtrim(string(categories(cat_col)))));
present    = cellfun(@(lv) sum(cat_col == lv) > 0, all_levels);
levels     = all_levels(present);
n = numel(levels);
if n < 3, grid_name = ''; return; end

THRESHOLD = 0.60;
best_name  = '';
best_score = 0;
for gi = 1:numel(GEO_GRIDS)
    vocab = GEO_GRIDS(gi).vocab;
    hits  = sum(cellfun(@(lv) isKey(vocab, lv), levels));
    score = hits / n;
    if score > best_score
        best_score = score;
        best_name  = GEO_GRIDS(gi).name;
    end
end
if best_score >= THRESHOLD
    grid_name = best_name;
else
    grid_name = '';
end
end
