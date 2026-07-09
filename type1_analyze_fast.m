function result = type1_analyze_fast(rx30, package, dataSlot)
%TYPE1_ANALYZE_FAST Low-latency one-slot Type-A monitor.
%
% Same sync pipeline as type1_analyze (PSS, CFO, SSS, PBCH/MIB), but
% equalizes and decodes only ONE representative data slot instead of
% all 19, cutting analysis time from ~300 ms to ~40 ms.
%
% Uses the known NID2 to run a single PSS hypothesis instead of three.
%
% Called every ~1 second by type1_rx_live for real-time monitoring.

arguments
    rx30 {mustBeNumeric}
    package (1,1) struct
    dataSlot (1,1) double {mustBeInteger,mustBeNonnegative}
end
cfg = package.cfg;
assert(any(cfg.dataSlots == dataSlot), 'Invalid data slot.');
nRxChannels = size(rx30, 2);
assert(nRxChannels >= 1, 'At least one RX channel is required.');
cfg.nRxChannels = nRxChannels;   % analysis follows the IQ column count

timer = tic;
frameSamples = round(cfg.frameDurationSec * cfg.txSampleRate);
slotSamples = frameSamples / cfg.slotsPerFrame;
if size(rx30, 1) < frameSamples + slotSamples
    error('type1:ShortFastWindow', ...
        'At least 10.5 ms is required for fast analysis.');
end

% Per-channel RMS normalization
rx30 = double(rx30);
for r = 1:nRxChannels
    scale = rms(rx30(:, r));
    if scale > 0, rx30(:, r) = rx30(:, r) / scale; end
end

carrier = type1_carrier_config(cfg, 0);
nSC = 12 * cfg.nRB;

%% ═══ Step 1: Single-hypothesis PSS timing (known NID2) ═══
expectedNID2 = mod(cfg.pci, 3);
localSSB = complex(zeros(240, 4));
localSSB(nrPSSIndices) = nrPSS(expectedNID2);
referenceGrid = complex(zeros(nSC, cfg.symbolsPerSlot));
referenceGrid(package.ssbSubcarriers, package.ssbSymbols) = localSSB;
[timingOffset, magnitude] = nrTimingEstimate(carrier, rx30, ...
    referenceGrid, 'Nfft', cfg.nfft, ...
    'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0);

% PSS peak-to-median ratio for signal presence quality
correlationPower = sum(abs(magnitude).^2, 2);
pssPeak = max(correlationPower, [], 'all');
pssMedian = median(correlationPower, 'all');
pssPeakToMedianDb = 10*log10(pssPeak / (pssMedian + eps));

while timingOffset + frameSamples > size(rx30, 1)
    timingOffset = timingOffset - frameSamples;
end
if timingOffset < 0
    error('type1:IncompleteFastFrame', ...
        'Expected PSS does not leave one complete frame.');
end

%% ═══ Step 2: Fine CFO estimation and compensation ═══
frameWaveform = rx30(timingOffset + (1:frameSamples), :);
[frequencyOffsetHz, cpCorrelation] = estimate_fine_cfo( ...
    frameWaveform, package.ofdmInfo.CyclicPrefixLengths, ...
    cfg.nfft, cfg.txSampleRate);
sampleIndex = (0:frameSamples-1).';
frameWaveform = frameWaveform .* exp( ...
    -1j * 2*pi * frequencyOffsetHz * sampleIndex / cfg.txSampleRate);

%% ═══ Step 3–5: Demodulate slot 0 (SSB) + SSS + PBCH/MIB ═══
% Only slot 0 and one data slot are demodulated (not all 20 slots).
ssbWaveform = frameWaveform(1:slotSamples, :);
carrier.NSlot = 0;
ssbSlotGrid = nrOFDMDemodulate(carrier, ssbWaveform, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, ...
    'CarrierFrequency', 0);
rxSSB = ssbSlotGrid(package.ssbSubcarriers, package.ssbSymbols, :);

% SSS non-coherent verification
sssReceived = complex(zeros(127, nRxChannels));
for r = 1:nRxChannels
    plane = rxSSB(:, :, r);
    sssReceived(:, r) = plane(nrSSSIndices);
end
expectedSSS = nrSSS(cfg.pci);
sssMetric = sum(abs(expectedSSS' * sssReceived).^2) / ...
    (sum(abs(expectedSSS).^2) * sum(abs(sssReceived).^2, 'all') + eps);

% PBCH decode (same as full analysis, kept for sync integrity monitoring)
ibarSSB = cfg.ssbIndex + 4 * cfg.halfFrameBit;
pbchDMRSIndices = nrPBCHDMRSIndices(cfg.pci);
pbchDMRSSymbols = nrPBCHDMRS(cfg.pci, ibarSSB);
rxSSBSlot = complex(zeros(240, cfg.symbolsPerSlot, nRxChannels));
rxSSBSlot(:, 1:4, :) = rxSSB;
[pbchChannel, pbchNoise] = nrChannelEstimate( ...
    rxSSBSlot, pbchDMRSIndices, pbchDMRSSymbols, ...
    'AveragingWindow', [5 1]);
equalizedSSB = complex(zeros(240, 4));
for symbol = 1:4
    for k = 1:240
        y = reshape(rxSSB(k, symbol, :), nRxChannels, 1);
        h = reshape(pbchChannel(k, symbol, :, 1), nRxChannels, 1);
        equalizedSSB(k, symbol) = (h' * y) / (h' * h + max(pbchNoise, eps));
    end
end
pbchSymbols = equalizedSSB(nrPBCHIndices(cfg.pci));
pbchLLR = nrPBCHDecode(pbchSymbols, cfg.pci, ...
    mod(cfg.ssbIndex, 8), max(pbchNoise, eps));
[~, pbchCRCError, decodedMIB] = nrBCHDecode( ...
    pbchLLR, 8, cfg.Lmax, cfg.pci);
mibMatches = ~pbchCRCError && isequal(decodedMIB, package.mib);

%% ═══ Step 6–7: Single data slot DM-RS + RZF ═══
slotPosition = find(cfg.dataSlots == dataSlot, 1);
slotStart = dataSlot * slotSamples;
dataWaveform = frameWaveform(slotStart + (1:slotSamples), :);
carrier.NSlot = dataSlot;
rxSlot = nrOFDMDemodulate(carrier, dataWaveform, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, ...
    'CarrierFrequency', 0);

% Type-1 CDM channel estimation
dmrsIndices = double(package.dmrsIndices(:, :, slotPosition));
dmrsSymbols = double(package.dmrsSymbols(:, :, slotPosition));
[channel, noiseVariance] = nrChannelEstimate( ...
    rxSlot, dmrsIndices, dmrsSymbols, ...
    'CDMLengths', package.dmrsCDMLengths);

% Extract data REs and channel at data positions
nDataRE = package.nDataREPerSlotLayer;
nLayers = cfg.nLayers;
firstLayerIndices = double(package.dataIndices(:, 1, slotPosition));
[subcarriers, symbols] = ind2sub( ...
    [nSC cfg.symbolsPerSlot nLayers], firstLayerIndices);
indices2D = sub2ind([nSC cfg.symbolsPerSlot], subcarriers, symbols);

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

preCompData = received(:, 1);
spatialDecodeEnabled = nRxChannels >= nLayers;

if spatialDecodeEnabled
% ── Page-wise nRx-by-nLayer RZF equalization ──
channelPages = permute(channelAtData, [2 3 1]);      % [nRx x nLayer x nRE]
receivedPages = permute(received, [2 3 1]);           % [nRx x 1 x nRE]
channelHermitian = pagectranspose(channelPages);
gram = pagemtimes(channelHermitian, channelPages);    % H^H H
matched = pagemtimes(channelHermitian, receivedPages);% H^H y
meanChannelPower = sum(abs(channelPages).^2, [1 2]) / nLayers;
lambda = cfg.rzfRegularization * max(meanChannelPower, eps);
regularized = gram + reshape(eye(nLayers), nLayers, nLayers, 1) .* lambda;
equalizedPages = pagemldivide(regularized, matched);  % (H^HH+λI)^-1 H^H y
postCompData = permute(equalizedPages, [3 1 2]);
postCompData = reshape(postCompData, nDataRE, nLayers);

%% ═══ Step 8–9: BER and EVM for this one slot ═══
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
    decoded = logical(vitdec(double(hardBits), package.trellis, ...
        cfg.viterbiTraceback, 'term', 'hard'));
    expectedInfo = package.infoBits(:, slotPosition, layer);
    decoded = decoded(1:numel(expectedInfo));
    infoBitErrors(layer) = sum(decoded ~= expectedInfo);
    infoBER(layer) = infoBitErrors(layer) / numel(expectedInfo);
    expectedSymbols = double(package.dataQPSK(:, slotPosition, layer));
    evmRMSPercent(layer) = 100 * ...
        rms(equalized - expectedSymbols) / rms(expectedSymbols);
end

% Channel condition sampling
sampleCount = min(cfg.channelConditionSamplesPerSlot, nDataRE);
sampleIndices = unique(round(linspace(1, nDataRE, sampleCount)));
conditionNumbers = zeros(1, numel(sampleIndices));
for q = 1:numel(sampleIndices)
    conditionNumbers(q) = cond(channelPages(:, :, sampleIndices(q)));
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
result.frequencyOffsetHz = frequencyOffsetHz;
result.cpCorrelation = cpCorrelation;
result.sssMetric = sssMetric;
result.pbchCRCError = logical(pbchCRCError);
result.mibMatches = mibMatches;
result.nRxChannels = nRxChannels;
result.nLayers = nLayers;
result.spatialDecodeEnabled = spatialDecodeEnabled;
result.preCompData = preCompData;
result.postCompData = postCompData;
result.codedBER = codedBER;
result.infoBER = infoBER;
result.codedBitErrors = codedBitErrors;
result.infoBitErrors = infoBitErrors;
result.evmRMSPercent = evmRMSPercent;
result.noiseVariance = noiseVariance;
result.conditionStats = [median(conditionNumbers), ...
    prctile(conditionNumbers, 95), max(conditionNumbers)];
result.elapsedMs = 1e3 * toc(timer);
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
