function T = de_reservoir_sample(filepath, nrows, options)
%RESERVOIRSAMPLE  Uniform random sample from a large CSV/TSV/text file.
%
%   Reads the file in chunks without loading it fully into memory,
%   using reservoir sampling (Algorithm R) to guarantee that every
%   row in the file has an equal probability of appearing in the result.
%
%   Usage
%   ─────
%   T = de_reservoir_sample('ebirddata.tsv')          % 10 000 rows (default)
%   T = de_reservoir_sample('ebirddata.tsv', 50000)   % 50 000 rows
%   T = de_reservoir_sample('bigfile.csv', 10000, Seed=42)   % reproducible sample
%
%   The result is a MATLAB table you can pass directly to DataExplorer:
%       T = de_reservoir_sample('ebirddata.tsv', 10000);
%       DataExplorer(T);
%   or save for later:
%       save('my_sample.mat', 'T');
%
%   Optional arguments
%   ──────────────────
%   Seed      ([]   )   Random seed for reproducibility. Empty = unseeded.
%   ChunkSize (50000)   Rows per read. Larger = faster but more memory per chunk.
%   Verbose   (true )   Print progress to the command window.
%
%   Supported formats: CSV, TSV, TXT, DAT (delimiter auto-detected).
%   For Excel or ZIP files, load manually and pass the table to DataExplorer.

arguments
    filepath  (1,1) string
    nrows     (1,1) double = 10000
    options.Seed      = []
    options.ChunkSize (1,1) double = 50000
    options.Verbose   (1,1) logical = true
end

if ~isfile(filepath)
    error('de_reservoir_sample:notFound', 'File not found: %s', filepath);
end

[~, fname, ext] = fileparts(filepath);
ext = lower(ext);
if ~ismember(ext, [".csv", ".tsv", ".txt", ".dat", ".tab", ".asc"])
    warning('de_reservoir_sample:format', ...
        'Unexpected extension "%s". Attempting to read as delimited text.', ext);
end

if ~isempty(options.Seed)
    rng(options.Seed);
end

fid = fopen(filepath, 'r', 'n', 'UTF-8');
if fid == -1
    fid = fopen(filepath, 'r');
end
firstline = fgetl(fid);
fclose(fid);

counts    = [sum(firstline == ','), sum(firstline == char(9)), ...
             sum(firstline == ';'),  sum(firstline == '|')];
delims    = {',', '\t', ';', '|'};
dnames    = {'comma-separated', 'tab-separated', 'semicolon-separated', 'pipe-separated'};
[~, di]   = max(counts);
delim     = delims{di};

if options.Verbose
    info   = dir(filepath);
    fprintf('\n  de_reservoir_sample: %s%s  (%.1f MB)\n', fname, ext, info.bytes/1e6);
    fprintf('  Format: %s\n', dnames{di});
    fprintf('  Target sample: %d rows\n\n', nrows);
end

try
    ds = datastore(filepath, 'Type', 'tabulartext', ...
        'Delimiter',      delim, ...
        'ReadSize',       options.ChunkSize, ...
        'FileExtensions', {'.csv','.tsv','.txt','.dat','.tab','.asc'});
    ds.TextscanFormats = repmat({'%q'}, 1, numel(ds.VariableNames));
catch ME
    error('de_reservoir_sample:datastoreError', ...
        'Could not create datastore: %s\nCheck that the file is readable text.', ...
        ME.message);
end

%% ── Reservoir sampling (Algorithm R) ─────────────────────────────────────────
%
%   Invariant: after processing row i, `reservoir` contains a uniform
%   random sample of min(nrows, i) rows from all rows seen so far.
%
%   For each new row i > nrows, replace a uniformly chosen reservoir
%   slot with probability nrows/i.

reservoir = [];
n_seen    = 0;
k         = nrows;

while hasdata(ds)
    chunk   = read(ds);
    n_chunk = height(chunk);
    if n_chunk == 0, continue; end

    if isempty(reservoir) && n_chunk < k
        reservoir = chunk;
        n_seen    = n_chunk;
        continue
    end

    if isempty(reservoir)
        reservoir = chunk(1:k, :);
        n_seen    = k;
        start_row = k + 1;
    else
        start_row = 1;
    end

    for i = start_row : n_chunk
        n_seen = n_seen + 1;

        if height(reservoir) < k
            reservoir(end+1, :) = chunk(i, :); %#ok<AGROW>
        else
            j = randi(n_seen);
            if j <= k
                reservoir(j, :) = chunk(i, :); %#ok<AGROW>
            end
        end
    end

    if options.Verbose
        fprintf('  Processed %d rows…\r', n_seen);
    end
end

if options.Verbose
    fprintf('  ✓ Done. Sampled %d of %d rows total.%s\n', ...
        height(reservoir), n_seen, repmat(' ', 1, 20));
    if n_seen <= k
        fprintf('  ℹ File had fewer rows than requested — returning all %d.\n', n_seen);
    end
    fprintf('\n');
end

T = reservoir;

names      = T.Properties.VariableNames;
is_default = all(cellfun(@(n) ~isempty(regexp(n, '^Var\d+$', 'once')), names));
if is_default
    fprintf(['  ⚠ All column names are Var1, Var2, … — the header row may\n' ...
             '    not have been detected. Check the file manually.\n\n']);
end
end
