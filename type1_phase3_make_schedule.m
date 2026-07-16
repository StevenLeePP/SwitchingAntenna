function schedule = type1_phase3_make_schedule(S, model)
%TYPE1_PHASE3_MAKE_SCHEDULE Lift mathematical S into canonical A[m,n,q].

arguments
    S {mustBeNumericOrLogical}
    model (1,1) struct
end
M = model.nPhysical; N = model.nVirtual;
assert(isequal(size(S), [M N]), 'type1:Phase3SelectionShape', ...
    'S must have size M-by-N.');
assert(all(isfinite(double(S(:)))) && all(S(:) == 0 | S(:) == 1), ...
    'type1:Phase3SelectionBinary', 'S must be finite and binary.');
A = false(M, N, N);
for n = 1:N
    A(:, n, n) = logical(S(:, n));
end
schedule = type1_phase3_validate_schedule(A, model);
end
