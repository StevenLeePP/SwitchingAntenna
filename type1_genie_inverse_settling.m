function virtualRF = type1_genie_inverse_settling(stitched, beta)
%TYPE1_GENIE_INVERSE_SETTLING Oracle inverse of the known beta[n] IIR.
%   For s[n]=(1-beta[n])*s[n-1]+beta[n]*target[n], exact knowledge of beta
%   gives target[n].  This removes only settling-memory mixing; it does not
%   grant an oracle channel, CFO, data symbol, leakage matrix, or noise-free
%   observation.  It is therefore a useful upper bound on beta-aware ICI
%   cancellation in this switch abstraction.

assert(isvector(stitched) && isvector(beta) && numel(stitched) == numel(beta), ...
    'type1:GenieSettling', 'stitched and beta must have equal vector lengths.');
assert(mod(numel(stitched), 4) == 0 && all(beta > 0 & beta <= 1), ...
    'type1:GenieSettling', 'beta must be in (0,1] and length divisible by four.');
stitched = stitched(:); beta = beta(:);
target = complex(zeros(size(stitched), 'like', stitched));
target(1) = stitched(1);
for n = 2:numel(stitched)
    target(n) = (stitched(n) - (1-beta(n))*stitched(n-1)) / beta(n);
end
virtualRF = reshape(target, 4, []).';
end
