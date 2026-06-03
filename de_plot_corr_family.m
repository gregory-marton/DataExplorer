function de_plot_corr_family(T, prof, family_idx, options)
%DE_PLOT_CORR_FAMILY  Visualise a group of strongly-correlated numeric columns.
%
%   de_plot_corr_family(T, prof, family_idx)
%
%   family_idx  — vector of column indices (into prof.name) forming the family,
%                 ordered most- to least-informative (first = representative).
%
%   Renders a pairplot of the family members, capped at the 8 most informative,
%   so their pairwise relationships are directly visible.  This is a drill-down
%   into a family that the main pairplot and choropleths collapse to a single
%   representative.
%
%   Requires no toolboxes (delegates to de_pairplot).

arguments
    T          table
    prof       struct
    family_idx (1,:) double
    options.Source   (1,1) string = ""   % reserved for a future geographic view
    options.FontSize (1,1) double = 8
    options.MaxVars  (1,1) double = 8
end

k = numel(family_idx);
if k < 2, return; end

% Cap at the most informative members (family_idx is variance-ordered).
members = family_idx(1:min(k, options.MaxVars));

rep_name = prof.name{family_idx(1)};
win_title = sprintf('Family: %s', rep_name);   % window name: short

% Detail (shown inside the figure, not in the window title):
% how many correlated, how many shown, and which members are not shown.
sub = sprintf('%d correlated variables', k);
if numel(members) < k
    omitted = prof.name(family_idx(numel(members)+1:end));
    sub = sprintf('%s — showing %d of %d; not shown: %s', ...
        sub, numel(members), k, strjoin(omitted, ', '));
end

de_pairplot(T, prof, members, FontSize=options.FontSize, ...
    Title=string(win_title), Subtitle=string(sub));
end
