function F = de__font_sizes(base)
%DE__FONT_SIZES  Shared font-size hierarchy for DataExplorer plots.
%
%   F = de__font_sizes()        base = 9  (association plots)
%   F = de__font_sizes(base)    caller-supplied base (e.g. 7 for overview / tilegrid)
%
%   Fields
%   ------
%   F.tiny     secondary labels, small annotations            (base - 1)
%   F.base     tick labels, data labels, small axis text      (base)
%   F.subtitle subplot titles, group-name tick labels         (base + 1)
%   F.axlabel  axis labels (xlabel / ylabel)                  (base + 2)
%   F.title    main title, sgtitle for figure-level titles    (base + 3)
%   F.page     page-level sgtitle, choropleth / overview head (base + 4)
if nargin < 1, base = 9; end
F.tiny     = base - 1;
F.base     = base;
F.subtitle = base + 1;
F.axlabel  = base + 2;
F.title    = base + 3;
F.page     = base + 4;
end
