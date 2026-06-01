function de__stamp_source(fig, source_name)
%DE__STAMP_SOURCE  Add a small gray source-name footnote at the bottom of a figure.
%   Skipped when source_name is empty or 'table input'.
%   FontSize is fixed at 7 to fit the constant-height annotation textbox.
%
%   Replaces: se_stamp_source (DataExplorer.m), pp_stamp_source (de_pairplot.m),
%             and the inline annotation in de_overview.m.
if isempty(source_name) || strcmp(char(source_name), 'table input'), return; end
annotation(fig, 'textbox', [0.0, 0.0, 1.0, 0.022], 'String', char(source_name), ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontSize', 7, 'Color', [0.55 0.55 0.55], 'Interpreter', 'none', 'FitBoxToText', 'off');
end
