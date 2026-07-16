function schedules = type1_phase3_enumerate_f1(M, N)
%TYPE1_PHASE3_ENUMERATE_F1 Exact Dmax=1/off/coverage feasible set.
%   Each physical port is assigned to none or exactly one virtual chain;
%   every virtual chain must contain at least one port.

if nargin < 1, M = 8; end
if nargin < 2, N = 4; end
assert(M == 8 && N == 4, 'type1:Phase3F1Dimensions', ...
    'The exact R18 F1 enumerator is frozen to M=8,N=4.');
code = uint32((0:(N+1)^M-1).');
assignment = zeros(numel(code), M, 'uint8');
work = code;
for m = 1:M
    assignment(:, m) = uint8(mod(work, N+1));
    work = idivide(work, uint32(N+1), 'floor');
end
covered = true(size(code));
for chain = 1:N, covered = covered & any(assignment == chain, 2); end
assignment = assignment(covered, :);
schedules = false(M, N, size(assignment, 1));
for m = 1:M
    for chain = 1:N
        schedules(m, chain, :) = assignment(:, m) == chain;
    end
end
assert(size(schedules, 3) == 166824, 'type1:Phase3F1Cardinality', ...
    'F1 cardinality must equal the inclusion-exclusion result 166824.');
end
