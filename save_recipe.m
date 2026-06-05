function save_recipe(dest, recipe)
%SAVE_RECIPE  Write a DataExplorer recipe to DEST.  Fails if DEST already exists.
%
%   save_recipe('myanalysis.m', recipe)   % recipe = 3rd output of DataExplorer:
%                                         %   [~, ~, recipe] = DataExplorer('data.csv');
%   save_recipe('myanalysis.m')           % fallback: copy the most recently written
%                                         %   dataexplorer_*.m from the temp directory
%
%   Prefer passing the recipe explicitly — the no-recipe form guesses the newest
%   recipe in tempdir, which is ambiguous when several runs (or a background test
%   run) have written recipes.

if nargin < 1
    error('save_recipe:noArgs', ...
        'Usage: save_recipe(''destination.m'', recipe)  (recipe optional)');
end

if exist(dest, 'file')
    error('save_recipe:destExists', ...
        'Destination already exists: %s\nChoose a different name or delete it first.', dest);
end

if nargin >= 2 && ~isempty(recipe)
    % Write the recipe handed to us (string array, string, or cellstr).
    writelines(string(recipe), dest);
else
    % Fallback: copy the most recently written recipe in tempdir.
    hits = dir(fullfile(tempdir, 'dataexplorer_*.m'));
    if isempty(hits)
        error('save_recipe:noRecipe', ...
            ['No DataExplorer recipe found in %s.\nRun DataExplorer first, or pass ' ...
             'the recipe: [~,~,recipe] = DataExplorer(...); save_recipe(dest, recipe).'], ...
            tempdir);
    end
    [~, newest] = max([hits.datenum]);
    copyfile(fullfile(hits(newest).folder, hits(newest).name), dest);
end

fprintf('  Recipe saved to: %s\n', dest);
end
