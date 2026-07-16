function objectiveDb = type1_phase3_batch_f1_objective(H, schedules, noiseVariance, batchSize)
%TYPE1_PHASE3_BATCH_F1_OBJECTIVE Vectorized exact F1 MMSE objective.
%   This is algebraically the same metric as type1_phase3_wideband_metrics.
%   Dmax=1 makes S'*S diagonal, which permits inexpensive page whitening.

if nargin < 4, batchSize = 512; end
[M, N, K] = size(H); nCandidate = size(schedules, 3);
assert(isequal(size(schedules,1),M) && isequal(size(schedules,2),N), ...
    'type1:Phase3BatchShape', 'Schedule and channel dimensions differ.');
rowDuty = sum(schedules, 2);
assert(all(rowDuty(:) <= 1) && all(sum(schedules,1) >= 1,'all'), ...
    'type1:Phase3BatchF1', 'Batch engine accepts only covered Dmax=1 schedules.');
objectiveDb = zeros(nCandidate, 1);
Hp = reshape(H, M, N, K, 1);
identity = reshape(eye(N), N, N, 1, 1);
for first = 1:batchSize:nCandidate
    last = min(nCandidate, first+batchSize-1); B = last-first+1;
    Sb = double(schedules(:,:,first:last));
    St = permute(Sb, [2 1 4 3]); % N x M x 1 x B
    G = pagemtimes(St, Hp);       % N x N x K x B
    counts = reshape(sum(Sb,1), N, B);
    scale = reshape(1./sqrt(noiseVariance*counts), N, 1, 1, B);
    Gw = G .* scale;
    gram = pagemtimes(pagectranspose(Gw), Gw);
    errorCovariance = pageinv(gram + identity);
    perUser = zeros(N, B);
    for user = 1:N
        diagonal = reshape(real(errorCovariance(user,user,:,:)), K, B);
        sinrDb = 10*log10(max(1./diagonal-1, realmin));
        perUser(user,:) = mean(sinrDb,1);
    end
    objectiveDb(first:last) = min(perUser,[],1).';
end
end
