function [stitched, virtualRF, meta] = type1_apply_switch_impairments(raw122, switchModel, stream)
%TYPE1_APPLY_SWITCH_IMPAIRMENTS Causal four-phase RF-switch abstraction.
%   At raw sample n, phase q=mod(n-1,4)+1 selects physical RX q.  Off-state
%   leakage is a coherent complex sum from the other ports.  Finite settling
%   is a first-order response of the *selected analog output*, so it mixes
%   successive switch phases and creates a time-varying/ICI-capable error.
%
%   A static leakage matrix is intentionally not treated as unmodelled
%   additive noise: Type-1 DM-RS can estimate much of its H transformation.

arguments
    raw122 {mustBeNumeric}
    switchModel (1,1) struct
    stream = []
end

assert(size(raw122, 2) == 4 && mod(size(raw122, 1), 4) == 0, ...
    'type1:SwitchShape', 'raw122 must be N-by-4 with N divisible by four.');
assert(isfield(switchModel, 'isolationDb') && ...
    isfield(switchModel, 'settlingRiseNs') && ...
    isfield(switchModel, 'leakagePhasesRad') && ...
    isfield(switchModel, 'rawSampleRateHz') && ...
    isfield(switchModel, 'transitionJitterStdPs'), ...
    'type1:SwitchModel', 'Incomplete switch model.');
assert(isscalar(switchModel.isolationDb) && ...
    (isinf(switchModel.isolationDb) || switchModel.isolationDb >= 0), ...
    'type1:SwitchIsolation', 'isolationDb must be nonnegative or Inf.');
assert(isscalar(switchModel.settlingRiseNs) && switchModel.settlingRiseNs >= 0, ...
    'type1:SwitchSettling', 'settlingRiseNs must be nonnegative.');
assert(isequal(size(switchModel.leakagePhasesRad), [4 4]), ...
    'type1:SwitchLeakage', 'leakagePhasesRad must be 4-by-4.');

if isinf(switchModel.isolationDb)
    leakageAmplitude = 0;
else
    leakageAmplitude = 10^(-switchModel.isolationDb / 20);
end
leakage = leakageAmplitude .* exp(1j * switchModel.leakagePhasesRad);
leakage(1:5:end) = 1;

assert(isscalar(switchModel.transitionJitterStdPs) && ...
    switchModel.transitionJitterStdPs >= 0, ...
    'type1:SwitchJitter', 'transitionJitterStdPs must be nonnegative.');
if switchModel.transitionJitterStdPs > 0
    assert(~isempty(stream), 'type1:SwitchJitter', ...
        'A RandStream is required for reproducible transition jitter.');
    timingJitter = switchModel.transitionJitterStdPs * 1e-12 * ...
        randn(stream, size(raw122, 1), 1);
else
    timingJitter = zeros(size(raw122, 1), 1);
end

if switchModel.settlingRiseNs == 0
    beta = ones(size(raw122, 1), 1);
else
    tauSec = switchModel.settlingRiseNs * 1e-9 / log(9); % 10--90% rise time
    dt = 1 / switchModel.rawSampleRateHz + [0; diff(timingJitter)];
    dt = max(dt, eps); % non-monotone jitter samples have no physical meaning
    beta = 1 - exp(-dt / tauSec);
end

nSamples = size(raw122, 1);
stitched = complex(zeros(nSamples, 1, 'like', raw122));
state = zeros(1, 1, 'like', raw122);
for n = 1:nSamples
    phase = mod(n-1, 4) + 1;
    target = raw122(n, :) * leakage(phase, :).';
    if n == 1
        state = target; % the preceding capture prefix is zero in the link model
    else
        state = (1-beta(n)) * state + beta(n) * target;
    end
    stitched(n) = state;
end
virtualRF = reshape(stitched, 4, []).';
meta = struct('leakageAmplitude', leakageAmplitude, 'leakageMatrix', leakage, ...
    'settlingBetaMean', mean(beta), 'settlingBetaStd', std(beta), ...
    'settlingRiseNs', switchModel.settlingRiseNs, ...
    'transitionJitterStdPs', switchModel.transitionJitterStdPs, ...
    'isolationDb', switchModel.isolationDb);
end
