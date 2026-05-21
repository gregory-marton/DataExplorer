function [ci_lo, ci_hi, x_fit, y_fit] = de_bootstrap_poly_ci(x, y, order, alpha, nboot)
%DE_BOOTSTRAP_POLY_CI  Polynomial regression with paired bootstrap CIs.
%
%   [ci_lo, ci_hi, x_fit, y_fit] = de_bootstrap_poly_ci(x, y)
%   [ci_lo, ci_hi, x_fit, y_fit] = de_bootstrap_poly_ci(x, y, order, alpha, nboot)
%
%   x, y    vectors of data (NaN pairs are dropped)
%   order   polynomial degree (default 1 — linear)
%   alpha   confidence level, 0–1 (default 0.95 → 95% CI)
%   nboot   bootstrap resamples (default 500)
%
%   Returns ci_lo, ci_hi (CI bounds at x_fit grid), x_fit (evaluation grid),
%   y_fit (fitted curve).  Resamples (x,y) pairs jointly (paired bootstrap).
%
%   Requires the Statistics and Machine Learning Toolbox (prctile).

if nargin < 3, order = 1;    end
if nargin < 4, alpha = 0.95; end
if nargin < 5, nboot = 500;  end

x = x(:);  y = y(:);
ok = ~isnan(x) & ~isnan(y);
x = x(ok);  y = y(ok);
n = numel(x);

if n < order + 2
    ci_lo = [];  ci_hi = [];  x_fit = x;  y_fit = [];
    return;
end

x_fit = linspace(min(x), max(x), max(n, 50))';

p     = polyfit(x, y, order);
y_fit = polyval(p, x_fit);

boot_pv = zeros(numel(x_fit), nboot);
for b = 1:nboot
    idx = randi(n, n, 1);
    pb  = polyfit(x(idx), y(idx), order);
    boot_pv(:, b) = polyval(pb, x_fit);
end

lo_pct = 100 * (1 - alpha) / 2;
ci_lo  = prctile(boot_pv, lo_pct,       2);
ci_hi  = prctile(boot_pv, 100 - lo_pct, 2);
end
