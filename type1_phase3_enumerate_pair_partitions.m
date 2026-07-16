function candidates = type1_phase3_enumerate_pair_partitions()
%TYPE1_PHASE3_ENUMERATE_PAIR_PARTITIONS Exact frozen M=8,N=4,Dmax=1 set.
%   Every physical port is assigned to exactly one labelled virtual chain,
%   and every virtual chain receives exactly two ports.  Within-pair order
%   is irrelevant, so the exact cardinality is 8!/(2!^4)=2520.

M = 8; N = 4;
candidates = false(M, N, 2520);
index = 0;
for pair1 = nchoosek(1:M, 2).'
    remaining1 = setdiff(1:M, pair1, 'stable');
    for pair2 = nchoosek(remaining1, 2).'
        remaining2 = setdiff(remaining1, pair2, 'stable');
        for pair3 = nchoosek(remaining2, 2).'
            pair4 = setdiff(remaining2, pair3, 'stable');
            index = index + 1;
            candidates(pair1, 1, index) = true;
            candidates(pair2, 2, index) = true;
            candidates(pair3, 3, index) = true;
            candidates(pair4, 4, index) = true;
        end
    end
end
assert(index == 2520, 'type1:Phase3EnumerationCardinality', ...
    'M=8 labelled pair partitions must contain exactly 2520 schedules.');
end
