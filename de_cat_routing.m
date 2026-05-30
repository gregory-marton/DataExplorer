function route = de_cat_routing(ng)
%DE_CAT_ROUTING  Canonical plot-type for a categorical pair with ng groups.
%
%   route = de_cat_routing(ng)
%
%   Returns 'pareto' | 'stacked' | 'heatmap'.  Single source of truth for
%   the thresholds shared by de_plot_cat_association and DataExplorer's
%   recipe generator (cg_cat_association_code).
%
%   ng should be the number of *observed* group categories (after removecats).
PARETO_MAX  = 6;
STACKED_MAX = 20;  % must equal MAX_S in ca_cond_heatmap: use proportion whenever all groups fit without "Other"
if ng <= PARETO_MAX
    route = 'pareto';
elseif ng <= STACKED_MAX
    route = 'stacked';
else
    route = 'heatmap';
end
end
