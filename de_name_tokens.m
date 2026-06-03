function tokens = de_name_tokens(name)
%DE_NAME_TOKENS  Split a variable name into lowercase word tokens.
%
%   tokens = de_name_tokens(name)
%
%   Handles CamelCase, snake_case, spaces, and letter/digit boundaries:
%     "StateCode"        -> ["state","code"]
%     "SiteNum"          -> ["site","num"]
%     "Observation Count"-> ["observation","count"]
%     "State_Code"       -> ["state","code"]
%     "POC"              -> ["poc"]
%
%   Uses regexprep (non-zero-width) for CamelCase boundaries because MATLAB's
%   regexp 'split' does NOT split on zero-width lookahead/lookbehind matches.
%   Returns a lowercase string array.  Requires no toolboxes.

s = char(name);
s = regexprep(s, '([a-z0-9])([A-Z])', '$1 $2');   % camelCase  -> camel Case
s = regexprep(s, '([A-Za-z])([0-9])', '$1 $2');    % Code2 / x10 -> Code 2 / x 10
parts = regexp(s, '[A-Za-z0-9]+', 'match');
tokens = lower(string(parts));
end
