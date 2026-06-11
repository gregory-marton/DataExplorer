function ln = de__guess_header_line(filepath, delim)
%DE__GUESS_HEADER_LINE  1-based line of the likely header in a delimited file
%   that has preamble rows above the header, or NaN if none is evident.
%
%   Heuristic: the header is the first line whose field count equals the file's
%   modal field count, is followed by another line of that same count, and is not
%   entirely numeric (it carries labels).  Preamble rows usually have a different
%   field count (e.g. a one-cell title), so they fall away.  Reads at most the
%   first 50 non-empty lines.  `delim` is the delimiter character (',', tab, …).
ln = NaN;
fid = fopen(filepath, 'r', 'n', 'UTF-8');
if fid == -1, fid = fopen(filepath, 'r'); end
if fid == -1, return; end

MAXL  = 50;
lines = strings(MAXL, 1);
n = 0;
while n < MAXL
    raw = fgetl(fid);
    if ~ischar(raw), break; end
    s = string(raw);
    if strlength(strtrim(s)) > 0
        n = n + 1;
        lines(n) = s;
    end
end
fclose(fid);
if n < 2, return; end
lines = lines(1:n);

fc    = arrayfun(@(s) 1 + count(s, delim), lines);   % fields per line
multi = fc(fc > 1);
if isempty(multi), return; end
modal = mode(multi);

for i = 1:n-1
    if fc(i) == modal && fc(i+1) == modal
        cells = strsplit(lines(i), delim);
        if ~all(~isnan(str2double(cells)))   % at least one non-numeric cell → labels
            ln = i;
            return
        end
    end
end
end
