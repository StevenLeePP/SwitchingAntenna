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
fprintf('Switch-impairment algebra validation PASSED (beta@10ns=%.6f).\n', ...
    meta.settlingBetaMean);
end

function model = default_model()
model = struct('isolationDb', Inf, 'settlingRiseNs', 0, ...
    'leakagePhasesRad', zeros(4), 'rawSampleRateHz', 122.88e6, ...
    'transitionJitterStdPs', 0);
end
