function result = type1_analyze_fast(rx30, package, dataSlot, options)
%TYPE1_ANALYZE_FAST Low-latency one-slot Type-A monitor.
%
% Acquire mode searches PSS over a full window. Track mode predicts the
% frame from hardware timestamps; its periodic PSS health check searches
% only a narrow window around that prediction. The function equalizes and
% decodes one selected data slot.
%
% Uses the known NID2 to run a single PSS hypothesis instead of three.
%
% Called every ~1 second by type1_rx_live for real-time monitoring.

arguments
    rx30 {mustBeNumeric}
    package (1,1) struct
    dataSlot (1,1) double {mustBeInteger,mustBeNonnegative}
    options.collectTiming (1,1) logical = false
    options.forcePSS (1,1) logical = true
    options.validatePSS (1,1) logical = false
    options.syncState struct = struct()
    options.snapshotStartRawTimestamp (1,1) uint64 = uint64(0)
    options.trackedTimingOffset (1,1) double = nan
    options.returnChannel (1,1) logical = false
    options.computeSNR (1,1) logical = true
    options.computeCondition (1,1) logical = true
end
collectTiming = options.collectTiming;
cfg = apply_fast_defaults(package.cfg);
package.cfg = cfg;
assert(any(cfg.dataSlots == dataSlot), 'Invalid data slot.');
nRxChannels = size(rx30, 2);
assert(nRxChannels >= 1, 'At least one RX channel is required.');
cfg.nRxChannels = nRxChannels;   % analysis follows the IQ column count

timer = tic;
stageTimesMs = empty_stage_times();
frameSamples = round(cfg.frameDurationSec * cfg.txSampleRate);
slotSamples = frameSamples / cfg.slotsPerFrame;
syncState = options.syncState;
acquirePSS = options.forcePSS || ~isfield(syncState, 'valid') || ...
    ~syncState.valid;
if acquirePSS && size(rx30, 1) < frameSamples + slotSamples
    error('type1:ShortFastWindow', ...
        'Acquire mode needs at least 10.5 ms of virtual30 IQ.');
end

% DM-RS channel estimation absorbs a fixed RX gain. Avoid a full-window
% double conversion/RMS pass in the default fast path.
tStage = tic;
if cfg.fastNormalizeRx
    rx30 = double(rx30);
    for r = 1:nRxChannels
        scale = rms(rx30(:, r));
        if scale > 0, rx30(:, r) = rx30(:, r) / scale; end
    end
else
    rx30 = single(rx30);
end
stageTimesMs.rmsNormalize = 1e3 * toc(tStage);

carrier = type1_carrier_config(cfg, 0);
nSC = 12 * cfg.nRB;

%% ═══ Step 1: Acquire / timestamp Track / narrow local PSS check ═══
expectedNID2 = mod(cfg.pci, 3);
usedPSS = acquirePSS;
localPSSChecked = false;
if acquirePSS
    tStage = tic;
    localSSB = complex(zeros(240, 4));
    localSSB(nrPSSIndices) = nrPSS(expectedNID2);
    referenceGrid = complex(zeros(nSC, cfg.symbolsPerSlot));
    referenceGrid(package.ssbSubcarriers, package.ssbSymbols) = localSSB;
    stageTimesMs.referenceSetup = 1e3 * toc(tStage);

    tStage = tic;
    [timingOffset, magnitude] = nrTimingEstimate(carrier, rx30, ...
        referenceGrid, 'Nfft', cfg.nfft, ...
        'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0);
    stageTimesMs.pssTiming = 1e3 * toc(tStage);

    % PSS peak-to-median ratio for signal presence quality
    tStage = tic;
    correlationPower = sum(abs(magnitude).^2, 2);
    pssPeak = max(correlationPower, [], 'all');
    pssMedian = median(correlationPower, 'all');
    pssPeakToMedianDb = 10*log10(pssPeak / (pssMedian + eps));
    requiredEnd = dataSlot * slotSamples + slotSamples;
    while timingOffset + requiredEnd > size(rx30, 1)
        timingOffset = timingOffset - frameSamples;
    end
    if timingOffset < 0
        error('type1:IncompleteFastFrame', ...
            'Expected PSS does not leave one complete frame.');
    end
    syncState = make_sync_state(syncState, timingOffset, pssPeak, ...
        pssPeakToMedianDb, options.snapshotStartRawTimestamp, cfg, frameSamples);
    pssAgeFrames = 0;
    pssMode = 'acquire';
    stageTimesMs.pssMetricAndFrameSelect = 1e3 * toc(tStage);
else
    tStage = tic;
    [timingOffset, pssAgeFrames] = tracked_timing_offset(syncState, ...
        options, cfg, frameSamples, slotSamples, dataSlot, size(rx30, 1));
    pssPeak = syncState.pssPeak;
    pssPeakToMedianDb = syncState.pssPeakToMedianDb;
    pssMode = 'track';
    if options.validatePSS
        localPssTimer = tic;
        [timingOffset, magnitude] = local_pss_timing(carrier, rx30, ...
            package, cfg, timingOffset);
        stageTimesMs.pssTiming = 1e3 * toc(localPssTimer);
        [pssPeak, pssPeakToMedianDb] = pss_quality(magnitude);
        if pssPeakToMedianDb < cfg.fastPSSMinPeakToMedianDb
            error('type1:PSSLocalLoss', ...
                ['Local PSS peak/median %.1f dB is below %.1f dB; ' ...
                 'declare loss and return to Acquire.'], ...
                pssPeakToMedianDb, cfg.fastPSSMinPeakToMedianDb);
        end
        syncState = make_sync_state(syncState, timingOffset, pssPeak, ...
            pssPeakToMedianDb, options.snapshotStartRawTimestamp, ...
            cfg, frameSamples);
        pssAgeFrames = 0;
        localPSSChecked = true;
        pssMode = 'local-check';
    end
    stageTimesMs.pssMetricAndFrameSelect = 1e3 * toc(tStage);
end

%% ═══ Step 2: low-rate CFO update and target-slot-only compensation ═══
tStage = tic;
slotStart = timingOffset + dataSlot * slotSamples;
if slotStart < 0 || slotStart + slotSamples > size(rx30, 1)
    error('type1:TrackingWindow', ...
        'The requested data slot is not fully inside this IQ window.');
end
dataWaveform = rx30(slotStart + (1:slotSamples), :);
frameStartRawTimestamp = current_frame_start_raw( ...
    options.snapshotStartRawTimestamp, timingOffset, cfg, syncState);
cfoUpdated = should_update_cfo(syncState, frameStartRawTimestamp, cfg, ...
    acquirePSS || localPSSChecked);
if cfoUpdated
    [frequencyOffsetHz, cpCorrelation] = estimate_fine_cfo( ...
        dataWaveform, slot_cp_lengths(package.ofdmInfo.CyclicPrefixLengths, ...
        dataSlot, cfg.symbolsPerSlot), ...
        cfg.nfft, cfg.txSampleRate);
    syncState.frequencyOffsetHz = frequencyOffsetHz;
    syncState.cpCorrelation = cpCorrelation;
    syncState.lastCFOFrameStartRawTimestamp = frameStartRawTimestamp;
else
    frequencyOffsetHz = field_or(syncState, 'frequencyOffsetHz', 0);
    cpCorrelation = field_or(syncState, 'cpCorrelation', nan);
end
sampleIndex = (0:slotSamples-1).';
dataWaveform = dataWaveform .* exp( ...
    -1j * 2*pi * frequencyOffsetHz * sampleIndex / cfg.txSampleRate);
stageTimesMs.cfoEstimateAndCompensate = 1e3 * toc(tStage);

%% ═══ Step 3–5: Optional SSS/PBCH verification on PSS reacquisition ═══
% The fast monitor intentionally skips PBCH/MIB by default. It is a
% control-plane integrity check, not a prerequisite for data equalization.
pbchChecked = false;
pbchCRCError = nan;            % Not evaluated while fast PBCH is disabled.
mibMatches = false;
sssMetric = field_or(syncState, 'sssMetric', nan);
needSSB = (usedPSS || localPSSChecked) && ...
    (cfg.fastValidateSSSWithPSS || cfg.fastEnablePBCH);
if needSSB
    tStage = tic;
    if timingOffset < 0 || timingOffset + slotSamples > size(rx30, 1)
        error('type1:SSBWindow', 'The PSS/SSS slot is outside the IQ window.');
    end
    ssbWaveform = rx30(timingOffset + (1:slotSamples), :);
    ssbIndex = (0:slotSamples-1).';
    ssbWaveform = ssbWaveform .* exp( ...
        -1j * 2*pi * frequencyOffsetHz * ssbIndex / cfg.txSampleRate);
    carrier.NSlot = 0;
    ssbSlotGrid = nrOFDMDemodulate(carrier, ssbWaveform, ...
        'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, ...
        'CarrierFrequency', 0);
    rxSSB = ssbSlotGrid(package.ssbSubcarriers, package.ssbSymbols, :);
    stageTimesMs.ssbOFDM = 1e3 * toc(tStage);

    if cfg.fastValidateSSSWithPSS
        tStage = tic;
        sssReceived = complex(zeros(127, nRxChannels));
        for r = 1:nRxChannels
            plane = rxSSB(:, :, r);
            sssReceived(:, r) = plane(nrSSSIndices);
        end
        expectedSSS = nrSSS(cfg.pci);
        sssMetric = sum(abs(expectedSSS' * sssReceived).^2) / ...
            (sum(abs(expectedSSS).^2) * sum(abs(sssReceived).^2, 'all') + eps);
        syncState.sssMetric = sssMetric;
        stageTimesMs.sssMetric = 1e3 * toc(tStage);
    end

    if cfg.fastEnablePBCH
        pbchChecked = true;
        tStage = tic;
        ibarSSB = cfg.ssbIndex + 4 * cfg.halfFrameBit;
        pbchDMRSIndices = nrPBCHDMRSIndices(cfg.pci);
        pbchDMRSSymbols = nrPBCHDMRS(cfg.pci, ibarSSB);
        rxSSBSlot = complex(zeros(240, cfg.symbolsPerSlot, nRxChannels));
        rxSSBSlot(:, 1:4, :) = rxSSB;
        [pbchChannel, pbchNoise] = nrChannelEstimate( ...
            rxSSBSlot, pbchDMRSIndices, pbchDMRSSymbols, ...
            'AveragingWindow', [5 1]);
        stageTimesMs.pbchChannelEstimate = 1e3 * toc(tStage);

        tStage = tic;
        equalizedSSB = complex(zeros(240, 4));
        for symbol = 1:4
            for k = 1:240
                y = reshape(rxSSB(k, symbol, :), nRxChannels, 1);
                h = reshape(pbchChannel(k, symbol, :, 1), nRxChannels, 1);
                equalizedSSB(k, symbol) = ...
                    (h' * y) / (h' * h + max(pbchNoise, eps));
            end
        end
        stageTimesMs.pbchEqualizeLoop = 1e3 * toc(tStage);

        tStage = tic;
        pbchSymbols = equalizedSSB(nrPBCHIndices(cfg.pci));
        pbchLLR = nrPBCHDecode(pbchSymbols, cfg.pci, ...
            mod(cfg.ssbIndex, 8), max(pbchNoise, eps));
        [~, pbchCRCError, decodedMIB] = nrBCHDecode( ...
            pbchLLR, 8, cfg.Lmax, cfg.pci);
        mibMatches = ~pbchCRCError && isequal(decodedMIB, package.mib);
        stageTimesMs.pbchDecode = 1e3 * toc(tStage);
    end
end

%% ═══ Step 6–7: Single data slot DM-RS + RZF ═══
slotPosition = find(cfg.dataSlots == dataSlot, 1);
tStage = tic;
carrier.NSlot = dataSlot;
rxSlot = nrOFDMDemodulate(carrier, dataWaveform, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, ...
    'CarrierFrequency', 0);
stageTimesMs.dataOFDM = 1e3 * toc(tStage);

% Type-1 CDM channel estimation
tStage = tic;
dmrsIndices = double(package.dmrsIndices(:, :, slotPosition));
dmrsSymbols = double(package.dmrsSymbols(:, :, slotPosition));
useType1DMRSMEX = cfg.fastUseType1DMRSMEX && ...
    exist('type1_dmrs_type1_mex', 'file') == 3;
if useType1DMRSMEX
    [channel, noiseVariance] = type1_dmrs_type1_mex(single(rxSlot), ...
        package.dmrsIndices(:, :, slotPosition), ...
        package.dmrsSymbols(:, :, slotPosition));
else
    [channel, noiseVariance] = nrChannelEstimate( ...
        rxSlot, dmrsIndices, dmrsSymbols, ...
        'CDMLengths', package.dmrsCDMLengths);
end
stageTimesMs.dmrsChannelEstimate = 1e3 * toc(tStage);

if options.computeSNR
    tStage = tic;
    snrMetrics = type1_snr_metrics(dataWaveform, rxSlot, channel, ...
        noiseVariance, package, slotPosition);
    stageTimesMs.snrMetrics = 1e3 * toc(tStage);
else
    snrMetrics = struct('snrNullDb',nan,'snrDmrsDb',nan, ...
        'nullSignalPower',nan,'nullNoisePower',nan, ...
        'dmrsSignalPower',nan,'dmrsResidualPower',nan);
end

% Extract data REs and channel at data positions
tStage = tic;
nDataRE = package.nDataREPerSlotLayer;
nLayers = cfg.nLayers;
firstLayerIndices = double(package.dataIndices(:, 1, slotPosition));
[subcarriers, symbols] = ind2sub( ...
    [nSC cfg.symbolsPerSlot nLayers], firstLayerIndices);
indices2D = sub2ind([nSC cfg.symbolsPerSlot], subcarriers, symbols);

received = complex(zeros(nDataRE, nRxChannels, 'like', rxSlot));
channelAtData = complex(zeros(nDataRE, nRxChannels, nLayers, 'like', channel));
for r = 1:nRxChannels
    plane = rxSlot(:, :, r);
    received(:, r) = plane(indices2D);
    for layer = 1:nLayers
        channelPlane = channel(:, :, r, layer);
        channelAtData(:, r, layer) = channelPlane(indices2D);
    end
end
stageTimesMs.dataAndChannelExtract = 1e3 * toc(tStage);

preCompData = received(:, 1);
spatialDecodeEnabled = nRxChannels >= nLayers;

if spatialDecodeEnabled
channelPages = permute(channelAtData, [2 3 1]);      % [nRx x nLayer x nRE]
receivedPages = permute(received, [2 3 1]);           % [nRx x 1 x nRE]
useRZFQPSKMEX = cfg.fastUseRZFQPSKMEX && ...
    strcmp(package.channelCoding, 'none') && ...
    exist('type1_rzf_qpsk_mex', 'file') == 3;
if useRZFQPSKMEX
    tStage = tic;
    expectedQPSK = reshape(single(package.dataQPSK(:, slotPosition, :)), ...
        nDataRE, nLayers);
    expectedBits = reshape(package.codedBits(:, slotPosition, :), ...
        2*nDataRE, nLayers);
    [postCompData, codedBitErrors, evmRMSPercent] = type1_rzf_qpsk_mex( ...
        single(received), single(channelAtData), expectedQPSK, ...
        expectedBits, cfg.rzfRegularization, ...
        nSC, true);
    postCompData = reshape(postCompData, nDataRE, nLayers);
    stageTimesMs.rzfEqualize = 1e3 * toc(tStage);
    tStage = tic;
    codedBER = codedBitErrors / package.nCodedBitsPerSlotLayer;
    infoBER = codedBER;
    infoBitErrors = codedBitErrors;
    stageTimesMs.berAndEvm = 1e3 * toc(tStage);
else
    % ── Generic page-wise nRx-by-nLayer RZF equalization ──
    tStage = tic;
    channelHermitian = pagectranspose(channelPages);
    gram = pagemtimes(channelHermitian, channelPages);    % H^H H
    matched = pagemtimes(channelHermitian, receivedPages);% H^H y
    meanChannelPower = sum(abs(channelPages).^2, [1 2]) / nLayers;
    lambda = cfg.rzfRegularization * max(meanChannelPower, eps);
    regularized = gram + reshape(eye(nLayers), nLayers, nLayers, 1) .* lambda;
    equalizedPages = pagemldivide(regularized, matched);
    postCompData = permute(equalizedPages, [3 1 2]);
    postCompData = reshape(postCompData, nDataRE, nLayers);
    stageTimesMs.rzfEqualize = 1e3 * toc(tStage);

    %% ═══ Step 8–9: BER and EVM for this one slot ═══
    tStage = tic;
    codedBER = zeros(1, nLayers);
    infoBER = zeros(1, nLayers);
    codedBitErrors = zeros(1, nLayers);
    infoBitErrors = zeros(1, nLayers);
    evmRMSPercent = zeros(1, nLayers);
    for layer = 1:nLayers
        equalized = postCompData(:, layer);
        hardBits = logical(nrSymbolDemodulate(equalized, ...
            cfg.modulation, 'DecisionType', 'hard'));
        expectedCoded = package.codedBits(:, slotPosition, layer);
        codedBitErrors(layer) = sum(hardBits ~= expectedCoded);
        codedBER(layer) = codedBitErrors(layer) / numel(expectedCoded);
        switch package.channelCoding
            case 'none'
                decoded = hardBits;
            case 'convolutional'
                decoded = logical(vitdec(double(hardBits), package.trellis, ...
                    cfg.viterbiTraceback, 'term', 'hard'));
            otherwise
                error('type1:Coding', 'Unsupported coding mode %s.', ...
                    package.channelCoding);
        end
        expectedInfo = package.infoBits(:, slotPosition, layer);
        decoded = decoded(1:numel(expectedInfo));
        infoBitErrors(layer) = sum(decoded ~= expectedInfo);
        infoBER(layer) = infoBitErrors(layer) / numel(expectedInfo);
        expectedSymbols = double(package.dataQPSK(:, slotPosition, layer));
        evmRMSPercent(layer) = 100 * ...
            rms(equalized - expectedSymbols) / rms(expectedSymbols);
    end
    stageTimesMs.berAndEvm = 1e3 * toc(tStage);
end

% Condition number is a diagnostic, not a demodulation prerequisite.
if options.computeCondition
    tStage = tic;
    sampleCount = min(cfg.channelConditionSamplesPerSlot, nDataRE);
    sampleIndices = unique(round(linspace(1, nDataRE, sampleCount)));
    conditionNumbers = zeros(1, numel(sampleIndices));
    for q = 1:numel(sampleIndices)
        conditionNumbers(q) = cond(channelPages(:, :, sampleIndices(q)));
    end
    stageTimesMs.conditionNumbers = 1e3 * toc(tStage);
else
    conditionNumbers = nan;
end
else
postCompData = complex(nan(nDataRE, nLayers));
codedBER = nan(1, nLayers);
infoBER = nan(1, nLayers);
codedBitErrors = nan(1, nLayers);
infoBitErrors = nan(1, nLayers);
evmRMSPercent = nan(1, nLayers);
conditionNumbers = nan;
end

%% ── Pack results ──
result = struct;
result.dataSlot = dataSlot;
result.timingOffset = timingOffset;
result.pssPeak = pssPeak;
result.pssPeakToMedianDb = pssPeakToMedianDb;
result.expectedNID2 = expectedNID2;
result.usedPSS = usedPSS;
result.localPSSChecked = localPSSChecked;
result.pssMode = pssMode;
result.pssAgeFrames = pssAgeFrames;
result.syncState = syncState;
result.frequencyOffsetHz = frequencyOffsetHz;
result.cpCorrelation = cpCorrelation;
result.cfoUpdated = cfoUpdated;
result.sssMetric = sssMetric;
result.pbchChecked = pbchChecked;
result.pbchCRCError = pbchCRCError;
result.mibMatches = mibMatches;
result.nRxChannels = nRxChannels;
result.nLayers = nLayers;
result.spatialDecodeEnabled = spatialDecodeEnabled;
result.preCompData = preCompData;
result.postCompData = postCompData;
result.channelCoding = package.channelCoding;
result.codedBER = codedBER;
result.infoBER = infoBER;
result.codedBitErrors = codedBitErrors;
result.infoBitErrors = infoBitErrors;
result.rawBER = codedBER;
result.decodedBER = infoBER;
result.rawBitErrors = codedBitErrors;
result.decodedBitErrors = infoBitErrors;
result.evmRMSPercent = evmRMSPercent;
result.noiseVariance = noiseVariance;
if options.returnChannel
    result.channel = channel;
end
result.snrNullDb = snrMetrics.snrNullDb;
result.snrDmrsDb = snrMetrics.snrDmrsDb;
result.snrNullSignalPower = snrMetrics.nullSignalPower;
result.snrNullNoisePower = snrMetrics.nullNoisePower;
result.snrDmrsSignalPower = snrMetrics.dmrsSignalPower;
result.snrDmrsResidualPower = snrMetrics.dmrsResidualPower;
result.conditionStats = [median(conditionNumbers), ...
    prctile(conditionNumbers, 95), max(conditionNumbers)];
result.elapsedMs = 1e3 * toc(timer);
if collectTiming
    stageTimesMs.accounted = sum(cell2mat(struct2cell(stageTimesMs)));
    stageTimesMs.unaccounted = max(result.elapsedMs - stageTimesMs.accounted, 0);
    result.stageTimesMs = stageTimesMs;
end
end

function stages = empty_stage_times()
stages = struct( ...
    'rmsNormalize', 0, ...
    'referenceSetup', 0, ...
    'pssTiming', 0, ...
    'pssMetricAndFrameSelect', 0, ...
    'cfoEstimateAndCompensate', 0, ...
    'ssbOFDM', 0, ...
    'sssMetric', 0, ...
    'pbchChannelEstimate', 0, ...
    'pbchEqualizeLoop', 0, ...
    'pbchDecode', 0, ...
    'dataOFDM', 0, ...
    'dmrsChannelEstimate', 0, ...
    'snrMetrics', 0, ...
    'dataAndChannelExtract', 0, ...
    'rzfEqualize', 0, ...
    'berAndEvm', 0, ...
    'conditionNumbers', 0);
end

function cfg = apply_fast_defaults(cfg)
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
if ~isfield(cfg, 'fastUseRZFQPSKMEX')
    cfg.fastUseRZFQPSKMEX = true;
end
if ~isfield(cfg, 'fastUseType1DMRSMEX')
    cfg.fastUseType1DMRSMEX = true;
end
end

function state = make_sync_state(state, timingOffset, pssPeak, ...
        pssPeakToMedianDb, snapshotStartRawTimestamp, cfg, frameSamples)
state.valid = true;
state.referenceTimingOffset = timingOffset;
state.pssPeak = pssPeak;
state.pssPeakToMedianDb = pssPeakToMedianDb;
rawPerVirtualSample = cfg.rxSampleRate / cfg.txSampleRate;
if snapshotStartRawTimestamp ~= 0
    state.frameStartRawTimestamp = snapshotStartRawTimestamp + ...
        uint64(round(rawPerVirtualSample * timingOffset));
else
    state.frameStartRawTimestamp = uint64(0);
end
state.frameSamples = frameSamples;
end

function [timingOffset, ageFrames] = tracked_timing_offset( ...
        state, options, cfg, frameSamples, slotSamples, dataSlot, inputSamples)
if isfinite(options.trackedTimingOffset)
    timingOffset = round(options.trackedTimingOffset);
    ageFrames = nan;
elseif options.snapshotStartRawTimestamp ~= 0 && ...
        isfield(state, 'frameStartRawTimestamp') && ...
        state.frameStartRawTimestamp ~= 0
    rawPerVirtualSample = cfg.rxSampleRate / cfg.txSampleRate;
    if abs(rawPerVirtualSample - round(rawPerVirtualSample)) > eps
        error('type1:TrackingRate', ...
            'Raw/virtual sample-rate ratio must be an integer.');
    end
    rawPerVirtualSample = round(rawPerVirtualSample);
    framePeriodRaw = rawPerVirtualSample * frameSamples;
    snapshotStart = double(options.snapshotStartRawTimestamp);
    referenceStart = double(state.frameStartRawTimestamp);
    slotOffsetRaw = rawPerVirtualSample * dataSlot * slotSamples;
    slotLengthRaw = rawPerVirtualSample * slotSamples;
    snapshotEnd = snapshotStart + rawPerVirtualSample * inputSamples;
    % Select the newest frame whose requested data slot is entirely in the
    % current window. This also supports a future 1 ms Track window, where
    % the frame start itself is normally before the window.
    firstCandidate = ceil((snapshotStart - referenceStart - slotOffsetRaw) ...
        / framePeriodRaw);
    lastCandidate = floor((snapshotEnd - referenceStart - slotOffsetRaw ...
        - slotLengthRaw) / framePeriodRaw);
    if firstCandidate > lastCandidate
        error('type1:TrackingWindow', ...
            'No complete requested data slot fits in this IQ window.');
    end
    frameIndex = lastCandidate;
    candidateStart = referenceStart + frameIndex * framePeriodRaw;
    timingOffset = round((candidateStart - snapshotStart) / rawPerVirtualSample);
    ageFrames = frameIndex;
else
    error('type1:TrackingState', ...
        'Tracked timing requires a valid raw timestamp state or trackedTimingOffset.');
end

dataStart = timingOffset + dataSlot * slotSamples;
if dataStart < 0 || dataStart + slotSamples > inputSamples
    error('type1:TrackingWindow', ...
        'Tracked data slot does not fit in the current analysis window.');
end
end

function [timingOffset, magnitude] = local_pss_timing( ...
        carrier, rx30, package, cfg, predictedTimingOffset)
% Run nrTimingEstimate only on [prediction-radius, prediction+radius]
% candidates plus the 0.5 ms SSB reference duration. This preserves the
% standard Toolbox correlator while removing the full 20 ms search.
slotSamples = round(cfg.frameDurationSec * cfg.txSampleRate / ...
    cfg.slotsPerFrame);
radius = round(cfg.fastPSSLocalSearchSamples);
searchStart = max(0, predictedTimingOffset - radius);
searchStop = min(size(rx30, 1), ...
    predictedTimingOffset + radius + slotSamples);
if searchStop - searchStart < slotSamples
    error('type1:PSSLocalWindow', ...
        'Local PSS search window does not contain a complete SSB slot.');
end
localSSB = complex(zeros(240, 4, 'like', rx30));
localSSB(nrPSSIndices) = nrPSS(mod(cfg.pci, 3));
referenceGrid = complex(zeros(12 * cfg.nRB, cfg.symbolsPerSlot, 'like', rx30));
referenceGrid(package.ssbSubcarriers, package.ssbSymbols) = localSSB;
[localOffset, magnitude] = nrTimingEstimate(carrier, ...
    rx30(searchStart + (1:(searchStop-searchStart)), :), referenceGrid, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, ...
    'CarrierFrequency', 0);
timingOffset = searchStart + localOffset;
if abs(timingOffset - predictedTimingOffset) > radius
    error('type1:PSSLocalRange', ...
        'Local PSS timing escaped its +/- %d sample prediction window.', radius);
end
end

function [peak, peakToMedianDb] = pss_quality(magnitude)
correlationPower = sum(abs(magnitude).^2, 2);
peak = max(correlationPower, [], 'all');
medianPower = median(correlationPower, 'all');
peakToMedianDb = 10 * log10(peak / (medianPower + eps));
end

function cpLengths = slot_cp_lengths(allCpLengths, slotNumber, symbolsPerSlot)
% nrOFDMInfo may expose one slot or a two-slot 1 ms CP pattern. Select the
% matching slot phase rather than assuming a 10 ms CP vector is present.
slotsDescribed = numel(allCpLengths) / symbolsPerSlot;
if slotsDescribed < 1 || mod(slotsDescribed, 1) ~= 0
    error('type1:CPInfo', 'Unexpected CyclicPrefixLengths shape.');
end
slotPhase = mod(slotNumber, slotsDescribed);
indices = slotPhase * symbolsPerSlot + (1:symbolsPerSlot);
cpLengths = allCpLengths(indices);
end

function timestamp = current_frame_start_raw(snapshotStartRaw, timingOffset, cfg, state)
if snapshotStartRaw ~= 0
    rawPerVirtualSample = cfg.rxSampleRate / cfg.txSampleRate;
    value = double(snapshotStartRaw) + rawPerVirtualSample * timingOffset;
    if value >= 0
        timestamp = uint64(round(value));
        return;
    end
end
timestamp = field_or(state, 'frameStartRawTimestamp', uint64(0));
end

function update = should_update_cfo(state, frameStartRawTimestamp, cfg, forced)
update = forced || ~isfield(state, 'frequencyOffsetHz') || ...
    ~isfinite(state.frequencyOffsetHz) || ...
    ~isfield(state, 'lastCFOFrameStartRawTimestamp') || ...
    state.lastCFOFrameStartRawTimestamp == 0;
if update || frameStartRawTimestamp == 0
    return;
end
periodRaw = round(cfg.frameDurationSec * cfg.rxSampleRate);
update = double(frameStartRawTimestamp) - ...
    double(state.lastCFOFrameStartRawTimestamp) >= ...
    cfg.fastCFOCheckIntervalFrames * periodRaw;
end

function value = field_or(s, fieldName, defaultValue)
if isfield(s, fieldName)
    value = s.(fieldName);
else
    value = defaultValue;
end
end

%% ═══ Local: CP-based fine CFO estimator (shared with type1_analyze) ═══
function [frequencyOffsetHz, quality] = estimate_fine_cfo( ...
        waveform, cpLengths, nfft, sampleRate)
correlation = 0;
earlyEnergy = 0;
lateEnergy = 0;
cursor = 1;
for symbol = 1:numel(cpLengths)
    cp = cpLengths(symbol);
    early = waveform(cursor + (0:cp-1), :);
    late = waveform(cursor + nfft + (0:cp-1), :);
    correlation = correlation + sum(conj(early) .* late, 'all');
    earlyEnergy = earlyEnergy + sum(abs(early).^2, 'all');
    lateEnergy = lateEnergy + sum(abs(late).^2, 'all');
    cursor = cursor + cp + nfft;
end
frequencyOffsetHz = angle(correlation) * sampleRate / (2*pi*nfft);
quality = abs(correlation) / sqrt(earlyEnergy * lateEnergy + eps);
end
