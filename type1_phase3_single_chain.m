function [stitched, virtualRF, meta] = type1_phase3_single_chain(rawWide, schedule)
%TYPE1_PHASE3_SINGLE_CHAIN Collapse M antenna inputs into one scalar stream.
%   At raw sample k, q=mod(k-1,N)+1 and
%       y[k] = sum_m schedule.S(m,q) * rawWide(k,m).
%   The only digitized output is y.  reshape(y,N,[]) de-spreads it into N
%   virtual chains; no per-antenna digital output is exposed.

arguments
    rawWide {mustBeNumeric}
    schedule (1,1) struct
end
S = schedule.S;
[M, N] = size(S);
assert(size(rawWide, 2) == M, 'type1:Phase3RawShape', ...
    'rawWide must have M physical-antenna columns.');
assert(mod(size(rawWide, 1), N) == 0, 'type1:Phase3RawLength', ...
    'rawWide length must be divisible by the N-phase code period.');
assert(schedule.singleChainOutputWidth == 1, 'type1:Phase3ScalarInvariant', ...
    'Schedule violates the frozen scalar-output invariant.');

stitched = complex(zeros(size(rawWide, 1), 1, 'like', rawWide));
for q = 1:N
    rows = q:N:size(rawWide, 1);
    active = find(S(:, q) ~= 0);
    assert(~isempty(active), 'type1:Phase3Coverage', ...
        'Cannot synthesize an empty virtual chain.');
    stitched(rows) = sum(rawWide(rows, active), 2);
end
virtualRF = reshape(stitched, N, []).';
meta = struct('nPhysical', M, 'nVirtual', N, ...
    'inputPhysicalColumns', M, 'digitizedOutputColumns', size(stitched, 2), ...
    'phaseLoad', sum(S, 1), 'scalarInvariantPassed', size(stitched, 2) == 1);
end
