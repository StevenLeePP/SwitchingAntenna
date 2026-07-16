function metrics = type1_phase3_wideband_metrics(H, S, noiseVariance)
%TYPE1_PHASE3_WIDEBAND_METRICS Noise-aware linear-MMSE post-SINR metrics.
%   v=S.'*H*x+S.'*n, with independent per-port n~CN(0,sigma2).
%   Therefore Rn=sigma2*S.'*S.  Omitting this covariance would grant a
%   fictitious gain to schedules that sum more antenna noise.

arguments
    H {mustBeNumeric}
    S {mustBeNumericOrLogical}
    noiseVariance (1,1) double {mustBePositive}
end
[M, N, nTones] = size(H);
assert(isequal(size(S), [M N]), 'type1:Phase3MetricShape', ...
    'S must be M-by-N for H of size M-by-N-by-K.');
S = double(S);
noiseCovariance = noiseVariance * (S.' * S);
assert(rcond(noiseCovariance) > 1e-12, 'type1:Phase3MetricNoiseRank', ...
    'The virtual-chain noise covariance is singular.');

G = pagemtimes(S.', H);
weightedG = pagemtimes(noiseCovariance \ eye(N), G);
gram = pagemtimes(pagectranspose(G), weightedG);
errorCovariance = pageinv(gram + eye(N));
sinrLinear = zeros(N, nTones);
for user = 1:N
    diagonal = reshape(real(errorCovariance(user, user, :)), 1, nTones);
    sinrLinear(user, :) = max(1 ./ diagonal - 1, realmin);
end
sinrDb = 10*log10(sinrLinear);
perUserMeanSinrDb = mean(sinrDb, 2).';
perUserRate = mean(log2(1 + sinrLinear), 2).';
metrics = struct('objectiveDb', min(perUserMeanSinrDb), ...
    'perUserMeanSinrDb', perUserMeanSinrDb, ...
    'minToneSinrDb', min(sinrDb, [], 'all'), ...
    'minUserRate', min(perUserRate), 'perUserRate', perUserRate, ...
    'noiseCovariance', noiseCovariance, ...
    'sinrLinear', sinrLinear);
end
