function cmap = dex_blues_cmap(n)
%DEX_BLUES_CMAP  White-to-blue perceptual colormap for heatmaps.
%
%   cmap = dex_blues_cmap(n)   returns an n×3 RGB array
%
%   Used by ca_plot_v_matrix, ca_cond_heatmap, and pp_cat_cat wherever a
%   light-background blues scale is needed.  The endpoint [0.13 0.44 0.71]
%   matches MATLAB's default blue.
cmap = interp1([0 1], [1 1 1; 0.13 0.44 0.71], linspace(0, 1, n));
end
