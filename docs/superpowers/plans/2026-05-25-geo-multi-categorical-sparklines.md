# Geo × Categorical × Numeric — Multi-Dimensional Tile Figures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a static geographic tile-grid figure (de_statebins / de_countrybins layout) where each state/country cell contains per-category sparklines (when time data exists) or a scatter (when multiple numerics exist but no time axis), firing automatically when two categoricals cross-index the rows and one is geographic.

**Architecture:** Extend de_tilegrid with a `CellRenderer` option that drives new per-tile drawing modes. de_statebins and de_countrybins pass the new options through unchanged. A new `se_plot_geo_multicategorical` function in DataExplorer.m handles detection and dispatch.

**Tech Stack:** MATLAB R2025b. matlab.unittest for tests (run via pytest harness: `pytest -m slow -k <name>`). No new dependencies.

---

## File Map

| File | Change |
|------|--------|
| `de_tilegrid.m` | New options: `CellRenderer`, `CatCol`, `TopK`, `SharedYLim`, `CatColors`, `XCol`, `YCol`, `SharedXLim`. New rendering branches for `sparkline_cat` and `scatter_cat`. |
| `de_statebins.m` | Add same new options; pass through to `de_tilegrid`. Relax `ColorCol` requirement when `CellRenderer != 'color'`. |
| `de_countrybins.m` | Same passthrough changes as de_statebins. |
| `DataExplorer.m` | New `se_plot_geo_multicategorical` function. Detection logic before the `cat_big` loop (~line 2823). |
| `tests/test_DataExplorer.m` | Four new test methods added inside the `methods (Test)` block (before the `end` at line 1162). |

---

## Task 1: `CellRenderer='sparkline_cat'` in de_tilegrid

**Files:**
- Modify: `de_tilegrid.m:33-42` (arguments block), `:58` (after has_choro), `:106` (after Heat matrix), `:202` (suppress existing sparkline), `:229` (new drawing section)
- Test: `tests/test_DataExplorer.m:1161` (insert before `end` of methods block)

- [ ] **Step 1: Write the failing test**

Insert this method before line 1161 (the `end` that closes the `methods (Test)` block):

```matlab
        function test_tilegrid_sparkline_cat_draws_lines(testCase)
            % Long-format table: 2 states × 2 cat levels × 3 years = 12 rows.
            % de_tilegrid with CellRenderer='sparkline_cat' must draw at least
            % one 'cat_spark' line per non-empty tile.
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

            lines_cat = findobj(fig, 'Type','line', 'Tag','cat_spark');
            testCase.verifyGreaterThanOrEqual(numel(lines_cat), 2, ...
                'Expected cat_spark lines for each non-empty tile');
        end
```

- [ ] **Step 2: Run test to verify it fails**

```
pytest -m slow -k test_tilegrid_sparkline_cat_draws_lines -v
```

Expected: FAIL — error in de_tilegrid about unrecognised option `CellRenderer`.

- [ ] **Step 3: Add new options to de_tilegrid arguments block**

In `de_tilegrid.m`, replace lines 35–42:

```matlab
    options.ColorCol          (1,1) string  = ""
    options.TimeCol           (1,1) string  = ""
    options.Title             (1,1) string  = ""
    options.Colormap                        = 'parula'
    options.OverflowEdgeColor (1,3) double  = [0.75 0.40 0.05]
    options.MapLabel          (1,1) string  = "Map"
    options.FontSize          (1,1) double  = 7
end
```

with:

```matlab
    options.ColorCol          (1,1) string  = ""
    options.TimeCol           (1,1) string  = ""
    options.Title             (1,1) string  = ""
    options.Colormap                        = 'parula'
    options.OverflowEdgeColor (1,3) double  = [0.75 0.40 0.05]
    options.MapLabel          (1,1) string  = "Map"
    options.FontSize          (1,1) double  = 7
    options.CellRenderer      (1,1) string  = "color"
    options.CatCol            (1,1) string  = ""
    options.TopK              (1,1) double  = 5
    options.SharedYLim        (1,2) double  = [NaN NaN]
    options.CatColors                       = []
end
```

- [ ] **Step 4: Add `is_sparkline_cat` flag after `has_choro`**

After line 58 (`has_choro = has_color && ...`), add:

```matlab
is_sparkline_cat = options.CellRenderer == "sparkline_cat" && ...
    options.CatCol ~= "" && ismember(options.CatCol, varnames) && ...
    options.ColorCol ~= "" && ismember(options.ColorCol, varnames) && ...
    has_time && numel(normed) == height(T) && height(T) > 0;
```

- [ ] **Step 5: Add multi-category data aggregation after the Heat matrix block**

After line 106 (`end` of the `if has_choro` block, just before `vmin = min(Heat...)`), add:

```matlab
%% ── Multi-category sparkline data ────────────────────────────────────────────
multi_heat = []; top_cat_levels = {}; cat_colors_mat = [];
sh_lo = NaN; sh_hi = NaN; K = 0;
if is_sparkline_cat
    ydata_sc   = double(T.(char(options.ColorCol)));
    tdata_sc   = T.(char(options.TimeCol));
    if ~isa(tdata_sc,'datetime'), tdata_sc = double(tdata_sc); end
    cat_col_sc = categorical(string(T.(char(options.CatCol))));
    all_lv     = cellstr(categories(cat_col_sc));
    cnt_lv     = countcats(cat_col_sc);
    [~, ord_lv] = sort(cnt_lv,'descend');
    K           = min(options.TopK, numel(all_lv));
    top_cat_levels = all_lv(ord_lv(1:K));

    multi_heat = NaN(n_tiles, n_t, K);
    for ti = 1:n_tiles
        s_mask = normed == CODES{ti};
        if ~any(s_mask), continue; end
        for ki = 1:K
            k_mask = cat_col_sc == top_cat_levels{ki};
            for tt = 1:n_t
                v_ki = ydata_sc(s_mask & k_mask & (tdata_sc == t_vals(tt)));
                v_ki = v_ki(~isnan(v_ki));
                if ~isempty(v_ki), multi_heat(ti,tt,ki) = mean(v_ki); end
            end
        end
    end

    if ~isempty(options.CatColors) && size(options.CatColors,1) >= K
        cat_colors_mat = options.CatColors(1:K,:);
    else
        cat_colors_mat = lines(K);
    end
    if all(isnan(options.SharedYLim))
        sh_lo = min(multi_heat(:),[],'omitnan');
        sh_hi = max(multi_heat(:),[],'omitnan');
    else
        sh_lo = options.SharedYLim(1);
        sh_hi = options.SharedYLim(2);
    end
end
```

- [ ] **Step 6: Suppress the existing single sparkline when `is_sparkline_cat`**

Find the line `if has_spark && has_choro` (line 202) and change to:

```matlab
if has_spark && has_choro && ~is_sparkline_cat
```

Also find the legend key block two lines below it `if has_spark && has_choro` (line 230) and apply the same change:

```matlab
if has_spark && has_choro && ~is_sparkline_cat
```

- [ ] **Step 7: Add category sparkline drawing after the legend key block**

After the `end` of the legend key block (line 239), before `%% ── Datacursor`, add:

```matlab
%% ── Category sparklines (CellRenderer='sparkline_cat') ──────────────────────
if is_sparkline_cat && K > 0 && ~isnan(sh_lo) && sh_lo < sh_hi
    tile_h   = 1 - 2*GAP;
    SPARK_MX = 0.10;
    x_ticks  = linspace(0, 1, n_t);
    for ti = 1:n_tiles
        if all(isnan(multi_heat(ti,:,:)),'all'), continue; end
        r = ROWS(ti); c = COLS(ti);
        spark_y_top = r + GAP + (1 - SPARK_FRAC) * tile_h;
        spark_y_bot = r + 1 - GAP - 0.01;
        x_spark = c + GAP + SPARK_MX + x_ticks * (tile_h - 2*SPARK_MX);
        for ki = 1:K
            hr = multi_heat(ti,:,ki);
            if all(isnan(hr)), continue; end
            y_norm  = (hr - sh_lo) / (sh_hi - sh_lo);
            y_s     = spark_y_bot - y_norm * (spark_y_bot - spark_y_top);
            y_s(isnan(hr)) = NaN;
            line(ax, x_spark, y_s, 'Color', cat_colors_mat(ki,:), ...
                'LineWidth', 1.0, 'Tag', 'cat_spark');
        end
    end
    leg_h = gobjects(K, 1);
    for ki = 1:K
        leg_h(ki) = line(nan, nan, 'Parent', ax, ...
            'Color', cat_colors_mat(ki,:), 'LineWidth', 1.5, ...
            'DisplayName', top_cat_levels{ki});
    end
    legend(leg_h, 'Location','southeast', 'FontSize', 6, 'Interpreter','none');
end
```

- [ ] **Step 8: Run test to verify it passes**

```
pytest -m slow -k test_tilegrid_sparkline_cat_draws_lines -v
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add de_tilegrid.m tests/test_DataExplorer.m
git commit -m "feat(de_tilegrid): add CellRenderer=sparkline_cat for per-tile category sparklines"
```

---

## Task 2: Pass new options through de_statebins and de_countrybins

**Files:**
- Modify: `de_statebins.m:53-63` (arguments block), `:151-157` (de_tilegrid call)
- Modify: `de_countrybins.m` — same two sections (find matching arguments block and de_tilegrid call)
- Test: `tests/test_DataExplorer.m:1161`

- [ ] **Step 1: Write the failing test**

Insert before line 1161 in `tests/test_DataExplorer.m`:

```matlab
        function test_statebins_sparkline_cat_passthrough(testCase)
            % de_statebins must forward CellRenderer options to de_tilegrid
            % and produce cat_spark lines identical to calling de_tilegrid directly.
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

            lines_cat = findobj(fig, 'Type','line', 'Tag','cat_spark');
            testCase.verifyGreaterThanOrEqual(numel(lines_cat), 2, ...
                'de_statebins should forward CellRenderer and produce cat_spark lines');
        end
```

- [ ] **Step 2: Run test to verify it fails**

```
pytest -m slow -k test_statebins_sparkline_cat_passthrough -v
```

Expected: FAIL — unrecognised option `CellRenderer` in de_statebins.

- [ ] **Step 3: Add new options to de_statebins arguments block**

In `de_statebins.m`, after `options.Aliases = []` (line 62), before `end` (line 63), add:

```matlab
    options.CellRenderer      (1,1) string  = "color"
    options.CatCol            (1,1) string  = ""
    options.TopK              (1,1) double  = 5
    options.SharedYLim        (1,2) double  = [NaN NaN]
    options.CatColors                       = []
```

- [ ] **Step 4: Update the de_tilegrid call in de_statebins**

Replace lines 151–157:

```matlab
[fig, ax] = de_tilegrid(T, g, normed, ...
    'ColorCol',  options.ColorCol, ...
    'TimeCol',   options.TimeCol, ...
    'Title',     options.Title, ...
    'Colormap',  options.Colormap, ...
    'MapLabel',  'States', ...
    'FontSize',  7);
```

with:

```matlab
[fig, ax] = de_tilegrid(T, g, normed, ...
    'ColorCol',      options.ColorCol, ...
    'TimeCol',       options.TimeCol, ...
    'Title',         options.Title, ...
    'Colormap',      options.Colormap, ...
    'MapLabel',      'States', ...
    'FontSize',      7, ...
    'CellRenderer',  options.CellRenderer, ...
    'CatCol',        options.CatCol, ...
    'TopK',          options.TopK, ...
    'SharedYLim',    options.SharedYLim, ...
    'CatColors',     options.CatColors);
```

- [ ] **Step 5: Apply the same two changes to de_countrybins**

Open `de_countrybins.m`. Find its arguments block and its `de_tilegrid` call. Add the same five new options to the arguments block, and the same five keyword arguments to the `de_tilegrid` call. (The exact line numbers differ; find by searching for `options.Colormap` and `de_tilegrid(` in that file.)

- [ ] **Step 6: Run test to verify it passes**

```
pytest -m slow -k test_statebins_sparkline_cat_passthrough -v
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add de_statebins.m de_countrybins.m tests/test_DataExplorer.m
git commit -m "feat(de_statebins, de_countrybins): pass through CellRenderer sparkline_cat options"
```

---

## Task 3: Detection + `se_plot_geo_multicategorical` in DataExplorer.m

**Files:**
- Modify: `DataExplorer.m:2823` (detection block before `cat_big` loop)
- Modify: `DataExplorer.m` (add `se_plot_geo_multicategorical` function before `end % se_plot_categorical_drilldown` or after `se_pivot_wide_to_long`)
- Test: `tests/test_DataExplorer.m:1161`

- [ ] **Step 1: Write the failing test**

Insert before line 1161 in `tests/test_DataExplorer.m`:

```matlab
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
```

- [ ] **Step 2: Run test to verify it fails**

```
pytest -m slow -k test_geo_multicategorical_produces_figure -v
```

Expected: FAIL — no figure with both column names is produced.

- [ ] **Step 3: Add detection block in the drill-down section**

In `DataExplorer.m`, immediately before the comment `% High-cardinality categoricals: geo treatment OR top-K drill-down with Other` (~line 2823), insert:

```matlab
%% ── Cross-indexed geo × categorical: sparklines or scatter per tile ──────────
geo_cats   = cat_big(arrayfun(@(ci) ...
    se_looks_like_states(prof,ci,T) || se_looks_like_countries(prof,ci,T), cat_big));
other_cats = [cat_useful(:)', cat_big(~ismember(cat_big, geo_cats))'];
for gi = 1:numel(geo_cats)
    geo_ci = geo_cats(gi);
    for oi = 1:numel(other_cats)
        other_ci = other_cats(oi);
        n_geo    = prof.nunique(geo_ci);
        n_other  = prof.nunique(other_ci);
        ratio    = height(T) / (n_geo * n_other);
        if ratio >= 0.5 && ratio <= 1.5
            num_plot = unique([ts_num(:)', sel_num(:)'], 'stable');
            if ~isempty(wide_yr_idxs) || numel(num_plot) >= 2
                se_plot_geo_multicategorical(T, prof, geo_ci, other_ci, ...
                    wide_yr_idxs, wide_yr_vals, num_plot);
            end
        end
    end
end
```

- [ ] **Step 4: Add `se_plot_geo_multicategorical` function**

Add this function to `DataExplorer.m` after `se_pivot_wide_to_long` (~line 3482):

```matlab
% ── se_plot_geo_multicategorical ──────────────────────────────────────────────
function se_plot_geo_multicategorical(T, prof, geo_idx, cat_idx, yr_idxs, yr_vals, num_idxs)
%SE_PLOT_GEO_MULTICATEGORICAL  Tile-grid figure with per-tile category sparklines or scatter.
%   Fires when a geo categorical and another categorical cross-index the dataset rows.
geo_name  = prof.name{geo_idx};
cat_name  = prof.name{cat_idx};
is_states = se_looks_like_states(prof, geo_idx, T);

% Top-K category levels by row frequency
cat_col  = T.(cat_name);
cat_levs = cellstr(categories(cat_col));
cnt_levs = countcats(cat_col);
[~, ord] = sort(cnt_levs,'descend');
K        = min(5, numel(cat_levs));
top_levs = cat_levs(ord(1:K));

if ~isempty(yr_idxs)
    T_long  = se_pivot_wide_to_long(T, prof, yr_idxs, yr_vals);
    T_plot  = T_long(ismember(string(T_long.(cat_name)), string(top_levs)), :);
    ydata_v = T_plot.Value(~isnan(T_plot.Value));
    if isempty(ydata_v), return; end
    sh_ylim   = [min(ydata_v), max(ydata_v)];
    title_str = sprintf('%s \x00D7 %s: Value over time', geo_name, cat_name);
    fprintf('  Geo \x00D7 categorical sparklines: %s\n', title_str);
    if is_states
        de_statebins(T_plot, 'StateCol',geo_name, 'ColorCol','Value', ...
            'TimeCol','Year', 'CellRenderer','sparkline_cat', 'CatCol',cat_name, ...
            'TopK',K, 'SharedYLim',sh_ylim, 'Title',title_str);
    else
        de_countrybins(T_plot, 'CountryCol',geo_name, 'ColorCol','Value', ...
            'TimeCol','Year', 'CellRenderer','sparkline_cat', 'CatCol',cat_name, ...
            'TopK',K, 'SharedYLim',sh_ylim, 'Title',title_str);
    end

elseif numel(num_idxs) >= 2
    num1_name = prof.name{num_idxs(1)};
    num2_name = prof.name{num_idxs(2)};
    T_plot    = T(ismember(string(T.(cat_name)), string(top_levs)), :);
    xd = T_plot.(num1_name)(~isnan(T_plot.(num1_name)));
    yd = T_plot.(num2_name)(~isnan(T_plot.(num2_name)));
    if isempty(xd) || isempty(yd), return; end
    sh_xlim   = [min(xd), max(xd)];
    sh_ylim   = [min(yd), max(yd)];
    title_str = sprintf('%s \x00D7 %s: %s vs %s', geo_name, cat_name, num1_name, num2_name);
    fprintf('  Geo \x00D7 categorical scatter: %s\n', title_str);
    if is_states
        de_statebins(T_plot, 'StateCol',geo_name, 'CellRenderer','scatter_cat', ...
            'CatCol',cat_name, 'XCol',num1_name, 'YCol',num2_name, ...
            'SharedXLim',sh_xlim, 'SharedYLim',sh_ylim, 'Title',title_str);
    else
        de_countrybins(T_plot, 'CountryCol',geo_name, 'CellRenderer','scatter_cat', ...
            'CatCol',cat_name, 'XCol',num1_name, 'YCol',num2_name, ...
            'SharedXLim',sh_xlim, 'SharedYLim',sh_ylim, 'Title',title_str);
    end
end
end
```

Note: `\x00D7` is the UTF-8 × character; MATLAB R2025b handles it in `sprintf` strings. If it renders incorrectly, replace with the literal character `×` or just ` x `.

- [ ] **Step 5: Run test to verify it passes**

```
pytest -m slow -k test_geo_multicategorical_produces_figure -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DataExplorer.m tests/test_DataExplorer.m
git commit -m "feat(DataExplorer): detect cross-indexed geo×cat pairs and plot per-tile sparklines"
```

---

## Task 4: `CellRenderer='scatter_cat'` in de_tilegrid + wiring

**Files:**
- Modify: `de_tilegrid.m` — add `XCol`, `YCol`, `SharedXLim` options; add `is_scatter_cat` flag; add scatter drawing section
- Modify: `de_statebins.m` — add `XCol`, `YCol`, `SharedXLim` options; relax ColorCol requirement; pass through to de_tilegrid
- Modify: `de_countrybins.m` — same changes as de_statebins
- Test: `tests/test_DataExplorer.m:1161`

- [ ] **Step 1: Write the failing test**

Insert before line 1161 in `tests/test_DataExplorer.m`:

```matlab
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
```

- [ ] **Step 2: Run test to verify it fails**

```
pytest -m slow -k test_tilegrid_scatter_cat_draws_points -v
```

Expected: FAIL — unrecognised option `XCol`.

- [ ] **Step 3: Add scatter options to de_tilegrid arguments block**

After the `options.CatColors` line added in Task 1, add:

```matlab
    options.XCol              (1,1) string  = ""
    options.YCol              (1,1) string  = ""
    options.SharedXLim        (1,2) double  = [NaN NaN]
```

- [ ] **Step 4: Add `is_scatter_cat` flag alongside `is_sparkline_cat`**

After the `is_sparkline_cat = ...` line (added in Task 1, Step 4), add:

```matlab
is_scatter_cat = options.CellRenderer == "scatter_cat" && ...
    options.CatCol ~= "" && ismember(options.CatCol, varnames) && ...
    options.XCol ~= "" && ismember(options.XCol, varnames) && ...
    options.YCol ~= "" && ismember(options.YCol, varnames) && ...
    numel(normed) == height(T) && height(T) > 0;
```

- [ ] **Step 5: Add scatter data preparation after the multi_heat block**

After the `end` of the `if is_sparkline_cat` block (end of Task 1 Step 5 addition), add:

```matlab
%% ── Scatter cat data ─────────────────────────────────────────────────────────
xdata_sc2 = []; ydata_sc2 = []; cat_col_sc2 = categorical([]);
sh_xlim = [NaN NaN];
if is_scatter_cat
    xdata_sc2  = double(T.(char(options.XCol)));
    ydata_sc2  = double(T.(char(options.YCol)));
    cat_col_sc2 = categorical(string(T.(char(options.CatCol))));
    all_lv2    = cellstr(categories(cat_col_sc2));
    cnt_lv2    = countcats(cat_col_sc2);
    [~, ord2]  = sort(cnt_lv2,'descend');
    K2         = min(options.TopK, numel(all_lv2));
    top_cat_levels = all_lv2(ord2(1:K2));
    if ~isempty(options.CatColors) && size(options.CatColors,1) >= K2
        cat_colors_mat = options.CatColors(1:K2,:);
    else
        cat_colors_mat = lines(K2);
    end
    K = K2;
    if all(isnan(options.SharedXLim))
        sh_xlim = [min(xdata_sc2,[],'omitnan'), max(xdata_sc2,[],'omitnan')];
    else
        sh_xlim = options.SharedXLim;
    end
    if all(isnan(options.SharedYLim))
        sh_lo = min(ydata_sc2,[],'omitnan');
        sh_hi = max(ydata_sc2,[],'omitnan');
    else
        sh_lo = options.SharedYLim(1);
        sh_hi = options.SharedYLim(2);
    end
end
```

- [ ] **Step 6: Add scatter drawing section**

After the category sparklines block (end of Task 1 Step 7 addition, before `%% ── Datacursor`), add:

```matlab
%% ── Category scatter (CellRenderer='scatter_cat') ───────────────────────────
if is_scatter_cat && K > 0 && ~isnan(sh_lo) && sh_lo < sh_hi && ...
        ~isnan(sh_xlim(1)) && sh_xlim(1) < sh_xlim(2)
    tile_w = 1 - 2*GAP;
    for ti = 1:n_tiles
        s_mask = normed == CODES{ti};
        if ~any(s_mask), continue; end
        r = ROWS(ti);  c = COLS(ti);
        for ki = 1:K
            k_mask = cat_col_sc2 == top_cat_levels{ki};
            pts = s_mask & k_mask & ~isnan(xdata_sc2) & ~isnan(ydata_sc2);
            if ~any(pts), continue; end
            xn = (xdata_sc2(pts) - sh_xlim(1)) / (sh_xlim(2) - sh_xlim(1));
            yn = (ydata_sc2(pts) - sh_lo)      / (sh_hi - sh_lo);
            x_plot = c + GAP + xn * tile_w;
            y_plot = r + GAP + (1 - yn) * tile_w;
            line(ax, x_plot, y_plot, 'Color', cat_colors_mat(ki,:), ...
                'LineStyle','none', 'Marker','.', 'MarkerSize', 4, ...
                'Tag', 'cat_scatter');
        end
    end
    leg_h = gobjects(K,1);
    for ki = 1:K
        leg_h(ki) = line(nan, nan, 'Parent', ax, ...
            'Color', cat_colors_mat(ki,:), 'LineWidth', 1.5, ...
            'DisplayName', top_cat_levels{ki}, ...
            'LineStyle','none', 'Marker','.');
    end
    legend(leg_h, 'Location','southeast', 'FontSize',6, 'Interpreter','none');
end
```

- [ ] **Step 7: Add `XCol`, `YCol`, `SharedXLim` to de_statebins and de_countrybins**

In `de_statebins.m`, after the `options.CatColors` line (added in Task 2), add:

```matlab
    options.XCol              (1,1) string  = ""
    options.YCol              (1,1) string  = ""
    options.SharedXLim        (1,2) double  = [NaN NaN]
```

Also relax the ColorCol validation. Find:

```matlab
if options.StateCol == "" || ~ismember(options.StateCol, varnames) || ...
   options.ColorCol == ""
```

Replace with:

```matlab
needs_color = options.CellRenderer == "color" || options.CellRenderer == "sparkline_cat";
if options.StateCol == "" || ~ismember(options.StateCol, varnames) || ...
   (needs_color && options.ColorCol == "")
```

Add the three new options to the `de_tilegrid` call in de_statebins:

```matlab
    'XCol',          options.XCol, ...
    'YCol',          options.YCol, ...
    'SharedXLim',    options.SharedXLim, ...
```

Apply the same three changes to `de_countrybins.m`.

- [ ] **Step 8: Run test to verify it passes**

```
pytest -m slow -k test_tilegrid_scatter_cat_draws_points -v
```

Expected: PASS.

- [ ] **Step 9: Run the full relevant test set**

```
pytest -m slow -k "sparkline_cat or scatter_cat or geo_multicategorical" -v
```

Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add de_tilegrid.m de_statebins.m de_countrybins.m tests/test_DataExplorer.m
git commit -m "feat: add scatter_cat cell renderer; complete geo×categorical tile figures"
```

---

## Self-Review Notes

- **Spec coverage:** Detection logic ✓, sparkline_cat renderer ✓, scatter_cat renderer ✓, de_statebins/de_countrybins passthrough ✓, se_plot_geo_multicategorical ✓, no sliders ✓, shared y-limits ✓, interestingness-ranked top-K ✓ (uses frequency proxy; full interestingness ranker from Task 6 is a future improvement).
- **Non-geo case:** Explicitly deferred per design — no task here.
- **`top_cat_levels` variable:** Defined in the sparkline_cat block in Task 1 and reused in the scatter_cat block in Task 4. Both blocks guard on their respective `is_*` flag so there's no conflict; both set `top_cat_levels` and `cat_colors_mat` independently.
- **`SPARK_FRAC`:** Always defined unconditionally in de_tilegrid before the drawing loop (line 143), so it's safely accessible in the new sparkline_cat block.
- **`\x00D7` in sprintf:** If this causes issues in MATLAB, replace with the literal `×` character or ` x `.
