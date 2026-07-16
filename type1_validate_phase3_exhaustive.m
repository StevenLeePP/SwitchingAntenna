function report = type1_validate_phase3_exhaustive()
%TYPE1_VALIDATE_PHASE3_EXHAUSTIVE R17 set/metric/optimality regression.

candidates = type1_phase3_enumerate_pair_partitions();
[M, N, count] = size(candidates);
model = type1_phase3_config(M, N); model.maxDutyCount = 1;
flattened = reshape(candidates, M*N, count).';
uniqueCount = size(unique(flattened, 'rows'), 1);
structurePassed = count == 2520 && uniqueCount == count && ...
    all(sum(candidates, 1) == 2, 'all') && ...
    all(sum(candidates, 2) == 1, 'all');
assert(structurePassed, 'type1:Phase3EnumerationStructure', ...
    'The exhaustive set is incomplete, duplicated, or violates pair partitions.');
for k = 1:count
    schedule = type1_phase3_make_schedule(candidates(:, :, k), model);
    assert(schedule.singleChainOutputWidth == 1);
end

stream = RandStream('mt19937ar', 'Seed', 20261700);
H = randn(stream, M, N, 7) + 1j*randn(stream, M, N, 7);
sigma2 = 0.17;
testIndices = [1 317 2520];
metricRelativeError = 0;
for index = testIndices
    S = candidates(:, :, index);
    pageMetric = type1_phase3_wideband_metrics(H, S, sigma2);
    directSinr = zeros(N, size(H, 3));
    Rn = sigma2 * (double(S).' * double(S));
    for tone = 1:size(H, 3)
        G = double(S).' * H(:, :, tone);
        W = (G' / Rn * G + eye(N)) \ (G' / Rn);
        for user = 1:N
            desired = abs(W(user, :) * G(:, user))^2;
            interference = sum(abs(W(user, :) * G).^2) - desired;
            noise = real(W(user, :) * Rn * W(user, :)');
            directSinr(user, tone) = desired / (interference + noise);
        end
    end
    metricRelativeError = max(metricRelativeError, ...
        norm(pageMetric.sinrLinear-directSinr, 'fro') / norm(directSinr, 'fro'));
end
assert(metricRelativeError <= 1e-12, 'type1:Phase3MetricRegression', ...
    'MMSE error-covariance SINR differs from direct combiner evaluation.');

objective = zeros(count, 1);
for index = 1:count
    metric = type1_phase3_wideband_metrics(H, candidates(:, :, index), sigma2);
    objective(index) = metric.objectiveDb;
end
[bestObjective, bestIndex] = max(objective);
optimalityPassed = objective(bestIndex) == bestObjective && ...
    all(bestObjective >= objective);
assert(optimalityPassed, 'type1:Phase3ExhaustiveOptimality', ...
    'Stored exhaustive optimum is not the maximum enumerated objective.');

report = struct('candidateCount', count, 'uniqueCount', uniqueCount, ...
    'structurePassed', structurePassed, ...
    'metricRelativeError', metricRelativeError, ...
    'optimalityPassed', optimalityPassed, 'allPassed', true);
fprintf(['Phase-3 R17 exhaustive validation PASSED: candidates=%d, ' ...
    'unique=%d, metric relerr=%.3g, optimum audit=%d.\n'], ...
    count, uniqueCount, metricRelativeError, optimalityPassed);
end
