function result = type1_analyze(rx30, package)
%TYPE1_ANALYZE Full-frame sync, Type-1 DM-RS estimation, RZF and BER.
%
% Processing chain (all 19 data slots):
%  1. PSS timing -> 10 ms frame boundary (3 NID2 hypotheses)
%  2. CP-based fine CFO estimation and compensation
%  3. OFDM demodulation -> 612x280x4 received grid
%  4. SSS non-coherent verification
%  5. PBCH DM-RS channel estimation + PBCH decode + MIB check
%  6. Per-data-slot Type-1 DM-RS channel estimation with CDM OCC
%  7. Per-RE nRx-by-nLayer RZF equalization (page-wise for speed)
%  8. Hard decision + Viterbi decode + BER per slot/layer
%  9. EVM and estimated-channel condition-number statistics
%
% Used by selftest and offline analysis. For live monitoring, use
% type1_analyze_fast which decodes only one slot per update.

arguments
    rx30 {mustBeNumeric}       % [N x 4] 30.72 MS/s virtual RF
    package (1,1) struct        % shared TX/RX reference
end
cfg = package.cfg;
nRxChannels = size(rx30, 2);
assert(nRxChannels >= 1, 'At least one RX channel is required.');
cfg.nRxChannels = nRxChannels;   % analysis follows the IQ column count

timer = tic;
frameSamples = round(cfg.frameDurationSec * cfg.txSampleRate);   % 307200
slotSamples = frameSamples / cfg.slotsPerFrame;                  % 15360
if size(rx30, 1) < frameSamples + slotSamples
    error('type1:ShortWindow', ...
        'At least 10.5 ms is required for a complete synchronized frame.');
end

% Per-RX-channel RMS normalization (CFO estimation is more stable)
rx30 = double(rx30);
for r = 1:nRxChannels
    scale = rms(rx30(:, r));
    if scale > 0, rx30(:, r) = rx30(:, r) / scale; end
end

carrier = type1_carrier_config(cfg, 0);
nSC = 12 * cfg.nRB;
ssbSC = package.ssbSubcarriers;
ssbSym = package.ssbSymbols;

%% ═══ Step 1: PSS timing — 3 NID2 hypotheses, max correlation ═══
% nrTimingEstimate cross-correlates the received signal with a local
% PSS-only reference grid and returns the best timing offset.
pssMetrics = zeros(3, 1);
pssPeakIndices = zeros(3, 1);
for nid2 = 0:2
    localSSB = complex(zeros(240, 4));
    localSSB(nrPSSIndices) = nrPSS(nid2);                 % PSS sequence
    referenceGrid = complex(zeros(nSC, cfg.symbolsPerSlot));
    referenceGrid(ssbSC, ssbSym) = localSSB;
    [offset, magnitude] = nrTimingEstimate(carrier, rx30, ...
        referenceGrid, 'Nfft', cfg.nfft, ...
        'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0);
    pssPeakIndices(nid2 + 1) = offset;
    pssMetrics(nid2 + 1) = max(sum(abs(magnitude).^2, 2), [], 'all');
end
[~, bestPSSIndex] = max(pssMetrics);                      % pick best NID2
timingOffset = pssPeakIndices(bestPSSIndex);

% Adjust timing offset into the captured window to extract a full frame
pssModuloOffsets = mod(pssPeakIndices - timingOffset + ...
    frameSamples / 2, frameSamples) - frameSamples / 2;
while timingOffset + frameSamples > size(rx30, 1)
    timingOffset = timingOffset - frameSamples;
end
if timingOffset < 0
    error('type1:IncompleteFrame', ...
        'PSS peak does not leave a complete frame in the window.');
end

%% ═══ Step 2: CP-based fine CFO estimation and compensation ═══
% Exploits the repetition between CP and the end of each OFDM symbol.
% Unambiguous range = +/- SCS/2 = +/- 15 kHz.
frameWaveform = rx30(timingOffset + (1:frameSamples), :);
[frequencyOffsetHz, cpCorrelation] = estimate_fine_cfo( ...
    frameWaveform, package.ofdmInfo.CyclicPrefixLengths, ...
    cfg.nfft, cfg.txSampleRate);

% Time-domain phase de-rotation to compensate CFO
sampleIndex = (0:frameSamples-1).';
frameWaveform = frameWaveform .* exp( ...
    -1j * 2*pi * frequencyOffsetHz * sampleIndex / cfg.txSampleRate);

%% ═══ Step 3: OFDM demodulation -> 612x280x4 received grid ═══
rxGrid = nrOFDMDemodulate(carrier, frameWaveform, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, ...
    'CarrierFrequency', 0);
assert(size(rxGrid, 2) >= cfg.symbolsPerFrame);
rxGrid = rxGrid(:, 1:cfg.symbolsPerFrame, :);

%% ═══ Step 4: SSS verification (known PCI, 4-RX noncoherent combine) ═══
% Non-coherent: |s^H y|^2, insensitive to residual phase.
rxSSB = rxGrid(ssbSC, ssbSym, :);
sssReceived = complex(zeros(127, nRxChannels));
for r = 1:nRxChannels
    plane = rxSSB(:, :, r);
    sssReceived(:, r) = plane(nrSSSIndices);
end
expectedSSS = nrSSS(cfg.pci);
sssMetric = sum(abs(expectedSSS' * sssReceived).^2) / ...
    (sum(abs(expectedSSS).^2) * sum(abs(sssReceived).^2, 'all') + eps);

%% ═══ Step 5: PBCH DM-RS estimation + PBCH decode + MIB check ═══
% Single-port PBCH equalization using PBCH DM-RS from the known PCI.
ibarSSB = cfg.ssbIndex + 4 * cfg.halfFrameBit;
pbchDMRSIndices = nrPBCHDMRSIndices(cfg.pci);
pbchDMRSSymbols = nrPBCHDMRS(cfg.pci, ibarSSB);
rxSSBSlot = complex(zeros(240, cfg.symbolsPerSlot, nRxChannels));
rxSSBSlot(:, 1:4, :) = rxSSB;
[pbchChannel, pbchNoise] = nrChannelEstimate( ...
    rxSSBSlot, pbchDMRSIndices, pbchDMRSSymbols, ...
    'AveragingWindow', [5 1]);             % 5-subcarrier smoothing

% Manual single-layer MRC equalization for PBCH symbols
equalizedSSB = complex(zeros(240, 4));
for symbol = 1:4
    for k = 1:240
        y = reshape(rxSSB(k, symbol, :), nRxChannels, 1);
        h = reshape(pbchChannel(k, symbol, :, 1), nRxChannels, 1);
        equalizedSSB(k, symbol) = (h' * y) / (h' * h + max(pbchNoise, eps));
    end
end

% PBCH descrambling -> LLRs -> BCH Polar decode -> MIB bits
pbchSymbols = equalizedSSB(nrPBCHIndices(cfg.pci));
pbchLLR = nrPBCHDecode(pbchSymbols, cfg.pci, ...
    mod(cfg.ssbIndex, 8), max(pbchNoise, eps));
[~, pbchCRCError, decodedMIB] = nrBCHDecode( ...
    pbchLLR, 8, cfg.Lmax, cfg.pci);
mibMatches = ~pbchCRCError && isequal(decodedMIB, package.mib);

%% ═══ Step 6–7: Per-slot Type-1 DM-RS + RZF equalization ═══
% Each data slot: estimate H(nRx-by-nLayer) from DM-RS symbol (l=2), then RZF
% equalize all data REs using that slot's channel estimate.
% RZF: x_hat = (H^H H + lambda*I)^-1 H^H y
% lambda = rzfRegularization * mean(|H|^2) / nLayers
nSlots = numel(cfg.dataSlots);
nDataRE = package.nDataREPerSlotLayer;
nLayers = cfg.nLayers;
spatialDecodeEnabled = nRxChannels >= nLayers;
postCompData = complex(zeros(nDataRE, nSlots, nLayers));
preCompData = complex(zeros(nDataRE, nSlots));
noiseVariance = zeros(1, nSlots);
snrNullDbBySlot = nan(nSlots, nRxChannels);
snrDmrsDbBySlot = nan(nSlots, nRxChannels);
snrNullSignalPowerBySlot = nan(nSlots, nRxChannels);
snrNullNoisePowerBySlot = nan(nSlots, nRxChannels);
snrDmrsSignalPowerBySlot = nan(nSlots, nRxChannels);
snrDmrsResidualPowerBySlot = nan(nSlots, nRxChannels);
conditionNumbers = [];
channelMatrixCenterBySlot = complex(nan(nRxChannels, nLayers, nSlots));
channelMatrixMagnitudeMeanBySlot = nan(nRxChannels, nLayers, nSlots);

for s = 1:nSlots
    slot = cfg.dataSlots(s);
    globalSymbols = slot * cfg.symbolsPerSlot + (1:cfg.symbolsPerSlot);
    rxSlot = rxGrid(:, globalSymbols, :);

    % Standard Type-1 DM-RS channel estimation with CDM OCC despreading
    dmrsIndices = double(package.dmrsIndices(:, :, s));
    dmrsSymbols = double(package.dmrsSymbols(:, :, s));
    [channel, noiseVariance(s)] = nrChannelEstimate( ...
        rxSlot, dmrsIndices, dmrsSymbols, ...
        'CDMLengths', package.dmrsCDMLengths);     % [2 1] for OCC

    % Aggregate input SNR before equalization: active/null FFT bins and
    % standard DM-RS prediction/residual, separately for every RX channel.
    slotStart = slot * slotSamples;
    slotWaveform = frameWaveform(slotStart + (1:slotSamples), :);
    snrMetrics = type1_snr_metrics(slotWaveform, rxSlot, channel, ...
        noiseVariance(s), package, s);
    snrNullDbBySlot(s, :) = snrMetrics.snrNullDb;
    snrDmrsDbBySlot(s, :) = snrMetrics.snrDmrsDb;
    snrNullSignalPowerBySlot(s, :) = snrMetrics.nullSignalPower;
    snrNullNoisePowerBySlot(s, :) = snrMetrics.nullNoisePower;
    snrDmrsSignalPowerBySlot(s, :) = snrMetrics.dmrsSignalPower;
    snrDmrsResidualPowerBySlot(s, :) = snrMetrics.dmrsResidualPower;

    % Extract data REs (all layers share the same 2D positions)
    firstLayerIndices = double(package.dataIndices(:, 1, s));
    [subcarriers, symbols] = ind2sub( ...
        [nSC cfg.symbolsPerSlot nLayers], firstLayerIndices);
    indices2D = sub2ind([nSC cfg.symbolsPerSlot], subcarriers, symbols);

    % Gather received symbols and channel estimates at data REs
    received = complex(zeros(nDataRE, nRxChannels));
    channelAtData = complex(zeros(nDataRE, nRxChannels, nLayers));
    for r = 1:nRxChannels
        plane = rxSlot(:, :, r);
        received(:, r) = plane(indices2D);
        for layer = 1:nLayers
            channelPlane = channel(:, :, r, layer);
            channelAtData(:, r, layer) = channelPlane(indices2D);
        end
    end
    preCompData(:, s) = received(:, 1);  % RX1 raw for constellation display

    % Representative H values for diagnostics.
    % channelAtData has size [nDataRE x nRx x nLayer].  The complex H phase
    % can vary over frequency, so we keep a centre-RE complex matrix and an
    % average magnitude matrix separately.
    centerDataRE = round(nDataRE / 2);
    channelMatrixCenterBySlot(:, :, s) = ...
        reshape(channelAtData(centerDataRE, :, :), nRxChannels, nLayers);
    channelMatrixMagnitudeMeanBySlot(:, :, s) = ...
        reshape(mean(abs(channelAtData), 1), nRxChannels, nLayers);

    if ~spatialDecodeEnabled
        postCompData(:, s, :) = complex(nan(nDataRE, 1, nLayers));
        continue;
    end

    % ── Page-wise RZF: vectorized across all REs ──
    % Reshape to [nRX x nLayer x nRE] pages for pagemtimes
    channelPages = permute(channelAtData, [2 3 1]);   % [nRx x nLayer x nRE]
    receivedPages = permute(received, [2 3 1]);        % [nRx x 1 x nRE]
    channelHermitian = pagectranspose(channelPages);
    gram = pagemtimes(channelHermitian, channelPages); % H^H H per RE
    matched = pagemtimes(channelHermitian, receivedPages); % H^H y per RE
    meanChannelPower = sum(abs(channelPages).^2, [1 2]) / nLayers;
    lambda = cfg.rzfRegularization * max(meanChannelPower, eps);
    regularized = gram + reshape(eye(nLayers), nLayers, nLayers, 1) .* lambda;
    equalized = pagemldivide(regularized, matched);    % (H^H H+λI)^-1 H^H y
    postCompData(:, s, :) = permute(equalized, [3 2 1]);

    % Condition numbers of the DM-RS-estimated channel Hhat at sampled REs.
    % These are receiver diagnostics, not oracle condition numbers of the
    % physical/composite channel.  In particular, interpolation error under
    % a frequency-phase slope can change cond(Hhat) even if cond(H) does not.
    sampleCount = min(cfg.channelConditionSamplesPerSlot, nDataRE);
    sampleIndices = unique(round(linspace(1, nDataRE, sampleCount)));
    localCondition = zeros(1, numel(sampleIndices));
    for q = 1:numel(sampleIndices)
        localCondition(q) = cond(channelPages(:, :, sampleIndices(q)));
    end
    conditionNumbers = [conditionNumbers localCondition]; %#ok<AGROW>
end

%% ═══ Step 8–9: Hard demod, Viterbi decode, BER, EVM ═══
if spatialDecodeEnabled
    codedBER = zeros(nSlots, nLayers);
    infoBER = zeros(nSlots, nLayers);
    codedBitErrors = zeros(nSlots, nLayers);
    infoBitErrors = zeros(nSlots, nLayers);
    evmRMSPercent = zeros(nSlots, nLayers);
    for s = 1:nSlots
        for layer = 1:nLayers
            equalized = postCompData(:, s, layer);
            % Hard-decision QPSK demodulation
            hardBits = logical(nrSymbolDemodulate(equalized, ...
                cfg.modulation, 'DecisionType', 'hard'));
            expectedCoded = package.codedBits(:, s, layer);
            codedBitErrors(s, layer) = sum(hardBits ~= expectedCoded);
            codedBER(s, layer) = codedBitErrors(s, layer) / numel(expectedCoded);

            % Optional decoder. In the default 'none' mode, decoded BER is
            % exactly the uncoded PHY BER and contains no coding gain.
            switch package.channelCoding
                case 'none'
                    decoded = hardBits;
                case 'convolutional'
                    decoded = logical(vitdec(double(hardBits), ...
                        package.trellis, cfg.viterbiTraceback, ...
                        'term', 'hard'));
                otherwise
                    error('type1:Coding', 'Unsupported coding mode %s.', ...
                        package.channelCoding);
            end
            expectedInfo = package.infoBits(:, s, layer);
            decoded = decoded(1:numel(expectedInfo));      % strip tail bits
            infoBitErrors(s, layer) = sum(decoded ~= expectedInfo);
            infoBER(s, layer) = infoBitErrors(s, layer) / numel(expectedInfo);

            % EVM: RMS error relative to known TX symbols
            expectedSymbols = double(package.dataQPSK(:, s, layer));
            evmRMSPercent(s, layer) = 100 * ...
                rms(equalized - expectedSymbols) / rms(expectedSymbols);
        end
    end
else
    codedBER = nan(nSlots, nLayers);
    infoBER = nan(nSlots, nLayers);
    codedBitErrors = nan(nSlots, nLayers);
    infoBitErrors = nan(nSlots, nLayers);
    evmRMSPercent = nan(nSlots, nLayers);
end

%% ── Pack results ──
result = struct;
result.timingOffset = timingOffset;
result.pssPeakIndices = pssPeakIndices;
result.pssModuloOffsets = pssModuloOffsets;
result.pssMetrics = pssMetrics;
result.bestNID2 = bestPSSIndex - 1;
result.expectedNID2 = mod(cfg.pci, 3);
result.frequencyOffsetHz = frequencyOffsetHz;
result.cpCorrelation = cpCorrelation;
result.sssMetric = sssMetric;
result.pbchCRCError = logical(pbchCRCError);
result.mibMatches = mibMatches;
result.decodedMIB = decodedMIB;
result.pbchSymbols = pbchSymbols;
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
result.snrNullDbBySlot = snrNullDbBySlot;
result.snrDmrsDbBySlot = snrDmrsDbBySlot;
result.snrNullDb = median(snrNullDbBySlot, 1, 'omitnan');
result.snrDmrsDb = median(snrDmrsDbBySlot, 1, 'omitnan');
result.snrNullSignalPowerBySlot = snrNullSignalPowerBySlot;
result.snrNullNoisePowerBySlot = snrNullNoisePowerBySlot;
result.snrDmrsSignalPowerBySlot = snrDmrsSignalPowerBySlot;
result.snrDmrsResidualPowerBySlot = snrDmrsResidualPowerBySlot;
result.estimatedChannelConditionNumbers = conditionNumbers;
result.conditionNumbers = conditionNumbers; % legacy alias: cond(Hhat)
result.channelMatrixCenterBySlot = channelMatrixCenterBySlot;
result.channelMatrixMagnitudeMeanBySlot = channelMatrixMagnitudeMeanBySlot;
result.channelMatrixMean = mean(channelMatrixCenterBySlot, 3, 'omitnan');
result.channelMatrixMagnitudeMean = mean( ...
    channelMatrixMagnitudeMeanBySlot, 3, 'omitnan');
% Same channel matrices, but printed in the user's preferred convention:
%   H_ij = channel from TX/layer i to RX antenna j.
% Rows are TX/layers, columns are RX antennas.
result.channelMatrixTxRxMean = result.channelMatrixMean.';
result.channelMatrixTxRxMagnitudeMean = result.channelMatrixMagnitudeMean.';
if spatialDecodeEnabled
    result.estimatedConditionStats = [median(conditionNumbers), ...
        prctile(conditionNumbers, 95), max(conditionNumbers)];
else
    result.estimatedConditionStats = [nan nan nan];
end
result.conditionStats = result.estimatedConditionStats; % legacy alias: cond(Hhat)
result.elapsedMs = 1e3 * toc(timer);
end

%% ═══ Local: CP-based fine CFO estimator ═══
function [frequencyOffsetHz, quality] = estimate_fine_cfo( ...
        waveform, cpLengths, nfft, sampleRate)
% Estimate residual CFO from the phase difference between CP and the
% corresponding tail of each OFDM symbol.
%   f_hat = angle( sum conj(CP) .* tail ) * Fs / (2*pi*NFFT)
% Unambiguous range: +/- SCS/2 = +/- 15 kHz (for 30 kHz SCS).

correlation = 0;
earlyEnergy = 0;
lateEnergy = 0;
cursor = 1;
for symbol = 1:numel(cpLengths)
    cp = cpLengths(symbol);
    earlyIndices = cursor + (0:cp-1);
    lateIndices = cursor + nfft + (0:cp-1);
    early = waveform(earlyIndices, :);
    late = waveform(lateIndices, :);
    correlation = correlation + sum(conj(early) .* late, 'all');
    earlyEnergy = earlyEnergy + sum(abs(early).^2, 'all');
    lateEnergy = lateEnergy + sum(abs(late).^2, 'all');
    cursor = cursor + cp + nfft;
end
frequencyOffsetHz = angle(correlation) * sampleRate / (2*pi*nfft);
quality = abs(correlation) / sqrt(earlyEnergy * lateEnergy + eps);
end
