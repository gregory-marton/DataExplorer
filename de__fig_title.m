function s = de__fig_title(label, source_name)
%DE__FIG_TITLE  Build a figure Name string from a label and source_name.
%   Appends ": varname" when source_name ends with [varname] (NetCDF convention).
%
%   Replaces: se_fig_title (DataExplorer.m), ov_fig_name (de_overview.m),
%             pp_fig_name (de_pairplot.m), fig_title (drilldown, panel_totals).
m = regexp(char(source_name), '\[([^\]]+)\]\s*$', 'tokens', 'once');
if ~isempty(m)
    s = sprintf('%s: %s', label, strtrim(m{1}));
else
    s = label;
end
end
