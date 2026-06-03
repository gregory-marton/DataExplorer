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
        % Keys are uppercased to match the uppercased column values below
        % (so full names like "Alabama" match, not just 2-letter codes).
        for ci = 1:numel(g.codes)
            k = upper(char(g.codes{ci}));
            if ~isKey(vocab, k), vocab(k) = true; end
        end
        for ki = 1:numel(g.alias_keys)
            k = upper(char(g.alias_keys{ki}));
            if ~isKey(vocab, k), vocab(k) = true; end
        end
        GEO_GRIDS(gi).name  = g.name;
        GEO_GRIDS(gi).vocab = vocab;
    end
end

catname   = prof.name{idx};
col_lower = lower(catname);

% Always score against actual VALUES — a geographic name (e.g. "StateCode") is
% only a hint; the values must really match the grid (FIPS numbers must not pass
% as us-states just because the name says "state").
cat_col   = T.(catname);
cats_orig = categories(cat_col);
cnts      = countcats(cat_col);                         % occurrences per category
levels    = cellstr(upper(strtrim(string(cats_orig(cnts > 0)))));  % uppercase for matching
n = numel(levels);
if n == 0, grid_name = ''; return; end

scores = zeros(1, numel(GEO_GRIDS));
for gi = 1:numel(GEO_GRIDS)
    vocab     = GEO_GRIDS(gi).vocab;
    scores(gi) = sum(cellfun(@(lv) isKey(vocab, lv), levels)) / n;
end
[best_score, gi_best] = max(scores);

% Name hint: relaxes the bar for the named grid, but values must still match it.
NAME_THRESH = 0.40;   % a name-hinted grid needs at least this fraction of values
SCAN_THRESH = 0.60;   % a grid vouched for by values alone needs more

hinted = '';
if contains(col_lower, 'state')
    hinted = 'us-states';
elseif any(contains(col_lower, {'country','nation','iso'}))
    hinted = 'world';
end

if ~isempty(hinted)
    hi = find(strcmp({GEO_GRIDS.name}, hinted), 1);
    if ~isempty(hi) && scores(hi) >= NAME_THRESH
        grid_name = hinted;  return
    end
end

if n >= 3 && best_score >= SCAN_THRESH
    grid_name = GEO_GRIDS(gi_best).name;
else
    grid_name = '';
end
end
