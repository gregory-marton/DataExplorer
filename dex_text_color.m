function clr = dex_text_color(bg_rgb, threshold)
%DEX_TEXT_COLOR  White or dark text color for legibility on a given background.
%
%   clr = dex_text_color(bg_rgb)            uses threshold = 0.5
%   clr = dex_text_color(bg_rgb, threshold) caller-supplied threshold
%
%   Returns [1 1 1] (white) when the background luminance is below the
%   threshold; [0 0 0] (black) otherwise.  Luminance via ITU-R BT.601.
if nargin < 2, threshold = 0.5; end
lum = 0.299*bg_rgb(1) + 0.587*bg_rgb(2) + 0.114*bg_rgb(3);
clr = [1 1 1] * double(lum < threshold);
end
