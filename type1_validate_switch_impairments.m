function type1_validate_switch_impairments()
%TYPE1_VALIDATE_SWITCH_IMPAIRMENTS Algebraic regression for the switch model.
%   This test deliberately validates the abstraction itself before BER scans.

stream = RandStream('mt19937ar', 'Seed', 20260714);
raw = randn(stream, 256, 4) + 1j * randn(stream, 256, 4);
model = default_model();
[ideal, virtual] = type1_apply_switch_impairments(raw, model);
[reference, referenceVirtual] = type1_digital_switch(raw);
assert(isequal(ideal, reference) && isequal(virtual, referenceVirtual), ...
    'type1:SwitchValidation', 'Ideal impairment model differs from digital switch.');

model.isolationDb = 0;
[allLeak, ~] = type1_apply_switch_impairments(raw, model);
assert(max(abs(allLeak - sum(raw, 2))) < 1e-12, ...
    'type1:SwitchValidation', '0-dB in-phase leakage does not equal the coherent sum.');

model = default_model();
model.settlingRiseNs = 10;
[settled, ~, meta] = type1_apply_switch_impairments(raw, model);
assert(meta.settlingBetaMean > 0 && meta.settlingBetaMean < 1, ...
    'type1:SwitchValidation', 'Finite settling did not produce a stable IIR coefficient.');
assert(abs(settled(2) - ((1-meta.settlingBetaMean)*settled(1) + ...
    meta.settlingBetaMean*raw(2, 2))) < 1e-12, ...
    'type1:SwitchValidation', 'Settling recurrence is inconsistent.');

% Sampling-boundary jitter is a distinct model: it must affect a zero-rise
% switch, be reproducible with a seed, and never alter the exact zero-jitter
% identity path.
model = default_model(); model.samplingBoundaryJitterStdPs = 100;
jitterStream = RandStream('mt19937ar', 'Seed', 77);
[boundaryJittered, ~, boundaryMeta] = type1_apply_switch_impairments(raw, model, jitterStream);
jitterStream = RandStream('mt19937ar', 'Seed', 77);
boundaryRepeat = type1_apply_switch_impairments(raw, model, jitterStream);
assert(norm(boundaryJittered-reference) > 1e-9 && isequal(boundaryJittered,boundaryRepeat) && ...
    boundaryMeta.boundaryOffsetStdSamples > 0, 'type1:SwitchValidation', ...
    'Boundary jitter is not active/reproducible when rise time is zero.');

% tau(t) must vary beta(t) without violating the causal positive-time IIR.
model = default_model(); model.settlingRiseNs = 5;
model.settlingSlowDriftFraction = 0.2; model.settlingSlowDriftHz = 1e5;
model.settlingFastJitterStdFraction = 0.1;
[timeVarying, ~, timeMeta] = type1_apply_switch_impairments(raw, model, ...
    RandStream('mt19937ar', 'Seed', 78));
assert(all(isfinite(timeVarying),'all') && timeMeta.settlingBetaStd > 0 && ...
    timeMeta.settlingTauStdNs > 0, 'type1:SwitchValidation', ...
    'Time-varying settling failed to produce a finite beta(t).');

% An OU/AR(1) process must preserve the configured stationary fast-jitter
% standard deviation while introducing the requested finite correlation time.
rawLong = randn(stream, 4096, 4) + 1j*randn(stream, 4096, 4);
model = default_model(); model.settlingRiseNs = 5;
model.settlingFastJitterStdFraction = 0.2;
model.settlingFastJitterCorrelationSec = 1e-6;
[~, ~, arMeta] = type1_apply_switch_impairments(rawLong, model, ...
    RandStream('mt19937ar', 'Seed', 79));
assert(arMeta.fastFractionLag1Correlation > 0.98, 'type1:SwitchValidation', ...
    'Configured correlated fast tau jitter did not retain AR(1) correlation.');

model = default_model(); model.settlingRiseNs = 5;
model.settlingFastJitterStdFraction = 1.0;
[~, ~, floorMeta] = type1_apply_switch_impairments(rawLong, model, ...
    RandStream('mt19937ar', 'Seed', 80));
assert(floorMeta.tauFloorHitCount > 0 && floorMeta.tauFloorHitFraction > 0, ...
    'type1:SwitchValidation', 'Tau lower-bound hits were not audited.');

% Genie beta inversion is an exact algebraic upper-bound operation for this
% IIR model; it must recover the no-settling four-phase virtual stream.
model = default_model(); model.settlingRiseNs = 20;
model.settlingFastJitterStdFraction = 0.6; model.recordTimeSeries = true;
[genieStitched, ~, genieMeta] = type1_apply_switch_impairments(raw, model, ...
    RandStream('mt19937ar', 'Seed', 81));
genieVirtual = type1_genie_inverse_settling(genieStitched, genieMeta.settlingBeta);
assert(max(abs(genieVirtual-referenceVirtual), [], 'all') < 1e-10, ...
    'type1:SwitchValidation', 'Known-beta genie inverse did not cancel IIR mixing.');
fprintf(['Switch-impairment algebra validation PASSED (beta@10ns=%.6f, ' ...
    'boundary jitter and tau(t) active).\n'], meta.settlingBetaMean);
end

function model = default_model()
model = struct('isolationDb', Inf, 'settlingRiseNs', 0, ...
    'leakagePhasesRad', zeros(4), 'rawSampleRateHz', 122.88e6, ...
    'transitionJitterStdPs', 0, 'settlingSlowDriftFraction', 0, ...
    'settlingSlowDriftHz', 0, 'settlingFastJitterStdFraction', 0, ...
    'samplingBoundaryJitterStdPs', 0, 'timeOriginSec', 0);
end
