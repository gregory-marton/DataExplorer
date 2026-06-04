function T = de__fix_names(T, filepath, ext, sheet)
%DE__FIX_NAMES  If all names are Var1, Var2, …, try using the literal first row.

    names = T.Properties.VariableNames;
    is_default = all(cellfun(@(n) ~isempty(regexp(n, '^Var\d+$', 'once')), names));

    if ~is_default
        return
    end

    fprintf('  ⚠ All column names are Var1, Var2, … — inspecting raw first row.\n');

    try
        if ismember(ext, [".xlsx", ".xls", ".xlsm"])
            raw = readtable(filepath, 'Sheet', sheet, ...
                'ReadVariableNames', false, 'ReadRowNames', false);
        else
            % Re-sniff delimiter
            fid = fopen(filepath, 'r');
            fl  = fgetl(fid);
            fclose(fid);
            ntabs = sum(fl == char(9));
            delim = ',';
            if ntabs > sum(fl == ','), delim = '\t'; end
            raw = readtable(filepath, 'Delimiter', delim, ...
                'ReadVariableNames', false, 'ReadRowNames', false);
        end

        firstrow = table2cell(raw(1, :));

        % A row looks like a pure-text header if every cell is non-numeric text
        is_text = cellfun(@(v) ischar(v) || isstring(v), firstrow);
        is_num  = cellfun(@(v) ~isnan(str2double(string(v))), firstrow);
        looks_like_header = all(is_text) && ~all(is_num);

        % Also detect mixed headers: some text labels + year-like integers
        % (e.g. "Data_Status, StateCode, MSN, 1960, 1961, …, 2023").
        % Require ≥3 year-like integers to avoid false positives on data rows
        % that happen to include one year value (e.g. survey year).
        YEAR_MIN  = 1900;  YEAR_MAX = 2100;
        year_vals = cellfun(@(v) isnumeric(v) && isscalar(v) && ~isnan(v) && ...
            v >= YEAR_MIN && v <= YEAR_MAX && v == floor(v), firstrow);
        looks_like_mixed_header = any(is_text) && sum(year_vals) >= 3 && ~looks_like_header;

        if looks_like_header || looks_like_mixed_header
            % Build candidate names; convert numeric cells (e.g. 1960) to
            % their string representation before makeValidName.
            cand = cell(1, numel(firstrow));
            for j = 1:numel(firstrow)
                v = firstrow{j};
                if isnumeric(v) && isscalar(v)
                    cand{j} = sprintf('%g', v);   % 1960 → '1960' → x1960
                else
                    cand{j} = char(string(v));
                end
            end
            valid = matlab.lang.makeValidName(cand);
            T.Properties.VariableNames = cellstr(valid);
            T(1, :) = [];   % drop the now-redundant first row
            if looks_like_mixed_header
                fprintf('  ✓ Header row has mixed text + year columns — names reassigned:\n');
            else
                fprintf('  ✓ Reassigned variable names from first data row:\n');
            end
            preview = strjoin(valid(1:min(6, end)), ',  ');
            if numel(valid) > 6
                fprintf('      %s, … (%d more)\n', preview, numel(valid) - 6);
            else
                fprintf('      %s\n', preview);
            end
        else
            fprintf('  First row looks like data (not headers). Keeping Var1/Var2/…\n');
            fprintf('  TODO: rename columns manually via T.Properties.VariableNames\n');
        end

    catch ME
        fprintf('  Could not re-read for header check: %s\n', ME.message);
    end
end
