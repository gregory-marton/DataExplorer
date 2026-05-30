function p = de_cat_assoc_params()
%DE_CAT_ASSOC_PARAMS  Default thresholds for categorical association figures.
%
%   p = de_cat_assoc_params()
%
%   Returns a struct with fields:
%     VThresh   — min Cramer's V to qualify a pair for a figure  (0.10)
%     MaxPairs  — max number of pair figures produced            (3)
%
%   Single source of truth shared by de_plot_cat_association (named-argument
%   defaults) and cg_cat_association_code (recipe generator).
p.VThresh  = 0.10;
p.MaxPairs = 3;
end
