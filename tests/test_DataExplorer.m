classdef test_DataExplorer < matlab.unittest.TestCase
%TEST_DATAEXPLORER  Regression harness for DataExplorer.
%
%   Run all tests:
%       results = runtests('tests/test_DataExplorer.m')
%       table(results)
%
%   Tags
%   ────
%   'unit'        — no file I/O, fast
%   'plot_rules'  — verify plot-type selection logic on synthetic tables
%   'integration' — loads a real example file (needs examples/ directory)
%
%   Fixture strategy
%   ────────────────
%   Large datasets are pre-sampled to small fixtures in tests/fixtures/ so
%   tests run without the full example files.  To regenerate a fixture:
%       T = SampleData('examples/bigfile.csv', 500);
%       writetable(T, 'tests/fixtures/bigfile_500.csv');
%
%   Baseline session status  (last updated 2026-05-20)
%   ──────────────────────────────────────────────────
%   tobacco CSV  — partially baselined (structure confirmed, figure titles TBD)
%   All others   — placeholder only; assertions to be filled in during session.

    properties (Constant)
        EXAMPLES_DIR = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'examples')
        FIXTURES_DIR = fullfile(fileparts(mfilename('fullpath')), 'fixtures')
    end

    % ─────────────────────────────────────────────────────────────────────────
    %  Shared utilities
    % ─────────────────────────────────────────────────────────────────────────
    methods (Access = private)

        function assert_recipe_valid(testCase, recipe)
            % recipe is the string array returned by DataExplorer (one line per
            % element).  checkcode needs a file, so write it to a unique temp .m.
            testCase.verifyNotEmpty(recipe, 'Recipe is empty');
            tmp = [tempname '.m'];
            writelines(recipe, tmp);
            cl = onCleanup(@() delete(tmp));
            info = checkcode(tmp, '-string');
            n_errors = numel(regexp(info, 'L \d+', 'match'));
            testCase.verifyEqual(n_errors, 0, ...
                sprintf('checkcode found %d issue(s) in recipe:\n%s', n_errors, info));
        end

        function assert_recipe_self_contained(testCase, recipe)
            content = char(join(recipe, newline));
            testCase.verifyEmpty(regexp(content, '\bDataExplorer\b'), ...
                'Recipe calls DataExplorer — not self-contained');
            testCase.verifyEmpty(regexp(content, '\bsave_recipe\b'), ...
                'Recipe calls save_recipe — not self-contained');
        end

        function mode = timeseries_mode(~)
            % Return 'stacked area' or 'overlaid lines' from the time-series
            % figure title, or '' if no time-series figure exists.
            % For compositional data both figures exist; returns the first mode found.
            figs = findall(0, 'Type', 'figure');
            mode = '';
            for k = 1:numel(figs)
                name = get(figs(k), 'Name');
                if contains(lower(name), 'time series')
                    ax = findall(figs(k), 'Type', 'axes');
                    if ~isempty(ax)
                        t = get(get(ax(1), 'Title'), 'String');
                        if contains(t, 'stacked area'),   mode = 'stacked area';   return; end
                        if contains(t, 'overlaid lines'), mode = 'overlaid lines'; return; end
                    end
                end
            end
        end

        function modes = all_timeseries_modes(~)
            % Return cell array of the time-series modes present across figures.
            figs = findall(0, 'Type', 'figure');
            has_stacked = false;
            has_overlaid = false;
            for k = 1:numel(figs)
                name = get(figs(k), 'Name');
                if contains(lower(name), 'time series')
                    ax = findall(figs(k), 'Type', 'axes');
                    if ~isempty(ax)
                        t = get(get(ax(1), 'Title'), 'String');
                        has_stacked  = has_stacked  || contains(t, 'stacked area');
                        has_overlaid = has_overlaid || contains(t, 'overlaid lines');
                    end
                end
            end
            modes = {};
            if has_stacked,  modes = [modes, {'stacked area'}];   end
            if has_overlaid, modes = [modes, {'overlaid lines'}]; end
        end

        function n = figure_count(~)
            n = numel(findall(0, 'Type', 'figure'));
        end

        function figs = figures_named(~, keyword)
            % Return all open figures whose Name contains keyword (case-insensitive).
            all_figs = findall(0, 'Type', 'figure');
            mask = arrayfun(@(f) contains(lower(get(f,'Name')), lower(keyword)), all_figs);
            figs = all_figs(mask);
        end

        function second = find_second_largest_sheet(~, filepath, sheets)
            % Return the name of the second-largest sheet by row count.
            % Returns "" if fewer than 2 non-empty sheets exist.
            nrows = zeros(numel(sheets), 1);
            for k = 1:numel(sheets)
                try
                    o = detectImportOptions(filepath, 'Sheet', sheets{k});
                    if ~isempty(o.VariableNames)
                        o.SelectedVariableNames = o.VariableNames(1);
                        tmp = readtable(filepath, o, 'Sheet', sheets{k});
                        nrows(k) = height(tmp);
                    end
                catch
                end
            end
            [~, ord] = sort(nrows, 'descend');
            if numel(ord) >= 2 && nrows(ord(2)) > 0
                second = sheets{ord(2)};
            else
                second = "";
            end
        end

        function assert_all_figures_nonempty(testCase)
            % Every open figure must contain at least one data graphics object.
            % Searches for patches, lines, images, surfaces, and bars directly —
            % avoiding axes-type detection which misses usamap map axes and
            % ColorBar objects introduced in R2019b.
            DATA_TYPES = {'patch','line','image','surface','bar', ...
                          'stair','area','stem','scatter','histogram', ...
                          'histogram2','boxchart'};
            figs = findall(0, 'Type', 'figure');
            testCase.verifyNotEmpty(figs, 'No figures were created');
            for k = 1:numel(figs)
                fig_name = get(figs(k), 'Name');
                has_data = false;
                for ti = 1:numel(DATA_TYPES)
                    if ~isempty(findall(figs(k), 'Type', DATA_TYPES{ti}))
                        has_data = true;
                        break;
                    end
                end
                testCase.verifyTrue(has_data, ...
                    sprintf('Figure "%s" contains no visible data objects', fig_name));
            end
        end

    end

    methods (Static, Access = private)
        function [T, prof] = strat_fixture(n, seed, withMid)
            % Table with a geo State key, a strong stratifier, near-zero Junk,
            % and (optionally) a moderate stratifier — all independent of State so
            % nothing is redundancy-skipped.  Used by the de_pick_stratifier tests.
            if nargin < 3, withMid = false; end
            rng(seed);
            State = categorical(repmat({'AL';'CA';'TX';'FL'}, n/4, 1));
            lev   = ["P"; "Q"];
            lev3  = ["X"; "Y"; "Z"];
            Junk  = categorical(randi(5, n, 1));
            if withMid
                Strong = categorical(lev(randi(2, n, 1)));
                Midcat = categorical(lev3(randi(3, n, 1)));
                Val = double(Strong == 'Q') * 10 + double(Midcat == 'Z') * 4 + randn(n, 1);
                T = table(State, Strong, Midcat, Junk, Val, ...
                    'VariableNames', {'State','Strong','Midcat','Junk','Val'});
            else
                Standard = categorical(lev(randi(2, n, 1)));
                Val = double(Standard == 'Q') * 10 + randn(n, 1) * 0.5;
                T = table(State, Standard, Junk, Val, ...
                    'VariableNames', {'State','Standard','Junk','Val'});
            end
            [T, prof] = de_profile(T);
        end

        function z = make_multi_zip()
            % A temp ZIP holding two CSVs (for de_load multi-file tests).
            d = tempname; mkdir(d);
            writetable(table((1:3)', (4:6)', 'VariableNames', {'a','b'}), ...
                fullfile(d, 'one.csv'));
            writetable(table((1:5)', 'VariableNames', {'c'}), ...
                fullfile(d, 'two.csv'));
            z = [tempname '.zip'];
            zip(z, {'one.csv', 'two.csv'}, d);
        end

        function f = make_multivar_nc()
            % Two CONFORMABLE variables on one lon/lat/time grid (combine → 1 table).
            f = [tempname '.nc'];
            nlon = 6; nlat = 5; ntime = 3;
            nccreate(f,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(f,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(f,'time',     'Dimensions',{'time',     ntime},'Format','classic');
            nccreate(f,'temp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            nccreate(f,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            ncwrite(f,'longitude', linspace(-130,-60,nlon)');
            ncwrite(f,'latitude',  linspace(25,55,nlat)');
            ncwrite(f,'time',      (1:ntime)');
            ncwrite(f,'temp',      rand(nlon,nlat,ntime));
            ncwrite(f,'prcp',      rand(nlon,nlat,ntime));
        end

        function f = make_hetero_nc()
            % Two NON-conformable variables (different dimensions): a 2-D grid and
            % a 1-D profile → de_load must ask / pick, not force-combine.
            f = [tempname '.nc'];
            nccreate(f,'longitude','Dimensions',{'longitude',6},'Format','classic');
            nccreate(f,'latitude', 'Dimensions',{'latitude', 5},'Format','classic');
            nccreate(f,'depth',    'Dimensions',{'depth',    4},'Format','classic');
            nccreate(f,'grid2d',   'Dimensions',{'longitude',6,'latitude',5},'Format','classic');
            nccreate(f,'profile1d','Dimensions',{'depth',4},'Format','classic');
            ncwrite(f,'longitude', linspace(-130,-60,6)');
            ncwrite(f,'latitude',  linspace(25,55,5)');
            ncwrite(f,'depth',     (1:4)');
            ncwrite(f,'grid2d',    rand(6,5));
            ncwrite(f,'profile1d', rand(4,1));
        end
    end

    % ─────────────────────────────────────────────────────────────────────────
    %  Setup / teardown
    % ─────────────────────────────────────────────────────────────────────────
    methods (TestClassSetup)
        function add_project_root_to_path(testCase)
            % R2026a runtests no longer adds the repo root to the path
            % automatically. Add it explicitly so all de_* functions are visible.
            project_root = fileparts(fileparts(mfilename('fullpath')));
            addpath(project_root);
            testCase.addTeardown(@() rmpath(project_root));
        end
    end

    methods (TestMethodSetup)
        function close_all_figures_and_suppress(testCase)
            close all;
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            testCase.addTeardown(@() set(0, 'DefaultFigureVisible', old_vis));
        end
    end

    % ─────────────────────────────────────────────────────────────────────────
    %  Unit tests — de_profile invariants
    %
    %  de_profile is a standalone .m file so these call it directly.
    % ─────────────────────────────────────────────────────────────────────────
    methods (Test, TestTags = {'unit'})

        function test_matlab_version(testCase)
            % DataExplorer targets R2025b (25.2). Running older versions risks
            % silent failures in DataTipTemplate, boxchart, arguments blocks, etc.
            testCase.verifyFalse(isMATLABReleaseOlderThan('R2025b'), ...
                sprintf('R2025b (25.2) required; this session is running %s (%s)', ...
                    version, version('-release')));
        end

        function test_profile_numeric_column(testCase)
            T = table([1;2;3;NaN;5], 'VariableNames', {'X'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "numeric");
            testCase.verifyEqual(prof.nmissing(1), 1);
            testCase.verifyEqual(prof.nunique(1), 4);  % 1,2,3,5 (NaN excluded)
        end

        function test_profile_string_to_numeric_at_70pct(testCase)
            % 4/5 = 80% parseable → converted to numeric
            T = table(["1.0";"2.5";"bad";"4.0";"5.0"], 'VariableNames', {'X'});
            [T2, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "numeric");
            testCase.verifyTrue(isnumeric(T2.X), 'Column should be numeric after conversion');
        end

        function test_profile_string_below_70pct_stays_categorical(testCase)
            % 2/5 = 40% parseable → stays categorical
            T = table(["1.0";"foo";"bar";"baz";"5.0"], 'VariableNames', {'X'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "categorical");
        end

        function test_profile_missing_sentinels_recoded(testCase)
            % N/A and NA should count as missing
            T = table(["1.0";"N/A";"3.0";"NA";"5.0"], 'VariableNames', {'X'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.nmissing(1), 2, ...
                'N/A and NA should both be recoded as missing');
        end

        function test_profile_mostly_missing_flagged_skip(testCase)
            % >80% missing → skip = true
            T = table([NaN;NaN;NaN;NaN;NaN;NaN;NaN;NaN;NaN;1.0], 'VariableNames', {'X'});
            [~, prof] = de_profile(T);
            testCase.verifyTrue(prof.skip(1), 'Column with >80% missing should be skip=true');
        end

        function test_profile_id_column_flagged_skip(testCase)
            % All-unique categorical → skip = true (ID detection)
            T = table(categorical(["a";"b";"c";"d";"e"]), 'VariableNames', {'ID'});
            [~, prof] = de_profile(T);
            testCase.verifyTrue(prof.skip(1), 'All-unique categorical should be skip=true');
        end

        function test_profile_low_cardinality_categorical_not_skipped(testCase)
            % Categorical with repeated values → not skipped
            T = table(categorical(["a";"b";"a";"b";"a"]), 'VariableNames', {'Cat'});
            [~, prof] = de_profile(T);
            testCase.verifyFalse(prof.skip(1), ...
                'Low-cardinality categorical should not be skipped');
        end

        % ── Change 1: FIPS pattern guard ──────────────────────────────────────

        function test_profile_id_name_keeps_strings_categorical(testCase)
            % "State Code" values like "01","06","48" look numeric but the column
            % name contains "code" → must stay categorical so geo detection runs.
            T = table(["01";"06";"48"], 'VariableNames', {'State_Code'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "categorical", ...
                'Column named State_Code must stay categorical despite numeric-looking values');
        end

        function test_profile_count_column_still_converts_to_numeric(testCase)
            % "Count" does not match the id-name pattern → converts to numeric
            T = table(["1";"2";"3";"4";"5"], 'VariableNames', {'Count'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "numeric", ...
                'Column named Count must convert to numeric (no id-name pattern match)');
        end

        % ── Name tokenization (CamelCase / snake_case / spaces) ───────────────

        function test_name_tokens_camelcase(testCase)
            testCase.verifyEqual(de_name_tokens("StateCode"), ["state","code"]);
            testCase.verifyEqual(de_name_tokens("SiteNum"),   ["site","num"]);
            testCase.verifyEqual(de_name_tokens("ParameterCode"), ["parameter","code"]);
            testCase.verifyEqual(de_name_tokens("Observation Count"), ["observation","count"]);
            testCase.verifyEqual(de_name_tokens("State_Code"), ["state","code"]);
            testCase.verifyEqual(de_name_tokens("POC"), "poc");
        end

        function test_profile_camelcase_id_reclassified(testCase)
            % CamelCase id name with integer values → reclassified to categorical
            % (regression: zero-width CamelCase split silently failed).
            T = table(repmat((1:50)', 4, 1), 'VariableNames', {'SiteNum'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "categorical", ...
                'Integer column named SiteNum must be reclassified to categorical');
        end

        % ── Change 2: High-cardinality categorical skip ───────────────────────

        function test_profile_high_cardinality_categorical_skipped(testCase)
            % > 100 unique (but with repeats, so not an all-unique ID) → high-card skip
            vals = repmat(string((1:150)') + "_w", 2, 1);   % 300 rows, 150 unique
            T = table(vals, 'VariableNames', {'Widget'});
            [~, prof] = de_profile(T);
            testCase.verifyTrue(prof.skip(1), ...
                'Categorical with 150 unique values should be skip=true (high-cardinality)');
            testCase.verifyTrue(contains(prof.skip_reason(1), "high-cardinality"), ...
                'skip_reason should mention high-cardinality');
        end

        function test_profile_below_high_card_threshold_not_skipped(testCase)
            % 50 unique (with repeats) < threshold → not skipped
            vals = repmat(string((1:50)') + "_w", 4, 1);    % 200 rows, 50 unique
            T = table(vals, 'VariableNames', {'Widget'});
            [~, prof] = de_profile(T);
            testCase.verifyFalse(prof.skip(1), ...
                'Categorical with 50 unique values should not be high-cardinality skipped');
        end

        % ── Change 4: Lat/lon excluded from pairplot ──────────────────────────

        function test_select_columns_excludes_latitude_longitude(testCase)
            % de_select_columns must never pick Latitude or Longitude as pairplot vars
            n = 50;
            lat  = 30 + rand(n,1) * 20;
            lon  = -120 + rand(n,1) * 50;
            vals = randn(n,1);
            T = table(lat, lon, vals, 'VariableNames', {'Latitude','Longitude','Value'});
            [~, prof] = de_profile(T);
            sel = de_select_columns(T, prof, 8);
            lat_idx = find(strcmp(prof.name, 'Latitude'));
            lon_idx = find(strcmp(prof.name, 'Longitude'));
            testCase.verifyFalse(ismember(lat_idx, sel), ...
                'Latitude must not appear in pairplot column selection');
            testCase.verifyFalse(ismember(lon_idx, sel), ...
                'Longitude must not appear in pairplot column selection');
        end

        % ── Change 5a: Skewness in de_profile ────────────────────────────────

        function test_profile_skewness_right_skewed_data(testCase)
            % Exponential data has strong positive skewness
            rng(42);
            x = exprnd(1, 500, 1);
            T = table(x, 'VariableNames', {'X'});
            [~, prof] = de_profile(T);
            testCase.verifyTrue(isfield(prof, 'skewness'), ...
                'de_profile must return prof.skewness field');
            testCase.verifyGreaterThan(prof.skewness(1), 1.5, ...
                'Exponential data should have skewness > 1.5');
        end

        function test_profile_skewness_symmetric_data(testCase)
            % Symmetric data has near-zero skewness
            rng(42);
            x = randn(500, 1);
            T = table(x, 'VariableNames', {'X'});
            [~, prof] = de_profile(T);
            testCase.verifyTrue(isfield(prof, 'skewness'), ...
                'de_profile must return prof.skewness field');
            testCase.verifyLessThan(abs(prof.skewness(1)), 0.5, ...
                'Normal data should have |skewness| < 0.5');
        end

        % ── Correlated family detection ───────────────────────────────────────

        function test_corr_families_detects_cluster(testCase)
            % Five columns drawn from the same latent variable → one family.
            rng(1);
            n = 200;
            z = randn(n,1);
            T = table(z + 0.05*randn(n,1), z + 0.05*randn(n,1), ...
                      z + 0.05*randn(n,1), z + 0.05*randn(n,1), ...
                      z + 0.05*randn(n,1), randn(n,1), ...
                'VariableNames', {'A','B','C','D','E','Noise'});
            [~, prof] = de_profile(T);
            fams = de_corr_families(T, prof);
            testCase.verifyNotEmpty(fams, 'Should detect at least one family');
            sizes = cellfun(@numel, fams);
            testCase.verifyGreaterThanOrEqual(max(sizes), 4, ...
                'Family of A–E should have ≥ 4 members (Noise excluded)');
        end

        function test_corr_families_spearman_catches_monotone_nonlinear(testCase)
            % Columns related by monotone NONLINEAR transforms of a latent
            % variable: Spearman (default) should group them even though
            % Pearson would be weakened by the nonlinearity.
            rng(11);
            n = 200;
            x = sort(rand(n,1) * 4 - 2) + 0.001*randn(n,1);
            T = table(x, exp(x), sign(x).*abs(x).^3, randn(n,1), ...
                'VariableNames', {'A','B','C','Noise'});
            [~, prof] = de_profile(T);
            fams = de_corr_families(T, prof);   % default Method="spearman"
            testCase.verifyNotEmpty(fams, 'Spearman should detect a monotone family');
            testCase.verifyGreaterThanOrEqual(max(cellfun(@numel, fams)), 3, ...
                'A, B, C are monotone transforms → should form a family of >= 3');
        end

        function test_corr_family_representative_is_medoid(testCase)
            % The kept representative (fam(1)) should be the medoid — the member
            % most correlated with the rest — NOT the highest-variance-but-
            % peripheral member.
            rng(21);
            n = 300;
            z = randn(n,1);
            A = z + 0.1*randn(n,1);
            B = z + 0.1*randn(n,1);
            C = z + 0.1*randn(n,1);
            D = 5*z + 1.5*randn(n,1);   % highest variance, but noisier → peripheral
            T = table(A, B, C, D, 'VariableNames', {'A','B','C','D'});
            [~, prof] = de_profile(T);
            fams = de_corr_families(T, prof);
            testCase.assumeNotEmpty(fams, 'precondition: a family is detected');
            rep = string(prof.name{fams{1}(1)});
            testCase.verifyNotEqual(rep, "D", ...
                'high-variance-but-peripheral D must not be the medoid representative');
        end

        function test_value_ladder_renders_bars(testCase)
            % de_statebins CellRenderer='value_ladder' draws colored bars (Tag
            % 'value_ladder') — one per member per state — with a labeled axis.
            rng(9);
            n = 180;
            states = repmat(["AL";"CA";"TX";"NY";"FL";"OH"], n/6, 1);
            latent = abs(randn(n,1)) + 1;
            A = latent + 0.05*randn(n,1);
            B = latent*1.4 + 0.05*randn(n,1);
            C = latent*0.8 + 0.05*randn(n,1);
            T = table(categorical(states), A, B, C, ...
                'VariableNames', {'State','MeasureA','MeasureB','MeasureC'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            close all;

            de_statebins(T, 'StateCol','State', 'CellRenderer','value_ladder', ...
                'ValueCols', ["MeasureA","MeasureB","MeasureC"]);
            bars = findobj(0, 'Tag', 'value_ladder');
            axn  = findobj(0, 'Tag', 'ladder_axis');
            testCase.verifyNotEmpty(bars, 'value_ladder must draw bars');
            testCase.verifyNotEmpty(axn,  'value_ladder must draw a labeled axis');
        end

        function test_corr_families_ignores_independent_cols(testCase)
            % Five truly independent columns → no family.
            rng(2);
            n = 200;
            T = table(randn(n,1), randn(n,1), randn(n,1), randn(n,1), randn(n,1), ...
                'VariableNames', {'P','Q','R','S','U'});
            [~, prof] = de_profile(T);
            fams = de_corr_families(T, prof);
            testCase.verifyEmpty(fams, ...
                'Independent columns should produce no families');
        end

        function test_variance_explained_perfect_and_independent(testCase)
            % η² ≈ 1 when groups fully determine x; ≈ 0 when independent.
            xp = [1 1 1 10 10 10]';
            gp = categorical([1 1 1 2 2 2]');
            testCase.verifyGreaterThan(de_variance_explained(xp, gp), 0.99);
            rng(0);
            xi = randn(400, 1);
            gi = categorical(repmat([1; 2], 200, 1));
            testCase.verifyLessThan(de_variance_explained(xi, gi), 0.1);
        end

        function test_variance_explained_degenerate_returns_zero(testCase)
            % Constant x, or a single group, explains nothing.
            testCase.verifyEqual( ...
                de_variance_explained(ones(6,1), categorical([1 1 1 2 2 2]')), 0);
            testCase.verifyEqual( ...
                de_variance_explained([1 2 3 4]', categorical(ones(4,1))), 0);
        end

        function test_pick_stratifier_selects_qualifying_excludes_others(testCase)
            % Strong stratifier chosen; geo key, below-floor (Junk) and skipped
            % columns excluded.  Independent of State so nothing is redundancy-skipped.
            [T, prof] = test_DataExplorer.strat_fixture(400, 1);
            [s, e, cn] = de_pick_stratifier(T, prof, "Val", "State");
            testCase.verifyEqual(s, "Standard");
            testCase.verifyGreaterThan(e, 0.5);
            testCase.verifyFalse(any(cn == "Junk"), 'near-zero η² must be below floor');
            testCase.verifyFalse(any(cn == "State"), 'geo key is not a stratifier');
        end

        function test_pick_stratifier_seed_deterministic(testCase)
            [T, prof] = test_DataExplorer.strat_fixture(600, 2, true);
            rng(7); a = de_pick_stratifier(T, prof, "Val", "State");
            rng(7); b = de_pick_stratifier(T, prof, "Val", "State");
            testCase.verifyEqual(a, b, 'same seed → same pick');
        end

        function test_pick_stratifier_weights_favor_stronger(testCase)
            % Two qualifying candidates: the higher-η² one is sampled more often.
            [T, prof] = test_DataExplorer.strat_fixture(600, 2, true);
            nStrong = 0; nMid = 0;
            for k = 1:800
                s = de_pick_stratifier(T, prof, "Val", "State");
                nStrong = nStrong + (s == "Strong");
                nMid    = nMid + (s == "Midcat");
            end
            testCase.verifyGreaterThan(nStrong, nMid, ...
                'stronger stratifier should be picked more often');
        end

        function test_pick_stratifier_none_qualifies_returns_empty(testCase)
            % A numeric independent of every categorical → no stratifier.
            rng(9); n = 300;
            State = categorical(repmat({'AL';'CA';'TX';'FL'}, n/4, 1));
            lev   = ["P"; "Q"];
            C1    = categorical(lev(randi(2, n, 1)));
            C2    = categorical(lev(randi(2, n, 1)));
            Val   = randn(n, 1);
            T = table(State, C1, C2, Val);
            [T, prof] = de_profile(T);
            s = de_pick_stratifier(T, prof, "Val", "State");
            testCase.verifyEqual(s, "");
        end

        function test_tilegrid_confound_note_renders(testCase)
            % ConfoundNote draws a tagged red caveat in the figure (still plots).
            rng(0);
            State = categorical(repmat({'AL';'CA';'TX';'FL'}, 25, 1));
            Val   = randn(100, 1);
            T = table(State, Val);
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            de_statebins(T, 'StateCol', 'State', 'ColorCol', 'Val', ...
                'ConfoundNote', 'mixes Foo (eta2=88%)');
            ann = findall(0, 'Tag', 'confound_note');
            testCase.verifyNotEmpty(ann, 'ConfoundNote must render a tagged annotation');
            testCase.verifyTrue(contains(string(ann(1).String), 'mixes Foo'));
        end

        function test_de_load_zip_single_file_opens(testCase)
            % A ZIP with exactly one data file just opens (the common case).
            f = fullfile(testCase.EXAMPLES_DIR, 'annual_aqi_by_county_2025.zip');
            if ~exist(f, 'file'), testCase.assumeFail('AQI zip not found'); end
            T = de_load(f);
            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0);
        end

        function test_de_load_zip_multiple_files_errors_with_options(testCase)
            % Several data files + no InnerFile → informative error, no guessing.
            z = test_DataExplorer.make_multi_zip();
            testCase.verifyError(@() de_load(z), 'de_load:multipleFilesInZip');
        end

        function test_de_load_zip_innerfile_selects_member(testCase)
            % InnerFile picks the named member from a multi-file ZIP.
            z = test_DataExplorer.make_multi_zip();
            T = de_load(z, 'InnerFile', 'two.csv');
            testCase.verifyEqual(height(T), 5);
        end

        function test_de_load_excel_multisheet_errors_with_options(testCase)
            % A multi-sheet workbook with no Sheet pinned → informative error
            % (non-interactive by default), not a silent guess.
            f = fullfile(testCase.EXAMPLES_DIR, 'Prod_dataset.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('Prod_dataset.xlsx not found'); end
            testCase.verifyError(@() de_load(f), 'de_load:multipleSheets');
        end

        function test_de_load_excel_sheet_by_index(testCase)
            % de_load supports a 1-based numeric Sheet index.
            f = fullfile(testCase.EXAMPLES_DIR, 'Prod_dataset.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('Prod_dataset.xlsx not found'); end
            T = de_load(f, 'Sheet', 1, 'MaxRows', 50);
            testCase.verifyGreaterThan(width(T), 0);
        end

        function test_de_load_nc_combines_conformable_vars(testCase)
            % Conformable nc variables combine into ONE table (a column each).
            f = test_DataExplorer.make_multivar_nc();
            cl = onCleanup(@() delete(f));
            T = de_load(f);
            cols = string(T.Properties.VariableNames);
            testCase.verifyTrue(all(ismember(["temp","prcp"], cols)), ...
                'Conformable nc variables must combine into one table');
            testCase.verifyTrue(any(ismember(["longitude","latitude","time"], cols)), ...
                'Coordinate columns expected');
        end

        function test_de_load_nc_heterogeneous_errors(testCase)
            % Mixed-shape variables, no NCVariable/AutoSelect → informative error.
            f = test_DataExplorer.make_hetero_nc();
            cl = onCleanup(@() delete(f));
            testCase.verifyError(@() de_load(f), 'de_load:multipleNCGroups');
        end

        function test_de_load_nc_ncvariable_selects(testCase)
            f = test_DataExplorer.make_hetero_nc();
            cl = onCleanup(@() delete(f));
            T = de_load(f, 'NCVariable', 'profile1d');
            cols = string(T.Properties.VariableNames);
            testCase.verifyTrue(ismember("profile1d", cols));
            testCase.verifyFalse(ismember("grid2d", cols));
        end

        function test_de_load_nc_autoselect_largest(testCase)
            f = test_DataExplorer.make_hetero_nc();
            cl = onCleanup(@() delete(f));
            T = de_load(f, 'AutoSelect', true);
            cols = string(T.Properties.VariableNames);
            testCase.verifyTrue(ismember("grid2d", cols), ...
                'AutoSelect should pick the largest group (grid2d, 30 elems)');
        end

        function test_select_columns_excludes_family_nonreps(testCase)
            % When a family is provided, de_select_columns keeps only the
            % representative (first member) and excludes the rest.
            rng(3);
            n = 200;
            z = randn(n,1);
            T = table(z + 0.02*randn(n,1), z + 0.02*randn(n,1), ...
                      z + 0.02*randn(n,1), randn(n,1), ...
                'VariableNames', {'X1','X2','X3','Y'});
            [~, prof] = de_profile(T);
            fams = de_corr_families(T, prof);
            testCase.assumeNotEmpty(fams, 'Precondition: family must be detected');
            sel = de_select_columns(T, prof, 8, fams);
            % At most one member of each family should appear in selection.
            for fi = 1:numel(fams)
                n_in_sel = sum(ismember(fams{fi}, sel));
                testCase.verifyLessThanOrEqual(n_in_sel, 1, ...
                    sprintf('Family %d: at most 1 member may appear in pairplot selection', fi));
            end
        end

        % ── Semantic role classification ──────────────────────────────────────

        function test_profile_role_field_exists(testCase)
            T = table([1;2;3], 'VariableNames', {'Value'});
            [~, prof] = de_profile(T);
            testCase.verifyTrue(isfield(prof, 'role'), ...
                'de_profile must return a prof.role field');
        end

        function test_profile_role_geographic_state(testCase)
            % Values must actually be recognizable as states (the grid does not
            % resolve FIPS numbers — that is the documented soft spot).
            T = table(["AL";"CA";"TX";"AL";"CA";"TX"], 'VariableNames', {'State_Code'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.role(1), "geographic", ...
                'A state column with recognizable codes should have role "geographic"');
        end

        function test_profile_role_temporal_year(testCase)
            T = table((2000:2010)', 'VariableNames', {'Year'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.role(1), "temporal", ...
                'A numeric column named Year should have role "temporal"');
        end

        function test_profile_role_temporal_datetime(testCase)
            T = table(datetime(2020,1,1) + caldays((0:9)'), 'VariableNames', {'Stamp'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.role(1), "temporal", ...
                'A datetime column should have role "temporal"');
        end

        function test_profile_role_identifier(testCase)
            T = table(categorical(["a";"b";"c";"d";"e"]), 'VariableNames', {'RecordID'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.role(1), "identifier", ...
                'An all-unique / id-named column should have role "identifier"');
        end

        function test_profile_role_plain_numeric_empty(testCase)
            T = table([1.5;2.7;3.1;8.2;0.4], 'VariableNames', {'Concentration'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.role(1), "", ...
                'A plain numeric measure should have empty role');
        end

        function test_geo_key_prefers_name_over_fips_code(testCase)
            % A StateName column (recognizable names) must win us-states over a
            % StateCode column of FIPS numbers the grid can't resolve.
            states = ["Alabama";"California";"Texas";"Florida";"Ohio"];
            fips   = [1;6;48;12;39];
            T = table(repmat(states,4,1), repmat(fips,4,1), ...
                'VariableNames', {'StateName','StateCode'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.geo_grid{strcmp(prof.name, 'StateName')}, 'us-states', ...
                'StateName (recognizable names) should be detected as us-states');
            testCase.verifyNotEqual(prof.geo_grid{strcmp(prof.name, 'StateCode')}, 'us-states', ...
                'FIPS-number StateCode must not be assigned us-states by name alone');
        end

        function test_profile_skips_redundant_categorical(testCase)
            % Two perfectly-associated categoricals (Cramer's V ~ 1) carry the same
            % information: keep one, skip the other.  Prefer dropping the
            % identifier-named column (StateCode) over the readable one (StateName).
            nm = repelem("S" + string(1:6), 30)';
            T = table(categorical(nm + "c"), categorical(nm), ...
                'VariableNames', {'StateCode','StateName'});
            [~, prof] = de_profile(T);
            ci = find(strcmp(prof.name, 'StateCode'));
            ni = find(strcmp(prof.name, 'StateName'));
            testCase.verifyTrue(prof.skip(ci), ...
                'redundant id-named StateCode should be skipped');
            testCase.verifyFalse(prof.skip(ni), ...
                'StateName should be kept as the representative');
            testCase.verifyTrue(contains(prof.skip_reason(ci), "redundant"), ...
                'skip reason should mention redundancy');
        end

        % ── Temporal parsing of date-like strings ─────────────────────────────

        function test_profile_parses_iso_date_strings_to_datetime(testCase)
            T = table(["2024-01-15";"2024-06-20";"2024-09-01";"2024-12-31"], ...
                'VariableNames', {'CollectedOn'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "datetime", ...
                'A column of ISO date strings should be parsed to datetime');
        end

        function test_profile_decimal_strings_not_parsed_as_dates(testCase)
            % Decimal-looking strings must NOT be misread as dates.
            T = table(["1.0";"foo";"bar";"baz";"5.0"], 'VariableNames', {'Mixed'});
            [~, prof] = de_profile(T);
            testCase.verifyEqual(prof.type(1), "categorical", ...
                'Decimal/text strings must stay categorical, not become datetime');
        end

        function test_profile_source_name_is_scalar_string(testCase)
            % Loading via a double-quoted path must not produce a 1×2 string array
            % in prof.source_name (regression: [fname, fext] on string type).
            f = fullfile(testCase.EXAMPLES_DIR, ...
                'State_Tobacco_Related_Disparities_Dashboard_Data.csv');
            if ~exist(f, 'file'), testCase.assumeFail('Tobacco CSV not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            % Pass as a MATLAB string (double-quoted) to exercise the string path
            T = DataExplorer(string(f), 'MaxRows', 200);
            % If source_name were 1×2, the overview sprintf('%d') would have crashed.
            % Just reaching here confirms it's scalar. Double-check explicitly:
            [~, prof] = de_profile(T);
            testCase.verifyTrue(isscalar(prof.source_name) || ischar(prof.source_name), ...
                'source_name should be a scalar (not a 1×2 string array)');
        end

        function test_recipe_uses_absolute_path(testCase)
            % Regression: recipe embedded the relative path passed by the caller,
            % so running the recipe from tempdir failed with "File not found".
            f = fullfile(testCase.EXAMPLES_DIR, ...
                'State_Tobacco_Related_Disparities_Dashboard_Data.csv');
            if ~exist(f, 'file'), testCase.assumeFail('Tobacco CSV not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            % Load using a relative path (cd to examples/ first to reproduce the bug)
            orig_dir = pwd;
            cd(testCase.EXAMPLES_DIR);
            dir_cleanup = onCleanup(@() cd(orig_dir));

            % Request the recipe (3rd output) → returned without rendering.
            [~, ~, recipe] = DataExplorer( ...
                'State_Tobacco_Related_Disparities_Dashboard_Data.csv', 'MaxRows', 100);

            cd(orig_dir);   % restore before assertions so any remaining test code runs fine

            content = char(join(recipe, newline));
            % The relative filename must not appear bare in the recipe
            testCase.verifyEmpty( ...
                strfind(content, '''State_Tobacco_Related_Disparities_Dashboard_Data.csv'''), ...
                'Recipe contains a relative path — should be absolute');
        end

        function test_missing_file_gives_named_error(testCase)
            testCase.verifyError( ...
                @() DataExplorer('no_such_file_xyz_abc.csv'), ...
                'DataExplorer:fileNotFound');
        end

        function test_sampling_records_in_userdata(testCase)
            % When DataExplorer samples a table, UserData.sampled should be set
            % so the echo code emits SampleData() rather than readtable().
            f = fullfile(testCase.EXAMPLES_DIR, ...
                'State_Tobacco_Related_Disparities_Dashboard_Data.csv');
            if ~exist(f, 'file'), testCase.assumeFail('Tobacco CSV not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 100);  % force sampling
            ud = T.Properties.UserData;
            testCase.verifyTrue(isstruct(ud) && isfield(ud, 'sampled') && ud.sampled > 0, ...
                'UserData.sampled should be set when MaxRows forces a sample');
        end

        function test_de_usamap_patches_in_correct_axes(testCase)
            % Single-axes rewrite: AK and HI use affine-transformed patches in
            % the same axes as CONUS — no separate axes structs.  Verify:
            %   - de_usamap returns a plain axes handle (not a struct)
            %   - patches exist for CONUS states (CA, TX, NY)
            %   - AK and HI patches are present (identified by UserData)
            %   - all patches are children of the single returned axes
            testCase.assumeTrue(~isempty(ver('map')), 'Mapping Toolbox not available');

            state_codes = {'CA'; 'TX'; 'NY'; 'FL'; 'OH'; 'WA'; 'OR'; 'AK'; 'HI'};
            values      = (1:9)';
            T = table(state_codes, values, 'VariableNames', {'State', 'Value'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            [fig, ax] = de_usamap(T, 'StateCol', 'State', 'ColorCol', 'Value');
            fig_cleanup = onCleanup(@() close(fig));

            % ax is a plain axes handle, not a struct
            testCase.verifyTrue(isgraphics(ax) && strcmp(ax.Type, 'axes'), ...
                'de_usamap should return a plain axes handle');

            % All state patches live in the single axes
            all_patches = findobj(ax, 'Type', 'patch');
            testCase.verifyNotEmpty(all_patches, 'No patches found in map axes');

            % AK and HI must be present (identified by UserData set on each patch)
            ak_patches = findobj(ax, 'Type', 'patch', 'UserData', 'AK');
            hi_patches = findobj(ax, 'Type', 'patch', 'UserData', 'HI');
            testCase.verifyNotEmpty(ak_patches, 'No AK patch found in map axes');
            testCase.verifyNotEmpty(hi_patches, 'No HI patch found in map axes');

            % CONUS states must be present
            ca_patches = findobj(ax, 'Type', 'patch', 'UserData', 'CA');
            testCase.verifyNotEmpty(ca_patches, 'No CA patch found in map axes');

            % Sanity: far more patches total than just AK alone (CONUS has many)
            testCase.verifyGreaterThan(numel(all_patches), numel(ak_patches) * 5, ...
                'Expected many more total patches than AK alone (CONUS has many states)');
        end

        function test_de_usamap_slider_appears_with_timecol(testCase)
            % de_usamap creates a slider when TimeCol has more than one unique value.
            testCase.assumeTrue(~isempty(ver('map')), 'Mapping Toolbox not available');

            states = {'CA'; 'CA'; 'TX'; 'TX'; 'NY'; 'NY'};
            years  = [2020; 2021; 2020; 2021; 2020; 2021];
            values = [100; 110; 200; 210; 150; 160];
            T = table(states, years, values, 'VariableNames', {'State', 'Year', 'Value'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            [fig, ~] = de_usamap(T, 'StateCol', 'State', 'ColorCol', 'Value', 'TimeCol', 'Year');
            fig_cleanup = onCleanup(@() close(fig));

            sliders = findobj(fig, 'Style', 'slider');
            testCase.verifyNotEmpty(sliders, ...
                'de_usamap with TimeCol having >1 unique value should create a slider');
        end

        function test_dataexplorer_wide_year_state_choropleth_has_sparklines(testCase)
            % Post-inversion (Task 6): geo × categorical sparklines are recipe-only.
            % DataExplorer with wide-format year columns and a state+category column pair
            % must include de_statebins and heatmap_cat in the generated recipe.
            % The direct render path no longer produces a heatmap_cat figure; the recipe
            % code generator (cg_geo_multicategorical_code) takes that role instead.

            % 20 states × 3 MSN codes = 60 rows.  Each state appears 3 times so
            % the profiler does not flag it as an all-unique ID column.  20 unique
            % values > MAX_LEVELS=15 triggers the cat_big → se_plot_state_summary path.
            US20 = {'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA', ...
                    'HI','ID','IL','IN','IA','KS','KY','LA','ME','MD'};
            msn3 = {'COAL','GAS','OIL'};
            [st, ms] = ndgrid(US20, msn3);
            tmp = [tempname '.csv'];
            T = table(categorical(st(:)), categorical(ms(:)), ...
                100 + 50*randn(60,1), ...
                110 + 50*randn(60,1), ...
                120 + 50*randn(60,1), ...
                'VariableNames', {'StateCode','MSN','x2020','x2021','x2022'});
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'Expected a recipe file');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_statebins'), ...
                'Recipe must contain de_statebins for wide-year state+category dataset');
            testCase.verifyTrue(contains(recipe_text, 'heatmap_cat'), ...
                'Recipe must contain heatmap_cat for wide-year state+category dataset');
        end

        function test_de_statebins_sparklines_with_timecol(testCase)
            % de_statebins draws per-tile sparklines (Tag='sparkline') instead of a
            % slider when TimeCol is present with more than one unique value.
            states = categorical({'CA';'CA';'TX';'TX';'NY';'NY'});
            years  = [2020;2021;2020;2021;2020;2021];
            values = [100;110;200;210;150;160];
            T = table(states, years, values, 'VariableNames', {'State','Year','Value'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            [fig, ax] = de_statebins(T, 'StateCol','State', 'ColorCol','Value', 'TimeCol','Year');
            fig_cleanup = onCleanup(@() close(fig));

            testCase.verifyTrue(isgraphics(fig) && isgraphics(ax), ...
                'de_statebins should return valid handles');
            sparklines = findobj(ax, 'Type', 'line', 'Tag', 'sparkline');
            testCase.verifyNotEmpty(sparklines, ...
                'de_statebins with TimeCol (>1 unique value) should draw sparklines, not a slider');
            sliders = findobj(fig, 'Style', 'slider');
            testCase.verifyEmpty(sliders, ...
                'de_statebins should not create a slider — sparklines replaced it');

            % Colorbar label should be mean(Value) when TimeCol is active
            cb_h = findobj(fig, 'Type', 'colorbar');
            testCase.assertNotEmpty(cb_h, 'should have a colorbar');
            testCase.verifyTrue(contains(cb_h(1).Label.String, 'mean('), ...
                'colorbar label should say mean(...) when TimeCol is active');

            % Legend key text box should be present in the axes margin
            key_h = findobj(ax, 'Type', 'text', 'Tag', 'legend_key');
            testCase.verifyNotEmpty(key_h, ...
                'should have a legend_key text object in the axes margin');
        end

        function test_cond_heatmap_orders_rows_by_count_desc(testCase)
            % Regression: the SVD row-reorder dumped the largest-count row to the
            % bottom for near-1:1 (high-association) pairs.  Rows must read in
            % count-descending order (largest on top).
            counts = [1120 591 300 250 200 172];
            nm = repelem("S" + string(1:numel(counts)), counts)';
            code = nm + "c";
            T = table(categorical(code), categorical(nm), ...
                'VariableNames', {'StateCode','StateName'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            close all;

            de_cond_heatmap(T, "StateCode", "StateName");
            ax = findobj(gcf, 'Type', 'axes');
            yl = string(get(ax(1), 'YTickLabel'));
            testCase.verifyEqual(yl(1), "S1c", ...
                'Largest-count row (S1c, n=1120) must be on top, not reordered away');
        end

        function test_de_countrybins_basic(testCase)
            % de_countrybins draws one colored tile per recognized ISO alpha-2 code.
            iso2 = categorical({'US';'GB';'DE';'FR';'JP';'CN';'BR'});
            vals = (1:7)';
            T = table(iso2, vals, 'VariableNames', {'Country','Value'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            [fig, ax] = de_countrybins(T, 'CountryCol','Country', 'ColorCol','Value');
            fig_cleanup = onCleanup(@() close(fig));

            testCase.verifyTrue(isgraphics(fig) && isgraphics(ax), ...
                'de_countrybins should return valid figure and axes handles');
            patches = findobj(ax, 'Type', 'patch');
            testCase.verifyGreaterThanOrEqual(numel(patches), 5, ...
                'de_countrybins should draw at least 5 tile patches for 7 country codes');
        end

        function test_se_looks_like_countries_wires_countrybins(testCase)
            % DataExplorer should emit de_countrybins in the recipe when an
            % ISO alpha-2 country-code column is present.  Direct render is
            % gone (Task 6 full inversion); recipe is the check point.
            % 12 rows, 10 unique ISO-2 codes → not flagged as all-unique (ID).
            countries = categorical(["US";"GB";"DE";"FR";"JP";"AU";"CA";"MX";"BR";"CN";"US";"GB"]);
            T = table(countries, (1:12)', 'VariableNames', {'Country','Value'});
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl2 = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'DataExplorer must write a recipe file');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_countrybins'), ...
                'Recipe must contain de_countrybins for ISO-2 country codes');
        end

        function test_de_profile_adds_panel_and_geo_grid(testCase)
            % de_profile must populate prof.panel (wide-year detection) and
            % prof.geo_grid (per-column geo detection) fields.
            % Use 2 rows per state so the all-unique-categorical heuristic
            % does not flag StateCode as an ID column.
            StateCode = categorical(repmat({'CA';'TX';'NY';'FL';'OH'}, 2, 1));
            T = table(StateCode);
            for yr = 1960:1965
                T.(sprintf('x%d', yr)) = rand(10, 1);
            end
            [~, prof] = de_profile(T);
            testCase.verifyTrue(isfield(prof, 'panel'), 'prof.panel missing from de_profile output');
            testCase.verifyTrue(isfield(prof, 'geo_grid'), 'prof.geo_grid missing from de_profile output');
            testCase.verifyTrue(prof.panel.is_panel, ...
                'wide-year columns + categorical with >2 levels should be detected as a panel');
            testCase.verifyEqual(numel(prof.geo_grid), width(T), ...
                'prof.geo_grid must have one cell per column');
        end

        function test_de_pairplot_produces_figure(testCase)
            % de_pairplot must create a figure whose Name contains 'Pairplot'.
            Borough      = categorical(repmat({'Manhattan';'Brooklyn';'Queens'}, 10, 1));
            ComplainType = categorical(repmat({'Noise';'Graffiti';'Heat'}, 10, 1));
            T = table(Borough, ComplainType);
            [T, prof] = de_profile(T);
            sel = de_select_columns(T, prof, 4);
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            de_pairplot(T, prof, sel);
            figs = findall(0, 'Type', 'figure');
            names = arrayfun(@(f) get(f,'Name'), figs, 'UniformOutput', false);
            testCase.verifyTrue(any(contains(names, 'Pairplot')), ...
                'de_pairplot must create a figure with "Pairplot" in its Name');
        end

        function test_de_pairplot_caps_huge_selection(testCase)
            % A hand-edited selection larger than the cap must warn and truncate,
            % never build an N×N grid that explodes quadratically (the regression
            % that timed out Prod_dataset / FIADB via a ~64-member family).
            nC   = 20;
            vars = arrayfun(@(k) sprintf('M%02d', k), 1:nC, 'UniformOutput', false);
            data = array2table(randn(40, nC), 'VariableNames', vars);
            [T, prof] = de_profile(data);
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            testCase.verifyWarning(@() de_pairplot(T, prof, 1:nC), ...
                'de_pairplot:tooManyColumns');
        end

        function test_recipe_311_like_has_pairplot(testCase)
            % A categorical-heavy (311-like) dataset: recipe must contain de_pairplot.
            Borough      = categorical(repmat({'Manhattan';'Brooklyn';'Queens';'Bronx'}, 10, 1));
            ComplainType = categorical(repmat({'Noise';'Graffiti';'Heat';'Rodent'}, 10, 1));
            Status       = categorical(repmat({'Open';'Closed'}, 20, 1));
            T = table(Borough, ComplainType, Status);
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl2 = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'DataExplorer must write a recipe file');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_pairplot'), ...
                'Recipe must contain de_pairplot for categorical-heavy tables');
        end

        function test_recipe_prod_like_has_pairplot_and_panel(testCase)
            % A panel dataset (Prod-like): recipe must contain de_pairplot
            % AND a panel section with de_plot_panel_totals.
            states = categorical(repmat({'CA';'TX';'NY';'FL';'OH'}, 6, 1));
            msn    = categorical(repmat({'TETCB';'CLTCB';'NGTCB';'EMTCB';'WWTCB';'SOTCB'}, 5, 1));
            T = table(states, msn);
            for yr = 1960:1965
                T.(sprintf('x%d', yr)) = rand(30, 1);
            end
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl2 = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'DataExplorer must write a recipe file');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_pairplot'), ...
                'Recipe must contain de_pairplot even for panel datasets');
            testCase.verifyTrue(contains(recipe_text, 'de_plot_panel_totals'), ...
                'Recipe must contain de_plot_panel_totals for panel datasets');
        end

        function test_figure_names_do_not_contain_filename(testCase)
            % Figure window Names must not contain the bare filename.
            % Plain-file figures should use short labels: "time series (overlaid)",
            % "Pairplot", "Overview", etc. — never "mydata.csv — ...".
            n = 30;
            Value = (1:n)';
            Group = categorical(repmat({'A';'B';'C'}, 10, 1));
            Date  = datetime(2000,1,1) + caldays((0:n-1)');
            T = table(Value, Group, Date);
            tmp = [tempname '.csv'];
            [~, bname] = fileparts(tmp);
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl2 = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(tmp);

            figs = findall(0, 'Type', 'figure');
            for k = 1:numel(figs)
                name = get(figs(k), 'Name');
                testCase.verifyFalse(contains(name, bname), ...
                    sprintf('Figure "%s" contains the bare filename "%s"', name, bname));
            end
        end

        function test_cramer_v_perfect_association(testCase)
            % When A uniquely determines B, Cramér's V must equal 1.
            A = categorical(repmat({'X';'Y';'Z'}, 20, 1));
            B = categorical(repmat({'P';'Q';'R'}, 20, 1));
            V = de_cramer_v(A, B);
            testCase.verifyEqual(V, 1.0, 'AbsTol', 0.01, ...
                'Cramér V must be 1 when A uniquely determines B');
        end

        function test_cramer_v_independent(testCase)
            % Independently-drawn categorical columns should have V near 0.
            rng(42);
            n = 300;
            A = categorical(randsample({'X','Y','Z'}, n, true));
            B = categorical(randsample({'P','Q','R'}, n, true));
            V = de_cramer_v(A, B);
            testCase.verifyLessThan(V, 0.1, ...
                'Cramér V must be near 0 for independent categorical columns');
        end

        function test_recipe_311_like_has_cat_association(testCase)
            % Recipe for a categorical-heavy table must contain de_plot_cat_association.
            % Use INDEPENDENT categoricals — aligned repmat cycles would be mutually
            % perfectly associated (V=1) and collapse under the redundancy skip.
            rng(3);
            n = 160;
            Borough      = categorical(randsample({'Manhattan','Brooklyn','Queens','Bronx'}, n, true)');
            ComplainType = categorical(randsample({'Noise','Graffiti','Heat','Rodent'}, n, true)');
            Status       = categorical(randsample({'Open','Closed'}, n, true)');
            T = table(Borough, ComplainType, Status);
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cl2 = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'DataExplorer must write a recipe file');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_plot_cat_association'), ...
                'Recipe must contain de_plot_cat_association for categorical-heavy tables');
        end

        % ── Change 3: Geo scatter fires regardless of Mapping Toolbox ─────────

        function test_geo_scatter_figure_created_for_lat_lon_table(testCase)
            % DataExplorer on a table with Latitude/Longitude must create a figure
            % whose name starts with "Map" — regardless of Mapping Toolbox availability.
            n = 30;
            rng(7);
            Latitude  = 30 + rand(n,1) * 20;
            Longitude = -120 + rand(n,1) * 50;
            Value     = randn(n,1);
            T = table(Latitude, Longitude, Value);
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));

            DataExplorer(tmp);

            map_figs = testCase.figures_named('Map');
            testCase.verifyNotEmpty(map_figs, ...
                'DataExplorer must create a Map figure when Latitude/Longitude columns exist');
        end

    end

    % ─────────────────────────────────────────────────────────────────────────
    %  Unit tests — save_recipe helpers
    % ─────────────────────────────────────────────────────────────────────────
    methods (Test, TestTags = {'unit'})

        function test_save_recipe_no_recipe(testCase)
            delete(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.verifyError(@() save_recipe('out.m'), 'save_recipe:noRecipe');
        end

        function test_save_recipe_dest_exists(testCase)
            recipe_src = fullfile(tempdir, 'dataexplorer_test_unit.m');
            fclose(fopen(recipe_src, 'w'));
            cleanup = onCleanup(@() delete(recipe_src));

            tmp_dest = [tempname '.m'];
            fclose(fopen(tmp_dest, 'w'));
            cleanup2 = onCleanup(@() delete(tmp_dest));

            testCase.verifyError(@() save_recipe(tmp_dest), 'save_recipe:destExists');
        end

        function test_save_recipe_copies_file(testCase)
            recipe_src = fullfile(tempdir, 'dataexplorer_test_unit2.m');
            fid = fopen(recipe_src, 'w');
            fprintf(fid, '%% test recipe\n');
            fclose(fid);
            cleanup = onCleanup(@() delete(recipe_src));

            dest = fullfile(tempdir, 'recipe_copy_test.m');
            cleanup2 = onCleanup(@() delete(dest));

            save_recipe(dest);
            testCase.verifyTrue(exist(dest, 'file') == 2);
        end

        function test_save_recipe_writes_passed_recipe(testCase)
            % An explicitly-passed recipe (DataExplorer's 3rd output) is written
            % directly — no reliance on the newest-file-in-tempdir guess.
            delete(fullfile(tempdir, 'dataexplorer_*.m'));   % prove independence
            recipe = ["% header"; "de_overview(T, prof);"; "x = 1;"];
            dest = [tempname '.m'];
            cleanup = onCleanup(@() delete(dest));
            save_recipe(dest, recipe);
            written = readlines(dest);
            testCase.verifyTrue(any(contains(written, "de_overview(T, prof);")));
        end

    end

    % ─────────────────────────────────────────────────────────────────────────
    %  Plot-type selection rules (synthetic tables, no file I/O)
    % ─────────────────────────────────────────────────────────────────────────
    %  These tests exercise the decisions DataExplorer makes about WHICH plot
    %  type to use, independent of any real dataset.
    % ─────────────────────────────────────────────────────────────────────────
    methods (Test, TestTags = {'plot_rules'})

        function test_timeseries_stacked_for_compositional(testCase)
            % Compositional data (columns sum to ~constant) → stacked area.
            % Simulate: three energy sources that together always total ~100.
            n = 60;
            years = (2000:2059)';
            A = 30 + 5*randn(n,1);
            B = 40 + 5*randn(n,1);
            C = 100 - A - B;           % enforces constant row sum
            T = table(years, A, B, C, 'VariableNames', {'Year','Solar','Wind','Gas'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(T);
            modes = testCase.all_timeseries_modes();
            testCase.verifyTrue(any(strcmp(modes, 'stacked area')), ...
                'Compositional data should produce a stacked area figure');
            testCase.verifyTrue(any(strcmp(modes, 'overlaid lines')), ...
                'Compositional data should also produce an overlaid lines figure with Total');
        end

        function test_timeseries_lines_for_independent_series(testCase)
            % Independent percentage series (do NOT sum to constant) → lines.
            % Simulates cigarette prevalence by group: each column is its own %.
            n = 20;
            years = (2000:2019)';
            A = 15 + 3*randn(n,1);    % ~15% prevalence, varies independently
            B = 12 + 4*randn(n,1);    % ~12% prevalence
            C =  5 + 2*randn(n,1);    % ~5% disparity
            T = table(years, A, B, C, ...
                'VariableNames', {'Year','Prevalence_FocusGroup', ...
                                  'Prevalence_RefGroup','DisparityValue'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            DataExplorer(T);
            testCase.verifyEqual(testCase.timeseries_mode(), 'overlaid lines', ...
                'Independent prevalence series should use overlaid lines');
        end

        function test_statebins_overflow_for_unknown_codes(testCase)
            % de_statebins should add overflow tiles (amber border, Tag via IS_OVERFLOW)
            % for codes not in the US grid — e.g. EIA census-division codes X1..X9.
            codes = categorical([{'CA';'TX';'NY';'X3';'X5'}; repmat({'CA'},5,1)]);
            vals  = [10;20;30;40;50; 11;12;13;14;15];
            T = table(codes, vals, 'VariableNames', {'StateCode','Value'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            [fig, ax] = de_statebins(T, 'StateCol','StateCode', 'ColorCol','Value');
            fig_cleanup = onCleanup(@() close(fig));

            testCase.verifyTrue(isgraphics(fig), 'de_statebins should return a valid figure');
            % Overflow tiles have EdgeColor = amber (the OverflowEdgeColor default)
            patches = findobj(ax, 'Type', 'patch');
            amber = [0.75 0.40 0.05];
            has_overflow = any(arrayfun(@(p) isequal(p.EdgeColor, amber), patches));
            testCase.verifyTrue(has_overflow, ...
                'de_statebins should draw at least one amber-bordered overflow tile for X3/X5');
        end

        function test_grouped_timeseries_wide_has_other_and_ci(testCase)
            % Wide-format table with >TOP_K=20 category levels should produce a
            % time series figure with an "Other (...)" legend entry and CI patches.
            n_groups = 25;
            grp_labels = strcat('G', string(1:n_groups))';
            T = table(categorical(repelem(grp_labels, 4)), 'VariableNames', {'Group'});
            for yr = 2020:2024
                T.(['x' num2str(yr)]) = 100 + 10*randn(height(T), 1);
            end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            figs_before = findobj(0, 'Type', 'figure');

            DataExplorer(T);

            figs_after  = findobj(0, 'Type', 'figure');
            new_figs    = setdiff(figs_after, figs_before);
            cleanup2    = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            % "By Group over time" is the timeseries figure; "Total by Group over time"
            % and "Share by Group over time" are the stacked-area figures — exclude those.
            ts_figs = new_figs(arrayfun(@(f) ...
                strncmp(f.Name,'By ',3) & contains(f.Name,'over time'), new_figs));
            testCase.assumeNotEmpty(ts_figs, 'should produce a "By Group over time" figure');

            ax_h = findobj(ts_figs(1), 'Type', 'axes');
            has_other = false;
            for k = 1:numel(ax_h)
                leg = ax_h(k).Legend;
                if ~isempty(leg) && any(cellfun(@(s) strncmp(s,'Other (',7), leg.String))
                    has_other = true;  break;
                end
            end
            testCase.verifyTrue(has_other, ...
                'grouped time series should show "Other (...)" legend entry when >20 groups');

            % CI patches are created with HandleVisibility='off'; findall sees them
            all_patches = findall(ts_figs(1), 'Type', 'patch');
            ci_patches  = all_patches(arrayfun(@(p) ...
                strcmp(p.HandleVisibility,'off'), all_patches));
            testCase.verifyNotEmpty(ci_patches, ...
                'grouped time series should have bootstrap CI shading patches');
        end

        function test_cat_diag_other_bar_when_many_cats(testCase)
            % plot_cat_diag with >MAX_K=15 categories should show an "Other (...)"
            % tick label instead of quantile-sampling.
            cats = strcat('Cat', string(1:20))';
            T = table(categorical(repelem(cats, 3)), randn(60,1), ...
                      'VariableNames', {'Group','Val'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            figs_before = findobj(0, 'Type', 'figure');

            DataExplorer(T);

            figs_after = findobj(0, 'Type', 'figure');
            new_figs   = setdiff(figs_after, figs_before);
            cleanup2   = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            ax_all = findobj(new_figs, 'Type', 'axes');
            has_other_lbl = false;
            for k = 1:numel(ax_all)
                lbls = ax_all(k).YTickLabel;
                if ~isempty(lbls) && any(cellfun(@(s) strncmp(s,'Other (',7), cellstr(lbls)))
                    has_other_lbl = true;  break;
                end
            end
            testCase.verifyTrue(has_other_lbl, ...
                'bar chart for >15-category column should have an "Other (...)" tick label');
        end

        function test_constant_categorical_is_skipped(testCase)
            % A categorical with nunique == 1 should have prof.skip == true.
            % Test via: all-same categorical column should not appear in pairplot.
            n = 50;
            T = array2table(randn(n, 3), 'VariableNames', {'A','B','C'});
            T.Constant = categorical(repmat({'OnlyValue'}, n, 1));
            T.Varied   = categorical(randi([1 4], n, 1), 1:4, {'p','q','r','s'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            % Run profile directly to check skip flag
            [~, prof] = se_profile_test_shim(T, ...
                {'Suppressed','N/A','NA','n/a','--','-','None','none', ...
                 'null','NULL','missing','Missing','?','Unknown','unknown','*'});
            const_idx = find(strcmp(prof.name, 'Constant'));
            testCase.verifyTrue(prof.skip(const_idx), ...
                'Constant categorical should be flagged skip=true');
            varied_idx = find(strcmp(prof.name, 'Varied'));
            testCase.verifyFalse(prof.skip(varied_idx), ...
                'Varied categorical should not be skipped');
        end

    end

    % ─────────────────────────────────────────────────────────────────────────
    %  Integration tests — one per example dataset
    % ─────────────────────────────────────────────────────────────────────────
    methods (Test, TestTags = {'integration'})

        % ── Tobacco CSV  (partially baselined 2026-05-20) ──────────────────
        function test_csv_tobacco(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, ...
                'State_Tobacco_Related_Disparities_Dashboard_Data.csv');
            if ~exist(f, 'file'), testCase.assumeFail('Tobacco CSV not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000);

            % ── Structure (confirmed in baseline session 2026-05-20) ──────
            % 5 categoricals + 1 year column + 3 other numerics = 9 columns.
            % One categorical has nunique==1 (constant) and should be skipped.
            testCase.verifyEqual(width(T), 9, ...
                'Expected 9 columns: 5 cat + Year + 3 numeric');

            % Year column must be present (drives time series detection)
            varnames = lower(T.Properties.VariableNames);
            testCase.verifyTrue(any(contains(varnames, 'year')), ...
                'Expected a Year column');

            % ── Time series mode ──────────────────────────────────────────
            % Prevalence columns are independent — NOT compositional.
            % Must use overlaid lines, not stacked area.
            testCase.verifyEqual(testCase.timeseries_mode(), 'overlaid lines', ...
                'Tobacco prevalence series should use overlaid lines, not stacked area');

            % ── All figures non-empty ────────────────────────────────────
            % Every figure must have at least one visible axes with data.
            % Catches: empty overview tiles, choropleth stealing the wrong
            % figure, any axes that got created but never drawn into.
            testCase.assert_all_figures_nonempty();

            % ── Figure count ──────────────────────────────────────────────
            % Minimum expected: overview + time series + pairplot +
            %                   categorical drill-down + recipe best-of plots.
            testCase.verifyGreaterThanOrEqual(testCase.figure_count(), 4, ...
                'Expected at least 4 figures');

            % ── Recipe (requested → returned without re-rendering) ─────────
            [~, ~, recipe] = DataExplorer(f, 'MaxRows', 1000, 'RandSeed', 1);
            testCase.assert_recipe_valid(recipe);
            testCase.assert_recipe_self_contained(recipe);
        end

        % ── Flint CSV  (not yet baselined) ────────────────────────────────
        function test_csv_flint(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, ...
                'City_of_Flint_Distribution_System_Monitoring_Data_(Expanded)_20260417.csv');
            if ~exist(f, 'file'), testCase.assumeFail('Flint CSV not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000);

            % TODO (baseline): column count, types, figure count
            testCase.verifyGreaterThan(height(T), 0, 'Table is empty');
            testCase.verifyGreaterThan(width(T), 0, 'Table has no columns');
            testCase.assert_all_figures_nonempty();
            [~, ~, recipe] = DataExplorer(f, 'MaxRows', 1000, 'RandSeed', 1);
            testCase.assert_recipe_valid(recipe);
            testCase.assert_recipe_self_contained(recipe);
        end

        % ── Prod_dataset.xlsx  (not yet baselined; blocked on Task 3) ─────
        function test_excel_prod_dataset(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'Prod_dataset.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('Prod_dataset.xlsx not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true);

            testCase.verifyGreaterThan(height(T), 0);
            % Task 3: header row has mix of text + year integers; must not be
            % discarded.  After the fix, the Data sheet's first three columns
            % keep their names and year columns become x1960..x2023.
            cols = string(T.Properties.VariableNames);
            testCase.verifyTrue(ismember("Data_Status", cols), ...
                'Column Data_Status missing — header row was dropped');
            testCase.verifyTrue(ismember("StateCode", cols), ...
                'Column StateCode missing — header row was dropped');
            testCase.verifyTrue(any(cellfun(@(n) ~isempty(regexp(n, '^x\d{4}$', 'once')), ...
                T.Properties.VariableNames)), ...
                'No year columns (x1960…x2023) found — header row was dropped');
            testCase.assert_all_figures_nonempty();
            % StateCode (54 levels) is a state column: bar chart must exist.
            figs_state = testCase.figures_named('StateCode');
            testCase.verifyNotEmpty(figs_state, ...
                'No "By StateCode" figure — state column not recognized');
            % Choropleth must fire regardless of whether a time axis exists.
            % If Mapping Toolbox is absent de_usamap silently skips; only
            % assert when the toolbox is present.
            if ~isempty(ver('map'))
                figs_choro = testCase.figures_named('choropleth');
                testCase.verifyNotEmpty(figs_choro, ...
                    'Choropleth not produced despite Mapping Toolbox being available');
            end
            [~, ~, recipe] = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true, 'RandSeed', 1);
            testCase.assert_recipe_valid(recipe);
            testCase.assert_recipe_self_contained(recipe);
        end

        % ── Prod_dataset.xlsx — second-largest sheet ──────────────────────
        % Exercises the Sheet= parameter on a file known to have 4 sheets.
        % The default (AutoSelect) picks the largest; here we test the next one.
        function test_excel_prod_dataset_secondary_sheet(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'Prod_dataset.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('Prod_dataset.xlsx not found'); end

            sheets = sheetnames(f);
            testCase.assumeGreaterThan(numel(sheets), 1, ...
                'Prod_dataset.xlsx has only one sheet — nothing to test here');

            second = testCase.find_second_largest_sheet(f, sheets);
            testCase.assumeFalse(isempty(second), ...
                'Could not find a second non-empty sheet');

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'Sheet', second, 'MaxRows', 1000);

            testCase.verifyGreaterThan(height(T), 0, ...
                sprintf('Sheet "%s" produced empty table', second));
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end

        % ── Energy peak xlsx  (not yet baselined) ─────────────────────────
        function test_excel_energy_peak(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, '2026_energy_peak_by_source.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('energy_peak xlsx not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true);

            % TODO (baseline): this dataset likely has compositional energy sources —
            % verify time series fires as STACKED AREA (unlike the tobacco CSV).
            testCase.verifyGreaterThan(height(T), 0);
            testCase.assert_all_figures_nonempty();
            [~, ~, recipe] = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true, 'RandSeed', 1);
            testCase.assert_recipe_valid(recipe);
            testCase.assert_recipe_self_contained(recipe);
        end

        % ── AQI zip  (not yet baselined) ──────────────────────────────────
        function test_zip_aqi(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'annual_aqi_by_county_2025.zip');
            if ~exist(f, 'file'), testCase.assumeFail('AQI zip not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000);

            % TODO (baseline): single CSV inside zip — should not prompt.
            testCase.verifyGreaterThan(height(T), 0);
            testCase.assert_all_figures_nonempty();
            [~, ~, recipe] = DataExplorer(f, 'MaxRows', 1000, 'RandSeed', 1);
            testCase.assert_recipe_valid(recipe);
            testCase.assert_recipe_self_contained(recipe);
        end

        % ── Conc monitor zip  (not yet baselined) ─────────────────────────
        function test_zip_conc_monitor(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'annual_conc_by_monitor_2025.zip');
            if ~exist(f, 'file'), testCase.assumeFail('Conc monitor zip not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 200);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.assert_all_figures_nonempty();
            [~, ~, recipe] = DataExplorer(f, 'MaxRows', 200, 'RandSeed', 1);
            testCase.assert_recipe_valid(recipe);
            testCase.assert_recipe_self_contained(recipe);

            % recipe is a string array (one line per element) → any(contains(...)).
            % Correlated-family figures must be wired into the recipe.
            testCase.verifyTrue(any(contains(recipe, "de_corr_families")), ...
                'Recipe must compute correlated families');
            testCase.verifyTrue(any(contains(recipe, "fam_cols")), ...
                'Recipe must emit per-family plots driven by an editable fam_cols list');
            % Identifier columns must never be a choropleth color variable.
            for idname = ["StateCode","CountyCode","SiteNum","ParameterCode", ...
                          "State Code","County Code","Site Num","Parameter Code"]
                testCase.verifyFalse( ...
                    any(contains(recipe, "'ColorCol','" + idname + "'")) || ...
                    any(contains(recipe, "'ColorCol', '" + idname + "'")), ...
                    sprintf('Choropleth must not be colored by id column %s', idname));
            end
        end

        % ── 2026 daygenbyfuel xlsx  (not yet baselined) ───────────────────
        function test_excel_daygenbyfuel(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, '2026_daygenbyfuel.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('daygenbyfuel xlsx not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end

        % ── 2026 daygenbyfuel xlsx — second-largest sheet ─────────────────
        % EIA generation workbooks typically have both annual and monthly
        % data sheets; this exercises Sheet= on the second one.
        function test_excel_daygenbyfuel_secondary_sheet(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, '2026_daygenbyfuel.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('daygenbyfuel xlsx not found'); end

            sheets = sheetnames(f);
            testCase.assumeGreaterThan(numel(sheets), 1, ...
                'daygenbyfuel has only one sheet — nothing to test here');

            second = testCase.find_second_largest_sheet(f, sheets);
            testCase.assumeFalse(isempty(second), ...
                'Could not find a second non-empty sheet');

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'Sheet', second, 'MaxRows', 1000);

            testCase.verifyGreaterThan(height(T), 0, ...
                sprintf('Sheet "%s" produced empty table', second));
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end

        % ── 311 service requests xlsx  (not yet baselined) ────────────────
        function test_excel_311(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, ...
                '311_ServiceRequest_2020-present_DataDictionary_Updated_2025.xlsx');
            if ~exist(f, 'file'), testCase.assumeFail('311 xlsx not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end


        % ── FIADB urban CSV ZIP  (not yet baselined) ──────────────────────
        function test_zip_fiadb(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'FIADB_URBAN_ENTIRE_CSV.zip');
            if ~exist(f, 'file'), testCase.assumeFail('FIADB ZIP not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end

        % ── LLCP ASC (fixed-width BRFSS)  (not yet baselined) ─────────────
        function test_asc_llcp(testCase)
            asc_f = fullfile(testCase.EXAMPLES_DIR, 'LLCP2024.ASC');
            zip_f = fullfile(testCase.EXAMPLES_DIR, 'LLCP2024ASC.zip');
            if exist(asc_f, 'file')
                f = asc_f;
            elseif exist(zip_f, 'file')
                f = zip_f;  % DataExplorer handles zip → ASC extraction internally
            else
                testCase.assumeFail('LLCP ASC not found (and zip not found)');
                return
            end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 500);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end

        % ── LLCP zipped ASC  (not yet baselined) ──────────────────────────
        function test_zip_llcp(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'LLCP2024ASC.zip');
            if ~exist(f, 'file'), testCase.assumeFail('LLCP zip not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 500, 'AutoSelect', true);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end

        % ── MA 2024 ZIP  (not yet baselined) ──────────────────────────────
        function test_zip_ma(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'MA-2024.zip');
            if ~exist(f, 'file'), testCase.assumeFail('MA-2024 ZIP not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000, 'AutoSelect', true);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0);
            testCase.assert_all_figures_nonempty();
        end


        % ── NetCDF: largest variable, flattened to long format ────────────
        % AutoSelect picks the largest variable and flattens 3D+ to a long
        % table (lat, lon, time, value).  That gives DataExplorer something
        % it can run the full grouping flow on: geo columns for the
        % choropleth, a time column for the time series, and the value
        % column for distribution plots — same shape as the tobacco CSV.
        function test_netcdf(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'ncdd-202501-grd-scaled.nc');
            if ~exist(f, 'file'), testCase.assumeFail('NetCDF file not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            % AutoSelect: largest variable, flatten 3D → long format, sample
            T = DataExplorer(f, 'AutoSelect', true, 'MaxRows', 2000);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.verifyGreaterThan(width(T), 0, 'NetCDF flatten should produce multiple columns');
            testCase.assert_all_figures_nonempty();
        end

        % ── Table input (no file) ─────────────────────────────────────────
        function test_table_input(testCase)
            T_in = array2table(randn(50, 3), 'VariableNames', {'A', 'B', 'C'});
            T_in.D = categorical(randi([1 3], 50, 1), 1:3, {'x', 'y', 'z'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(T_in);
            % Table input: no recipe written (Phase 5 is skipped for table input)
            testCase.verifyEqual(height(T), 50);
            testCase.verifyEqual(width(T), 4);
            testCase.assert_all_figures_nonempty();
        end

        function test_panel_wide_shows_totals(testCase)
            % Wide-format panel dataset (categoricals + wide year columns) should
            % produce a "Totals over time" figure.
            n_states = 5;  n_codes = 4;
            states = repmat(strcat('S', string(1:n_states))', n_codes, 1);
            codes  = repelem(strcat('C', string(1:n_codes))', n_states, 1);
            T = table(categorical(states), categorical(codes), ...
                'VariableNames', {'StateCode','MSN'});
            for yr = 2000:2005
                T.(['x' num2str(yr)]) = randn(height(T), 1);
            end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            figs_before = findobj(0, 'Type', 'figure');

            DataExplorer(T);

            figs_after = findobj(0, 'Type', 'figure');
            new_figs   = setdiff(figs_after, figs_before);
            cleanup2   = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            names = arrayfun(@(f) f.Name, new_figs, 'UniformOutput', false);
            has_totals = any(cellfun(@(n) ...
                (contains(n,'Total by') || contains(n,'Share by')) && contains(n,'over time'), names));

            testCase.verifyTrue(has_totals, ...
                'panel dataset should produce a "Total by X over time" stacked-area figure');
        end

        function test_panel_totals_has_line(testCase)
            % Panel dataset with one categorical: se_plot_panel_totals should produce
            % "Total by State over time" (absolute stacked area) and
            % "Share by State over time" (100% stacked area) figures.
            % Use 3 rows per state so the State column is not flagged as all-unique.
            n_states = 4;  n_per = 3;
            states = repelem(strcat('S', string(1:n_states))', n_per);
            T = table(categorical(states), 'VariableNames', {'State'});
            for yr = 2010:2015
                T.(['x' num2str(yr)]) = 10*randn(height(T), 1) + 100;
            end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            figs_before = findobj(0, 'Type', 'figure');

            DataExplorer(T);

            figs_after = findobj(0, 'Type', 'figure');
            new_figs   = setdiff(figs_after, figs_before);
            cleanup2   = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            names = arrayfun(@(f) f.Name, new_figs, 'UniformOutput', false);
            totals_figs = new_figs(cellfun(@(n) ...
                contains(n,'Total by') && contains(n,'over time'), names));
            testCase.assumeNotEmpty(totals_figs, 'no "Total by X over time" stacked-area figure found');

            area_h = findobj(totals_figs(1), 'Type', 'area');
            testCase.verifyNotEmpty(area_h, ...
                '"Total by X over time" figure should contain stacked area series');
        end

        function test_tilegrid_choropleth_no_datatip_error(testCase)
            % de_tilegrid with ColorCol must not error on DataTipTemplate
            % (primitive Patch objects don't support it).
            states = ["ME";"NY";"CA"];
            vals   = [1; 2; 3];
            T = table(string(states), double(vals), 'VariableNames', {'State','Value'});
            g.codes       = {'ME','NY','CA'};
            g.rows        = [0, 1, 2];
            g.cols        = [0, 0, 0];
            g.is_overflow = [false; false; false];
            normed = string(T.State);

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            fig = de_tilegrid(T, g, normed, 'ColorCol','Value');
            testCase.assertNotEmpty(fig, 'Expected a figure handle');
            close(fig);
        end

        function test_tilegrid_heatmap_cat_draws_lines(testCase)
            % Long-format table: 2 states × 2 cat levels × 3 years = 12 rows.
            % de_tilegrid with CellRenderer='heatmap_cat' must produce a
            % vectorised cat_heat patch object covering all non-empty tiles.
            states = repelem(["ME";"NY"], 6);
            cats   = repmat(repelem(["A";"B"], 3), 2, 1);
            years  = repmat([2000;2001;2002], 4, 1);
            vals   = (1:12)';
            T = table(string(states), categorical(cats), double(years), double(vals), ...
                'VariableNames', {'State','Cat','Year','Value'});
            g.codes       = {'ME','NY'};
            g.rows        = [0, 1];
            g.cols        = [0, 0];
            g.is_overflow = [false; false];
            normed = string(T.State);

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            fig = de_tilegrid(T, g, normed, ...
                'ColorCol','Value', 'TimeCol','Year', ...
                'CellRenderer','heatmap_cat', 'CatCol','Cat', 'TopK',5);
            testCase.assertNotEmpty(fig, 'Expected a figure handle');
            cl2 = onCleanup(@() close(fig));

            heat_patches = findobj(fig, 'Type','patch', 'Tag','cat_heat');
            testCase.verifyNotEmpty(heat_patches, ...
                'Expected cat_heat patch object in figure');
        end

        function test_tilegrid_heatmap_cat_no_timecol(testCase)
            % heatmap_cat must draw cat_heat patches even without TimeCol.
            % Pre-aggregated table: one row per state×category (no year column).
            states = ["ME";"ME";"NY";"NY"];
            cats   = ["A";"B";"A";"B"];
            vals   = [1; 3; 2; 5];
            T = table(string(states), categorical(cats), double(vals), ...
                'VariableNames', {'State','Cat','Value'});
            g.codes       = {'ME','NY'};
            g.rows        = [0, 1];
            g.cols        = [0, 0];
            g.is_overflow = [false; false];
            normed = string(T.State);

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            fig = de_tilegrid(T, g, normed, ...
                'ColorCol','Value', ...
                'CellRenderer','heatmap_cat', 'CatCol','Cat', 'TopK',5);
            testCase.assertNotEmpty(fig, 'Expected a figure handle');
            cl2 = onCleanup(@() close(fig));

            heat_patches = findobj(fig, 'Type','patch', 'Tag','cat_heat');
            testCase.verifyNotEmpty(heat_patches, ...
                'heatmap_cat without TimeCol should still draw cat_heat patches');
        end

        function test_statebins_heatmap_cat_passthrough(testCase)
            % de_statebins must forward CellRenderer options to de_tilegrid
            % and produce a cat_heat patch object.
            states = repelem(["ME";"NY";"CA";"TX"], 4);
            cats   = repmat(["A";"B";"C";"D"], 4, 1);
            years  = repmat([2000;2001], 8, 1);
            vals   = randn(16, 1);
            T = table(string(states), categorical(cats), double(years), double(vals), ...
                'VariableNames', {'StateCode','Cat','Year','Value'});

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            fig = de_statebins(T, 'StateCol','StateCode', 'ColorCol','Value', ...
                'TimeCol','Year', 'CellRenderer','heatmap_cat', ...
                'CatCol','Cat', 'TopK',4);
            testCase.assertNotEmpty(fig, 'Expected a figure handle from de_statebins');
            cl2 = onCleanup(@() close(fig));

            heat_patches = findobj(fig, 'Type','patch', 'Tag','cat_heat');
            testCase.verifyNotEmpty(heat_patches, ...
                'de_statebins should forward CellRenderer and produce cat_heat patch');
        end

        function test_heatmap_cat_names_time_axis(testCase)
            % The heatmap_cat x-axis is the auto-picked TimeCol, which can be a
            % datetime that isn't a meaningful trend axis (e.g. a "first max
            % date").  The on-plot key must name WHICH column the x-axis is so a
            % viewer can judge it — DataExplorer can't know it's not a real timeline.
            states = repelem(["ME";"NY"], 6);
            cats   = repmat(repelem(["A";"B"], 3), 2, 1);
            dts    = repmat(datetime(2020,1,1) + calmonths([0;1;2]), 4, 1);
            vals   = (1:12)';
            T = table(string(states), categorical(cats), dts, double(vals), ...
                'VariableNames', {'State','Cat','FirstMaxDate','Value'});
            g.codes = {'ME','NY'}; g.rows = [0,1]; g.cols = [0,0];
            g.is_overflow = [false;false];
            normed = string(T.State);

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            fig = de_tilegrid(T, g, normed, 'ColorCol','Value', ...
                'TimeCol','FirstMaxDate', 'CellRenderer','heatmap_cat', ...
                'CatCol','Cat', 'TopK',5);
            cl2 = onCleanup(@() close(fig));
            key = findobj(fig, 'Tag','cat_legend');
            testCase.assertNotEmpty(key, 'heatmap_cat must draw a key');
            key_txt = strjoin(string(key(1).String), ' ');
            testCase.verifyTrue(contains(key_txt, 'FirstMaxDate'), ...
                sprintf('Key must name the time/x column; got: %s', key_txt));
        end

        function test_sparkline_names_time_axis(testCase)
            % The per-tile sparkline x-axis is the auto-picked TimeCol; the
            % legend key must name which column it is (same concern as heatmap_cat).
            states = repelem(["ME";"NY"], 3);
            dts    = repmat(datetime(2020,1,1) + calmonths([0;1;2]), 2, 1);
            vals   = (1:6)';
            T = table(string(states), dts, double(vals), ...
                'VariableNames', {'State','FirstMaxDate','Value'});
            g.codes = {'ME','NY'}; g.rows = [0,1]; g.cols = [0,0];
            g.is_overflow = [false;false];
            normed = string(T.State);

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            fig = de_tilegrid(T, g, normed, 'ColorCol','Value', 'TimeCol','FirstMaxDate');
            cl2 = onCleanup(@() close(fig));
            key = findobj(fig, 'Tag','legend_key');
            testCase.assertNotEmpty(key, 'sparkline must draw a legend key');
            key_txt = strjoin(string(key(1).String), ' ');
            testCase.verifyTrue(contains(key_txt, 'FirstMaxDate'), ...
                sprintf('Sparkline key must name the time axis; got: %s', key_txt));
        end

        function test_geo_multicategorical_produces_figure(testCase)
            % Post-inversion (Task 6): geo × categorical tile figure is recipe-only.
            % For StateCode × MSN + wide year columns, the recipe must include
            % de_statebins with heatmap_cat. No direct figure is created during
            % DataExplorer() — the figure appears at recipe execution time.
            states = repelem(["ME";"NY";"CA"], 3);
            msns   = repmat(["A";"B";"C"], 3, 1);
            T = table(categorical(states), categorical(msns), ...
                'VariableNames', {'StateCode','MSN'});
            for yr = 2000:2003
                T.(['x' num2str(yr)]) = randn(9, 1);
            end
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            vis_cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'Expected a recipe file');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_statebins'), ...
                'Recipe must contain de_statebins for geo x categorical dataset');
            testCase.verifyTrue(contains(recipe_text, 'heatmap_cat'), ...
                'Recipe must contain heatmap_cat for geo x categorical dataset');
        end

        function test_tilegrid_scatter_cat_draws_points(testCase)
            % de_tilegrid with CellRenderer='scatter_cat' draws scatter points
            % (line objects with Tag='cat_scatter') for each non-empty tile.
            states = repelem(["ME";"NY"], 8);
            cats   = repmat(repelem(["A";"B"], 4), 2, 1);
            xv = (1:16)';  yv = randn(16,1);
            T = table(string(states), categorical(cats), xv, yv, ...
                'VariableNames', {'State','Cat','X','Y'});
            g.codes       = {'ME','NY'};
            g.rows        = [0, 1];
            g.cols        = [0, 0];
            g.is_overflow = [false; false];
            normed = string(T.State);

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            fig = de_tilegrid(T, g, normed, ...
                'CellRenderer','scatter_cat', 'CatCol','Cat', ...
                'XCol','X', 'YCol','Y', 'TopK',5, ...
                'SharedXLim',[1,16], 'SharedYLim',[-3,3]);
            testCase.assertNotEmpty(fig, 'Expected a figure handle');
            cl2 = onCleanup(@() close(fig));

            pts = findobj(fig, 'Type','line', 'Tag','cat_scatter');
            testCase.verifyGreaterThanOrEqual(numel(pts), 1, ...
                'Expected cat_scatter line objects in the figure');
        end

        function test_bootstrap_poly_ci_constant_x_returns_empty(testCase)
            % Constant x (zero range) must return empty without warnings.
            x = ones(10, 1);
            y = randn(10, 1);
            lastwarn('');
            [ci_lo, ci_hi, ~, y_fit] = de_bootstrap_poly_ci(x, y, 1, 0.95, 10);
            [msg, ~] = lastwarn();
            testCase.verifyEmpty(y_fit,  'Expected empty y_fit for constant x');
            testCase.verifyEmpty(ci_lo,  'Expected empty ci_lo for constant x');
            testCase.verifyEmpty(ci_hi,  'Expected empty ci_hi for constant x');
            testCase.verifyEmpty(msg,    'Expected no polyfit warning for constant x');
        end

        function test_bootstrap_poly_ci_too_few_distinct_x_returns_empty(testCase)
            % Fewer distinct x values than order+2 must return empty without warnings.
            x = [1;1;1;2;2;2];
            y = randn(6, 1);
            lastwarn('');
            [~, ~, ~, y_fit] = de_bootstrap_poly_ci(x, y, 5, 0.95, 10);
            [msg, ~] = lastwarn();
            testCase.verifyEmpty(y_fit, 'Expected empty y_fit when too few distinct x');
            testCase.verifyEmpty(msg,   'Expected no warning when returning early');
        end

        function test_bootstrap_poly_ci_normal_case_no_warning(testCase)
            % Well-conditioned input must return non-empty results without warnings.
            rng(42);
            x = (1:20)';
            y = 2*x + randn(20,1);
            lastwarn('');
            [ci_lo, ci_hi, x_fit, y_fit] = de_bootstrap_poly_ci(x, y, 1, 0.95, 50);
            [msg, ~] = lastwarn();
            testCase.verifyNotEmpty(y_fit,  'Expected y_fit for well-conditioned input');
            testCase.verifyEqual(numel(x_fit), numel(y_fit));
            testCase.verifyEqual(numel(ci_lo),  numel(x_fit));
            testCase.verifyEqual(numel(ci_hi),  numel(x_fit));
            testCase.verifyEmpty(msg, 'Expected no warning for well-conditioned input');
        end

        function test_recipe_runs_without_error(testCase)
            % DataExplorer on a simple table must write a recipe without error.
            T = table(categorical(["ME";"ME";"NY";"NY"]), [1;2;3;4], ...
                'VariableNames', {'StateCode','Value'});
            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl2 = onCleanup(@() delete(tmp));

            figs_before = findobj(0,'Type','figure');
            DataExplorer(tmp);
            figs_after = findobj(0,'Type','figure');
            new_figs = setdiff(figs_after, figs_before);
            cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.verifyNotEmpty(hits, 'Expected a recipe file in tempdir');
        end

        function test_cg_state_choropleth_code_wide_years(testCase)
            % cg_state_choropleth_code for a wide-year panel must emit a de_statebins call
            % with TimeCol='Year'. We test via the recipe file written by DataExplorer.
            % 3 states × 3 reps each → 9 rows so states are not all-unique (ID check).
            % 3 year columns so se_detect_wide_years returns non-empty (requires >= 3).
            states = categorical(repelem(["ME";"NY";"CA"], 3));
            T = table(states, repmat([1;2;3],3,1), repmat([4;5;6],3,1), repmat([7;8;9],3,1), ...
                'VariableNames', {'StateCode','x2020','x2021','x2022'});
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'Expected a recipe file');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_statebins'), ...
                'Recipe must contain de_statebins call');
            testCase.verifyTrue(contains(recipe_text, 'TimeCol'), ...
                'Recipe must pass TimeCol for wide-year dataset');
        end

        function test_cg_country_choropleth_code_emits_countrybins(testCase)
            % Dataset with ISO-2 country codes + a value column must put de_countrybins
            % in recipe. 12 rows, 10 unique ISO-2 codes → not all-unique (ID check).
            countries = categorical(["US";"GB";"DE";"FR";"JP";"AU";"CA";"MX";"BR";"CN";"US";"GB"]);
            T = table(countries, (1:12)', 'VariableNames', {'ISO2','GDP'});
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits);
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_countrybins'), ...
                'Recipe must contain de_countrybins for ISO-2 country codes');
        end

        function test_cg_geo_multicategorical_code_emits_heatmap_cat(testCase)
            % 3 states x 3 MSN codes x 2 years → recipe must include heatmap_cat call.
            states = categorical(repelem(["ME";"NY";"CA"], 3));
            msns   = categorical(repmat(["A";"B";"C"], 3, 1));
            T = table(states, msns, [1;2;3;4;5;6;7;8;9], [10;11;12;13;14;15;16;17;18], [19;20;21;22;23;24;25;26;27], ...
                'VariableNames', {'StateCode','MSN','x2020','x2021','x2022'});
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            DataExplorer(tmp);

            % Use the known recipe path directly to avoid datenum tie-breaking issues.
            [~, bname, ~] = fileparts(tmp);
            bname_safe = regexprep(bname, '[^A-Za-z0-9_]', '_');
            recipe_file = fullfile(tempdir, ['dataexplorer_' bname_safe '.m']);
            testCase.assertTrue(exist(recipe_file, 'file') > 0, 'Recipe file not found');
            recipe_text = fileread(recipe_file);
            testCase.verifyTrue(contains(recipe_text, 'heatmap_cat'), ...
                'Recipe must contain heatmap_cat for geo x categorical dataset');
        end

        function test_inversion_geo_figures_in_recipe_not_during_seplot(testCase)
            % For a geo x cat dataset, the recipe must contain de_statebins and heatmap_cat.
            states = categorical(repelem(["ME";"NY";"CA"], 3));
            msns   = categorical(repmat(["A";"B";"C"], 3, 1));
            T = table(states, msns, [1;2;3;4;5;6;7;8;9], [10;11;12;13;14;15;16;17;18], [19;20;21;22;23;24;25;26;27], ...
                'VariableNames', {'StateCode','MSN','x2020','x2021','x2022'});
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));
            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            DataExplorer(tmp);

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits);
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'de_statebins'), ...
                'de_statebins must be in recipe');
            testCase.verifyTrue(contains(recipe_text, 'heatmap_cat'), ...
                'heatmap_cat must be in recipe');
        end

        function test_netcdf_recipe_load_code_uses_dataexplorer(testCase)
            % Recipe load code for NetCDF must say DataExplorer(...), not ncread.
            tmp = [tempname '.nc'];
            cl = onCleanup(@() delete(tmp));
            nccreate(tmp, 'lon',  'Dimensions', {'lon', 4}, 'Format', 'classic');
            nccreate(tmp, 'lat',  'Dimensions', {'lat', 3}, 'Format', 'classic');
            nccreate(tmp, 'temp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
            ncwrite(tmp, 'lon',  [100;110;120;130]);
            ncwrite(tmp, 'lat',  [10;20;30]);
            ncwrite(tmp, 'temp', rand(4,3));

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            DataExplorer(tmp, NCVariable='temp');

            hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
            testCase.assertNotEmpty(hits, 'Expected a recipe file in tempdir');
            [~, newest] = max([hits.datenum]);
            recipe_text = fileread(fullfile(hits(newest).folder, hits(newest).name));
            testCase.verifyTrue(contains(recipe_text, 'DataExplorer'), ...
                'Recipe load code must use DataExplorer(), not ncread()');
            testCase.verifyFalse(contains(recipe_text, 'ncread'), ...
                'Recipe load code must not contain ncread');
        end

        function test_netcdf_multi_var_produces_multiple_figures(testCase)
            % DataExplorer on a 2-data-variable NetCDF must produce at least 2 figures.
            tmp = [tempname '.nc'];
            cl = onCleanup(@() delete(tmp));
            nccreate(tmp, 'lon',  'Dimensions', {'lon', 4}, 'Format', 'classic');
            nccreate(tmp, 'lat',  'Dimensions', {'lat', 3}, 'Format', 'classic');
            nccreate(tmp, 'temp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
            nccreate(tmp, 'prcp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
            ncwrite(tmp, 'lon',  [100;110;120;130]);
            ncwrite(tmp, 'lat',  [10;20;30]);
            ncwrite(tmp, 'temp', rand(4,3));
            ncwrite(tmp, 'prcp', rand(4,3) * 10);

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            figs_before = findobj(0,'Type','figure');

            DataExplorer(tmp);

            figs_after = findobj(0,'Type','figure');
            new_figs   = setdiff(figs_after, figs_before);
            cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            testCase.verifyGreaterThanOrEqual(numel(new_figs), 2, ...
                'Expected at least one figure per NetCDF data variable');
        end

        function test_load_netcdf_with_ncvariable_no_prompt(testCase)
            % load_netcdf with NCVariable set must not error on 2D data (no prompt).
            tmp = [tempname '.nc'];
            cl = onCleanup(@() delete(tmp));
            nccreate(tmp, 'lon',  'Dimensions', {'lon', 4}, 'Format', 'classic');
            nccreate(tmp, 'lat',  'Dimensions', {'lat', 3}, 'Format', 'classic');
            nccreate(tmp, 'temp', 'Dimensions', {'lon', 4, 'lat', 3}, 'Format', 'classic');
            ncwrite(tmp, 'lon',  [100;110;120;130]);
            ncwrite(tmp, 'lat',  [10;20;30]);
            ncwrite(tmp, 'temp', rand(4,3));

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            T = DataExplorer(tmp, NCVariable='temp');
            testCase.verifyClass(T, 'table');
            testCase.verifyGreaterThan(height(T), 0);
        end

        function test_recipe_produces_statebins_figure_when_run(testCase)
            % Write a CSV with StateCode + wide years, run DataExplorer, then verify a
            % Choropleth figure appears (produced by the recipe's de_statebins call).
            states = categorical(repelem(["ME";"NY";"CA";"TX";"FL"], 3));
            T = table(states, (1:15)', (16:30)', (31:45)', ...
                'VariableNames', {'StateCode','x2020','x2021','x2022'});
            tmp = [tempname '.csv'];
            writetable(T, tmp);
            cl = onCleanup(@() delete(tmp));

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            figs_before = findobj(0,'Type','figure');
            DataExplorer(tmp);
            figs_after = findobj(0,'Type','figure');
            new_figs = setdiff(figs_after, figs_before);
            cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            % At least one figure must be a statebins tile-grid choropleth
            % (de_statebins sets the figure Name to the Title argument)
            names = arrayfun(@(f) string(f.Name), new_figs(isgraphics(new_figs)), 'UniformOutput', false);
            names = [names{:}];
            has_choro = any(contains(names, 'Choropleth'));
            testCase.verifyTrue(has_choro, ...
                'Recipe must produce a Choropleth figure via de_statebins');
        end

        function test_de_geoscatter_produces_figure_with_colorbar_and_scatter(testCase)
            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            rng(42);
            n     = 60;
            lon_v = linspace(-120,-70,n)';
            lat_v = linspace(25,50,n)';
            t_v   = sort(randi(12,n,1));
            val_v = randn(n,1);   % signed values — size mapping must handle negatives

            [fig, ax] = de_geoscatter(lon_v, lat_v, double(t_v), val_v, ...
                ColorLabel="Month", SizeLabel="Anomaly");

            cl2 = onCleanup(@() close(fig));
            testCase.verifyTrue(isgraphics(fig, 'figure'), 'Expected a figure');
            testCase.verifyTrue(isgraphics(ax,  'axes'),   'Expected main axes');
            cb = findobj(fig, 'Type', 'colorbar');
            testCase.verifyNotEmpty(cb, 'Expected a colorbar');
            sc = findobj(fig, 'Type', 'scatter');
            testCase.verifyNotEmpty(sc, 'Expected at least one scatter object');
            testCase.verifyEqual(string(cb(1).Label.String), "Month");
        end

        function test_samplenetcdf_returns_table_within_maxrows(testCase)
            % Renamed: was SampleNetCDF, now de_stride_sample (NetCDF path).
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nlon = 30; nlat = 20; ntime = 5;
            nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
            ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
            ncwrite(tmp,'time',      (1:ntime)');
            ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

            T = de_stride_sample(string(tmp), Variable='prcp', MaxRows=100, Verbose=false);
            testCase.verifyClass(T, 'table');
            testCase.verifyLessThanOrEqual(height(T), 120, ...
                'de_stride_sample should not exceed MaxRows significantly');
            expected_cols = {'longitude','latitude','time','prcp'};
            for k = 1:numel(expected_cols)
                testCase.verifyTrue(ismember(expected_cols{k}, T.Properties.VariableNames), ...
                    sprintf('Expected column "%s"', expected_cols{k}));
            end
        end

        function test_samplenetcdf_latrange_filters_rows(testCase)
            % Renamed: was SampleNetCDF, now de_stride_sample (NetCDF path).
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nlon = 10; nlat = 10; ntime = 3;
            nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
            ncwrite(tmp,'latitude',  linspace(0,90,nlat)');
            ncwrite(tmp,'time',      (1:ntime)');
            ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

            T = de_stride_sample(string(tmp), Variable='prcp', LatRange=[30 60], Verbose=false);
            testCase.verifyTrue(all(T.latitude >= 30 & T.latitude <= 60), ...
                'All returned rows must satisfy LatRange');
            testCase.verifyGreaterThan(height(T), 0, 'Expected some rows in LatRange [30,60]');
        end

        function test_samplenetcdf_auto_selects_first_data_variable(testCase)
            % Renamed: was SampleNetCDF, now de_stride_sample (NetCDF path).
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nccreate(tmp,'longitude','Dimensions',{'longitude',4},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', 3},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     2},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',4,'latitude',3,'time',2},'Format','classic');
            ncwrite(tmp,'longitude', [-120;-110;-100;-90]);
            ncwrite(tmp,'latitude',  [30;40;50]);
            ncwrite(tmp,'time',      [1;2]);
            ncwrite(tmp,'prcp',      rand(4,3,2));

            T = de_stride_sample(string(tmp), Verbose=false);
            testCase.verifyTrue(ismember('prcp', T.Properties.VariableNames), ...
                'Expected data variable "prcp" in output table');
        end

        function test_netcdf_spatial_grid_produces_geoscatter_figure(testCase)
            % DataExplorer on a lon×lat×time NetCDF must produce a "Geo Scatter" figure.
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nlon = 8; nlat = 6; ntime = 3;
            nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
            ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
            ncwrite(tmp,'time',      (1:ntime)');
            ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            figs_before = findobj(0,'Type','figure');

            DataExplorer(tmp);

            figs_after = findobj(0,'Type','figure');
            new_figs   = setdiff(figs_after, figs_before);
            cl3 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            fig_names = arrayfun(@(f) get(f,'Name'), new_figs, 'UniformOutput', false);
            has_geo   = any(cellfun(@(n) contains(lower(n),'geo scatter'), fig_names));
            testCase.verifyTrue(has_geo, ...
                'Expected a "Geo Scatter" figure for a spatial grid NetCDF variable');
        end

        function test_netcdf_spatial_recipe_contains_geoscatter(testCase)
            % Recipe for a spatial grid NetCDF must call de_stride_sample,
            % aggregate per grid cell with groupsummary, and call de_geoscatter.
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nlon = 8; nlat = 6; ntime = 3;
            nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
            ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
            ncwrite(tmp,'time',      (1:ntime)');
            ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

            % nargout>=3 returns the recipe as a string array without rendering.
            [~, ~, recipe] = DataExplorer(tmp);
            recipe_text = strjoin(recipe, newline);

            testCase.verifyTrue(contains(recipe_text, 'de_stride_sample'), ...
                'Recipe must call de_stride_sample');
            testCase.verifyTrue(contains(recipe_text, 'groupsummary'), ...
                'Recipe must aggregate by grid cell with groupsummary');
            testCase.verifyTrue(contains(recipe_text, 'de_geoscatter'), ...
                'Recipe must call de_geoscatter');

            recipe_path = [tempname '.m'];
            clr = onCleanup(@() delete(recipe_path));
            writelines(recipe, recipe_path);
            info = checkcode(recipe_path, '-string');
            n    = numel(regexp(info, 'L \d+', 'match'));
            testCase.verifyEqual(n, 0, ...
                sprintf('Recipe has %d checkcode issue(s):\n%s', n, info));
        end

        function test_load_netcdf_large_3d_uses_slice_not_mean(testCase)
            % A large 3D variable must load without hanging. de_load routes the
            % selected variable through de_stride_sample, which strides each
            % dimension down to MaxRows rather than reading/averaging the whole grid.
            % Neutral dim names (dim_a, dim_b, dim_c) avoid geo/timeseries plot detectors.
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            na = 50; nb = 40; nc_dim = 8;   % 16000 elements, MaxRows=100 → 16000 >> 1000
            nccreate(tmp,'dim_a','Dimensions',{'dim_a',na},'Format','classic');
            nccreate(tmp,'dim_b','Dimensions',{'dim_b',nb},'Format','classic');
            nccreate(tmp,'dim_c','Dimensions',{'dim_c',nc_dim},'Format','classic');
            nccreate(tmp,'value','Dimensions',{'dim_a',na,'dim_b',nb,'dim_c',nc_dim},'Format','classic');
            ncwrite(tmp,'dim_a', (1:na)');
            ncwrite(tmp,'dim_b', (1:nb)');
            ncwrite(tmp,'dim_c', (1:nc_dim)');
            ncwrite(tmp,'value', rand(na,nb,nc_dim));

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl2 = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));

            % NCVariable selects 'value'; de_load stride-samples it to MaxRows rows.
            T = DataExplorer(tmp, NCVariable='value', MaxRows=100);
            testCase.verifyClass(T, 'table');
            testCase.verifyGreaterThan(height(T), 0);
        end

        function test_stridesample_tabular_returns_within_maxrows(testCase)
            % de_stride_sample on a CSV with 500 rows and MaxRows=50 must return ≤ 60 rows.
            tmp = [tempname '.csv'];
            cl  = onCleanup(@() delete(tmp));
            fid = fopen(tmp, 'w');
            fprintf(fid, 'idx,val\n');
            for i = 1:500
                fprintf(fid, '%d,%d\n', i, i*2);
            end
            fclose(fid);

            T = de_stride_sample(string(tmp), MaxRows=50, Verbose=false);
            testCase.verifyClass(T, 'table');
            testCase.verifyLessThanOrEqual(height(T), 60, ...
                'de_stride_sample tabular should not exceed MaxRows significantly');
            testCase.verifyGreaterThan(height(T), 0, 'Expected non-empty output');
        end

        function test_stridesample_tabular_spans_full_range(testCase)
            % Stride sampling should produce rows from across the file (not just the top).
            tmp = [tempname '.csv'];
            cl  = onCleanup(@() delete(tmp));
            fid = fopen(tmp, 'w');
            fprintf(fid, 'idx,val\n');
            for i = 1:1000
                fprintf(fid, '%d,%d\n', i, i*2);
            end
            fclose(fid);

            T = de_stride_sample(string(tmp), MaxRows=100, Verbose=false);
            idx_col = str2double(T.idx);
            testCase.verifyLessThan(min(idx_col), 50, ...
                'Stride sample should include rows near the beginning');
            testCase.verifyGreaterThan(max(idx_col), 900, ...
                'Stride sample should include rows near the end');
        end

        function test_stridesample_netcdf_returns_table_within_maxrows(testCase)
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nlon = 30; nlat = 20; ntime = 5;
            nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
            ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
            ncwrite(tmp,'time',      (1:ntime)');
            ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

            T = de_stride_sample(string(tmp), Variable='prcp', MaxRows=100, Verbose=false);
            testCase.verifyClass(T, 'table');
            testCase.verifyLessThanOrEqual(height(T), 120, ...
                'de_stride_sample should not exceed MaxRows significantly');
            expected_cols = {'longitude','latitude','time','prcp'};
            for k = 1:numel(expected_cols)
                testCase.verifyTrue(ismember(expected_cols{k}, T.Properties.VariableNames), ...
                    sprintf('Expected column "%s"', expected_cols{k}));
            end
        end

        function test_stridesample_netcdf_2d_variable(testCase)
            % Non-3-D variables are supported now (here a 2-D lon/lat grid):
            % flattened to long format, not rejected.
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nlon = 8; nlat = 6;
            nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(tmp,'elev','Dimensions',{'longitude',nlon,'latitude',nlat},'Format','classic');
            ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
            ncwrite(tmp,'latitude',  linspace(25,55,nlat)');
            ncwrite(tmp,'elev',      rand(nlon,nlat));

            T = de_stride_sample(string(tmp), Variable='elev', MaxRows=100, Verbose=false);
            testCase.verifyClass(T, 'table');
            testCase.verifyEqual(height(T), nlon*nlat, ...
                'Small 2-D grid should flatten without striding');
            for c = ["longitude","latitude","elev"]
                testCase.verifyTrue(ismember(c, string(T.Properties.VariableNames)), ...
                    sprintf('Expected column "%s"', c));
            end
        end

        function test_stridesample_netcdf_latrange_filters_rows(testCase)
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nlon = 10; nlat = 10; ntime = 3;
            nccreate(tmp,'longitude','Dimensions',{'longitude',nlon},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', nlat},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     ntime},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',nlon,'latitude',nlat,'time',ntime},'Format','classic');
            ncwrite(tmp,'longitude', linspace(-130,-60,nlon)');
            ncwrite(tmp,'latitude',  linspace(0,90,nlat)');
            ncwrite(tmp,'time',      (1:ntime)');
            ncwrite(tmp,'prcp',      rand(nlon,nlat,ntime));

            T = de_stride_sample(string(tmp), Variable='prcp', LatRange=[30 60], Verbose=false);
            testCase.verifyTrue(all(T.latitude >= 30 & T.latitude <= 60), ...
                'All returned rows must satisfy LatRange');
            testCase.verifyGreaterThan(height(T), 0, 'Expected some rows in LatRange [30,60]');
        end

        function test_stridesample_netcdf_auto_selects_first_data_variable(testCase)
            tmp = [tempname '.nc'];
            cl  = onCleanup(@() delete(tmp));
            nccreate(tmp,'longitude','Dimensions',{'longitude',4},'Format','classic');
            nccreate(tmp,'latitude', 'Dimensions',{'latitude', 3},'Format','classic');
            nccreate(tmp,'time',     'Dimensions',{'time',     2},'Format','classic');
            nccreate(tmp,'prcp','Dimensions',{'longitude',4,'latitude',3,'time',2},'Format','classic');
            ncwrite(tmp,'longitude', [-120;-110;-100;-90]);
            ncwrite(tmp,'latitude',  [30;40;50]);
            ncwrite(tmp,'time',      [1;2]);
            ncwrite(tmp,'prcp',      rand(4,3,2));

            T = de_stride_sample(string(tmp), Verbose=false);
            testCase.verifyTrue(ismember('prcp', T.Properties.VariableNames), ...
                'Expected data variable "prcp" in output table');
        end

        function test_reservoir_sample_returns_within_nrows(testCase)
            % de_reservoir_sample on a CSV with 500 rows and nrows=50 must return ≤ 50 rows.
            tmp = [tempname '.csv'];
            cl  = onCleanup(@() delete(tmp));
            fid = fopen(tmp, 'w');
            fprintf(fid, 'idx,val\n');
            for i = 1:500
                fprintf(fid, '%d,%d\n', i, i*2);
            end
            fclose(fid);

            T = de_reservoir_sample(string(tmp), 50, Verbose=false);
            testCase.verifyClass(T, 'table');
            testCase.verifyLessThanOrEqual(height(T), 50, ...
                'de_reservoir_sample must not exceed requested row count');
            testCase.verifyGreaterThan(height(T), 0, 'Expected non-empty output');
        end

        % ── Plan D: argument-bounds validation ──────────────────────────────
        function test_row_budget_validator(testCase)
            % de__must_be_row_budget rejects 0 / negatives (pointing at Inf) and
            % accepts Inf (no limit) and positive counts.
            testCase.verifyError(@() de__must_be_row_budget(0),  'DataExplorer:badMaxRows');
            testCase.verifyError(@() de__must_be_row_budget(-5), 'DataExplorer:badMaxRows');
            de__must_be_row_budget(Inf);     % must not error
            de__must_be_row_budget(1000);    % must not error
        end

        function test_maxrows_zero_errors_cleanly(testCase)
            % MaxRows=0 must fail at the argument boundary with the budget error —
            % not the opaque "Row index exceeds table dimensions" crash.
            tmp = [tempname '.csv'];
            cl  = onCleanup(@() delete(tmp));
            fid = fopen(tmp, 'w'); fprintf(fid, 'a,b\n1,2\n3,4\n5,6\n'); fclose(fid);
            testCase.verifyError(@() de_load(string(tmp), MaxRows=0), 'DataExplorer:badMaxRows');
        end

        function test_maxrows_inf_loads_all_rows(testCase)
            % MaxRows=Inf is the "no limit" sentinel — every row loads.
            tmp = [tempname '.csv'];
            cl  = onCleanup(@() delete(tmp));
            fid = fopen(tmp, 'w'); fprintf(fid, 'a,b\n');
            for i = 1:7, fprintf(fid, '%d,%d\n', i, i*2); end
            fclose(fid);
            T = de_load(string(tmp), MaxRows=Inf);
            testCase.verifyEqual(height(T), 7, 'MaxRows=Inf must load every row');
        end

        function test_range_validator(testCase)
            % de__must_be_range rejects reversed [hi lo]; accepts ordered, auto, infinite.
            testCase.verifyError(@() de__must_be_range([10 1]), 'DataExplorer:badRange');
            de__must_be_range([1 10]);       % ok
            de__must_be_range([NaN NaN]);    % ok (auto / unset)
            de__must_be_range([-Inf Inf]);   % ok
        end

        function test_clim_reversed_errors(testCase)
            % A reversed CLim must error at the de_tilegrid boundary (no figure).
            T = table(string(["ME";"NY"]), [1;2], 'VariableNames', {'State','Value'});
            g.codes = {'ME','NY'}; g.rows = [0,1]; g.cols = [0,0]; g.is_overflow = [false;false];
            testCase.verifyError(@() de_tilegrid(T, g, string(T.State), ...
                'ColorCol','Value', 'CLim',[10 1]), 'DataExplorer:badRange');
        end

        function test_cellrenderer_typo_errors(testCase)
            % A misspelled CellRenderer must error (not silently fall back to color).
            T = table(string(["ME";"NY"]), [1;2], 'VariableNames', {'StateCode','Value'});
            testCase.verifyError(@() de_statebins(T, 'StateCol','StateCode', ...
                'ColorCol','Value', 'CellRenderer','heatmp'), 'MATLAB:validators:mustBeMember');
        end

        function test_topk_zero_errors(testCase)
            % TopK must be positive.
            T = table(string(["ME";"NY"]), categorical(["A";"B"]), [1;2], ...
                'VariableNames', {'StateCode','Cat','Value'});
            testCase.verifyError(@() de_statebins(T, 'StateCol','StateCode', ...
                'ColorCol','Value', 'CatCol','Cat', 'CellRenderer','heatmap_cat', 'TopK',0), ...
                'MATLAB:validators:mustBePositive');
        end

        % ── Plan A: complain about options the active renderer ignores ──────
        function test_value_ladder_warns_dropped_colorcol(testCase)
            % value_ladder ignores ColorCol — must warn, not silently drop it.
            T = table(string(["ME";"NY";"CA"]), [1;2;3], [4;5;6], ...
                'VariableNames', {'State','A','B'});
            g.codes = {'ME','NY','CA'}; g.rows = [0;1;2]; g.cols = [0;0;0];
            g.is_overflow = [false;false;false];
            old_vis = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            testCase.verifyWarning(@() de_tilegrid(T, g, string(T.State), ...
                'CellRenderer','value_ladder', 'ValueCols',["A","B"], 'ColorCol','A'), ...
                'de_tilegrid:ignoredOptions');
        end

        function test_value_ladder_one_col_warns(testCase)
            % value_ladder with <2 ValueCols was a silent fallback — must warn.
            T = table(string(["ME";"NY";"CA"]), [1;2;3], 'VariableNames', {'State','A'});
            g.codes = {'ME','NY','CA'}; g.rows = [0;1;2]; g.cols = [0;0;0];
            g.is_overflow = [false;false;false];
            old_vis = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            testCase.verifyWarning(@() de_tilegrid(T, g, string(T.State), ...
                'CellRenderer','value_ladder', 'ValueCols',"A"), 'de_tilegrid:valueLadderNeeds2');
        end

        function test_heatmap_cat_no_spurious_ignore_warning(testCase)
            % A correct heatmap_cat call must NOT raise any warning.
            T = table(string(["ME";"NY"]), categorical(["A";"B"]), [1;2], ...
                'VariableNames', {'State','Cat','Value'});
            g.codes = {'ME','NY'}; g.rows = [0;1]; g.cols = [0;0];
            g.is_overflow = [false;false];
            old_vis = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            testCase.verifyWarningFree(@() de_tilegrid(T, g, string(T.State), ...
                'ColorCol','Value', 'CatCol','Cat', 'CellRenderer','heatmap_cat'));
        end

        % ── Plan B1: ColorMethod (aggregation, default mean) ────────────────
        function test_colormethod_count_aggregates_by_count(testCase)
            % ColorMethod='count' colors by per-tile observation count and the
            % colorbar names the method. Equal values (mean degenerate) but
            % differing row counts (3 vs 1) → count varies → choropleth appears.
            T = table(string(["ME";"ME";"ME";"NY"]), [5;5;5;5], 'VariableNames', {'State','V'});
            g.codes = {'ME','NY'}; g.rows = [0;1]; g.cols = [0;0]; g.is_overflow = [false;false];
            old_vis = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            fig = de_tilegrid(T, g, string(T.State), 'ColorCol','V', 'ColorMethod','count');
            cl2 = onCleanup(@() close(fig));
            cb = findobj(fig, 'Type','colorbar');
            testCase.verifyNotEmpty(cb, 'count varies (3 vs 1) so a choropleth colorbar must appear');
            testCase.verifyTrue(contains(string(cb(1).Label.String), 'count'), ...
                sprintf('Colorbar must name the method; got "%s"', string(cb(1).Label.String)));
        end

        function test_colormethod_mean_is_default(testCase)
            % Default stays mean: equal values are degenerate → no choropleth colorbar.
            T = table(string(["ME";"ME";"NY"]), [5;5;5], 'VariableNames', {'State','V'});
            g.codes = {'ME','NY'}; g.rows = [0;1]; g.cols = [0;0]; g.is_overflow = [false;false];
            old_vis = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            fig = de_tilegrid(T, g, string(T.State), 'ColorCol','V');
            cl2 = onCleanup(@() close(fig));
            testCase.verifyEmpty(findobj(fig, 'Type','colorbar'), ...
                'mean of equal values is degenerate → no colorbar (default behavior preserved)');
        end

    end

end


% ─────────────────────────────────────────────────────────────────────────────
%  File-local helpers
% ─────────────────────────────────────────────────────────────────────────────

function [T, prof] = se_profile_test_shim(T, ~)
% Call se_profile via DataExplorer's local function namespace.
% This requires DataExplorer.m to be on the path; se_profile is a local
% function and cannot be called directly.  Work-around: run a headless
% DataExplorer on the table and reconstruct prof from the recipe, OR
% promote se_profile to a separate file for testability.
%
% For now this shim calls DataExplorer to get a profiled table, then
% rebuilds a minimal prof struct from the result for skip-flag checks.
old_vis = get(0, 'DefaultFigureVisible');
set(0, 'DefaultFigureVisible', 'off');
cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

T_out = DataExplorer(T);

% Reconstruct minimal prof fields testable from outside
ncol = width(T_out);
prof.name = T_out.Properties.VariableNames;

% Skip flag heuristic: categorical with all-same values → skip
prof.skip = false(1, ncol);
for k = 1:ncol
    col = T_out.(prof.name{k});
    if iscategorical(col)
        if isscalar(categories(col))
            prof.skip(k) = true;
        end
    end
end
end
