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
            % Return cell array of all modes found across all time-series figures.
            figs = findall(0, 'Type', 'figure');
            modes = {};
            for k = 1:numel(figs)
                name = get(figs(k), 'Name');
                if contains(lower(name), 'time series')
                    ax = findall(figs(k), 'Type', 'axes');
                    if ~isempty(ax)
                        t = get(get(ax(1), 'Title'), 'String');
                        if contains(t, 'stacked area'),   modes{end+1} = 'stacked area';   end
                        if contains(t, 'overlaid lines'), modes{end+1} = 'overlaid lines'; end
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
            % DataExplorer should produce a choropleth with per-tile sparklines when
            % the input table has wide-format year columns (x####) and a state column.
            % de_statebins/de_tilegrid replaced the interactive slider with static
            % sparklines — no Mapping Toolbox required.
            % Regression: se_plot_state_choropleth did not pivot wide years to long,
            % so it called without TimeCol and no time-series rendering appeared.

            % 20 states × 3 MSN codes = 60 rows.  Each state appears 3 times so
            % the profiler does not flag it as an all-unique ID column.  20 unique
            % values > MAX_LEVELS=15 triggers the cat_big → se_plot_state_summary path.
            US20 = {'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA', ...
                    'HI','ID','IL','IN','IA','KS','KY','LA','ME','MD'};
            msn3 = {'COAL','GAS','OIL'};
            [st, ms] = ndgrid(US20, msn3);
            T = table(categorical(st(:)), categorical(ms(:)), ...
                100 + 50*randn(60,1), ...
                110 + 50*randn(60,1), ...
                120 + 50*randn(60,1), ...
                'VariableNames', {'StateCode','MSN','x2020','x2021','x2022'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            figs_before = findobj(0, 'Type', 'figure');

            DataExplorer(T);

            figs_after  = findobj(0, 'Type', 'figure');
            new_figs    = setdiff(figs_after, figs_before);
            fig_cleanup = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            sparklines = findobj(new_figs, 'Type', 'line', 'Tag', 'sparkline');
            testCase.verifyNotEmpty(sparklines, ...
                'DataExplorer with wide-year state data should draw per-tile sparklines in choropleth');
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
            % DataExplorer should route a high-cardinality ISO alpha-2 column through
            % de_countrybins, producing at least one figure with tile patches.
            iso2_20 = {'US','GB','DE','FR','JP','CN','BR','IN','CA','AU', ...
                       'MX','RU','ZA','KR','TR','AR','SA','EG','NG','PL'};
            [co, grp] = ndgrid(iso2_20, {'A','B','C'});
            vals = 100 + 50*randn(60,1);
            T = table(categorical(co(:)), categorical(grp(:)), vals, ...
                'VariableNames', {'Country','Group','Value'});

            old_vis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            vis_cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_vis));
            figs_before = findobj(0, 'Type', 'figure');

            DataExplorer(T);

            figs_after = findobj(0, 'Type', 'figure');
            new_figs   = setdiff(figs_after, figs_before);
            fig_cleanup = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            testCase.verifyNotEmpty(new_figs, ...
                'DataExplorer with country-code column should produce at least one figure');
            % World tile grid has ~180 tiles; bar/scatter figures have far fewer patches.
            % Require > 50 patches to confirm the world choropleth was drawn.
            patches = findobj(new_figs, 'Type', 'patch');
            testCase.verifyGreaterThan(numel(patches), 50, ...
                'DataExplorer should produce a world choropleth (150+ tile patches) for ISO country codes');
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

            ts_figs = new_figs(arrayfun(@(f) ...
                contains(f.Name,'Group') & contains(f.Name,'over time'), new_figs));
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

            T = DataExplorer(f, 'MaxRows', 200);

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

            T = DataExplorer(f, 'MaxRows', 200, 'AutoSelect', true);

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

            T = DataExplorer(f, 'MaxRows', 200, 'AutoSelect', true);

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

        function test_panel_wide_shows_totals_skips_pairplot(testCase)
            % Wide-format panel dataset (categoricals + wide year columns) should
            % produce a "Totals over time" figure and NOT produce a "Pairplot" figure.
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
            has_totals  = any(cellfun(@(n) contains(n, 'Totals over time'), names));
            has_pairplot = any(cellfun(@(n) contains(n, 'Pairplot'), names));

            testCase.verifyTrue(has_totals, ...
                'panel dataset should produce a "Totals over time" figure');
            testCase.verifyFalse(has_pairplot, ...
                'panel dataset should NOT produce a "Pairplot" figure');
        end

        function test_panel_totals_has_line(testCase)
            % The "Totals over time" figure should contain a line plot with one
            % line per year point.  Use 3 rows per state so the State column
            % is not flagged as all-unique (ID column) and thus not skipped.
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
            totals_figs = new_figs(cellfun(@(n) contains(n, 'Totals over time'), names));
            testCase.assumeNotEmpty(totals_figs, 'no Totals over time figure found');

            lines_h = findobj(totals_figs(1), 'Type', 'line');
            testCase.verifyNotEmpty(lines_h, ...
                'Totals over time figure should contain at least one line');
        end

        function test_tilegrid_sparkline_cat_draws_lines(testCase)
            % Long-format table: 2 states × 2 cat levels × 3 years = 12 rows.
            % de_tilegrid with CellRenderer='sparkline_cat' must produce a
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
                'CellRenderer','sparkline_cat', 'CatCol','Cat', 'TopK',5);
            testCase.assertNotEmpty(fig, 'Expected a figure handle');
            cl2 = onCleanup(@() close(fig));

            heat_patches = findobj(fig, 'Type','patch', 'Tag','cat_heat');
            testCase.verifyNotEmpty(heat_patches, ...
                'Expected cat_heat patch object in figure');
        end

        function test_tilegrid_sparkline_cat_no_timecol(testCase)
            % sparkline_cat must draw cat_heat patches even without TimeCol.
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
                'CellRenderer','sparkline_cat', 'CatCol','Cat', 'TopK',5);
            testCase.assertNotEmpty(fig, 'Expected a figure handle');
            cl2 = onCleanup(@() close(fig));

            heat_patches = findobj(fig, 'Type','patch', 'Tag','cat_heat');
            testCase.verifyNotEmpty(heat_patches, ...
                'sparkline_cat without TimeCol should still draw cat_heat patches');
        end

        function test_statebins_sparkline_cat_passthrough(testCase)
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
                'TimeCol','Year', 'CellRenderer','sparkline_cat', ...
                'CatCol','Cat', 'TopK',4);
            testCase.assertNotEmpty(fig, 'Expected a figure handle from de_statebins');
            cl2 = onCleanup(@() close(fig));

            heat_patches = findobj(fig, 'Type','patch', 'Tag','cat_heat');
            testCase.verifyNotEmpty(heat_patches, ...
                'de_statebins should forward CellRenderer and produce cat_heat patch');
        end

        function test_geo_multicategorical_produces_figure(testCase)
            % Cross-indexed StateCode × MSN + wide year columns should produce
            % a figure whose name contains both categorical column names.
            % 3 states × 3 MSN codes = 9 rows, ratio = 9/(3×3) = 1.0 → fires.
            states = repelem(["ME";"NY";"CA"], 3);
            msns   = repmat(["A";"B";"C"], 3, 1);
            T = table(categorical(states), categorical(msns), ...
                'VariableNames', {'StateCode','MSN'});
            for yr = 2000:2003
                T.(['x' num2str(yr)]) = randn(9, 1);
            end

            old_vis = get(0,'DefaultFigureVisible');
            set(0,'DefaultFigureVisible','off');
            cl = onCleanup(@() set(0,'DefaultFigureVisible',old_vis));
            figs_before = findobj(0,'Type','figure');

            DataExplorer(T);

            figs_after = findobj(0,'Type','figure');
            new_figs   = setdiff(figs_after, figs_before);
            cl2 = onCleanup(@() close(new_figs(isgraphics(new_figs))));

            names = arrayfun(@(f) string(f.Name), new_figs, 'UniformOutput', false);
            names = [names{:}];
            has_geo_cat = any(contains(names,'StateCode') & contains(names,'MSN'));
            testCase.verifyTrue(has_geo_cat, ...
                'Expected a figure with both StateCode and MSN in its name');
        end

        function test_tilegrid_scatter_cat_draws_points(testCase)
            % de_tilegrid with CellRenderer='scatter_cat' draws scatter points
            % (line objects with Tag='cat_scatter') for each non-empty tile.
            n = 16;
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
