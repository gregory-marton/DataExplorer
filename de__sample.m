function T = de__sample(T, maxrows)
%DE__SAMPLE  Uniform-random downsample a table to maxrows rows (no-op if smaller).
    n = height(T);
    if n > maxrows
        idx = sort(randperm(n, maxrows));
        T   = T(idx, :);
        fprintf('  ℹ Large file: keeping %d of %d rows (random sample).\n', ...
            maxrows, n);
        fprintf('    Increase with:  DataExplorer(file, MaxRows=N)\n');
    end
end
