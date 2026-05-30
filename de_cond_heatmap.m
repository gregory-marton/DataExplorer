function de_cond_heatmap(T, grp_col, val_col)
%DE_COND_HEATMAP  Conditional heatmap for a high-cardinality categorical pair.
%
%   de_cond_heatmap(T, grp_col, val_col)
%
%   Heatmap of P(val_col | grp_col) with SVD-reordered rows and columns.
%   Suitable when both categoricals have high cardinality (>15 levels).
%
%   See also de_plot_cat_association, de_pareto_multiples, de_stacked_bars.
de_plot_cat_association(T, struct(), Figure="pair", ...
    Columns=[string(grp_col) string(val_col)], ForcePlot="heatmap");
end
