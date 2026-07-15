function [stitched, virtualRF, meta] = type1_apply_switch_impairments(raw122, switchModel, stream)
%TYPE1_APPLY_SWITCH_IMPAIRMENTS Causal four-phase RF-switch abstraction.
%   At raw sample n, phase q=mod(n-1,4)+1 selects physical RX q.  Off-state
%   leakage is a coherent complex sum from the other ports.  Finite settling
%   is a first-order response of the *selected analog output*, so it mixes
%   successive switch phases and creates a time-varying/ICI-capable error.
%   Phase-2 extensions make tau(t) time varying and apply a common sampling
%   boundary displacement before switching.  Unlike transition-time jitter,
%   boundary displacement remains active when settlingRiseNs is zero.
%
%   A static leakage matrix is intentionally not treated as unmodelled
%   additive noise: Type-1 DM-RS can estimate much of its H transformation.

arguments
    raw122 {mustBeNumeric}
    switchModel (1,1) struct
    stream = []
end

switchModel = complete_model(switchModel);
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
assert(isscalar(switchModel.settlingSlowDriftFraction) && ...
    isscalar(switchModel.settlingSlowDriftHz) && ...
    isscalar(switchModel.settlingFastJitterStdFraction) && ...
    isscalar(switchModel.settlingFastJitterCorrelationSec) && ...
    isscalar(switchModel.samplingBoundaryJitterStdPs) && ...
    isscalar(switchModel.recordTimeSeries) && ...
    isscalar(switchModel.timeOriginSec) && ...
    switchModel.settlingSlowDriftFraction >= 0 && ...
    switchModel.settlingSlowDriftHz >= 0 && ...
    switchModel.settlingFastJitterStdFraction >= 0 && ...
    switchModel.settlingFastJitterCorrelationSec >= 0 && ...
    switchModel.samplingBoundaryJitterStdPs >= 0 && ...
    (islogical(switchModel.recordTimeSeries) || isnumeric(switchModel.recordTimeSeries)) && ...
    isfinite(switchModel.timeOriginSec), ...
    'type1:SwitchTimeVarying', 'Invalid time-varying switch-model parameter.');

needsRandomness = switchModel.transitionJitterStdPs > 0 || ...
    switchModel.settlingFastJitterStdFraction > 0 || ...
    switchModel.samplingBoundaryJitterStdPs > 0;
if needsRandomness
    assert(~isempty(stream), 'type1:SwitchJitter', ...
        'A RandStream is required for reproducible switch jitter.');
end
if switchModel.transitionJitterStdPs > 0
    timingJitter = switchModel.transitionJitterStdPs * 1e-12 * ...
        randn(stream, size(raw122, 1), 1);
else
    timingJitter = zeros(size(raw122, 1), 1);
end

if switchModel.samplingBoundaryJitterStdPs > 0
    boundaryOffsetSamples = switchModel.samplingBoundaryJitterStdPs * 1e-12 * ...
        switchModel.rawSampleRateHz * randn(stream, size(raw122, 1), 1);
    % The model is explicitly a sub-sample boundary displacement.  Truncate
    % only the improbable Gaussian tails beyond 0.49 raw samples and expose
    % their count in meta instead of silently switching to an inter-symbol
    % timing-slip model.
    boundaryClippedCount = sum(abs(boundaryOffsetSamples) >= 0.49);
    boundaryOffsetSamples = min(max(boundaryOffsetSamples, -0.49), 0.49);
    rawAtBoundary = fractional_boundary_sample(raw122, boundaryOffsetSamples);
else
    boundaryOffsetSamples = zeros(size(raw122, 1), 1);
    boundaryClippedCount = 0;
    rawAtBoundary = raw122;
end

fastFraction = zeros(size(raw122, 1), 1);
tauFloorHitCount = 0;
if switchModel.settlingRiseNs == 0
    beta = ones(size(raw122, 1), 1);
    tauSec = zeros(size(raw122, 1), 1);
else
    tau0Sec = switchModel.settlingRiseNs * 1e-9 / log(9); % 10--90% rise time
    sampleTime = switchModel.timeOriginSec + ...
        (0:(size(raw122, 1)-1)).' / switchModel.rawSampleRateHz;
    slowFraction = switchModel.settlingSlowDriftFraction * ...
        sin(2*pi*switchModel.settlingSlowDriftHz*sampleTime);
    fastFraction = fast_fraction_process( ...
        switchModel.settlingFastJitterStdFraction, ...
        switchModel.settlingFastJitterCorrelationSec, ...
        switchModel.rawSampleRateHz, size(raw122, 1), stream);
    % A first-order time constant cannot be negative.  The floor represents
    % the physical positive-time constraint rather than a hidden stability
    % fix; validation records whether it was ever reached.
    tauScale = 1 + slowFraction + fastFraction;
    tauFloorHitCount = sum(tauScale <= 0.01);
    tauSec = tau0Sec * max(tauScale, 0.01);
    dt = 1 / switchModel.rawSampleRateHz + [0; diff(timingJitter)];
    dt = max(dt, eps); % non-monotone jitter samples have no physical meaning
    beta = 1 - exp(-dt ./ tauSec);
end

nSamples = size(raw122, 1);
stitched = complex(zeros(nSamples, 1, 'like', raw122));
recordTrace=logical(switchModel.recordTimeSeries);
if recordTrace, targetTrace=complex(zeros(nSamples,1,'like',raw122));
else, targetTrace=complex(zeros(0,1,'like',raw122)); end
state = zeros(1, 1, 'like', raw122);
for n = 1:nSamples
    phase = mod(n-1, 4) + 1;
    target = rawAtBoundary(n, :) * leakage(phase, :).';
    if recordTrace, targetTrace(n)=target; end
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
    'settlingTauMeanNs', 1e9*mean(tauSec), 'settlingTauStdNs', 1e9*std(tauSec), ...
    'settlingRiseNs', switchModel.settlingRiseNs, ...
    'transitionJitterStdPs', switchModel.transitionJitterStdPs, ...
    'samplingBoundaryJitterStdPs', switchModel.samplingBoundaryJitterStdPs, ...
    'boundaryOffsetStdSamples', std(boundaryOffsetSamples), ...
    'boundaryOffsetClippedCount', boundaryClippedCount, ...
    'settlingSlowDriftFraction', switchModel.settlingSlowDriftFraction, ...
    'settlingSlowDriftHz', switchModel.settlingSlowDriftHz, ...
    'settlingFastJitterStdFraction', switchModel.settlingFastJitterStdFraction, ...
    'settlingFastJitterCorrelationSec', switchModel.settlingFastJitterCorrelationSec, ...
    'fastFractionLag1Correlation', lag1_correlation(fastFraction), ...
    'tauFloorHitCount', tauFloorHitCount, ...
    'tauFloorHitFraction', tauFloorHitCount / nSamples, ...
    'timeOriginSec', switchModel.timeOriginSec, ...
    'settlingBeta', maybe_record(beta, switchModel.recordTimeSeries), ...
    'settlingTarget', targetTrace, ...
    'boundaryOffsetSamples', maybe_record(boundaryOffsetSamples, switchModel.recordTimeSeries), ...
    'isolationDb', switchModel.isolationDb);
end

function model = complete_model(model)
defaults = struct('settlingSlowDriftFraction', 0, 'settlingSlowDriftHz', 0, ...
    'settlingFastJitterStdFraction', 0, 'settlingFastJitterCorrelationSec', 0, ...
    'samplingBoundaryJitterStdPs', 0, 'timeOriginSec', 0, 'recordTimeSeries', false);
names = fieldnames(defaults);
for k = 1:numel(names)
    if ~isfield(model, names{k}), model.(names{k}) = defaults.(names{k}); end
end
end

function fraction = fast_fraction_process(stdFraction, correlationSec, fs, nSamples, stream)
if stdFraction == 0
    fraction = zeros(nSamples, 1);
elseif correlationSec == 0
    fraction = stdFraction * randn(stream, nSamples, 1);
else
    alpha = exp(-1 / (fs * correlationSec));
    innovationStd = stdFraction * sqrt(1 - alpha^2);
    fraction = zeros(nSamples, 1);
    fraction(1) = stdFraction * randn(stream);
    for n = 2:nSamples
        fraction(n) = alpha * fraction(n-1) + innovationStd * randn(stream);
    end
end
end

function value = lag1_correlation(x)
if numel(x) < 2 || all(x == 0)
    value = nan;
    return;
end
x = x - mean(x);
value = real(sum(x(1:end-1) .* x(2:end)) / ...
    sqrt(sum(x(1:end-1).^2) * sum(x(2:end).^2) + eps));
end

function value = maybe_record(x, enabled)
if logical(enabled), value = x; else, value = zeros(0, 1); end
end

function y = fractional_boundary_sample(x, offsetSamples)
% Evaluate x[n+delta_n] using a zero-padded, 9-tap windowed-sinc kernel.
% delta=0 is exactly the identity (all off-centre sinc weights are zero),
% so enabling this model with zero jitter cannot introduce interpolation loss.
assert(all(abs(offsetSamples) < 0.5), 'type1:BoundaryJitterRange', ...
    'Boundary displacement must remain below half a raw sample after truncation.');
n = size(x, 1); taps = -4:4;
window = 0.54 + 0.46*cos(pi*taps/4); % symmetric Hamming window
weights = zeros(n, numel(taps));
for k = 1:numel(taps)
    weights(:, k) = window(k) * sinc(offsetSamples - taps(k));
end
weights = weights ./ sum(weights, 2);
y = complex(zeros(size(x), 'like', x));
for k = 1:numel(taps)
    source = (1:n).' + taps(k);
    valid = source >= 1 & source <= n;
    if any(valid)
        y(valid, :) = y(valid, :) + x(source(valid), :) .* weights(valid, k);
    end
end
end
