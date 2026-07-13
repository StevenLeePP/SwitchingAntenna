function metrics = type1_snr_metrics( ...
        slotWaveform, rxSlot, channel, noiseVariance, package, slotPosition)
%TYPE1_SNR_METRICS Estimate pre-equalization SNR for every RX channel.
%  snrNullDb compares active FFT bins against nearby unused FFT bins.
%  snrDmrsDb compares the predicted Type-1 DM-RS with its residual after
%  frequency smoothing. Both are aggregate four-source input metrics; they
%  are deliberately measured before MIMO equalization.

cfg = package.cfg;
nRx = size(slotWaveform, 2);
nLayers = cfg.nLayers;
nSC = 12 * cfg.nRB;

%% Null-subcarrier SNR on aligned data OFDM symbols
cpStart = (cfg.dataSlots(slotPosition) * cfg.symbolsPerSlot) + 1;
cpTemplate = package.ofdmInfo.CyclicPrefixLengths(:);
cpIndices = mod(cpStart - 1 + (0:cfg.symbolsPerSlot-1), ...
    numel(cpTemplate)) + 1;
cpLengths = cpTemplate(cpIndices);
fullGrid = complex(zeros(cfg.nfft, cfg.symbolsPerSlot, nRx));
cursor = 1;
for symbol = 1:cfg.symbolsPerSlot
    cp = cpLengths(symbol);
    useful = slotWaveform(cursor + cp:cursor + cp + cfg.nfft - 1, :);
    transformed = fftshift(fft(useful, cfg.nfft, 1), 1) / sqrt(cfg.nfft);
    fullGrid(:, symbol, :) = reshape(transformed, cfg.nfft, 1, nRx);
    cursor = cursor + cp + cfg.nfft;
end

activeStart = floor((cfg.nfft - nSC) / 2) + 1;
activeBins = activeStart:(activeStart + nSC - 1);
gap = cfg.snrNullGuardSubcarriers;
nNoise = cfg.snrNullNoiseSubcarriers;
leftNoise = (activeStart - gap - nNoise):(activeStart - gap - 1);
rightStart = activeStart + nSC + gap;
rightNoise = rightStart:(rightStart + nNoise - 1);
assert(leftNoise(1) >= 1 && rightNoise(end) <= cfg.nfft, ...
    'Configured null-subcarrier noise bands exceed the FFT.');
noiseBins = [leftNoise rightNoise];
dataSymbols = cfg.dataSymbolSet + 1;

signalPlusNoisePower = reshape(mean( ...
    abs(fullGrid(activeBins, dataSymbols, :)).^2, [1 2]), 1, nRx);
nullNoisePower = reshape(mean( ...
    abs(fullGrid(noiseBins, dataSymbols, :)).^2, [1 2]), 1, nRx);
nullSignalPower = max(signalPlusNoisePower - nullNoisePower, eps);
snrNullLinear = nullSignalPower ./ max(nullNoisePower, eps);

%% DM-RS residual SNR on the standard Type-1 FDM+CDM symbol
dmrsIndices = double(package.dmrsIndices(:, :, slotPosition));
dmrsSymbols = double(package.dmrsSymbols(:, :, slotPosition));
txDMRSGrid = complex(zeros(nSC, cfg.symbolsPerSlot, nLayers));
for layer = 1:nLayers
    txDMRSGrid(dmrsIndices(:, layer)) = dmrsSymbols(:, layer);
end
dmrsMask = any(abs(txDMRSGrid) > 0, 3);

% Smooth H in frequency before forming the residual. This prevents the
% exact same noisy pilot sample from being perfectly fitted back to itself.
span = cfg.snrDmrsSmoothingSubcarriers;
smoothedChannel = movmean(channel, span, 1, 'Endpoints', 'shrink');
predicted = complex(zeros(nSC, cfg.symbolsPerSlot, nRx));
for layer = 1:nLayers
    predicted = predicted + smoothedChannel(:, :, :, layer) .* ...
        txDMRSGrid(:, :, layer);
end

dmrsSignalPower = zeros(1, nRx);
dmrsResidualPower = zeros(1, nRx);
for rx = 1:nRx
    receivedPlane = rxSlot(:, :, rx);
    predictedPlane = predicted(:, :, rx);
    residual = receivedPlane(dmrsMask) - predictedPlane(dmrsMask);
    dmrsSignalPower(rx) = mean(abs(predictedPlane(dmrsMask)).^2);
    dmrsResidualPower(rx) = mean(abs(residual).^2);
end
% nrChannelEstimate returns a useful conservative floor. It also prevents
% an unrealistically large result when the smoothed pilot fit is too good.
dmrsNoiseFloor = max(double(noiseVariance), eps);
dmrsResidualPower = max(dmrsResidualPower, dmrsNoiseFloor);
snrDmrsLinear = dmrsSignalPower ./ max(dmrsResidualPower, eps);

metrics = struct;
metrics.snrNullDb = 10 * log10(max(snrNullLinear, eps));
metrics.snrDmrsDb = 10 * log10(max(snrDmrsLinear, eps));
metrics.nullSignalPower = nullSignalPower;
metrics.nullNoisePower = nullNoisePower;
metrics.dmrsSignalPower = dmrsSignalPower;
metrics.dmrsResidualPower = dmrsResidualPower;
metrics.nullNoiseBins = noiseBins;
metrics.activeBins = activeBins;
metrics.definition = ['Per-RX aggregate pre-equalization SNR; null uses ' ...
    '(Pactive-Pnull)/Pnull, DM-RS uses smoothed prediction/residual.'];
end
