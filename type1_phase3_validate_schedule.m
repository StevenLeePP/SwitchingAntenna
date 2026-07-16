function schedule = type1_phase3_validate_schedule(A, model)
%TYPE1_PHASE3_VALIDATE_SCHEDULE Validate the physical A[m,n,q] schedule.
%   Multiple antennas may be summed into one scalar RF node in a phase.
%   One antenna may enter multiple virtual chains only in different phases;
%   assigning the same antenna sample to multiple virtual-chain labels in
%   one phase is forbidden analog fan-out.

arguments
    A {mustBeNumericOrLogical}
    model (1,1) struct
end

required = {'nPhysical','nVirtual','codePeriod','maxDutyCount', ...
    'allowEmptyVirtualChain','canonicalPhaseOwnership','rawSampleRateHz', ...
    'settlingRiseNs','enforceSettlingConstraint','maxSettlingUtilization'};
for k = 1:numel(required)
    assert(isfield(model, required{k}), 'type1:Phase3Config', ...
        'Phase-3 model is missing field %s.', required{k});
end
M = model.nPhysical; N = model.nVirtual; Q = model.codePeriod;
assert(Q == N, 'type1:Phase3CodePeriod', ...
    'Frozen Part A requires codePeriod=N virtual phases.');
assert(ndims(A) <= 3 && isequal(size(A), [M N Q]), ...
    'type1:Phase3ScheduleShape', 'A must have size M-by-N-by-N.');
assert(all(isfinite(double(A(:)))) && all(A(:) == 0 | A(:) == 1), ...
    'type1:Phase3ScheduleBinary', 'A must be finite and binary.');
A = logical(A);

fanout = reshape(sum(A, 2), M, Q);
assert(all(fanout <= 1, 'all'), 'type1:Phase3IllegalFanout', ...
    ['One antenna cannot feed multiple virtual-chain labels in the same ' ...
     'code phase; code-domain reuse must occur in different phases.']);

if logical(model.canonicalPhaseOwnership)
    canonical = false(M, N, Q);
    for n = 1:N, canonical(:, n, n) = true; end
    assert(~any(A & ~canonical, 'all'), 'type1:Phase3PhaseOwnership', ...
        'A[m,n,q] may be active only when q=n in the frozen canonical map.');
end

S = double(sum(A, 3));
assert(all(S(:) <= 1), 'type1:Phase3ScheduleProjection', ...
    'OR/sum projection from A to S is not binary.');
coverage = sum(S, 1);
if ~logical(model.allowEmptyVirtualChain)
    assert(all(coverage >= 1), 'type1:Phase3Coverage', ...
        'Every virtual chain must contain at least one physical port.');
end
dutyCount = sum(S, 2);
assert(all(dutyCount <= model.maxDutyCount), 'type1:Phase3DutyCycle', ...
    'At least one antenna exceeds maxDutyCount.');

codes = fanout;
transitionCount = sum(codes ~= circshift(codes, [0 1]), 2);
phaseIntervalNs = 1e9 / model.rawSampleRateHz;
settlingUtilization = model.settlingRiseNs / phaseIntervalNs;
if logical(model.enforceSettlingConstraint) && any(transitionCount > 0)
    assert(settlingUtilization <= model.maxSettlingUtilization, ...
        'type1:Phase3SettlingConstraint', ...
        'Configured settling time exceeds the allowed code-phase interval.');
end

schedule = struct('A', A, 'S', S, 'codes', codes, ...
    'dutyCount', dutyCount, 'dutyFraction', dutyCount / Q, ...
    'coverage', coverage, 'phaseLoad', sum(codes, 1), ...
    'transitionCount', transitionCount, ...
    'totalAssignments', sum(S, 'all'), ...
    'phaseIntervalNs', phaseIntervalNs, ...
    'settlingUtilization', settlingUtilization, ...
    'singleChainOutputWidth', 1, 'model', model);
end
