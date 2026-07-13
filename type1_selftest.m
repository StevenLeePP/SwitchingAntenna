%% Offline Type-A four-port end-to-end self-test
%  Validates the full TX->RX chain without accessing hardware:
%    - SSB resource placement (DM-RS at l=2, data on correct symbols)
%    - Type-1 DM-RS fills all 612 subcarriers
%    - Known MIMO channel + injected CFO + AWGN
%    - type1_analyze (all 19 slots) and type1_analyze_fast (one slot)
%    - 122.88 MS/s digital-switch path with resampled data
clear; close all; clc;

cfg = type1_config();
try
    package = type1_load_package();
catch
    package = type1_build_package(cfg);
    save(cfg.referenceFile, 'package', '-v7.3');
end
assert(strcmp(package.channelCoding, cfg.channelCoding));
assert(startsWith(package.payloadMetadata(1, 1).message, 'NR4T|VER=2|SRC=1'));

%% ═══ Verify strict Type-A resource placement ═══
nSC = 12 * cfg.nRB;
dmrsIndices = double(package.dmrsIndices(:, :, 1));
dataIndices = double(package.dataIndices(:, :, 1));

% Check DM-RS symbols are all on l=2 (dmrsTypeAPosition=2 -> 1-based index 3)
[dmrsK, dmrsL, ~] = ind2sub([nSC cfg.symbolsPerSlot cfg.nLayers], dmrsIndices(:));
[~, dataL, ~] = ind2sub([nSC cfg.symbolsPerSlot cfg.nLayers], dataIndices(:));
assert(all(dmrsL == cfg.dmrsTypeAPosition + 1));     % all DM-RS at symbol 2
assert(isequal(unique(dataL).' - 1, cfg.dataSymbolSet));  % data on [0 1 3:13]
assert(numel(unique(dmrsK)) == nSC, ...
    'The two Type-1 CDM groups must fill the DM-RS OFDM symbol.');

%% ═══ Deterministic well-conditioned 4x4 MIMO channel ═══
% Diagonal-dominant H ensures solvable but realistic condition number ~10.
H = [1.00, 0.12+0.05i, 0.08-0.04i, 0.05+0.02i; ...
     0.06-0.03i, 0.95, 0.10+0.04i, 0.07-0.02i; ...
     0.09+0.02i, 0.05-0.03i, 1.05, 0.11+0.01i; ...
     0.04+0.01i, 0.08+0.03i, 0.06-0.04i, 0.98];

% Apply channel: rx = tx * H.' (each row is one sample, each column one antenna)
tx = double(package.txWaveform);
rx = tx * H.';

% Inject 850 Hz CFO (within +/- 15 kHz unambiguous range)
injectedCFOHz = 850;
sampleIndex = (0:size(rx,1)-1).';
rx = rx .* exp(1j * 2*pi * injectedCFOHz * sampleIndex / cfg.txSampleRate);

% Add AWGN at 32 dB SNR per channel
stream = RandStream('mt19937ar', 'Seed', 7070);
signalPower = mean(abs(rx).^2, 'all');
noise = sqrt(signalPower / 10^(32/10) / 2) * ...
    (randn(stream, size(rx)) + 1i * randn(stream, size(rx)));

% Build a window with extra guard samples at start and end
prefix = complex(zeros(5000, 4));
rxWindow = [prefix; rx + noise; rx(1:50000, :) + noise(1:50000, :)];

%% ═══ Full analysis (all 19 data slots) ═══
result = type1_analyze(rxWindow, package);
assert(~result.pbchCRCError && result.mibMatches, ...
    'Offline PBCH/MIB test failed.');
assert(all(result.infoBER == 0, 'all'), ...
    'Offline Type-1 information BER is nonzero.');
assert(abs(result.frequencyOffsetHz - injectedCFOHz) < 5, ...
    'Fine CFO estimator failed.');
assert(all(isfinite(result.snrNullDb)) && all(result.snrNullDb > 15), ...
    'Null-subcarrier SNR estimator failed.');
assert(all(isfinite(result.snrDmrsDb)) && all(result.snrDmrsDb > 10), ...
    'DM-RS SNR estimator failed.');

%% ═══ Fast analysis (one data slot monitor path) ═══
fastResult = type1_analyze_fast(rxWindow, package, 10);
assert(fastResult.usedPSS && ~fastResult.pbchChecked, ...
    'Fast monitor acquisition/PBCH-skip state is wrong.');
assert(all(fastResult.infoBER == 0), ...
    'Fast monitor information BER is nonzero.');

% Timestamp-free offline tracking path: reuse the acquired timing result
% and verify that no second nrTimingEstimate/PSS search is needed.
trackedFastResult = type1_analyze_fast(rxWindow, package, 10, ...
    'forcePSS', false, 'syncState', fastResult.syncState, ...
    'trackedTimingOffset', fastResult.timingOffset);
assert(~trackedFastResult.usedPSS && ...
    all(trackedFastResult.infoBER == 0), ...
    'Fast monitor tracked-timing test failed.');

% Periodic Track health check: restrict PSS correlation to the predicted
% +/- search window, then continue decoding without a full-buffer Acquire.
localPssResult = type1_analyze_fast(rxWindow, package, 10, ...
    'forcePSS', false, 'validatePSS', true, ...
    'syncState', fastResult.syncState, ...
    'trackedTimingOffset', fastResult.timingOffset);
assert(~localPssResult.usedPSS && localPssResult.localPSSChecked && ...
    all(localPssResult.infoBER == 0), ...
    'Fast monitor local-PSS tracking test failed.');

%% ═══ 122.88 MS/s digital-switch path ═══
% Upsample by 4x to emulate the oversampled RX, then exercise the switch.
raw122 = complex(zeros(4 * size(rxWindow, 1), 4));
for r = 1:4
    raw122(:, r) = resample(rxWindow(:, r), 4, 1);
end
[~, switched] = type1_digital_switch(single(raw122));
switchResult = type1_analyze(switched, package);
assert(~switchResult.pbchCRCError && switchResult.mibMatches);
assert(all(switchResult.infoBER == 0, 'all'));

fprintf('\nType-A four-port self-test PASSED.\n');
fprintf('DM-RS symbols=%s, data symbols=%s\n', ...
    num2str(unique(dmrsL).' - 1), num2str(unique(dataL).' - 1));
fprintf('DM-RS groups=[%s], frequency OCC=%s\n', ...
    num2str(package.dmrsCDMGroups), ...
    mat2str(package.dmrsFrequencyWeights));
fprintf('PBCH/MIB OK=%d/%d, information BER=[%s]\n', ...
    ~result.pbchCRCError, result.mibMatches, ...
    num2str(sum(result.infoBitErrors, 1) ./ ...
    (package.nInfoBitsPerSlotLayer * numel(cfg.dataSlots))));
fprintf('Injected/estimated CFO=%.1f / %.1f Hz\n', ...
    injectedCFOHz, result.frequencyOffsetHz);
fprintf('Fast slot %d analysis=%.1f ms, BER=[%s]\n', ...
    fastResult.dataSlot, fastResult.elapsedMs, num2str(fastResult.infoBER));
fprintf('cond(H) median/p95/max=[%s]\n', ...
    num2str(result.conditionStats));
fprintf('Coding=%s, SNR null=[%s] dB, DM-RS=[%s] dB\n', ...
    result.channelCoding, num2str(result.snrNullDb, '%.2f '), ...
    num2str(result.snrDmrsDb, '%.2f '));

%% ═══ Legacy convolutional-code compatibility test ═══
convCfg = cfg;
convCfg.channelCoding = 'convolutional';
convPackage = type1_build_package(convCfg);
convTx = double(convPackage.txWaveform);
convRx = convTx * H.';
convRx = convRx .* exp(1j * 2*pi * injectedCFOHz * ...
    (0:size(convRx,1)-1).' / cfg.txSampleRate);
convSignalPower = mean(abs(convRx).^2, 'all');
convNoise = sqrt(convSignalPower / 10^(32/10) / 2) * ...
    (randn(stream, size(convRx)) + 1i * randn(stream, size(convRx)));
convWindow = [prefix; convRx + convNoise; ...
    convRx(1:50000, :) + convNoise(1:50000, :)];
convResult = type1_analyze_fast(convWindow, convPackage, 10);
assert(all(convResult.rawBER == 0) && all(convResult.decodedBER == 0), ...
    'Legacy convolutional coding compatibility test failed.');
fprintf('Convolutional compatibility PASSED, raw/decoded BER=[%s]/[%s]\n', ...
    num2str(convResult.rawBER), num2str(convResult.decodedBER));
