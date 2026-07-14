function report = type1_run_offline_experiment(sim, label)
%TYPE1_RUN_OFFLINE_EXPERIMENT Shared pure-MATLAB Monte-Carlo experiment loop.
%   label is only a result-directory label; all physical assumptions remain
%   explicit in sim and are saved with every result.

arguments
    sim (1,1) struct
    label (1,:) char
end

package = type1_load_package();
cfg = package.cfg;
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

fprintf('\n========== Type-A offline %s experiment ==========\n', label);
fprintf('frames=%d SNR=%.1f dB commonCFO=%+.1f Hz userCFO=[%s] Hz switch=[IS=%g dB rise=%g ns]\n', ...
    sim.frames, sim.snrDb, sim.commonCfoHz, num2str(sim.userCfoHz), ...
    sim.switch.isolationDb, sim.switch.settlingRiseNs);
for frame = 1:sim.frames
    link = type1_offline_link(package, sim, stream);
    result = type1_analyze(link.virtualRx30, package);
    infoErrors(frame, :) = sum(result.infoBitErrors, 1);
    codedErrors(frame, :) = sum(result.codedBitErrors, 1);
    evmPercent(frame, :) = mean(result.evmRMSPercent, 1);
    cfoEstimateHz(frame) = result.frequencyOffsetHz;
    timingOffset(frame) = result.timingOffset;
    pbchOK(frame) = ~result.pbchCRCError && result.mibMatches;
    conditionStats(frame, :) = result.estimatedConditionStats;
end

bitsPerLayer = sim.frames * nSlots * package.nInfoBitsPerSlotLayer;
report = struct('sim', sim, 'frames', sim.frames, 'bitsPerLayer', bitsPerLayer, ...
    'infoBitErrors', sum(infoErrors, 1), 'codedBitErrors', sum(codedErrors, 1), ...
    'infoBER', sum(infoErrors, 1) / bitsPerLayer, ...
    'codedBER', sum(codedErrors, 1) / (sim.frames * nSlots * package.nCodedBitsPerSlotLayer), ...
    'meanEvmPercent', mean(evmPercent, 1), 'cfoEstimateHz', cfoEstimateHz, ...
    'timingOffset', timingOffset, 'pbchOK', pbchOK, ...
    'estimatedConditionStats', conditionStats, 'conditionStats', conditionStats, ...
    'perFrame', struct( ...
        'infoBitErrors', infoErrors, 'codedBitErrors', codedErrors, ...
        'evmPercent', evmPercent, 'cfoEstimateHz', cfoEstimateHz, ...
        'timingOffset', timingOffset, 'pbchOK', pbchOK, ...
        'conditionStats', conditionStats));

outputRoot = getenv('TYPE1_OFFLINE_OUTPUT_ROOT');
if isempty(outputRoot), outputRoot = cfg.outputRoot; end
out = fullfile(outputRoot, ['type1_offline_' label '_' ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
[created, message] = mkdir(out);
if ~created
    outputRoot = fullfile(tempdir, 'type1_offline_captures');
    out = fullfile(outputRoot, ['type1_offline_' label '_' ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
    [created, fallbackMessage] = mkdir(out);
    assert(created, 'type1:OfflineOutput', ...
        'Cannot create offline output (%s; fallback: %s).', message, fallbackMessage);
end
save(fullfile(out, ['type1_offline_' label '_results.mat']), 'report', '-v7.3');
report.outputDir=out;
fprintf('OFFLINE %s result: BER=[%s], EVM=[%s]%%, output=%s\n', ...
    label, num2str(report.infoBER, '%.3g '), ...
    num2str(report.meanEvmPercent, '%.3f '), out);
end
