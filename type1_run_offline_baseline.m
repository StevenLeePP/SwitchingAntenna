function report = type1_run_offline_baseline()
%TYPE1_RUN_OFFLINE_BASELINE Pure-MATLAB reference-to-BER regression harness.
%   No YunSDR, MEX receiver, sudo, or recorded IQ is required.  This is the
%   Phase-0 anchor for later independent-user and switch-nonideality studies.

package = type1_load_package();
cfg = package.cfg;
sim = type1_offline_sim_config();
stream = RandStream('mt19937ar', 'Seed', sim.seed);
nLayers = cfg.nLayers;
nSlots = numel(cfg.dataSlots);

infoErrors = zeros(sim.frames, nLayers);
codedErrors = zeros(sim.frames, nLayers);
evmPercent = zeros(sim.frames, nLayers);
cfoEstimateHz = zeros(sim.frames, 1);
timingOffset = zeros(sim.frames, 1);
pbchOK = false(sim.frames, 1);
conditionStats = zeros(sim.frames, 3);

fprintf('\n========== Type-A offline Phase-0 baseline ==========\n');
fprintf('frames=%d seed=%d SNR=%.1f dB commonCFO=%+.1f Hz switch=%d\n', ...
    sim.frames, sim.seed, sim.snrDb, sim.commonCfoHz, sim.useSwitchEmulation);
for frame = 1:sim.frames
    link = type1_offline_link(package, sim, stream);
    result = type1_analyze(link.virtualRx30, package);
    infoErrors(frame, :) = sum(result.infoBitErrors, 1);
    codedErrors(frame, :) = sum(result.codedBitErrors, 1);
    evmPercent(frame, :) = mean(result.evmRMSPercent, 1);
    cfoEstimateHz(frame) = result.frequencyOffsetHz;
    timingOffset(frame) = result.timingOffset;
    pbchOK(frame) = ~result.pbchCRCError && result.mibMatches;
    conditionStats(frame, :) = result.conditionStats;
    fprintf('offline frame=%d/%d PSS=%d CFO=%+.2fHz BER=[%s] EVM=[%s]%%\n', ...
        frame, sim.frames, result.timingOffset, result.frequencyOffsetHz, ...
        num2str(result.infoBER, '%.3g '), num2str(evmPercent(frame, :), '%.3f '));
end

bitsPerLayer = sim.frames * nSlots * package.nInfoBitsPerSlotLayer;
report = struct;
report.sim = sim;
report.frames = sim.frames;
report.bitsPerLayer = bitsPerLayer;
report.infoBitErrors = sum(infoErrors, 1);
report.codedBitErrors = sum(codedErrors, 1);
report.infoBER = report.infoBitErrors / bitsPerLayer;
report.codedBER = report.codedBitErrors / ...
    (sim.frames * nSlots * package.nCodedBitsPerSlotLayer);
report.meanEvmPercent = mean(evmPercent, 1);
report.cfoEstimateHz = cfoEstimateHz;
report.timingOffset = timingOffset;
report.pbchOK = pbchOK;
report.conditionStats = conditionStats;
report.perFrame = struct('infoBitErrors', infoErrors, ...
    'codedBitErrors', codedErrors, 'evmPercent', evmPercent, ...
    'cfoEstimateHz', cfoEstimateHz, 'timingOffset', timingOffset, ...
    'pbchOK', pbchOK, 'conditionStats', conditionStats);

if sim.assertIdealBaseline
    assert(all(pbchOK), 'type1:OfflineBaseline', 'PBCH/MIB failed in ideal baseline.');
    assert(all(report.infoBitErrors == 0), 'type1:OfflineBaseline', ...
        'Ideal baseline produced information-bit errors.');
    % Four-phase interpolation/de-interleaving changes the finite-window CP
    % estimate slightly (about 14 Hz in the deterministic regression); BER
    % is the end-to-end invariant, while 25 Hz still catches a bad CFO sign
    % or a materially broken synchronizer.
    assert(max(abs(cfoEstimateHz - sim.commonCfoHz)) < 25, ...
        'type1:OfflineBaseline', 'Common CFO estimate deviated by >=25 Hz.');
end

outputRoot = getenv('TYPE1_OFFLINE_OUTPUT_ROOT');
if isempty(outputRoot), outputRoot = cfg.outputRoot; end
out = fullfile(outputRoot, ['type1_offline_baseline_' ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
[created, message] = mkdir(out);
if ~created
    % Real-time MEX runs commonly create captures/ through sudo.  A pure
    % offline simulation must remain runnable as an unprivileged user.
    outputRoot = fullfile(tempdir, 'type1_offline_captures');
    out = fullfile(outputRoot, ['type1_offline_baseline_' ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
    [created, fallbackMessage] = mkdir(out);
    assert(created, 'type1:OfflineOutput', ...
        'Cannot create offline output (%s; fallback: %s).', message, fallbackMessage);
    warning('type1:OfflineOutputFallback', ...
        'Using user-writable offline output root: %s', outputRoot);
end
save(fullfile(out, 'type1_offline_baseline_results.mat'), 'report', '-v7.3');
fprintf('OFFLINE result: BER=[%s], EVM=[%s]%%, output=%s\n', ...
    num2str(report.infoBER, '%.3g '), ...
    num2str(report.meanEvmPercent, '%.3f '), out);
end
