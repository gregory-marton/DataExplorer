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
%   When the table has a geographic key, it ALSO draws a geo small-multiples
%   ("value ladder"): each region tile holds a sparkline of the family members,
%   on a y-scale shared across all tiles, so you can compare members within a
%   region and across regions.  Members whose scale is too small to read on the
%   shared axis are dropped, with a note in the legend.
%
%   Requires no toolboxes (delegates to de_pairplot / de_statebins).

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

% ── Geo small-multiples (value ladder), if a geographic key exists ────────────
geo_idx = [];
if isfield(prof, 'geo_grid')
    for gk = find((prof.type == "categorical") & ~prof.skip)
        if numel(prof.geo_grid) >= gk && ~isempty(prof.geo_grid{gk})
            geo_idx = gk; break
        end
    end
end
if isempty(geo_idx), return; end

% Order all family members by overall magnitude (largest median first) and drop
% members whose scale is too small to read on a shared axis (note them).
fam_names = string(prof.name(family_idx));
meds = arrayfun(@(nm) median(double(T.(char(nm))), 'omitnan'), fam_names);
[~, ord] = sort(meds, 'descend', 'MissingPlacement', 'last');
fam_names = fam_names(ord);  meds = meds(ord);
ref = max(abs(meds));
keep = abs(meds) >= ref / 50 & ~isnan(meds);   % within ~1.7 decades of the top
ladder_cols = fam_names(keep);
dropped     = fam_names(~keep);
if numel(ladder_cols) < 2, return; end

note = "";
if ~isempty(dropped)
    note = "scale-omitted: " + strjoin(dropped, ", ");
end

geo_col  = string(prof.name{geo_idx});
grid_nm  = prof.geo_grid{geo_idx};
gtitle   = sprintf('Family ladder: %s', rep_name);
switch grid_nm
    case 'us-states'
        de_statebins(T, StateCol=geo_col, ColorCol=ladder_cols(1), ...
            CellRenderer="value_ladder", ValueCols=ladder_cols, ...
            LegendNote=note, Title=string(gtitle));
    case 'world'
        de_countrybins(T, CountryCol=geo_col, ColorCol=ladder_cols(1), ...
            CellRenderer="value_ladder", ValueCols=ladder_cols, ...
            LegendNote=note, Title=string(gtitle));
    otherwise
        de_geobins(T, GeoCol=geo_col, Grid=grid_nm, ColorCol=ladder_cols(1), ...
            CellRenderer="value_ladder", ValueCols=ladder_cols, ...
            LegendNote=note, Title=string(gtitle));
end
end
