function entries = de__zip_list(filepath)
%DE__ZIP_LIST  Return struct array (.name, .bytes) for all non-directory ZIP entries.
%   Uses system unzip -l — fast even for archives with 20 000+ entries.
[status, out] = system(sprintf('unzip -l "%s" 2>/dev/null', filepath));
entries = struct('name', {}, 'bytes', {});
if status ~= 0, return; end
lines = strsplit(out, newline);
% Data lines: leading spaces, byte count, date MM-DD-YY[YY], time HH:MM, name
pat = '^\s*(\d+)\s+\d{2}-\d{2}-\d{2,4}\s+\d{2}:\d{2}\s+(.+)$';
buf = repmat(struct('name', '', 'bytes', 0), 1, numel(lines));
ne = 0;
for k = 1:numel(lines)
    tok = regexp(lines{k}, pat, 'tokens', 'once');
    if isempty(tok), continue; end
    name = tok{2};
    if isempty(name), continue; end
    if name(end) == '/', continue; end  % skip directory entries
    ne = ne + 1;
    buf(ne).name  = name;
    buf(ne).bytes = str2double(tok{1});
end
entries = buf(1:ne);
end
