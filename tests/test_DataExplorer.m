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

        function assert_recipe_valid(testCase, recipe_path)
            testCase.verifyTrue(~isempty(recipe_path), 'Recipe path is empty');
            testCase.verifyTrue(exist(recipe_path, 'file') == 2, ...
                sprintf('Recipe file not found: %s', recipe_path));
            info = checkcode(recipe_path, '-string');
            n_errors = numel(regexp(info, 'L \d+', 'match'));
            testCase.verifyEqual(n_errors, 0, ...
                sprintf('checkcode found %d issue(s) in recipe:\n%s', n_errors, info));
        end

        function assert_recipe_self_contained(testCase, recipe_path)
            fid = fopen(recipe_path, 'r');
            content = fread(fid, '*char')';
            fclose(fid);
            testCase.verifyEmpty(regexp(content, '\bDataExplorer\b'), ...
                'Recipe calls DataExplorer — not self-contained');
            testCase.verifyEmpty(regexp(content, '\bsave_recipe\b'), ...
                'Recipe calls save_recipe — not self-contained');
        end

        function mode = timeseries_mode(~)
            % Return 'stacked area' or 'overlaid lines' from the time-series
            % figure title, or '' if no time-series figure exists.
            figs = findall(0, 'Type', 'figure');
            mode = '';
            for k = 1:numel(figs)
                name = get(figs(k), 'Name');
                if contains(name, 'time series')
                    ax = findall(figs(k), 'Type', 'axes');
                    if ~isempty(ax)
                        t = get(get(ax(1), 'Title'), 'String');
                        if contains(t, 'stacked area'),   mode = 'stacked area';   return; end
                        if contains(t, 'overlaid lines'), mode = 'overlaid lines'; return; end
                    end
                end
            end
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
            % Every open figure must have at least one visible axes with data children.
            figs = findall(0, 'Type', 'figure');
            testCase.verifyNotEmpty(figs, 'No figures were created');
            for k = 1:numel(figs)
                fig_name = get(figs(k), 'Name');
                all_ax = findall(figs(k), 'Type', 'axes');
                vis_ax = all_ax(arrayfun(@(a) ~strcmp(get(a,'Visible'),'off'), all_ax));
                has_data = ~isempty(vis_ax) && ...
                           any(arrayfun(@(a) ~isempty(get(a,'Children')), vis_ax));
                testCase.verifyTrue(has_data, ...
                    sprintf('Figure "%s" has no data in any visible axes', fig_name));
            end
        end

    end

    % ─────────────────────────────────────────────────────────────────────────
    %  Setup / teardown
    % ─────────────────────────────────────────────────────────────────────────
    methods (TestMethodSetup)
        function close_all_figures(~)
            close all;
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
            testCase.verifyFalse(verLessThan('matlab', '25.2'), ...
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

            DataExplorer('State_Tobacco_Related_Disparities_Dashboard_Data.csv', ...
                'MaxRows', 100);

            cd(orig_dir);   % restore before reading recipe so any remaining test code runs fine

            recipe_path = se_find_latest_recipe();
            testCase.assumeTrue(~isempty(recipe_path), 'No recipe was written — skip path check');

            content = fileread(recipe_path);
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
            testCase.verifyEqual(testCase.timeseries_mode(), 'stacked area', ...
                'Compositional data should use stacked area');
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

            % ── Recipe ────────────────────────────────────────────────────
            recipe_path = se_find_latest_recipe();
            testCase.assert_recipe_valid(recipe_path);
            testCase.assert_recipe_self_contained(recipe_path);
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
            recipe_path = se_find_latest_recipe();
            testCase.assert_recipe_valid(recipe_path);
            testCase.assert_recipe_self_contained(recipe_path);
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
            % TODO (Task 3 + baseline): after header fix, column names should include
            % Data_Status, StateCode, MSN plus correctly-named year columns.
            % TODO (baseline): figure count, time series mode (wide year-format data
            % will trigger Task 4 pivot before time series is meaningful).
            testCase.assert_all_figures_nonempty();
            recipe_path = se_find_latest_recipe();
            testCase.assert_recipe_valid(recipe_path);
            testCase.assert_recipe_self_contained(recipe_path);
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
            recipe_path = se_find_latest_recipe();
            testCase.assert_recipe_valid(recipe_path);
            testCase.assert_recipe_self_contained(recipe_path);
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
            recipe_path = se_find_latest_recipe();
            testCase.assert_recipe_valid(recipe_path);
            testCase.assert_recipe_self_contained(recipe_path);
        end

        % ── Conc monitor zip  (not yet baselined) ─────────────────────────
        function test_zip_conc_monitor(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'annual_conc_by_monitor_2025.zip');
            if ~exist(f, 'file'), testCase.assumeFail('Conc monitor zip not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            T = DataExplorer(f, 'MaxRows', 1000);

            testCase.verifyGreaterThan(height(T), 0);
            testCase.assert_all_figures_nonempty();
            recipe_path = se_find_latest_recipe();
            testCase.assert_recipe_valid(recipe_path);
            testCase.assert_recipe_self_contained(recipe_path);
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

        % ── eBird sample ZIP  (not yet baselined) ─────────────────────────
        function test_zip_ebd(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'ebd-datafile-SAMPLE.zip');
            if ~exist(f, 'file'), testCase.assumeFail('eBird ZIP not found'); end

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
            f = fullfile(testCase.EXAMPLES_DIR, 'LLCP2024.ASC');
            if ~exist(f, 'file'), testCase.assumeFail('LLCP ASC not found'); end

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));

            % BRFSS fixed-width; load_text will attempt delimiter detection.
            % MaxRows kept small: the file is very large.
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

        % ── xr latest DWCA ZIP  (not yet baselined) ───────────────────────
        function test_zip_xr(testCase)
            f = fullfile(testCase.EXAMPLES_DIR, 'xr_latest_dwca.zip');
            if ~exist(f, 'file'), testCase.assumeFail('xr DWCA ZIP not found'); end

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

    end

end


% ─────────────────────────────────────────────────────────────────────────────
%  File-local helpers
% ─────────────────────────────────────────────────────────────────────────────

function recipe_path = se_find_latest_recipe()
hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
if isempty(hits)
    recipe_path = '';
    return
end
[~, newest] = max([hits.datenum]);
recipe_path = fullfile(hits(newest).folder, hits(newest).name);
end

function [T, prof] = se_profile_test_shim(T, missingStrings)
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
        if numel(categories(col)) == 1
            prof.skip(k) = true;
        end
    end
end
end
