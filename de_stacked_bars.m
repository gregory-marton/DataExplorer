function de_stacked_bars(T, grp_col, val_col)
%DE_STACKED_BARS  100% stacked bar chart for a categorical pair.
%
%   de_stacked_bars(T, grp_col, val_col)
%
%   One horizontal bar per level of GRP_COL. Bar segments show the
%   proportion of each VAL_COL category within that group. Segment labels
%   are printed directly on the bars (no legend).
%
%   See also de_plot_cat_association, de_pareto_multiples, de_cond_heatmap.
de_plot_cat_association(T, struct(), Figure="pair", ...
    Columns=[string(grp_col) string(val_col)], ForcePlot="stacked");
end
