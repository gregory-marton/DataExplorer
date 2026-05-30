function de_pareto_multiples(T, grp_col, val_col)
%DE_PARETO_MULTIPLES  Side-by-side Pareto charts for a categorical pair.
%
%   de_pareto_multiples(T, grp_col, val_col)
%
%   One Pareto subplot per level of GRP_COL (≤6 levels typical). Bars show
%   the count of each VAL_COL category within that group, sorted descending.
%   Left y-axis: shared count scale. Right y-axis: cumulative %.
%
%   See also de_plot_cat_association, de_stacked_bars, de_cond_heatmap.
de_plot_cat_association(T, struct(), Figure="pair", ...
    Columns=[string(grp_col) string(val_col)], ForcePlot="pareto");
end
