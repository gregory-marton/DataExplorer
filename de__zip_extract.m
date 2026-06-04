function de__zip_extract(zippath, entry_name, outdir)
%DE__ZIP_EXTRACT  Extract one named entry using the system unzip tool (-j junks paths).
    cmd = sprintf('unzip -j -d "%s" "%s" "%s"', outdir, zippath, entry_name);
    [status, out] = system(cmd);
    if status ~= 0
        error('DataExplorer:zipExtractFailed', ...
            'unzip failed for entry "%s":\n%s', entry_name, out);
    end
    % Some ZIP tools encode filenames with trailing whitespace.  unzip
    % preserves that in the output filename; rename to the clean version.
    [~, base, ext] = fileparts(entry_name);
    raw_base   = [base ext];
    clean_base = strtrim(raw_base);
    if ~strcmp(raw_base, clean_base)
        src = fullfile(outdir, raw_base);
        dst = fullfile(outdir, clean_base);
        if exist(src, 'file') && ~exist(dst, 'file')
            movefile(src, dst);
        end
    end
end
