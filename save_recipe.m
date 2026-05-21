function save_recipe(dest)
%SAVE_RECIPE  Copy the most recent DataExplorer recipe script to DEST.
%
%   save_recipe('myanalysis.m')
%
%   Finds the most recently written dataexplorer_*.m in the system temp
%   directory and copies it to DEST.  Fails if DEST already exists.

if nargin < 1
    error('save_recipe:noArgs', 'Usage: save_recipe(''destination.m'')');
end

% Find candidate recipe files in tempdir
pattern = fullfile(tempdir, 'dataexplorer_*.m');
hits = dir(pattern);

if isempty(hits)
    error('save_recipe:noRecipe', ...
        'No DataExplorer recipe found in %s.\nRun DataExplorer on a file first.', ...
        tempdir);
end

% Pick the most recently modified
[~, newest] = max([hits.datenum]);
src = fullfile(hits(newest).folder, hits(newest).name);

if exist(dest, 'file')
    error('save_recipe:destExists', ...
        'Destination already exists: %s\nChoose a different name or delete it first.', dest);
end

copyfile(src, dest);
fprintf('  Recipe saved to: %s\n', dest);
end
