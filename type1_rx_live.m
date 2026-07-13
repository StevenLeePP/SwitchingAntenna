function type1_rx_live()
%TYPE1_RX_LIVE YunSDR Type-A live receiver with selectable RX channels.
%
% Architecture:
%   C MEX background thread:  continuous 122.88 MS/s 4-ch ring buffer (64 ms)
%   MATLAB foreground loop:   C-side virtual snapshot -> fast DSP -> BER
%   Diagnostics/plots:        low-rate raw snapshot, independent of BER
%
% The function scope ensures proper cleanup of the radio device on
% normal exit, Ctrl+C, error, or MATLAB Stop.

close all; clc;

package = type1_load_package();
cfg = apply_runtime_rx_config(package.cfg);
package.cfg = cfg;
durationSec = env_number('TYPE1_LIVE_DURATION_SEC', cfg.liveDurationSec);
warmupSec = env_nonnegative('TYPE1_LIVE_WARMUP_SEC', cfg.liveWarmupSec);
updatePeriodSec = env_number('TYPE1_LIVE_UPDATE_SEC', cfg.liveUpdateSec);
computeThreads = round(env_number('TYPE1_LIVE_COMPUTE_THREADS', ...
    cfg.liveComputeThreads));
visible = getenv('TYPE1_LIVE_VISIBLE');
if isempty(visible), visible = 'on'; end
graphicsEnabled = ~strcmpi(visible, 'off');
clockTicksPerSec = linux_clock_ticks();

% Limit MATLAB worker threads to avoid contention with MEX RX thread
previousComputeThreads = maxNumCompThreads;
maxNumCompThreads(computeThreads);
computeCleanup = onCleanup(@() maxNumCompThreads(previousComputeThreads));

% ── Ring buffer parameters ──
blockDurationSec = 1e-3;                                  % 1 ms per block
blockSamples = round(cfg.rxSampleRate * blockDurationSec); % 122880 samples
analysisBlocks = cfg.liveAnalysisBlocks;                  % 20 ms Acquire/check window
initialIQBlocks = max(1, round(cfg.initialIQCaptureSec / blockDurationSec));
ringBlocks = cfg.liveRingBlocks;                          % 64 ms ring
fastDataSlot = cfg.dataSlots(ceil(numel(cfg.dataSlots) / 2));  % slot 10
fastSpectrumNfft = 2048;
fastConstellationPoints = 500;
signalPresenceThresholdDb = 8;  % in-band vs guard-band PSD difference
syncState = struct('valid', false);

% ── Build or locate the MEX ──
if exist('type1_yunsdr_rx_mex', 'file') ~= 3
    fprintf('Type-A RX MEX is missing; building it now.\n');
    type1_build_rx_mex();
end

% ── Open device, start background streaming ──
type1_yunsdr_rx_mex('open', cfg.deviceString, cfg.rxSampleRate, ...
    cfg.centerFrequencyHz, cfg.rxGain);
radioCleanup = onCleanup(@close_live_radio);
hardwareDepth = type1_yunsdr_rx_mex('hwdepth');
type1_yunsdr_rx_mex('start', blockSamples, ringBlocks);

% Create output directory
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outputDir = fullfile(cfg.outputRoot, ['type1_live_' stamp]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

% Create graphics only when requested. Headless benchmarking must not spend
% time constructing or updating invisible plot objects.
if graphicsEnabled
    [figureHandle, spectrumLines, beforeScatter, afterScatter] = ...
        create_live_figure(visible, cfg);
else
    figureHandle = gobjects(0);
    spectrumLines = gobjects(0);
    beforeScatter = gobjects(0);
    afterScatter = gobjects(0);
end

fprintf('\n========== YunSDR Type-A live RX ==========\n');
fprintf('Reference              : %s\n', cfg.referenceFile);
fprintf('Raw / virtual rates    : %.2f / %.2f MS/s\n', ...
    cfg.rxSampleRate / 1e6, cfg.txSampleRate / 1e6);
fprintf('Hardware / active RX   : %d captured / %d used, select=[%s]\n', ...
    cfg.nHardwareRxChannels, cfg.nRxChannels, num2str(cfg.rxChannelSelect));
fprintf('TX layers / DM-RS ports: %d / [%s]\n', ...
    cfg.nLayers, num2str(cfg.dmrsPortSet));
fprintf('Channel coding         : %s\n', package.channelCoding);
fprintf('Source example         : %s\n', ...
    package.payloadMetadata(1, 1).message);
if cfg.nRxChannels < cfg.nLayers
    fprintf(2, ['WARNING: active RX channels (%d) < TX layers (%d). ' ...
        'The receiver will monitor spectrum/PSS/SSS/PBCH only; ' ...
        'spatial data RZF, BER, and EVM are disabled.\n'], ...
        cfg.nRxChannels, cfg.nLayers);
end
fprintf('Background block/ring  : 1 ms / %d ms\n', ringBlocks);
fprintf('Acquire/check window   : %d ms / %.2f s BER loop\n', ...
    analysisBlocks, updatePeriodSec);
fprintf('Initial IQ dump        : %.1f ms raw122 + virtual30 into %s\n', ...
    1e3 * initialIQBlocks * blockDurationSec, cfg.dataRoot);
fprintf('Fast data slot         : %d (one of 19 slots/update)\n', fastDataSlot);
fprintf(['Sync policy            : full Acquire on loss; local +/- %d samples ' ...
    'PSS check every %d frames\n'], ...
    cfg.fastPSSLocalSearchSamples, cfg.fastPSSCheckIntervalFrames);
fprintf('CFO / diagnostics      : every %d frames / every %.2f s\n', ...
    cfg.fastCFOCheckIntervalFrames, cfg.liveDiagnosticsIntervalSec);
fprintf('PBCH / RMS normalize   : %d / %d\n', ...
    cfg.fastEnablePBCH, cfg.fastNormalizeRx);
fprintf('Constellation points   : %d per layer\n', fastConstellationPoints);
fprintf('MATLAB compute threads : %d\n', computeThreads);
fprintf('Configured HW buf depth: %u vendor units (capacity, not fill level)\n', ...
    hardwareDepth);
fprintf('Warm-up / measurement  : %.1f / %.1f s\n', warmupSec, durationSec);
graphicsText = 'disabled';
if graphicsEnabled, graphicsText = 'enabled'; end
fprintf('Graphics               : %s\n\n', graphicsText);

% ── Save the earliest short IQ dump before the heavier live loop starts ──
wait_for_rx_blocks(initialIQBlocks);
initialIQ = save_initial_iq_capture(cfg, initialIQBlocks);
fprintf('Initial IQ raw122      : %s\n', initialIQ.raw122File);
fprintf('Initial IQ virtual30   : %s\n\n', initialIQ.virtual30File);

% ── Wait for ring buffer to fill ──
startupTimer = tic;
while true
    status = type1_yunsdr_rx_mex('status');
    if status(3) == 0
        error('type1:RXThread', ...
            'Background RX stopped with return value %d.', status(4));
    end
    if status(2) >= analysisBlocks, break; end
    if toc(startupTimer) > 10
        error('type1:Startup', 'RX ring did not fill in 10 seconds.');
    end
    pause(0.02);
end

% Keep acquisition running during warm-up, but exclude it from statistics.
if warmupSec > 0
    fprintf('RX warm-up started: %.1f s (excluded from statistics).\n', warmupSec);
    warmupTimer = tic;
    % Exercise the complete fast DSP path once so JIT compilation and
    % MATLAB memory-pool growth are excluded from the 60 s leak benchmark.
    [warmupRaw, ~, ~] = type1_yunsdr_rx_mex('snapshot', 1);
    [warmupFrequencyMHz, warmupSpectrumDb] = live_spectrum( ...
        warmupRaw(end-blockSamples+1:end, cfg.rxChannelSelect), ...
        cfg.rxSampleRate, fastSpectrumNfft);
    if signal_presence_db(warmupFrequencyMHz, warmupSpectrumDb) >= ...
            signalPresenceThresholdDb
        warmupDspTimer = tic;
        [warmupVirtual, warmupTimestamps, ~] = ...
            type1_yunsdr_rx_mex('snapshotvirtual', analysisBlocks);
        warmupVirtual = warmupVirtual(:, cfg.rxChannelSelect);
        try
            warmupResult = type1_analyze_fast(warmupVirtual, package, ...
                fastDataSlot, 'snapshotStartRawTimestamp', ...
                warmupTimestamps(1), 'forcePSS', true);
            syncState = warmupResult.syncState;
            fprintf('RX DSP warm-up complete: %.1f ms.\n', ...
                1e3 * toc(warmupDspTimer));
        catch ME
            fprintf(2, 'RX DSP warm-up skipped: %s\n', ME.message);
        end
        clear warmupVirtual warmupResult;
    end
    clear warmupRaw warmupTimestamps warmupFrequencyMHz warmupSpectrumDb;
    while toc(warmupTimer) < warmupSec
        status = type1_yunsdr_rx_mex('status');
        if status(3) == 0
            error('type1:RXThread', ...
                'Background RX stopped with return value %d.', status(4));
        end
        if graphicsEnabled, drawnow limitrate nocallbacks; end
        pause(0.05);
    end
    fprintf('RX warm-up complete; starting %.1f s measurement.\n\n', durationSec);
end

%% ═══ Main live loop ═══
runTimer = tic;
lastUpdate = -inf;
lastSequence = [];
lastTimestamp = [];
totalTimestampGap = 0;
lastResult = struct;
runtimeTemplate = runtime_sample_template(cfg.nRxChannels, cfg.nLayers);
runtimeSamples = repmat(runtimeTemplate, 0, 1);
eventsStart = type1_yunsdr_rx_mex('events');
currentEvents = eventsStart;
lastEventPoll = -inf;
firstHardwareTimestamp = [];
lastHardwareTimestamp = [];
firstHardwareWallSec = [];
lastHardwareWallSec = [];
lastDiagnosticsSec = -inf;
lastConstellationFrameRaw = uint64(0);
lastTerminalSec = -inf;
cachedPresenceDb = nan;
cachedSnrNullDb = nan(1, cfg.nRxChannels);
cachedSnrDmrsDb = nan(1, cfg.nRxChannels);
cachedConditionStats = nan(1, 3);
virtualAbsenceCount = 0;

while toc(runTimer) < durationSec && ...
        (~graphicsEnabled || isgraphics(figureHandle))
    % Wait for next update interval
    if toc(runTimer) - lastUpdate < updatePeriodSec
        if graphicsEnabled, drawnow limitrate nocallbacks; end
        pause(0.01);
        continue;
    end

    iterationTimer = tic;
    elapsedSec = toc(runTimer);
    sample = runtime_sample_template(cfg.nRxChannels, cfg.nLayers);
    sample.timeSec = elapsedSec;
    statusNow = type1_yunsdr_rx_mex('status');
    sample.storedRingBlocks = statusNow(2);
    sample.rxThreadRunning = statusNow(3);
    sample.lastReadReturn = statusNow(4);
    if statusNow(3) == 0
        error('type1:RXThread', ...
            'Background RX stopped with return value %d.', statusNow(4));
    end

    % ── Low-rate diagnostics: 1 ms raw IQ only, not part of BER path ──
    diagnosticsDue = elapsedSec - lastDiagnosticsSec >= ...
        cfg.liveDiagnosticsIntervalSec;
    if diagnosticsDue
        spectrumTimer = tic;
        [diagnosticRaw, ~, ~] = type1_yunsdr_rx_mex('snapshot', 1);
        [cachedFrequencyMHz, cachedSpectrumDb] = live_spectrum( ...
            diagnosticRaw(:, cfg.rxChannelSelect), cfg.rxSampleRate, ...
            fastSpectrumNfft);
        cachedPresenceDb = signal_presence_db(cachedFrequencyMHz, ...
            cachedSpectrumDb);
        sample.spectrumMs = 1e3 * toc(spectrumTimer);
        lastDiagnosticsSec = elapsedSec;
        if graphicsEnabled
            plotTimer = tic;
            update_spectrum(spectrumLines, cachedFrequencyMHz, cachedSpectrumDb);
            drawnow limitrate nocallbacks;
            sample.plotMs = sample.plotMs + 1e3 * toc(plotTimer);
        end
    end
    % The physical PSD is a display diagnostic only. Its 1 ms estimate can
    % fluctuate with switched phases, so it must not reset sync or suppress
    % BER. The virtual30 gate below is the authoritative data-path check.
    sample.presenceDb = cachedPresenceDb;

    % ── BER path: C-side switch returns only virtual30 samples ──
    snapshotTimer = tic;
    [virtualRF, timestamps, sequence] = ...
        type1_yunsdr_rx_mex('snapshotvirtual', analysisBlocks);
    snapshotMs = 1e3 * toc(snapshotTimer);
    sample.snapshotMs = snapshotMs;
    sample.switchMs = 0;  % included in snapshotMs: performed inside C MEX
    if size(virtualRF, 1) < analysisBlocks * blockSamples / 4
        pause(0.001);
        continue;
    end
    virtualRF = virtualRF(:, cfg.rxChannelSelect);
    sample.sequence = double(sequence);

    % A display spectrum is intentionally low-rate, but BER must never be
    % accumulated during the up-to-0.5 s interval after TX disappears.
    % Check signal presence on the already-copied virtual30 IQ every loop;
    % this adds no raw-122 copy and does not update the figure.
    virtualPresenceDb = virtual_signal_presence(virtualRF, cfg.txSampleRate);
    if virtualPresenceDb < signalPresenceThresholdDb
        virtualAbsenceCount = virtualAbsenceCount + 1;
        if virtualAbsenceCount >= cfg.fastSignalLossConfirmations
            syncState = struct('valid', false);
        end
        sample.outcome = 'no-signal-fast-gate';
        sample.presenceDb = virtualPresenceDb;
        if graphicsEnabled
            plotTimer = tic;
            clear_constellations(beforeScatter, afterScatter);
            drawnow limitrate nocallbacks;
            sample.plotMs = sample.plotMs + 1e3 * toc(plotTimer);
        end
        [sample.rssMb, sample.cpuTicks] = process_linux_stats();
        sample.iterationMs = 1e3 * toc(iterationTimer);
        runtimeSamples(end+1) = sample; %#ok<AGROW>
        lastUpdate = toc(runTimer);
        continue;
    end
    virtualAbsenceCount = 0;

    % ── Timestamp continuity check ──
    newestTimestamp = timestamps(end);
    if ~isempty(lastSequence)
        sequenceAdvance = double(sequence - lastSequence);
        sample.sequenceAdvanceBlocks = sequenceAdvance;
        sample.skippedCaptureBlocks = max(sequenceAdvance - analysisBlocks, 0);
        expectedAdvance = uint64(sequenceAdvance * blockSamples);
        actualAdvance = newestTimestamp - lastTimestamp;
        timestampGap = double(actualAdvance) - double(expectedAdvance);
        sample.timestampGapSamples = timestampGap;
        if timestampGap ~= 0
            totalTimestampGap = totalTimestampGap + max(timestampGap, 0);
            fprintf(2, ...
                'RX timestamp discontinuity: %+d raw samples at seq %u\n', ...
                timestampGap, sequence);
        end
    end
    lastSequence = sequence;
    lastTimestamp = newestTimestamp;

    hardwareTimestampNow = type1_yunsdr_rx_mex('timestamp');
    lastSampleTimestamp = newestTimestamp + uint64(blockSamples);
    if hardwareTimestampNow >= lastSampleTimestamp
        sample.captureAgeMs = 1e3 * ...
            double(hardwareTimestampNow - lastSampleTimestamp) / ...
            cfg.rxSampleRate;
    end
    if isempty(firstHardwareTimestamp)
        firstHardwareTimestamp = hardwareTimestampNow;
        firstHardwareWallSec = elapsedSec;
    end
    lastHardwareTimestamp = hardwareTimestampNow;
    lastHardwareWallSec = elapsedSec;

    try
        [forcePSS, localPSSCheck] = sync_actions(syncState, timestamps(1), cfg);
        result = type1_analyze_fast(virtualRF, package, fastDataSlot, ...
            'forcePSS', forcePSS, 'validatePSS', localPSSCheck, ...
            'syncState', syncState, ...
            'snapshotStartRawTimestamp', timestamps(1), ...
            'computeSNR', diagnosticsDue, ...
            'computeCondition', diagnosticsDue);
        syncState = result.syncState;
        if diagnosticsDue
            cachedSnrNullDb = result.snrNullDb;
            cachedSnrDmrsDb = result.snrDmrsDb;
            cachedConditionStats = result.conditionStats;
        else
            % Keep output/plots continuous while heavy diagnostics run only
            % at the independent low-rate diagnostic cadence.
            result.snrNullDb = cachedSnrNullDb;
            result.snrDmrsDb = cachedSnrDmrsDb;
            result.conditionStats = cachedConditionStats;
        end
    catch ME
        syncState = struct('valid', false);
        sample.outcome = 'analysis-error';
        sample.errorMessage = ME.message;
        [sample.rssMb, sample.cpuTicks] = process_linux_stats();
        sample.iterationMs = 1e3 * toc(iterationTimer);
        runtimeSamples(end+1) = sample; %#ok<AGROW>
        fprintf(2, 'Type-A analysis skipped: %s\n', ME.message);
        lastUpdate = toc(runTimer);
        continue;
    end
    sample.analysisMs = result.elapsedMs;
    lastResult = result;

    % ── Update constellation displays ──
    plotTimer = tic;
    updateConstellation = should_update_constellation( ...
        lastConstellationFrameRaw, timestamps(1), result.timingOffset, cfg);
    if updateConstellation
        lastConstellationFrameRaw = timestamps(1) + ...
            uint64(4 * max(result.timingOffset, 0));
    end
    if graphicsEnabled && updateConstellation
        before = normalize_symbols(result.preCompData(:));
        before = decimate_symbols(before, fastConstellationPoints);
        show_constellations(beforeScatter);
        set(beforeScatter, 'XData', real(before), 'YData', imag(before));
        if result.spatialDecodeEnabled
            for layer = 1:cfg.nLayers
                after = normalize_symbols(result.postCompData(:, layer));
                after = decimate_symbols(after(:), fastConstellationPoints);
                set(afterScatter(layer), 'XData', real(after), ...
                    'YData', imag(after));
            end
        else
            clear_after_constellation(afterScatter);
        end
        drawnow limitrate nocallbacks;
    end
    sample.plotMs = sample.plotMs + 1e3 * toc(plotTimer);

    % ── Terminal printout ──
    sample.outcome = 'decoded';
    sample.snrNullDb = result.snrNullDb;
    sample.snrDmrsDb = result.snrDmrsDb;
    sample.rawBER = result.rawBER;
    sample.decodedBER = result.decodedBER;
    sample.evmRMSPercent = result.evmRMSPercent;
    sample.conditionStats = result.conditionStats;
    sample.timingOffset = result.timingOffset;
    sample.frequencyOffsetHz = result.frequencyOffsetHz;
    sample.cpCorrelation = result.cpCorrelation;
    sample.sssMetric = result.sssMetric;
    sample.usedPSS = result.usedPSS;
    sample.localPSSChecked = result.localPSSChecked;
    sample.pssAgeFrames = result.pssAgeFrames;
    sample.cfoUpdated = result.cfoUpdated;
    sample.pbchChecked = result.pbchChecked;
    sample.pbchCRCOK = result.pbchChecked && ~result.pbchCRCError;
    sample.mibMatches = result.mibMatches;
    [sample.rssMb, sample.cpuTicks] = process_linux_stats();
    if elapsedSec - lastEventPoll >= 1
        currentEvents = type1_yunsdr_rx_mex('events');
        lastEventPoll = elapsedSec;
    end
    sample.rxEvents = currentEvents;
    sample.iterationMs = 1e3 * toc(iterationTimer);
    runtimeSamples(end+1) = sample; %#ok<AGROW>
    absolutePSSTimestamp = result.syncState.frameStartRawTimestamp;

    if result.pbchChecked
        pbchStatus = sprintf('PBCH_checked=1 CRC_OK=%d MIB_match=%d', ...
            ~result.pbchCRCError, result.mibMatches);
    else
        pbchStatus = 'PBCH=disabled';
    end
    if elapsedSec - lastTerminalSec >= cfg.liveTerminalIntervalSec || ...
            result.usedPSS || result.localPSSChecked
        fprintf(['type1 t=%6.2f s seq=%7u Cvirtual=%5.1f ms ' ...
            'analysis=%6.1f ms age=%5.2f ms slot=%d\n' ...
            '  PSS_mode=%s age_frames=%g peak=%g peak/median=%.1f dB raw_ts=%u\n' ...
            '  CFO=%+.1f Hz updated=%d CP_corr=%.3f SSS_metric=%.4f %s\n' ...
            '  SNR_null_rx_dB=[%s] SNR_dmrs_rx_dB=[%s]\n' ...
            '  coding=%s raw_BER=[%s] decoded_BER=[%s] errors=[%s]\n' ...
            '  EVM_pct=[%s] cond(H) med/p95/max=[%s] spatial_decode=%d\n'], ...
            toc(runTimer), sequence, snapshotMs, ...
            result.elapsedMs, sample.captureAgeMs, result.dataSlot, ...
            result.pssMode, result.pssAgeFrames, result.pssPeak, ...
            result.pssPeakToMedianDb, absolutePSSTimestamp, ...
            result.frequencyOffsetHz, result.cfoUpdated, result.cpCorrelation, ...
            result.sssMetric, pbchStatus, ...
            num2str(result.snrNullDb, '%.2f '), ...
            num2str(result.snrDmrsDb, '%.2f '), ...
            result.channelCoding, ...
            num2str(result.rawBER, '%.3g '), ...
            num2str(result.decodedBER, '%.3g '), ...
            num2str(result.decodedBitErrors, '%d '), ...
            num2str(result.evmRMSPercent, '%.1f '), ...
            num2str(result.conditionStats, '%.1f '), ...
            result.spatialDecodeEnabled);
        lastTerminalSec = elapsedSec;
    end
    lastUpdate = toc(runTimer);
end

%% ═══ Shutdown and save ═══
type1_yunsdr_rx_mex('stop');
events = type1_yunsdr_rx_mex('events');
eventDelta = events - eventsStart;

updates = numel(runtimeSamples);
snapshotTimes = [runtimeSamples.snapshotMs];
analysisTimes = [runtimeSamples.analysisMs];
switchTimes = [runtimeSamples.switchMs];
iterationTimes = [runtimeSamples.iterationMs];
plotTimes = [runtimeSamples.plotMs];
captureAges = [runtimeSamples.captureAgeMs];
rssMb = [runtimeSamples.rssMb];
cpuTicks = [runtimeSamples.cpuTicks];
sampleTimesSec = [runtimeSamples.timeSec];
decodedMask = strcmp({runtimeSamples.outcome}, 'decoded');
snrNullMatrix = vertcat(runtimeSamples.snrNullDb);
snrDmrsMatrix = vertcat(runtimeSamples.snrDmrsDb);
validAnalysisTimes = analysisTimes(isfinite(analysisTimes));
realtimeFactors = validAnalysisTimes / ...
    (1e3 * cfg.frameDurationSec);  % fast monitor touches one 10 ms frame
skippedCaptureBlocks = sum([runtimeSamples.skippedCaptureBlocks], 'omitnan');
captureAdvanceBlocks = sum([runtimeSamples.sequenceAdvanceBlocks], 'omitnan');
capturedMeasurementSec = captureAdvanceBlocks * blockDurationSec;
decodedDataSlots = sum(decodedMask);  % one representative slot per update
availableDataSlots = capturedMeasurementSec / cfg.frameDurationSec * ...
    numel(cfg.dataSlots);
payloadSlotCoveragePercent = 100 * decodedDataSlots / ...
    max(availableDataSlots, 1);

memorySlopeMbPerMin = linear_slope_per_minute(sampleTimesSec, rssMb);
steadyStart = max(1, floor(0.75 * numel(rssMb)) + 1);
steadyRss = rssMb(steadyStart:end);
[memorySteadySlopeMbPerMin, steadyRssRangeMb] = ...
    robust_memory_trend(sampleTimesSec(steadyStart:end), steadyRss);
cpuCoreEquivalent = nan(1, max(numel(cpuTicks) - 1, 0));
if numel(cpuTicks) >= 2
    deltaWall = diff(sampleTimesSec);
    deltaCpu = diff(cpuTicks) / clockTicksPerSec;
    validCpu = deltaWall > 0 & isfinite(deltaCpu);
    cpuCoreEquivalent(validCpu) = deltaCpu(validCpu) ./ deltaWall(validCpu);
end
timestampTickRate = nan;
if ~isempty(firstHardwareTimestamp) && lastHardwareWallSec > firstHardwareWallSec
    timestampTickRate = double(lastHardwareTimestamp - firstHardwareTimestamp) ...
        / (lastHardwareWallSec - firstHardwareWallSec);
end
sequenceAdvanceVector = [runtimeSamples.sequenceAdvanceBlocks];
timestampGapVector = [runtimeSamples.timestampGapSamples];
validTimestampBlocks = sequenceAdvanceVector > 0;
timestampTicksPerBlock = blockSamples + ...
    timestampGapVector(validTimestampBlocks) ./ ...
    sequenceAdvanceVector(validTimestampBlocks);
timestampRateFromBlocks = median(timestampTicksPerBlock, 'omitnan') / ...
    blockDurationSec;
snapshotStats = metric_stats(snapshotTimes);
ringCopyHeadroomMs = (ringBlocks - analysisBlocks) * blockDurationSec * 1e3 ...
    - snapshotStats(3);

imageFile = '';
figureFile = '';
if graphicsEnabled && isgraphics(figureHandle)
    imageFile = fullfile(outputDir, 'type1_live_last.png');
    figureFile = fullfile(outputDir, 'type1_live_last.fig');
    exportgraphics(figureHandle, imageFile, ...
        'Resolution', 160, 'BackgroundColor', 'white');
    savefig(figureHandle, figureFile);
end

summary = struct;
summary.cfg = cfg;
summary.durationSec = toc(runTimer);
summary.updates = updates;
summary.snapshotTimesMs = snapshotTimes;
summary.analysisTimesMs = analysisTimes;
summary.switchTimesMs = switchTimes;
summary.iterationTimesMs = iterationTimes;
summary.plotTimesMs = plotTimes;
summary.captureAgeMs = captureAges;
summary.runtimeSamples = runtimeSamples;
summary.realtimeFactors = realtimeFactors;
summary.skippedCaptureBlocks = skippedCaptureBlocks;
summary.captureAdvanceBlocks = captureAdvanceBlocks;
summary.payloadSlotCoveragePercent = payloadSlotCoveragePercent;
summary.snrNullDb = snrNullMatrix;
summary.snrDmrsDb = snrDmrsMatrix;
summary.memoryRssMb = rssMb;
summary.memorySlopeMbPerMin = memorySlopeMbPerMin;
summary.memorySteadySlopeMbPerMin = memorySteadySlopeMbPerMin;
summary.memorySteadyRangeMb = steadyRssRangeMb;
summary.cpuCoreEquivalent = cpuCoreEquivalent;
summary.clockTicksPerSec = clockTicksPerSec;
summary.timestampTickRate = timestampTickRate;
summary.timestampTickRateRatio = timestampTickRate / cfg.rxSampleRate;
summary.timestampRateFromBlocks = timestampRateFromBlocks;
summary.timestampRateFromBlocksRatio = timestampRateFromBlocks / ...
    cfg.rxSampleRate;
summary.configuredHardwareBufferDepth = hardwareDepth;
summary.ringCopyHeadroomMs = ringCopyHeadroomMs;
summary.totalTimestampGapSamples = totalTimestampGap;
summary.events = events;
summary.eventDelta = eventDelta;
summary.lastResult = lastResult;
summary.imageFile = imageFile;
summary.figureFile = figureFile;
save(fullfile(outputDir, 'type1_live_results.mat'), 'summary', '-v7.3');

fprintf('\nType-A live RX stopped.\n');
fprintf('Measurement duration       : %.2f s (after %.1f s warm-up)\n', ...
    summary.durationSec, warmupSec);
fprintf('Updates / decoded slots    : %d / %d\n', updates, decodedDataSlots);
fprintf('Snapshot ms med/p95/max    : [%s]\n', ...
    num2str(metric_stats(snapshotTimes), '%.2f '));
fprintf('Switch ms med/p95/max      : [%s]\n', ...
    num2str(metric_stats(switchTimes), '%.2f '));
fprintf('Analysis ms med/p95/max    : [%s]\n', ...
    num2str(metric_stats(validAnalysisTimes), '%.2f '));
fprintf('Plot ms med/p95/max        : [%s]\n', ...
    num2str(metric_stats(plotTimes), '%.2f '));
fprintf('Realtime factor med/p95/max: [%s] (must sustain <1)\n', ...
    num2str(metric_stats(realtimeFactors), '%.2f '));
fprintf('Payload-slot coverage      : %.3f %% of captured data slots\n', ...
    payloadSlotCoveragePercent);
fprintf('Null SNR median per RX dB  : [%s]\n', ...
    num2str(median(snrNullMatrix, 1, 'omitnan'), '%.2f '));
fprintf('DM-RS SNR median per RX dB : [%s]\n', ...
    num2str(median(snrDmrsMatrix, 1, 'omitnan'), '%.2f '));
fprintf('Skipped newest-ring blocks : %.0f (latest-snapshot monitor policy)\n', ...
    skippedCaptureBlocks);
fprintf('Capture age ms med/p95/max : [%s]\n', ...
    num2str(metric_stats(captureAges), '%.3f '));
fprintf('Ring copy safety headroom  : %.2f ms\n', ringCopyHeadroomMs);
fprintf('RSS MB start/end/full slope: %.1f / %.1f / %+.2f MB/min\n', ...
    first_finite(rssMb), last_finite(rssMb), memorySlopeMbPerMin);
fprintf('RSS last-quarter slope/range: %+.2f MB/min / %.2f MB\n', ...
    memorySteadySlopeMbPerMin, steadyRssRangeMb);
fprintf('CPU core use med/p95/max   : [%s] cores\n', ...
    num2str(metric_stats(cpuCoreEquivalent), '%.2f '));
fprintf('HW timestamp tick rate     : %.3f MS/s (%.6f x configured Fs)\n', ...
    timestampTickRate / 1e6, timestampTickRate / cfg.rxSampleRate);
fprintf('Timestamp rate from blocks : %.3f MS/s (%.6f x configured Fs)\n', ...
    timestampRateFromBlocks / 1e6, ...
    timestampRateFromBlocks / cfg.rxSampleRate);
fprintf('Timestamp gap total        : %.0f raw samples\n', totalTimestampGap);
fprintf('RX event delta overflow/count/timeout: [%s] / [%s] / [%s]\n', ...
    num2str(eventDelta(:,1).'), num2str(eventDelta(:,2).'), ...
    num2str(eventDelta(:,3).'));
fprintf('Results                    : %s\n', outputDir);

clear radioCleanup;
clear computeCleanup;
end

%% ═══ Local helper functions ═══

function value = env_number(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value <= 0, value = defaultValue; end
end

function value = env_nonnegative(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value < 0, value = defaultValue; end
end

function [forceAcquire, localPSSCheck] = sync_actions(syncState, snapshotStartRaw, cfg)
forceAcquire = ~isfield(syncState, 'valid') || ~syncState.valid || ...
    ~isfield(syncState, 'frameStartRawTimestamp') || ...
    syncState.frameStartRawTimestamp == 0;
localPSSCheck = false;
if forceAcquire, return; end
framePeriodRaw = round(cfg.rxSampleRate * cfg.frameDurationSec);
framesSincePSS = floor((double(snapshotStartRaw) - ...
    double(syncState.frameStartRawTimestamp)) / framePeriodRaw);
if ~isfinite(framesSincePSS) || framesSincePSS < 0
    forceAcquire = true;
else
    localPSSCheck = framesSincePSS >= cfg.fastPSSCheckIntervalFrames;
end
end

function update = should_update_constellation(lastFrameRaw, snapshotStartRaw, ...
        timingOffset, cfg)
if snapshotStartRaw == 0
    update = true;
    return;
end
frameRaw = double(snapshotStartRaw) + 4 * timingOffset;
if frameRaw < 0
    update = false;
    return;
end
if lastFrameRaw == 0
    update = true;
    return;
end
update = frameRaw - double(lastFrameRaw) >= ...
    cfg.liveConstellationIntervalFrames * ...
    cfg.frameDurationSec * cfg.rxSampleRate;
end

function cfg = apply_runtime_rx_config(cfg)
% Keep TX-layer/reference parameters fixed, but allow RX-side antenna
% selection at run time without regenerating nr4_type1_reference.mat.
sourceDir = fileparts(mfilename('fullpath'));
if ~isfield(cfg, 'dataRoot')
    cfg.dataRoot = fullfile(sourceDir, 'data');
end
if ~isfield(cfg, 'initialIQCaptureSec')
    cfg.initialIQCaptureSec = 20e-3;
end
if ~isfield(cfg, 'fastPSSCheckIntervalFrames')
    cfg.fastPSSCheckIntervalFrames = 50;
end
if ~isfield(cfg, 'fastPSSLocalSearchSamples')
    cfg.fastPSSLocalSearchSamples = 512;
end
if ~isfield(cfg, 'fastPSSMinPeakToMedianDb')
    cfg.fastPSSMinPeakToMedianDb = 8;
end
if ~isfield(cfg, 'fastEnablePBCH')
    cfg.fastEnablePBCH = false;
end
if ~isfield(cfg, 'fastValidateSSSWithPSS')
    cfg.fastValidateSSSWithPSS = true;
end
if ~isfield(cfg, 'fastNormalizeRx')
    cfg.fastNormalizeRx = false;
end
if ~isfield(cfg, 'fastCFOCheckIntervalFrames')
    cfg.fastCFOCheckIntervalFrames = 50;
end
if ~isfield(cfg, 'liveDiagnosticsIntervalSec')
    cfg.liveDiagnosticsIntervalSec = 1.0;
end
diagnosticInterval = str2double(getenv('TYPE1_LIVE_DIAGNOSTICS_SEC'));
if isfinite(diagnosticInterval) && diagnosticInterval > 0
    cfg.liveDiagnosticsIntervalSec = diagnosticInterval;
end
if ~isfield(cfg, 'liveConstellationIntervalFrames')
    cfg.liveConstellationIntervalFrames = 10;
end
if ~isfield(cfg, 'liveTerminalIntervalSec')
    cfg.liveTerminalIntervalSec = 0.5;
end
if ~isfield(cfg, 'fastSignalLossConfirmations')
    cfg.fastSignalLossConfirmations = 3;
end
if ~isfield(cfg, 'fastUseRZFQPSKMEX')
    cfg.fastUseRZFQPSKMEX = true;
end
if ~isfield(cfg, 'fastUseType1DMRSMEX')
    cfg.fastUseType1DMRSMEX = true;
end
if ~isfield(cfg, 'nHardwareRxChannels')
    cfg.nHardwareRxChannels = 4;
end
if ~isfield(cfg, 'rxChannelSelect')
    cfg.rxChannelSelect = 1:cfg.nHardwareRxChannels;
end

selectionText = getenv('TYPE1_RX_CHANNEL_SELECT');
if isempty(selectionText)
    selectionText = getenv('TYPE1_RX_CHANNELS');
end
if ~isempty(selectionText)
    selected = sscanf(regexprep(selectionText, '[,;: ]+', ' '), '%d').';
    if isempty(selected)
        error('type1:RxChannelSelect', ...
            'TYPE1_RX_CHANNEL_SELECT="%s" did not contain channel numbers.', ...
            selectionText);
    end
else
    requestedCount = str2double(getenv('TYPE1_N_RX_CHANNELS'));
    if isfinite(requestedCount) && requestedCount > 0
        selected = 1:round(requestedCount);
    else
        selected = cfg.rxChannelSelect;
    end
end

selected = unique(selected, 'stable');
if any(selected < 1) || any(selected > cfg.nHardwareRxChannels)
    error('type1:RxChannelSelect', ...
        'RX channel selection [%s] is outside 1..%d.', ...
        num2str(selected), cfg.nHardwareRxChannels);
end
cfg.rxChannelSelect = selected;
cfg.nRxChannels = numel(selected);
end

function close_live_radio()
try
    type1_yunsdr_rx_mex('stop');
catch
end
try
    type1_yunsdr_rx_mex('close');
catch
end
disp('Type-A YunSDR RX device closed.');
end

function wait_for_rx_blocks(requiredBlocks)
timer = tic;
while true
    status = type1_yunsdr_rx_mex('status');
    if status(3) == 0
        error('type1:RXThread', ...
            'Background RX stopped with return value %d.', status(4));
    end
    if status(2) >= requiredBlocks, return; end
    if toc(timer) > 10
        error('type1:Startup', ...
            'RX ring did not reach %d blocks in 10 seconds.', requiredBlocks);
    end
    pause(0.01);
end
end

function info = save_initial_iq_capture(cfg, initialBlocks)
% Save a short startup IQ dump in a simple fopen/fread-friendly format.
% Binary layout for each file:
%   single precision, column-major MATLAB order, interleaved real/imag.
%   For x = [nSamples x nChannels]:
%     file = [real(x(:)); imag interleaved sample-by-sample as I,Q,I,Q...]
[raw122, timestamps, sequence] = type1_yunsdr_rx_mex('snapshot', initialBlocks);
[~, virtual30] = type1_digital_switch(raw122);

if ~exist(cfg.dataRoot, 'dir'), mkdir(cfg.dataRoot); end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
baseName = sprintf('type1_initial_iq_%s_seq%u', stamp, sequence);
raw122File = fullfile(cfg.dataRoot, [baseName '_raw122_csingle_iq4.bin']);
virtual30File = fullfile(cfg.dataRoot, [baseName '_virtual30_csingle_iq4.bin']);
metaFile = fullfile(cfg.dataRoot, [baseName '_meta.mat']);

write_complex_single_binary(raw122File, raw122);
write_complex_single_binary(virtual30File, virtual30);

info = struct;
info.createdAt = datetime('now');
info.raw122File = raw122File;
info.virtual30File = virtual30File;
info.metaFile = metaFile;
info.format = 'complex single, column-major, interleaved I/Q';
info.rawSampleRate = cfg.rxSampleRate;
info.virtualSampleRate = cfg.txSampleRate;
info.rawSize = size(raw122);
info.virtualSize = size(virtual30);
info.nChannels = size(raw122, 2);
info.durationSec = size(raw122, 1) / cfg.rxSampleRate;
info.timestamps = timestamps;
info.sequence = sequence;
info.rxChannelSelect = cfg.rxChannelSelect;
info.nLayers = cfg.nLayers;
save(metaFile, 'info');
end

function write_complex_single_binary(fileName, x)
fid = fopen(fileName, 'wb');
if fid < 0
    error('type1:IQFileOpen', 'Could not open %s for writing.', fileName);
end
cleanup = onCleanup(@() fclose(fid));
x = single(x);
packed = zeros(2 * numel(x), 1, 'single');
packed(1:2:end) = real(x(:));
packed(2:2:end) = imag(x(:));
written = fwrite(fid, packed, 'single');
if written ~= numel(packed)
    error('type1:IQFileWrite', ...
        'Only wrote %d of %d single values to %s.', ...
        written, numel(packed), fileName);
end
clear cleanup;
end

function [fig, spectrumLines, beforeScatter, afterScatter] = ...
        create_live_figure(visible, cfg)
% Create 2×2 tiled figure: spectrum (top row, full width),
% before-eq constellation (bottom-left), after-eq constellation (bottom-right).
colors = lines(max(cfg.nLayers, cfg.nRxChannels));
fig = figure('Name', 'NR Type-A live monitor', ...
    'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
    'Position', [80 80 1280 820]);
layout = tiledlayout(fig, 2, 2, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

% Top: active-channel live spectrum
spectrumAxis = nexttile(layout, [1 2]);
hold(spectrumAxis, 'on');
spectrumLines = gobjects(1, cfg.nRxChannels);
for channel = 1:cfg.nRxChannels
    spectrumLines(channel) = plot(spectrumAxis, nan, nan, ...
        'Color', colors(channel,:), ...
        'DisplayName', sprintf('RX%d', cfg.rxChannelSelect(channel)));
end
grid(spectrumAxis, 'on'); box(spectrumAxis, 'on');
xlim(spectrumAxis, [-61.44 61.44]); ylim(spectrumAxis, [-170 -60]);
xlabel(spectrumAxis, 'Baseband frequency (MHz)');
ylabel(spectrumAxis, 'PSD (dBFS/Hz)');
title(spectrumAxis, sprintf( ...
    'Live physical RX spectrum, 122.88 MS/s, active RX=[%s]', ...
    num2str(cfg.rxChannelSelect)));
legend(spectrumAxis, 'Location', 'northeast');

% Bottom-left: before equalization (RX1 raw mixture)
beforeAxis = nexttile(layout);
afterAxis = nexttile(layout);
beforeScatter = scatter(beforeAxis, nan, nan, 8, ...
    [0.25 0.25 0.25], 'filled', 'MarkerFaceAlpha', 0.25, ...
    'DisplayName', 'RX1 four-layer mixture');
hold(beforeAxis, 'on');
% Bottom-right: after equalization (separated TX layers when nRx >= nLayers)
afterScatter = gobjects(1, cfg.nLayers);
hold(afterAxis, 'on');
for layer = 1:cfg.nLayers
    afterScatter(layer) = scatter(afterAxis, nan, nan, 8, ...
        colors(layer,:), 'filled', 'MarkerFaceAlpha', 0.3, ...
        'DisplayName', sprintf('Layer/port %d', layer));
end
% Ideal QPSK reference markers (hidden when no signal)
ideal = exp(1j * (pi/4 + (0:3)*pi/2));
plot(beforeAxis, real(ideal), imag(ideal), 'kx', ...
    'MarkerSize', 10, 'LineWidth', 1.5, ...
    'HandleVisibility', 'off', 'Tag', 'IdealQPSK', 'Visible', 'off');
plot(afterAxis, real(ideal), imag(ideal), 'kx', ...
    'MarkerSize', 10, 'LineWidth', 1.5, ...
    'HandleVisibility', 'off', 'Tag', 'IdealQPSK', 'Visible', 'off');
text(beforeAxis, 0, 0, 'NO SIGNAL', ...
    'Color', [0.8 0 0], 'FontSize', 18, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'Tag', 'NoSignalText');
text(afterAxis, 0, 0, 'NO SIGNAL', ...
    'Color', [0.8 0 0], 'FontSize', 18, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'Tag', 'NoSignalText');
format_axis(beforeAxis, 'Before equalization: valid data REs on RX1');
format_axis(afterAxis, sprintf( ...
    'After standard Type-1 DM-RS + %dx%d RZF', ...
    cfg.nRxChannels, cfg.nLayers));
legend(beforeAxis, 'Location', 'best');
legend(afterAxis, 'Location', 'best');
end

function format_axis(axisHandle, titleText)
grid(axisHandle, 'on'); box(axisHandle, 'on');
axis(axisHandle, 'equal');
xlim(axisHandle, [-2 2]); ylim(axisHandle, [-2 2]);
xlabel(axisHandle, 'In-phase');
ylabel(axisHandle, 'Quadrature');
title(axisHandle, titleText);
end

function symbols = normalize_symbols(symbols)
% RMS normalization before constellation display
scale = sqrt(mean(abs(symbols).^2, 'all'));
if scale > 0, symbols = symbols / scale; end
end

function symbols = decimate_symbols(symbols, maximumPoints)
% Subsample to keep plotting responsive under hundreds of thousands of points
if numel(symbols) > maximumPoints
    indices = round(linspace(1, numel(symbols), maximumPoints));
    symbols = symbols(indices);
end
end

function update_spectrum(lines, frequencyMHz, spectrumDb)
for channel = 1:numel(lines)
    set(lines(channel), 'XData', frequencyMHz, 'YData', spectrumDb(:, channel));
end
end

function presenceDb = signal_presence_db(frequencyMHz, spectrumDb)
% Compare in-band (|f| <= 8.5 MHz) vs guard-band (25 <= |f| <= 55 MHz) PSD.
% Returns the median difference in dB. > 8 dB indicates a valid NR signal.
inBand = abs(frequencyMHz) <= 8.5;
guardBand = abs(frequencyMHz) >= 25 & abs(frequencyMHz) <= 55;
presenceDb = median(spectrumDb(inBand, :), 'all') - ...
    median(spectrumDb(guardBand, :), 'all');
end

function presenceDb = virtual_signal_presence(virtualRF, sampleRate)
% Fast per-BER safety gate on 30.72 MS/s virtual IQ. The display retains
% the physical 122.88 MS/s PSD; this uses a close-in virtual guard band.
nfft = 2048;
x = virtualRF(end-nfft+1:end, :);
[frequencyMHz, spectrumDb] = live_spectrum(x, sampleRate, nfft);
inBand = abs(frequencyMHz) <= 8.5;
guardBand = abs(frequencyMHz) >= 12 & abs(frequencyMHz) <= 14;
presenceDb = median(spectrumDb(inBand, :), 'all') - ...
    median(spectrumDb(guardBand, :), 'all');
end

function clear_constellations(beforeScatter, afterScatter)
set(beforeScatter, 'XData', nan, 'YData', nan);
clear_after_constellation(afterScatter);
figureHandle = ancestor(beforeScatter, 'figure');
set(findobj(figureHandle, 'Tag', 'IdealQPSK'), 'Visible', 'off');
set(findobj(figureHandle, 'Tag', 'NoSignalText'), 'Visible', 'on');
end

function clear_after_constellation(afterScatter)
for layer = 1:numel(afterScatter)
    set(afterScatter(layer), 'XData', nan, 'YData', nan);
end
end

function show_constellations(beforeScatter)
figureHandle = ancestor(beforeScatter, 'figure');
set(findobj(figureHandle, 'Tag', 'IdealQPSK'), 'Visible', 'on');
set(findobj(figureHandle, 'Tag', 'NoSignalText'), 'Visible', 'off');
end

function [frequencyMHz, spectrumDb] = live_spectrum(x, fs, nfft)
% Hann-windowed periodogram for live spectrum display.
% Uses the last nfft samples of the input for fast update.
x = double(x(end-nfft+1:end, :));
x = x - mean(x, 1);                                % remove DC
n = (0:nfft-1).';
window = 0.5 - 0.5*cos(2*pi*n/nfft);               % Hann window
transform = fftshift(fft(x .* window, nfft, 1), 1);
psd = abs(transform).^2 / (fs * sum(window.^2));    % normalised PSD
spectrumDb = 10*log10(psd + realmin);
frequencyMHz = (-nfft/2:nfft/2-1).' * fs/nfft/1e6;
end

function sample = runtime_sample_template(nRx, nLayers)
sample = struct;
sample.timeSec = nan;
sample.sequence = nan;
sample.sequenceAdvanceBlocks = 0;
sample.skippedCaptureBlocks = 0;
sample.timestampGapSamples = 0;
sample.storedRingBlocks = nan;
sample.rxThreadRunning = nan;
sample.lastReadReturn = nan;
sample.snapshotMs = nan;
sample.spectrumMs = nan;
sample.switchMs = nan;
sample.analysisMs = nan;
sample.plotMs = nan;
sample.iterationMs = nan;
sample.captureAgeMs = nan;
sample.presenceDb = nan;
sample.rssMb = nan;
sample.cpuTicks = nan;
sample.snrNullDb = nan(1, nRx);
sample.snrDmrsDb = nan(1, nRx);
sample.rawBER = nan(1, nLayers);
sample.decodedBER = nan(1, nLayers);
sample.evmRMSPercent = nan(1, nLayers);
sample.conditionStats = nan(1, 3);
sample.timingOffset = nan;
sample.frequencyOffsetHz = nan;
sample.cpCorrelation = nan;
sample.sssMetric = nan;
sample.usedPSS = false;
sample.localPSSChecked = false;
sample.pssAgeFrames = nan;
sample.cfoUpdated = false;
sample.pbchChecked = false;
sample.pbchCRCOK = false;
sample.mibMatches = false;
sample.rxEvents = nan(4, 3);
sample.outcome = 'not-run';
sample.errorMessage = '';
end

function [rssMb, cpuTicks] = process_linux_stats()
% Linux process resident memory and cumulative user+system CPU ticks.
rssMb = nan;
cpuTicks = nan;
try
    pid = feature('getpid');
    statusText = fileread(sprintf('/proc/%d/status', pid));
    token = regexp(statusText, 'VmRSS:\s+(\d+)\s+kB', 'tokens', 'once');
    if ~isempty(token), rssMb = str2double(token{1}) / 1024; end
    statText = fileread(sprintf('/proc/%d/stat', pid));
    closingParenthesis = find(statText == ')', 1, 'last');
    fields = strsplit(strtrim(statText(closingParenthesis + 1:end)));
    % fields{1} is process state (kernel field 3); utime/stime are fields
    % 14/15, hence positions 12/13 in this suffix.
    cpuTicks = str2double(fields{12}) + str2double(fields{13});
catch
end
end

function ticks = linux_clock_ticks()
[status, text] = system('getconf CLK_TCK');
ticks = str2double(strtrim(text));
if status ~= 0 || ~isfinite(ticks) || ticks <= 0, ticks = 100; end
end

function slope = linear_slope_per_minute(timeSec, values)
valid = isfinite(timeSec) & isfinite(values);
if nnz(valid) < 2
    slope = nan;
    return;
end
minutes = timeSec(valid) / 60;
fit = polyfit(minutes - minutes(1), values(valid), 1);
slope = fit(1);
end

function [slope, robustRange] = robust_memory_trend(timeSec, values)
valid = isfinite(timeSec) & isfinite(values);
timeSec = timeSec(valid);
values = values(valid);
if numel(values) < 4
    slope = nan;
    robustRange = nan;
    return;
end
robustRange = prctile(values, 95) - prctile(values, 5);
group = max(1, floor(numel(values) / 3));
first = 1:group;
last = (numel(values) - group + 1):numel(values);
deltaMinutes = (median(timeSec(last)) - median(timeSec(first))) / 60;
if deltaMinutes <= 0
    slope = nan;
else
    slope = (median(values(last)) - median(values(first))) / deltaMinutes;
end
end

function stats = metric_stats(values)
values = values(isfinite(values));
if isempty(values)
    stats = [nan nan nan];
else
    stats = [median(values), prctile(values, 95), max(values)];
end
end

function value = first_finite(values)
index = find(isfinite(values), 1, 'first');
if isempty(index), value = nan; else, value = values(index); end
end

function value = last_finite(values)
index = find(isfinite(values), 1, 'last');
if isempty(index), value = nan; else, value = values(index); end
end
