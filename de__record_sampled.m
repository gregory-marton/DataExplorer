function T = de__record_sampled(T, n, n_orig)
%DE__RECORD_SAMPLED  Record sampled / original row counts in T.Properties.UserData
%   so cg_load_code can emit a sampling call and de_overview can show "n of N".
    if nargin < 3, n_orig = n; end
    if isempty(T.Properties.UserData)
        T.Properties.UserData = struct('sheet', '', 'inner_file', '', ...
            'sampled', n, 'n_orig', n_orig);
    else
        T.Properties.UserData.sampled = n;
        T.Properties.UserData.n_orig  = n_orig;
    end
end
