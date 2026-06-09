function [T, prof, recipe] = DataExplorer(source, options)
%DATAEXPLORER  Forgiving data exploration for mixed-type tables.
%
%   T = DataExplorer()                  file picker dialog
%   T = DataExplorer(filename)          load CSV, TSV, TXT, XLSX, ZIP, or NetCDF
%   T = DataExplorer(T_in)              explore an existing table
%
%   Outputs
%   ───────
%   [T, prof, recipe] = DataExplorer(...)
%     T       loaded, profiled table
%     prof    profile struct (column types, roles, skip flags, skewness, …)
%     recipe  the generated recipe as a string array (one line per element)
%   Requesting the recipe (the 3rd output) returns the code WITHOUT running it —
%   no figures are drawn.  T = DataExplorer(...) and [T,prof] = DataExplorer(...)
%   render as usual.
%
%   NetCDF
%   ──────
%   Data variables sharing a coordinate grid load together as columns of one
%   table (coordinates + one column per variable), so cross-variable views
%   (pairplots, correlations, gridded maps) work across them.  A file mixing
%   differently-shaped variables is treated like a multi-sheet workbook: pick
%   one with NCVariable= (or the largest group with AutoSelect).
%
%   Optional name-value arguments
%   ─────────────────────────────
%   MaxRows        (10000)   random-sample large files to this many rows
%   MaxVars        (8)       columns shown in the plot matrix; prefers numeric
%   Columns        ([])      override: specific names or indices to plot
%   MissingStrings (list)    extra strings to recode as missing (see defaults)
%   AutoSelect     (false)   skip all interactive prompts; pick defaults (largest
%                            sheet/file; NetCDF: combine all conformable variables)
%   Sheet          ("")      load a specific Excel sheet by name (bypasses prompt)
%   InnerFile      ("")      load a specific file from a ZIP by name (bypasses prompt)
%   NCVariable     ("")      NetCDF: variable name to load (bypasses variable prompt)
%   RandSeed       (NaN)     seed for the (otherwise random) stratifier choice in
%                            geo plots; set for a reproducible recipe, leave unset
%                            to get a different valid stratification on each run
%
%   Examples
%   ────────
%   T = DataExplorer();                       % pick a file interactively
%   T = DataExplorer('bluebikes_2024.csv');
%   T = DataExplorer('wonder_export.txt', MaxRows=50000);
%   T = DataExplorer(T, Columns=["age","sbp","dbp","sex"]);

arguments
    source = []
    options.MaxRows         (1,1) double {de__must_be_row_budget} = 10000
    options.MaxVars         (1,1) double {mustBePositive} = 8
    options.Columns                       = []          % names (string/char/cell) or indices
    options.MissingStrings  (1,:) string  = [...
        "Suppressed", "N/A", "NA", "n/a", "--", "-", ...
        "None", "none", "null", "NULL", "missing", ...
        "Missing", "?", "Unknown", "unknown", "*"]
    options.AutoSelect      (1,1) logical = false       % skip interactive prompts, pick default
    options.Sheet           (1,1) string  = ""          % load a specific Excel sheet by name
    options.InnerFile       (1,1) string  = ""          % load a specific file from a ZIP
    options.NCVariable      (1,1) string  = ""          % NetCDF: variable name to load
    options.RandSeed        (1,1) double  = NaN         % seed stratifier choice for a reproducible recipe
end

% prof and recipe are produced by the pipeline below; initialize them here so
% every early-return path (no file selected, empty table) still defines all
% three outputs.  (Requesting the recipe skips rendering — see help.)
prof   = struct([]);
recipe = strings(0, 1);

%% ── 0.  Version check ────────────────────────────────────────────────────
% Developed and tested on R2025b (25.2). Features like DataTipTemplate,
% boxchart, and the arguments block require recent releases.
if isMATLABReleaseOlderThan('R2025b')
    warning('DataExplorer:oldMatlab', ...
        'DataExplorer targets R2025b; running %s — tooltips, boxchart, and arguments blocks may not work.', ...
        version('-release'));
end

%% ── 1.  Load ──────────────────────────────────────────────────────────────
if isempty(source) && ~istable(source)
    [fname, fpath] = uigetfile( ...
        {'*.csv;*.tsv;*.txt;*.xlsx;*.xls;*.xlsm;*.zip;*.nc;*.nc4;*.netcdf', 'Data files'}, ...
        'Select a data file');
    if isequal(fname, 0)
        fprintf('  No file selected.\n');
        T = table();
        return
    end
    source = fullfile(fpath, fname);
end

%% ── 1+2.  Load & profile ──────────────────────────────────────────────────
if ischar(source) || isstring(source)
    [T, prof] = de_load(string(source), ...                % all formats incl. NetCDF
        'Interactive', true, 'AutoSelect', options.AutoSelect, ...
        'MaxRows', options.MaxRows, 'Sheet', options.Sheet, ...
        'InnerFile', options.InnerFile, 'NCVariable', options.NCVariable, ...
        'MissingStrings', options.MissingStrings);
elseif istable(source)
    T = source;
    if height(T) == 0
        fprintf('  ℹ Empty table (0 rows) — nothing to explore.\n');
        return
    end
    fprintf('  Using existing table: %d × %d\n', height(T), width(T));
    [T, prof] = se_profile(T, options.MissingStrings);
else
    error('DataExplorer:badInput', ...
        'source must be a filename (string/char) or a table.');
end

% Attach a display name for the figure title
if ischar(source) || isstring(source)
    [~, fname, fext] = fileparts(string(source));
    base = fname + fext;
    ud   = T.Properties.UserData;
    if isstruct(ud)
        if ~isempty(ud.inner_file)
            base = sprintf('%s » %s', base, ud.inner_file);
        end
        if ~isempty(ud.sheet)
            base = sprintf('%s [%s]', base, ud.sheet);
        end
    end
    prof.source_name = base;
elseif istable(source)
    prof.source_name = 'table input';
end

%% ── 4 + 5.  Recipe ────────────────────────────────────────────────────────
% The recipe is the canonical code path for all figure production.
% It is assembled, written to /tmp/, and echoed; then only the plot sections
% are eval'd here (T and prof are already loaded above, so re-running the
% load/clean sections would be redundant and slow).  The saved recipe file
% is always complete (load + clean + plots) so it re-runs correctly standalone.
panel = prof.panel;
src_str_ = '';
if ischar(source) || isstring(source)
    src_str_ = string(source);
end
[~, recipe_text] = se_assemble_recipe(src_str_, T, prof, panel, options);
recipe = splitlines(string(recipe_text));   % return as one-line-per-element array
% Run the recipe to produce figures — UNLESS the caller asked for it (nargout>=3),
% in which case they want the code, not its side effects.
if nargout < 3
    idx_ = strfind(recipe_text, '%% === Overview ===');
    if ~isempty(idx_), eval(recipe_text(idx_(1):end)); else, eval(recipe_text); end
end

end % ── DataExplorer ──────────────────────────────────────────────────────


%% ═══════════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTIONS  (se_ prefix = private to DataExplorer.m)
%  Shared internal utilities live in de__*.m files on the path.
%% ═══════════════════════════════════════════════════════════════════════════

% All loading lives in de_load (zip/excel/text/NetCDF) and the standalone
% de__*.m helpers (de__sample, de__fix_names, de__record_sampled, de__zip_*).
% The former local loaders (se_load, load_netcdf, the nc_* table builders,
% se_echo_load_code, se_report) were retired once every source routed through
% de_load + the recipe (B2b, 2026-06-05).


% ── se_filter_choro_cols ──────────────────────────────────────────────────────
function idxs = se_filter_choro_cols(idxs, prof, families)
%SE_FILTER_CHORO_COLS  Remove non-data-variable candidates from choropleth selection.
%   Excludes: constant, time-named, lat/lon coordinate, integer id-named columns,
%   and non-representative members of correlated families (keeps only fam(1)).
if nargin < 3, families = {}; end
if isempty(idxs), return; end

LAT_LON      = ["lat","latitude","lat_","latitude_dd","decimallatitude", ...
                "lon","long","longitude","lon_","longitude_dd","decimallongitude"];
names_lower  = lower(string(prof.name));

is_const     = prof.nunique(idxs) <= 1;
is_coord     = ismember(names_lower(idxs), LAT_LON);
% Identifier (id-like last token) and time-named columns, via robust tokenizer
% (MATLAB regexp \b does not work, and CamelCase needs de_name_tokens).
is_id        = false(size(idxs));
is_time_name = false(size(idxs));
TIME_TOKENS  = ["year","month","day","date","time"];
for ji = 1:numel(idxs)
    toks = de_name_tokens(prof.name{idxs(ji)});
    if ismember(toks(end), ["code","id","num","number"])
        is_id(ji) = true;
    end
    if any(ismember(toks, TIME_TOKENS))
        is_time_name(ji) = true;
    end
end

% Non-representative family members (keep only fam(1) per family)
is_fam_nonrep = false(size(idxs));
if ~isempty(families)
    non_rep = cell2mat(cellfun(@(f) f(2:end), families, 'UniformOutput', false));
    is_fam_nonrep = ismember(idxs, non_rep);
end

idxs = idxs(~is_const & ~is_time_name & ~is_coord & ~is_id & ~is_fam_nonrep);
end


% ── se_confound_note_arg ──────────────────────────────────────────────────────
function s = se_confound_note_arg(T, prof, target_name, geo_name, region_word)
%SE_CONFOUND_NOTE_ARG  Return ", 'ConfoundNote','…'" when a per-region mean of
%   target_name is strongly confounded by a categorical too high-cardinality to
%   facet cleanly (so it stays a plain mean map), else ''.  Reached only after the
%   faceable pick (cardinality ≤ 15) found nothing, so this catches the >15-level
%   strong stratifiers and warns rather than silently misleading.
s = '';
[~, ~, cn, cw] = de_pick_stratifier(T, prof, target_name, geo_name, ...
    'MaxCard', Inf, 'Floor', 0.5);
if isempty(cw), return; end
[emax, im] = max(cw);
note = sprintf('per-%s mean of %s mixes %s (eta2=%d%%); interpret with care', ...
    region_word, char(target_name), char(cn(im)), round(100*emax));
s = sprintf(', ''ConfoundNote'',''%s''', note);
end


% ── se_scale_arg ──────────────────────────────────────────────────────────────
function s = se_scale_arg(prof, idx)
%SE_SCALE_ARG  Return ", 'Scale','log'" for strongly-skewed numeric columns,
%   else ''.  Lets the recipe decide log scale from the profiled skewness.
%   Scale governs the quantitative axis of whichever renderer is active —
%   choropleth color or value_ladder bars.
s = '';
if isfield(prof, 'skewness') && idx >= 1 && idx <= numel(prof.skewness) ...
        && ~isnan(prof.skewness(idx)) && abs(prof.skewness(idx)) > 2
    s = ', ''Scale'',''log''';
end
end


% ── se_record_sampled ─────────────────────────────────────────────────────────
% de__record_sampled is defined in de__record_sampled.m


% ── se_profile ───────────────────────────────────────────────────────────────
function [T, prof] = se_profile(T, missingStrings)
%SE_PROFILE  Thin wrapper — delegates to the standalone de_profile library function.
if nargin < 2
    [T, prof] = de_profile(T);
else
    [T, prof] = de_profile(T, missingStrings);
end
end


% se_report / truncate removed — the report path is dead; the recipe is the
% single user-facing output (B2b).
function code = cg_load_code(filepath, T)
%CG_LOAD_CODE  Return MATLAB code string that loads this dataset.
if isempty(filepath)
    code = sprintf('%s\n%s\n%s\n%s\n%s', ...
        '% T was provided directly as a MATLAB table.', ...
        '% Replace this block with your own load code, for example:', ...
        '%   opts = detectImportOptions(''your_file.csv'');', ...
        '%   opts.MissingRule = ''fill'';', ...
        '%   T = readtable(''your_file.csv'', opts);');
    return
end

% Resolve to absolute path so the recipe works regardless of working directory.
d = dir(filepath);
if ~isempty(d)
    filepath = fullfile(d(1).folder, d(1).name);
end

[~, ~, ext] = fileparts(filepath);
ext = lower(string(ext));
ud  = T.Properties.UserData;
L   = {};   % lines

if ext == ".zip"
    inner     = '';
    inner_zip = '';   % original ZIP entry name (may have trailing whitespace)
    sampled_n = 0;
    if isstruct(ud)
        if isfield(ud, 'inner_file')     && ~isempty(ud.inner_file),     inner     = ud.inner_file; end
        if isfield(ud, 'inner_file_zip') && ~isempty(ud.inner_file_zip), inner_zip = ud.inner_file_zip; end
        if isfield(ud, 'sampled')        && ~isempty(ud.sampled),        sampled_n = ud.sampled; end
    end
    if isempty(inner_zip), inner_zip = inner; end
    [~, ~, inner_ext] = fileparts(inner);
    inner_ext = lower(inner_ext);
    % Use system unzip -j for selective extraction: avoids unpacking the
    % entire archive (critical for large ZIPs like DWCA with 20 000+ files).
    % inner_zip preserves any trailing whitespace in the original entry name.
    L{end+1} = 'tmpdir = tempname; mkdir(tmpdir);';
    L{end+1} = sprintf('system([''unzip -j -d "'' tmpdir ''" "%s" "%s"'']);', ...
        filepath, inner_zip);
    % If the ZIP entry name has trailing whitespace, rename the extracted file
    % to the clean (trimmed) name before referencing it.
    if ~strcmp(inner, inner_zip)
        L{end+1} = sprintf('raw_p_ = fullfile(tmpdir, ''%s'');', inner_zip);
        L{end+1} = sprintf('if exist(raw_p_, ''file''), movefile(raw_p_, fullfile(tmpdir, ''%s'')); end', inner);
    end
    L{end+1} = sprintf('inner_path = fullfile(tmpdir, ''%s'');', inner);
    if ismember(inner_ext, {'.xlsx','.xls','.xlsm'})
        sheet = '';
        if isstruct(ud) && ~isempty(ud.sheet), sheet = ud.sheet; end
        L{end+1} = sprintf('opts = detectImportOptions(inner_path, ''Sheet'', ''%s'');', sheet);
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = sprintf('T = readtable(inner_path, opts, ''Sheet'', ''%s'');', sheet);
    elseif sampled_n > 0
        L{end+1} = sprintf('T = de_reservoir_sample(inner_path, %d, Seed=42);', sampled_n);
    else
        L{end+1} = 'opts = detectImportOptions(inner_path, ''FileType'', ''text'');';
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = 'T = readtable(inner_path, opts);';
    end
elseif ismember(ext, [".xlsx", ".xls", ".xlsm"])
    sheet = '';
    explicit_hdr = false;
    if isstruct(ud)
        if ~isempty(ud.sheet), sheet = ud.sheet; end
        if isfield(ud, 'explicit_header') && ud.explicit_header
            explicit_hdr = true;
        end
    end
    if explicit_hdr
        L{end+1} = sprintf('opts = detectImportOptions(''%s'', ''Sheet'', ''%s'', ''VariableNamesRange'', ''A1'', ''DataRange'', ''A2'');', filepath, sheet);
    else
        L{end+1} = sprintf('opts = detectImportOptions(''%s'', ''Sheet'', ''%s'');', filepath, sheet);
    end
    L{end+1} = 'opts.MissingRule = ''fill'';';
    L{end+1} = sprintf('T = readtable(''%s'', opts, ''Sheet'', ''%s'');', filepath, sheet);
elseif ismember(ext, [".nc", ".nc4", ".netcdf"])
    % Conformable NetCDF variables were combined into one table by de_load;
    % reproduce that: stride-sample the first, then add each other variable's
    % column (identical striding → aligned rows).
    nc_vars = {};
    if isstruct(ud) && isfield(ud, 'nc_vars') && ~isempty(ud.nc_vars)
        nc_vars = ud.nc_vars;
    end
    if isempty(nc_vars)
        L{end+1} = sprintf('T = de_stride_sample(''%s'');', filepath);
    else
        L{end+1} = sprintf('T = de_stride_sample(''%s'', Variable=''%s'', Verbose=false);', ...
            filepath, nc_vars{1});
        extra = cell(1, numel(nc_vars) - 1);
        for vi = 2:numel(nc_vars)
            vk = matlab.lang.makeValidName(nc_vars{vi});
            extra{vi-1} = sprintf('T.%s = de_stride_sample(''%s'', Variable=''%s'', Verbose=false).%s;', ...
                vk, filepath, nc_vars{vi}, vk);
        end
        L = [L, extra];
    end
else
    sampled_n = 0;
    if isstruct(ud) && isfield(ud, 'sampled')
        sampled_n = ud.sampled;
    end
    if sampled_n > 0
        L{end+1} = sprintf('T = de_reservoir_sample(''%s'', %d, Seed=42);', filepath, sampled_n);
    else
        L{end+1} = sprintf('opts = detectImportOptions(''%s'', ''FileType'', ''text'');', filepath);
        L{end+1} = 'opts.MissingRule = ''fill'';';
        L{end+1} = sprintf('T = readtable(''%s'', opts);', filepath);
    end
end

code = strjoin(L, newline);
end


% ── cg_clean_code ──────────────────────────────────────────────────────
function code = cg_clean_code()
%CG_CLEAN_CODE  Emit recipe code for the clean/profile step.
%   Uses de_profile, which handles type conversion and missing-value recoding.
code = '[T, prof] = de_profile(T);';
end


% ── cg_best_plots_code ─────────────────────────────────────────────────
function code = cg_best_plots_code(T, prof, sel, source_name)
%CG_BEST_PLOTS_CODE  Emit recipe code for standalone full-page plots.
%
%   Top histogram, top scatter, and a full multi-series time-series block
%   (both overlaid + Total and stacked, when the data is compositional).

COLOR = '[0.35 0.55 0.75]';
L = {};

% Short figure-name prefix: use only the [sheet/var] tag if present, else empty.
% Never put the bare filename in a window title.
m_src = regexp(char(source_name), '\[([^\]]+)\]\s*$', 'tokens', 'once');
if ~isempty(m_src)
    fig_prefix = [strrep(strtrim(m_src{1}), '''', '''''') ' — '];
else
    fig_prefix = '';
end

% ── Numeric columns in sel ───────────────────────────────────────────────────
sel_num = sel(prof.type(sel) == "numeric");

% ── Best histogram ───────────────────────────────────────────────────────────
if ~isempty(sel_num)
    cn1 = prof.name{sel_num(1)};
    L{end+1} = sprintf('%% Best histogram: %s', cn1);
    L{end+1} = sprintf('de_histogram(T.%s, ''%s'');', cn1, strrep(cn1,'''',''''''));
    L{end+1} = '';
end

% ── Best scatter ─────────────────────────────────────────────────────────────
if numel(sel_num) >= 2
    cn1 = prof.name{sel_num(1)};
    cn2 = prof.name{sel_num(2)};
    L{end+1} = sprintf('%% Best scatter: %s vs %s', cn1, cn2);
    L{end+1} = sprintf('x = T.%s; y = T.%s;', cn1, cn2);
    L{end+1} = 'if isnumeric(x) && isnumeric(y)';
    L{end+1} = sprintf('    figure(''Name'', ''%s%s vs %s'', ''NumberTitle'', ''off'', ''Color'', [1 1 1]);', ...
        fig_prefix, strrep(cn1,'''',''''''), strrep(cn2,'''',''''''));
    L{end+1} = '    valid = ~isnan(x) & ~isnan(y); n_pts = sum(valid);';
    L{end+1} = '    alpha = max(0.05, min(0.8, 500 / max(n_pts, 1)));';
    L{end+1} = sprintf('    scatter(x(valid), y(valid), 20, %s, ''filled'', ''MarkerFaceAlpha'', alpha);', COLOR);
    L{end+1} = sprintf('    xlabel(''%s''); ylabel(''%s'');', ...
        strrep(cn1,'''',''''''), strrep(cn2,'''',''''''));
    L{end+1} = sprintf('    title(sprintf(''%s vs %s  (n=%%d)'', n_pts));', ...
        strrep(cn1,'''',''''''), strrep(cn2,'''',''''''));
    L{end+1} = '    box off;';
    L{end+1} = 'end'; L{end+1} = '';
end

% ── Time series (datetime or year-axis) ──────────────────────────────────────
[time_idx, is_year_axis] = de_find_time_axis(prof);
ts_num = sel_num;
if ~isempty(time_idx) && is_year_axis
    ts_num = ts_num(ts_num ~= time_idx);
end

if ~isempty(time_idx) && ~isempty(ts_num)
    tcn      = prof.name{time_idx};
    tcn_sq   = strrep(tcn, '''', '''''');
    ncn_list = prof.name(ts_num);
    n_ts     = numel(ts_num);

    % Aggregate to per-time-point means (same logic as live plotters) then
    % apply the shared compositional test.
    if is_year_axis
        xdata_g = double(T.(prof.name{time_idx}));
        valid_g  = ~isnan(xdata_g);
    else
        xdata_g = T.(prof.name{time_idx});
        valid_g  = ~isnat(xdata_g);
    end
    [~, ~, xidx_g] = unique(xdata_g(valid_g));
    n_ug = max(xidx_g);
    if isempty(n_ug) || n_ug < 2
        is_compositional = false;
    else
    Y_g  = NaN(n_ug, n_ts);
    for kk = 1:n_ts
        col_g = double(T.(ncn_list{kk})); col_g = col_g(valid_g);
        for tt = 1:n_ug
            v = col_g(xidx_g == tt); v = v(~isnan(v));
            if ~isempty(v), Y_g(tt, kk) = mean(v); end
        end
    end
    is_compositional = se_is_compositional(Y_g, T, prof);
    end

    if ~isempty(n_ug) && n_ug >= 2
    lbl_items = strjoin(cellfun(@(s) sprintf('''%s''', strrep(s,'''','''''')), ncn_list, 'UniformOutput', false), ', ');
    if is_compositional, comp_arg = 'on'; else, comp_arg = 'off'; end

    L{end+1} = sprintf('%% Time series: %d series over %s', n_ts, tcn);
    L{end+1} = sprintf('de_timeseries(T, ''%s'', {%s}, ''Compositional'', ''%s'', ''TitlePrefix'', ''%s'');', ...
        tcn_sq, lbl_items, comp_arg, fig_prefix);
    L{end+1} = '';
    end  % n_ug >= 2
end

if isempty(L)
    code = '% No plottable numeric columns found.';
else
    code = strjoin(L, newline);
end
end


% ── cg_cat_association_code ─────────────────────────────────────────────────
function lines = cg_cat_association_code(T, prof)
%CG_CAT_ASSOCIATION_CODE  Recipe lines for categorical association figures.
%   Returns one line per figure: first the V-matrix, then one line per pair.
lines = {};
cat_mask = (prof.type == "categorical" | prof.type == "logical") & ~prof.skip;
cat_idx  = find(cat_mask);
if numel(cat_idx) < 2, return; end
names = prof.name(cat_idx);
nc    = numel(cat_idx);
p         = de__cat_assoc_params();
V_THRESH  = p.VThresh;
MAX_PAIRS = p.MaxPairs;
pairs = zeros(nc*(nc-1)/2, 3);
np = 0;
for i = 1:nc
    for j = i+1:nc
        v = de_cramer_v(T.(names{i}), T.(names{j}));
        if v >= V_THRESH
            np = np + 1;
            pairs(np,:) = [i, j, v];
        end
    end
end
pairs = pairs(1:np,:);
out = cell(1 + MAX_PAIRS, 1);
nl  = 1;
out{nl} = 'de_plot_cat_association(T, prof, Figure="vmatrix");';
if ~isempty(pairs)
    [~, ord] = sort(pairs(:,3), 'descend');
    pairs = pairs(ord(1:min(MAX_PAIRS,end)), :);
    for k = 1:size(pairs,1)
        ni = pairs(k,1); nj = pairs(k,2);
        a = T.(names{ni}); b = T.(names{nj});
        if ~iscategorical(a), a = categorical(a); end
        if ~iscategorical(b), b = categorical(b); end
        nu_i = numel(categories(removecats(a)));
        nu_j = numel(categories(removecats(b)));
        if nu_i <= nu_j
            col_grp = names{ni}; col_val = names{nj}; ng_pair = nu_i;
        else
            col_grp = names{nj}; col_val = names{ni}; ng_pair = nu_j;
        end
        switch de_cat_routing(ng_pair)
            case 'pareto',  fn = 'de_pareto_multiples';
            case 'stacked', fn = 'de_stacked_bars';
            otherwise,      fn = 'de_cond_heatmap';
        end
        nl = nl + 1;
        out{nl} = sprintf('%s(T, "%s", "%s");  %% V=%.2f', fn, col_grp, col_val, pairs(k,3));
    end
end
lines = out(1:nl);
end


% ── cg_state_choropleth_code ────────────────────────────────────────────────
function code = cg_state_choropleth_code(T, prof, families)
%CG_STATE_CHOROPLETH_CODE  Return recipe code for state choropleth figures.
%   A single-numeric per-state mean mixes sub-populations (e.g. a state's monitor
%   mix), so where a categorical stratifies the numeric we emit a state×level
%   heatmap (de-confounded) instead of a bare mean map.  The stratifier is a
%   weighted-random pick (de_pick_stratifier); re-running surfaces other views.
if nargin < 3, families = {}; end
code = '';
cat_all = find(prof.type == "categorical" & ~prof.skip);
geo_idx = [];
for ci = cat_all(:)'
    if isfield(prof, 'geo_grid') && numel(prof.geo_grid) >= ci && ...
            strcmp(prof.geo_grid{ci}, 'us-states')
        geo_idx = ci; break;
    end
end
if isempty(geo_idx), return; end

catname = prof.name{geo_idx};
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
[time_idx, ~] = de_find_time_axis(prof);
num_idxs = find(prof.type == "numeric" & ~prof.skip);
num_idxs = se_filter_choro_cols(num_idxs, prof, families);
L = {};

if ~isempty(wide_yr_idxs)
    [~, yr_ord] = sort(wide_yr_vals);
    yr_names_s = prof.name(wide_yr_idxs(yr_ord));
    yr_cell = strjoin(cellfun(@(s) sprintf('''%s''', s), yr_names_s, 'UniformOutput', false), ', ');

    L{end+1} = sprintf('%% Choropleth: %s (wide years → long)', catname);
    L{end+1} = sprintf('yr_ch = {%s};', yr_cell);
    L{end+1} = 'T_long_ch = de_pivot_wide_years(T, yr_ch);';
    L{end+1} = sprintf('de_statebins(T_long_ch, ''StateCol'',''%s'', ''ColorVariable'',''Value'', ''TimeCol'',''Year'', ''Title'',''Choropleth: %s'');', catname, catname);
    L{end+1} = '';
else
    num_plot = num_idxs(~ismember(num_idxs, [geo_idx, time_idx]));
    sub = cell(1, 3*numel(num_plot));   % comment + call + blank per numeric
    si  = 0;
    for j = 1:numel(num_plot)
        ncn = prof.name{num_plot(j)};
        sca = se_scale_arg(prof, num_plot(j));
        [strat, eta2] = de_pick_stratifier(T, prof, string(ncn), string(catname));
        if strat ~= ""
            si = si+1; sub{si} = sprintf(['%% %s mean per state mixes %s (eta2=%d%%); ' ...
                'shown stratified — re-run DataExplorer for a different view'], ...
                ncn, char(strat), round(100*eta2));
            if isempty(time_idx)
                si = si+1; sub{si} = sprintf(['de_statebins(T, ''StateCol'',''%s'', ''ColorVariable'',''%s'', ' ...
                    '''GroupVariable'',''%s'', ''CellRenderer'',''heatmap_cat'', ''Title'',''%s by %s'');'], ...
                    catname, ncn, char(strat), ncn, char(strat));
            else
                tcn = prof.name{time_idx};
                si = si+1; sub{si} = sprintf(['de_statebins(T, ''StateCol'',''%s'', ''ColorVariable'',''%s'', ' ...
                    '''GroupVariable'',''%s'', ''TimeCol'',''%s'', ''CellRenderer'',''heatmap_cat'', ''Title'',''%s by %s'');'], ...
                    catname, ncn, char(strat), tcn, ncn, char(strat));
            end
        else
            cna = se_confound_note_arg(T, prof, string(ncn), string(catname), 'state');
            if isempty(time_idx)
                si = si+1; sub{si} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''ColorVariable'',''%s'', ''Title'',''Choropleth: %s''%s%s);', catname, ncn, ncn, sca, cna);
            else
                tcn = prof.name{time_idx};
                si = si+1; sub{si} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''ColorVariable'',''%s'', ''TimeCol'',''%s'', ''Title'',''Choropleth: %s''%s%s);', catname, ncn, tcn, ncn, sca, cna);
            end
        end
        si = si+1; sub{si} = '';
    end
    L = [L, sub(1:si)];
end

if isempty(L), return; end
code = strjoin(L, newline);
end


% ── cg_country_choropleth_code ───────────────────────────────────────────────
function code = cg_country_choropleth_code(T, prof, families)
%CG_COUNTRY_CHOROPLETH_CODE  Return recipe code for world choropleth figures.
%   Single-numeric per-country means are stratified into a country×level heatmap
%   where a categorical explains the numeric (see cg_state_choropleth_code).
if nargin < 3, families = {}; end
code = '';
cat_all = find(prof.type == "categorical" & ~prof.skip);
geo_idx = [];
for ci = cat_all(:)'
    if isfield(prof, 'geo_grid') && numel(prof.geo_grid) >= ci && ...
            strcmp(prof.geo_grid{ci}, 'world')
        geo_idx = ci; break;
    end
end
if isempty(geo_idx), return; end

catname = prof.name{geo_idx};
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
[time_idx, ~] = de_find_time_axis(prof);
num_idxs = find(prof.type == "numeric" & ~prof.skip);
num_idxs = se_filter_choro_cols(num_idxs, prof, families);
L = {};

if ~isempty(wide_yr_idxs)
    [~, yr_ord] = sort(wide_yr_vals);
    yr_names_s = prof.name(wide_yr_idxs(yr_ord));
    yr_cell = strjoin(cellfun(@(s) sprintf('''%s''', s), yr_names_s, 'UniformOutput', false), ', ');

    L{end+1} = sprintf('%% World choropleth: %s (wide years → long)', catname);
    L{end+1} = sprintf('yr_co = {%s};', yr_cell);
    L{end+1} = 'T_long_co = de_pivot_wide_years(T, yr_co);';
    L{end+1} = sprintf('de_countrybins(T_long_co, ''CountryCol'',''%s'', ''ColorVariable'',''Value'', ''TimeCol'',''Year'', ''Title'',''World choropleth: %s'');', catname, catname);
    L{end+1} = '';
else
    num_plot = num_idxs(~ismember(num_idxs, [geo_idx, time_idx]));
    sub = cell(1, 3*numel(num_plot));   % comment + call + blank per numeric
    si  = 0;
    for j = 1:numel(num_plot)
        ncn = prof.name{num_plot(j)};
        sca = se_scale_arg(prof, num_plot(j));
        [strat, eta2] = de_pick_stratifier(T, prof, string(ncn), string(catname));
        if strat ~= ""
            si = si+1; sub{si} = sprintf(['%% %s mean per country mixes %s (eta2=%d%%); ' ...
                'shown stratified — re-run DataExplorer for a different view'], ...
                ncn, char(strat), round(100*eta2));
            if isempty(time_idx)
                si = si+1; sub{si} = sprintf(['de_countrybins(T, ''CountryCol'',''%s'', ''ColorVariable'',''%s'', ' ...
                    '''GroupVariable'',''%s'', ''CellRenderer'',''heatmap_cat'', ''Title'',''%s by %s'');'], ...
                    catname, ncn, char(strat), ncn, char(strat));
            else
                tcn = prof.name{time_idx};
                si = si+1; sub{si} = sprintf(['de_countrybins(T, ''CountryCol'',''%s'', ''ColorVariable'',''%s'', ' ...
                    '''GroupVariable'',''%s'', ''TimeCol'',''%s'', ''CellRenderer'',''heatmap_cat'', ''Title'',''%s by %s'');'], ...
                    catname, ncn, char(strat), tcn, ncn, char(strat));
            end
        else
            cna = se_confound_note_arg(T, prof, string(ncn), string(catname), 'country');
            if isempty(time_idx)
                si = si+1; sub{si} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''ColorVariable'',''%s'', ''Title'',''World choropleth: %s''%s%s);', catname, ncn, ncn, sca, cna);
            else
                tcn = prof.name{time_idx};
                si = si+1; sub{si} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''ColorVariable'',''%s'', ''TimeCol'',''%s'', ''Title'',''World choropleth: %s''%s%s);', catname, ncn, tcn, ncn, sca, cna);
            end
        end
        si = si+1; sub{si} = '';
    end
    L = [L, sub(1:si)];
end

if isempty(L), return; end
code = strjoin(L, newline);
end


% ── cg_geo_multicategorical_code ────────────────────────────────────────────
function code = cg_geo_multicategorical_code(T, prof)
%CG_GEO_MULTICATEGORICAL_CODE  Recipe code for geo x categorical heatmap figures.
code = '';
[wide_yr_idxs, wide_yr_vals] = de_detect_wide_years(prof);
if isempty(wide_yr_idxs), return; end

cat_all = find(prof.type == "categorical" & ~prof.skip);
if numel(cat_all) < 2, return; end

if isfield(prof, 'geo_grid')
    geo_cats = cat_all(arrayfun(@(ci) numel(prof.geo_grid) >= ci && ~isempty(prof.geo_grid{ci}), cat_all));
else
    geo_cats = [];
end
other_cats = cat_all(~ismember(cat_all, geo_cats));
if isempty(geo_cats) || isempty(other_cats), return; end

TOTAL_WORDS = {'total','totals','grand total','all totals'};
[~, yr_ord] = sort(wide_yr_vals);
yr_names_s = prof.name(wide_yr_idxs(yr_ord));
yr_cell = strjoin(cellfun(@(s) sprintf('''%s''',s), yr_names_s, 'UniformOutput',false), ', ');

% 4 header lines + up to 4 lines per geo×cat pair
L = cell(1, 4 + 4*numel(geo_cats)*numel(other_cats));
li = 0;
li = li+1; L{li} = '%% Geo x categorical heatmap';
li = li+1; L{li} = sprintf('yr_gm = {%s};', yr_cell);
li = li+1; L{li} = 'T_long_gm = de_pivot_wide_years(T, yr_gm);';
li = li+1; L{li} = '';

n_pairs = 0;
for gi = 1:numel(geo_cats)
    geo_idx      = geo_cats(gi);
    geo_name     = prof.name{geo_idx};
    geo_grid_name = prof.geo_grid{geo_idx};
    is_states_geo = strcmp(geo_grid_name, 'us-states');

    for oi = 1:numel(other_cats)
        cat_idx  = other_cats(oi);
        cat_name = prof.name{cat_idx};
        n_geo    = prof.nunique(geo_idx);
        n_other  = prof.nunique(cat_idx);
        ratio    = height(T) / (n_geo * n_other);
        if ratio < 0.5 || ratio > 1.5, continue; end

        % Top-K non-total levels
        cat_col = T.(cat_name);
        cat_levs = cellstr(categories(cat_col));
        cnt_levs = countcats(cat_col);
        is_tot   = cellfun(@(lv) any(strcmpi(lv, TOTAL_WORDS)), cat_levs);
        cat_levs = cat_levs(~is_tot);
        cnt_levs = cnt_levs(~is_tot);
        if isempty(cat_levs), continue; end
        [~, ord] = sort(cnt_levs,'descend');
        K = min(5, numel(cat_levs));
        top_levs = cat_levs(ord(1:K));

        levs_cell = strjoin(cellfun(@(s) sprintf('''%s''',strrep(s,'''','''''')), top_levs, 'UniformOutput',false), ', ');
        title_str = strrep(sprintf('%s x %s: Value by category over time', geo_name, cat_name), '''', '''''');

        li = li+1; L{li} = sprintf('top_gm = {%s};', levs_cell);
        li = li+1; L{li} = sprintf('T_filt_gm = T_long_gm(ismember(string(T_long_gm.%s), string(top_gm)), :);', cat_name);
        if is_states_geo
            li = li+1; L{li} = sprintf('de_statebins(T_filt_gm, ''StateCol'',''%s'', ''ColorVariable'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''heatmap_cat'', ''GroupVariable'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, cat_name, K, title_str);
        elseif strcmp(geo_grid_name, 'world')
            li = li+1; L{li} = sprintf('de_countrybins(T_filt_gm, ''CountryCol'',''%s'', ''ColorVariable'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''heatmap_cat'', ''GroupVariable'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, cat_name, K, title_str);
        else
            li = li+1; L{li} = sprintf('de_geobins(T_filt_gm, ''GeoCol'',''%s'', ''Grid'',''%s'', ''ColorVariable'',''Value'', ''TimeCol'',''Year'', ''CellRenderer'',''heatmap_cat'', ''GroupVariable'',''%s'', ''TopK'',%d, ''Title'',''%s'');', ...
                geo_name, geo_grid_name, cat_name, K, title_str);
        end
        li = li+1; L{li} = '';
        n_pairs = n_pairs + 1;
    end
end
L = L(1:li);

if n_pairs == 0
    code = ''; return;
end
code = strjoin(L, newline);
end


% ── cg_geoscatter_code ───────────────────────────────────────────────────────
function code = cg_geoscatter_code(T, prof)
%CG_GEOSCATTER_CODE  Recipe code for a lat/lon map.
%   NetCDF grids (a combined stride-sample with a time axis) are aggregated by
%   grid cell — color = temporal mean, size = temporal std — one map per variable.
%   Tabular lat/lon data gets a point map colored/sized by its numeric columns.
code = '';

LAT_NAMES = ["lat","latitude","lat_","latitude_dd","decimallatitude"];
LON_NAMES = ["lon","long","longitude","lon_","longitude_dd","decimallongitude"];
nl = lower(string(prof.name));
lat_i = find(ismember(nl, LAT_NAMES) & ~prof.skip, 1);
lon_i = find(ismember(nl, LON_NAMES) & ~prof.skip, 1);
if isempty(lat_i) || isempty(lon_i), return; end

lat = double(T.(prof.name{lat_i}));
lon = double(T.(prof.name{lon_i}));
if sum(~isnan(lat) & ~isnan(lon)) < 2, return; end

latn = prof.name{lat_i};
lonn = prof.name{lon_i};

% NetCDF grid: aggregate over time per cell → a mean/std map per variable.
ud = T.Properties.UserData;
if isstruct(ud) && isfield(ud, 'nc_vars') && ~isempty(ud.nc_vars) && any(nl == "time")
    nc_vars   = ud.nc_vars;
    safe      = cellfun(@matlab.lang.makeValidName, nc_vars, 'UniformOutput', false);
    vars_cell = ['{''', strjoin(safe, ''','''), '''}'];
    L    = cell(1, numel(safe) + 1);
    L{1} = sprintf('T_agg = groupsummary(T, {''%s'',''%s''}, {''mean'',''std''}, %s);', ...
        lonn, latn, vars_cell);
    for k = 1:numel(safe)
        L{k+1} = sprintf(['de_geoscatter(T_agg.%s, T_agg.%s, T_agg.mean_%s, T_agg.std_%s, ' ...
            'ColorLabel=''mean(%s)'', SizeLabel=''std(%s)'', MinSize=5, MaxSize=150, Title=''%s'');'], ...
            lonn, latn, safe{k}, safe{k}, nc_vars{k}, nc_vars{k}, nc_vars{k});
    end
    code = strjoin(L, newline);
    return
end

% Tabular point map: color by the first numeric data column, size by the second.
num = find(prof.type == "numeric" & ~prof.skip);
num = num(~ismember(num, [lat_i, lon_i]));
if isempty(num), return; end
ccol = prof.name{num(1)};
if numel(num) >= 2
    scol = prof.name{num(2)};
    code = sprintf(['de_geoscatter(T.%s, T.%s, T.%s, T.%s, ' ...
        'ColorLabel=''%s'', SizeLabel=''%s'', Title=''Map'');'], ...
        lonn, latn, ccol, scol, ccol, scol);
else
    code = sprintf(['de_geoscatter(T.%s, T.%s, T.%s, ones(height(T),1), ' ...
        'ColorLabel=''%s'', SizeLabel='''', Title=''Map'');'], ...
        lonn, latn, ccol, ccol);
end
end


% ── cg_corr_family_code ──────────────────────────────────────────────────────
function code = cg_corr_family_code(~, prof, families, max_members)
%CG_CORR_FAMILY_CODE  Recipe code for each correlated family.
%   The medoid/family/scale decisions are resolved here (generation time); the
%   emitted recipe is flat and editable: a member pairplot and, when a geo key
%   exists, a per-region value-ladder, both driven by one editable name list.
%   The member list is capped at max_members (medoid + top-(K-1)) so a large
%   family — e.g. ~64 correlated wide-year columns — cannot emit a 64x64
%   pairplot or 64-bar ladder.  The (+N correlated) comment keeps the full size.
code = '';
if isempty(families), return; end
if nargin < 4 || isempty(max_members), max_members = 8; end

% Geo key (first non-skipped categorical with a recognised grid)
geo_idx = [];
if isfield(prof, 'geo_grid')
    for gk = find(prof.type == "categorical" & ~prof.skip)
        if numel(prof.geo_grid) >= gk && ~isempty(prof.geo_grid{gk})
            geo_idx = gk; break
        end
    end
end

L  = cell(1, 5 * numel(families));   % up to 5 lines per family
li = 0;
for fi = 1:numel(families)
    fam_full = families{fi};                     % medoid-ordered column indices
    nfull    = numel(fam_full);
    fam      = fam_full(1:min(max_members, nfull));   % medoid + top-(K-1)
    rep   = prof.name{fam(1)};
    names = prof.name(fam);
    cols_cell = strjoin(cellfun(@(s) sprintf('''%s''', strrep(s,'''','''''')), ...
        names, 'UniformOutput', false), ', ');

    li = li+1; L{li} = sprintf('%% Correlated family: %s (+%d correlated)', rep, nfull-1);
    li = li+1; L{li} = sprintf('fam_cols = {%s};', cols_cell);
    li = li+1; L{li} = 'de_pairplot(T, prof, fam_cols);';
    if ~isempty(geo_idx)
        gname   = prof.name{geo_idx};
        grid_nm = prof.geo_grid{geo_idx};
        sk = max(prof.skewness(fam), [], 'omitnan');
        if isempty(sk) || isnan(sk), sk = 0; end
        if sk > 2, scale = 'log'; else, scale = 'linear'; end
        switch grid_nm
            case 'us-states'
                li = li+1; L{li} = sprintf('de_statebins(T, ''StateCol'',''%s'', ''CellRenderer'',''value_ladder'', ''DataVariables'',fam_cols, ''Scale'',''%s'');', gname, scale);
            case 'world'
                li = li+1; L{li} = sprintf('de_countrybins(T, ''CountryCol'',''%s'', ''CellRenderer'',''value_ladder'', ''DataVariables'',fam_cols, ''Scale'',''%s'');', gname, scale);
            otherwise
                li = li+1; L{li} = sprintf('de_geobins(T, ''GeoCol'',''%s'', ''Grid'',''%s'', ''CellRenderer'',''value_ladder'', ''DataVariables'',fam_cols, ''Scale'',''%s'');', gname, grid_nm, scale);
        end
    end
    li = li+1; L{li} = '';
end
code = strjoin(L(1:li), newline);
end


% ── cg_panel_code ────────────────────────────────────────────────────────────
function code = cg_panel_code(~, ~, panel)
%CG_PANEL_CODE  Recipe code for panel (wide-year) stacked-area and grouped
%   time-series figures.  Uses standalone de_* library functions.
code = '';
if ~isstruct(panel) || ~panel.is_panel, return; end
L = {};
L{end+1} = '% Panel: stacked-area and grouped time series';
L{end+1} = 'if prof.panel.is_panel';
L{end+1} = '    de_plot_panel_totals(T, prof, prof.panel);';
L{end+1} = '    sel_ = de_select_columns(T, prof, 8);';
L{end+1} = '    de_plot_categorical_drilldown(T, prof, sel_);';
L{end+1} = 'end';
code = strjoin(L, newline);
end


% ── se_assemble_recipe ───────────────────────────────────────────────────────
function [recipe_path, recipe_text] = se_assemble_recipe(filepath, T, prof, panel, options)
%SE_ASSEMBLE_RECIPE  Build a self-contained recipe, write to /tmp/, print, return.
%
%   Returns:
%     recipe_path — path to the saved .m file (for save_recipe())
%     recipe_text — the script as a string; caller should eval() this
%
%   For table input (empty filepath) the Load section is a placeholder comment.

assert(isstruct(panel), 'panel must be a struct');

% Geo stratifier choice is weighted-random (see de_pick_stratifier).  Seed it for
% a reproducible recipe when RandSeed is set; otherwise leave the RNG alone so
% each run surfaces a different valid stratification.
if isfield(options, 'RandSeed') && ~isnan(options.RandSeed)
    rng(options.RandSeed);
end

if isempty(filepath)
    bname_safe = 'table_input';
else
    [~, bname, ~] = fileparts(filepath);
    bname_safe = regexprep(bname, '[^A-Za-z0-9_]', '_');
end
recipe_path = fullfile(tempdir, sprintf('dataexplorer_%s.m', bname_safe));

% Detect correlated families so they collapse to one representative everywhere.
families = de_corr_families(T, prof);

% Select the same columns the pairplot used
if ~isempty(options.Columns)
    if isnumeric(options.Columns)
        sel = options.Columns(:)';
    else
        cols = string(options.Columns);
        sel  = find(ismember(string(prof.name), cols));
    end
    sel = sel(~prof.skip(sel));
else
    sel = de_select_columns(T, prof, options.MaxVars, families);
end

load_code   = cg_load_code(filepath, T);
clean_code  = cg_clean_code();
plots_code  = cg_best_plots_code(T, prof, sel, prof.source_name);
choro_code         = cg_state_choropleth_code(T, prof, families);
country_code       = cg_country_choropleth_code(T, prof, families);
geo_multi_code     = cg_geo_multicategorical_code(T, prof);
geoscatter_code    = cg_geoscatter_code(T, prof);
family_code        = cg_corr_family_code(T, prof, families, options.MaxVars);
panel_code         = cg_panel_code(T, prof, panel);

header = sprintf([...
    '%% DataExplorer recipe — %s\n' ...
    '%% Generated %s\n' ...
    '%% Requires DataExplorer.m on the MATLAB path (for de_profile, de_overview, de_histogram).\n' ...
    '%% To save this script: save_recipe(''%s_recipe.m'')\n'], ...
    prof.source_name, datetime('now','Format','yyyy-MM-dd HH:mm'), ...
    regexprep(prof.source_name, '[^A-Za-z0-9]', '_'));

pairplot_code = sprintf('de_pairplot(T, prof, de_select_columns(T, prof, %d, fams));', ...
    options.MaxVars);

cat_assoc_lines = cg_cat_association_code(T, prof);

sections = { ...
    header, ...
    '%% === Load ===', load_code, '', ...
    '%% === Clean ===', clean_code, '', ...
    '%% === Overview ===', 'de_overview(T, prof);', '', ...
    '%% === Pairplot ===', 'fams = de_corr_families(T, prof);', pairplot_code, '', ...
    '%% === Best-of Plots ===', plots_code ...
};
if ~isempty(family_code)
    sections = [sections, {'', '%% === Correlated families ===', family_code}];
end
if ~isempty(cat_assoc_lines)
    sections = [sections, {'', '%% === Categorical Associations ==='}, cat_assoc_lines(:)'];
end
if ~isempty(choro_code)
    sections{end+1} = '';
    sections{end+1} = '%% === State Choropleth ===';
    sections{end+1} = choro_code;
end
if ~isempty(country_code)
    sections{end+1} = '';
    sections{end+1} = '%% === World Choropleth ===';
    sections{end+1} = country_code;
end
if ~isempty(geo_multi_code)
    sections{end+1} = '';
    sections{end+1} = '%% === Geo x Categorical ===';
    sections{end+1} = geo_multi_code;
end
if ~isempty(geoscatter_code)
    sections{end+1} = '';
    sections{end+1} = '%% === Geo Scatter (lat/lon) ===';
    sections{end+1} = geoscatter_code;
end
if ~isempty(panel_code)
    sections{end+1} = '';
    sections{end+1} = '%% === Panel (stacked area + grouped time series) ===';
    sections{end+1} = panel_code;
end

recipe_text = strjoin(sections, newline);

fid = fopen(recipe_path, 'w');
if fid == -1
    warning('DataExplorer:recipeFailed', ...
        'Could not write recipe to %s', recipe_path);
    recipe_path = '';
    return
end
fprintf(fid, '%s\n', recipe_text);
fclose(fid);
se_print_recipe(recipe_text, sprintf('%s_recipe.m', bname_safe));
end


% ── se_print_recipe ──────────────────────────────────────────────────────────
function se_print_recipe(code, save_name)
%SE_PRINT_RECIPE  Print recipe code to the console with a save command.
sep = repmat('═', 1, 64);
fprintf('\n  %s\n', sep);
fprintf('%s\n', code);
fprintf('  %s\n', sep);
fprintf('  save_recipe(''%s'')\n', save_name);
fprintf('  %s\n\n', sep);
end
function tf = se_is_compositional(Y_mean, T, prof)
% True when numeric time series form a compositional whole (parts sum to a
% near-constant total).  Two signals, in priority order:
%   1. Any categorical column has a "Total"-like level name.
%   2. Row sums of per-time-point means have CV < 0.05.
TOTAL_WORDS = {'total', 'totals', 'grand total', 'all totals'};
has_total_label = false;
cat_search = find(prof.type == "categorical" & ~prof.skip);
for kk = 1:numel(cat_search)
    lvls = cellstr(categories(T.(prof.name{cat_search(kk)})));
    if any(cellfun(@(lv) any(strcmpi(lv, TOTAL_WORDS)), lvls))
        has_total_label = true; break;
    end
end
Y_comp     = Y_mean(all(~isnan(Y_mean), 2), :);
all_nonneg = ~isempty(Y_comp) && size(Y_comp, 1) > 1 && size(Y_comp, 2) > 1 && all(Y_comp(:) >= 0);
if has_total_label && all_nonneg
    tf = true;
elseif all_nonneg
    row_sums = sum(Y_comp, 2);
    tf = std(row_sums) / max(abs(mean(row_sums)), eps) < 0.05;
else
    tf = false;
end
end
% de__zip_extract is defined in de__zip_extract.m


% ── zip_list_entries ──────────────────────────────────────────────────────────
% de__zip_list is defined in de__zip_list.m
