function [strat, eta2, cand_names, cand_w] = de_pick_stratifier(T, prof, target_names, geo_name, options)
%DE_PICK_STRATIFIER  Weighted-random pick of a categorical to stratify a numeric.
%
%   [strat, eta2, cand_names, cand_w] = de_pick_stratifier(T, prof, targets, geo)
%
%   targets — name(s) of the numeric column(s) whose per-region mean we are about
%             to map.  geo — name of the geographic key (excluded as a candidate).
%
%   Scores every qualifying categorical by η² (de_variance_explained) against the
%   target numeric(s) — how strongly it stratifies them — then samples ONE with
%   probability proportional to that strength.  The pick is deliberately random,
%   not argmax: the tool cannot know which stratifier is *semantically* the right
%   commensurability key (e.g. PollutantStandard vs the leaky proxy UnitsOfMeasure),
%   so it surfaces strong candidates with proportional likelihood and lets the
%   student choose.  Re-running (a fresh RNG) yields a different valid view.
%
%   Seed the global RNG before calling for a reproducible pick.
%
%   Returns strat="" when no categorical clears the Floor.  cand_names/cand_w are
%   the qualifying candidates and their η² weights (for transparency / testing).
%
%   Qualifying candidate: categorical, not profiler-skipped, not the geo key,
%   not itself geographic or temporal, with cardinality in [2, MaxCard].

arguments
    T                   table
    prof                struct
    target_names        (1,:) string
    geo_name            (1,1) string = ""
    options.Floor       (1,1) double = 0.05
    options.MaxCard     (1,1) double = 15
end

strat = "";  eta2 = 0;  cand_names = strings(0, 1);  cand_w = [];

names = string(prof.name(:)).';
ncol  = numel(names);

% Numeric targets that actually exist
tgt = find(ismember(names, target_names) & prof.type(:).' == "numeric");
if isempty(tgt), return; end

% Geo-grid and role masks
has_grid = false(1, ncol);
if isfield(prof, 'geo_grid')
    for k = 1:ncol
        if numel(prof.geo_grid) >= k && ~isempty(prof.geo_grid{k})
            has_grid(k) = true;
        end
    end
end
role = strings(1, ncol);
if isfield(prof, 'role'), role = string(prof.role(:)).'; end

is_cat = prof.type(:).' == "categorical" & ~prof.skip(:).';
ok = is_cat & ~has_grid & names ~= geo_name ...
    & role ~= "temporal" & role ~= "geographic" ...
    & prof.nunique(:).' >= 2 & prof.nunique(:).' <= options.MaxCard;
cand_idx = find(ok);
if isempty(cand_idx), return; end

% η² weight = mean strength across the target numeric(s)
w = zeros(1, numel(cand_idx));
for ci = 1:numel(cand_idx)
    g  = T.(char(names(cand_idx(ci))));
    es = zeros(1, numel(tgt));
    for ti = 1:numel(tgt)
        es(ti) = de_variance_explained(T.(char(names(tgt(ti)))), g);
    end
    w(ci) = mean(es);
end

keep     = w >= options.Floor;
cand_idx = cand_idx(keep);
w        = w(keep);
if isempty(cand_idx), return; end

cand_names = names(cand_idx).';
cand_w     = w;

% Weighted-random sample, probability ∝ η²
cw   = cumsum(w) / sum(w);
pick = find(rand <= cw, 1);
if isempty(pick), pick = numel(cand_idx); end

strat = names(cand_idx(pick));
eta2  = w(pick);
end
