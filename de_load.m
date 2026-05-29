function [T, prof] = de_load(filepath, options)
%DE_LOAD  Load a tabular file, optionally sample it, and profile it.
%
%   T          = de_load('data.csv')
%   T          = de_load('data.xlsx', Sheet='Data')
%   [T, prof]  = de_load('bigfile.csv', MaxRows=50000)
%   [T, prof]  = de_load('Prod_dataset.xlsx', Sheet='Data', MaxRows=10000)
%
%   For text files (CSV/TSV/TXT) with MaxRows set, uses de_reservoir_sample so
%   every row has equal probability regardless of file size.
%   For Excel with MaxRows set, loads the sheet first then draws a uniform
%   random subsample (Excel cannot be streamed).
%
%   Name-value options
%   ──────────────────
%   Sheet                Sheet name or index for xlsx (default: first sheet)
%   VariableNamesRange   Header cell range, e.g. 'A1' (xlsx, default 'A1')
%   DataRange            Data start cell, e.g. 'A2' (xlsx, default 'A2')
%   MaxRows              Row budget. Inf = load everything (default).

arguments
    filepath (1,1) string
    options.Sheet               = ""
    options.VariableNamesRange  (1,1) string = "A1"
    options.DataRange           (1,1) string = "A2"
    options.MaxRows             (1,1) double = Inf
end

[~, ~, ext] = fileparts(filepath);
is_excel = ismember(lower(string(ext)), [".xlsx", ".xls", ".xlsm", ".xlsb"]);

if is_excel
    io_args = {'VariableNamesRange', char(options.VariableNamesRange), ...
               'DataRange',          char(options.DataRange)};
    if strlength(options.Sheet) > 0
        io_args = [io_args, {'Sheet', char(options.Sheet)}];
    end
    io = detectImportOptions(filepath, io_args{:});
    io.MissingRule = 'fill';
    T = readtable(filepath, io);
    if isfinite(options.MaxRows) && height(T) > options.MaxRows
        n_total = height(T);
        idx     = sort(randperm(n_total, options.MaxRows));
        T       = T(idx, :);
        fprintf('  de_load: sampled %d of %d rows (uniform random).\n', ...
            options.MaxRows, n_total);
    end
else
    if isfinite(options.MaxRows)
        T = de_reservoir_sample(filepath, options.MaxRows);
    else
        T = readtable(filepath, 'TextType', 'string');
    end
end

[T, prof] = de_profile(T);
end
