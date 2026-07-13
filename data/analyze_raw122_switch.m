%% Analyze saved 122.88 MS/s raw IQ through the digital antenna switch.
%
% Purpose:
%   Read the newest *_raw122_csingle_iq4.bin file, emulate the proposed
%   switching/de-interleaving path with type1_digital_switch, then run:
%     synchronization -> channel estimation -> channel compensation/RZF
%     -> MIMO layer separation -> BER against the known reference bits.
%
% Run:
%   cd('/home/bupt/tools/matlab_test/nr4x4_type1/data')
%   analyze_raw122_switch

clear; close all; clc;

dataDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(dataDir);
addpath(projectDir);

nChannels = 4;
rawSampleRate = 122.88e6;
virtualSampleRate = 30.72e6;
rawFile = newest_file(dataDir, '*_raw122_csingle_iq4.bin');

fprintf('\n========== Analyze raw122 IQ through digital switch ==========\n');
fprintf('Raw IQ file : %s\n', rawFile);

raw122 = read_complex_single_iq(rawFile, nChannels);
fprintf('raw122 size : %d samples x %d channels, %.3f ms @ %.2f MS/s\n', ...
    size(raw122, 1), size(raw122, 2), ...
    1e3 * size(raw122, 1) / rawSampleRate, rawSampleRate / 1e6);
print_iq_stats('raw122', raw122);

% Emulate the switching antenna scheme:
%   raw122 physical RX streams -> one stitched 122.88 MS/s stream
%   -> four de-interleaved 30.72 MS/s virtual-RX streams.
[stitched122, rx30] = type1_digital_switch(raw122);
fprintf('stitched122 size: %d samples x %d channel\n', ...
    size(stitched122, 1), size(stitched122, 2));
fprintf('rx30 size       : %d samples x %d channels, %.3f ms @ %.2f MS/s\n', ...
    size(rx30, 1), size(rx30, 2), ...
    1e3 * size(rx30, 1) / virtualSampleRate, virtualSampleRate / 1e6);
print_iq_stats('rx30_from_raw122_switch', rx30);

% Optional consistency check against the saved virtual30 file from the same
% RX run. If present, this should be ~0 because type1_rx_live writes
% virtual30 using the same type1_digital_switch function.
virtualFile = matching_or_newest_virtual_file(dataDir, rawFile);
if ~isempty(virtualFile)
    savedVirtual30 = read_complex_single_iq(virtualFile, nChannels);
    if isequal(size(savedVirtual30), size(rx30))
        relativeError = norm(rx30(:) - savedVirtual30(:)) / ...
            max(norm(savedVirtual30(:)), eps);
        fprintf('Consistency vs saved virtual30: relative error = %.3e\n', ...
            relativeError);
        fprintf('Saved virtual30 file          : %s\n\n', virtualFile);
    end
end

package = type1_load_package();
result = type1_analyze(rx30, package);

print_type1_result(result);
plot_type1_result(result, 'raw122 -> digital switch -> rx30 analysis');

save(fullfile(dataDir, 'analyze_raw122_switch_result.mat'), ...
    'rawFile', 'virtualFile', 'rawSampleRate', 'virtualSampleRate', ...
    'result', '-v7.3');
fprintf('Saved result: %s\n', ...
    fullfile(dataDir, 'analyze_raw122_switch_result.mat'));

%% Local helpers

function fileName = newest_file(dataDir, pattern)
files = dir(fullfile(dataDir, pattern));
if isempty(files)
    error('type1:NoIQFile', ...
        'No file matching %s under %s. Run type1_rx_live first.', ...
        pattern, dataDir);
end
[~, index] = max([files.datenum]);
fileName = fullfile(files(index).folder, files(index).name);
end

function virtualFile = matching_or_newest_virtual_file(dataDir, rawFile)
[~, rawName] = fileparts(rawFile);
prefix = erase(rawName, '_raw122_csingle_iq4');
candidate = fullfile(dataDir, [prefix '_virtual30_csingle_iq4.bin']);
if exist(candidate, 'file')
    virtualFile = candidate;
    return;
end
files = dir(fullfile(dataDir, '*_virtual30_csingle_iq4.bin'));
if isempty(files)
    virtualFile = '';
else
    [~, index] = max([files.datenum]);
    virtualFile = fullfile(files(index).folder, files(index).name);
end
end

function x = read_complex_single_iq(fileName, nChannels)
fid = fopen(fileName, 'rb');
if fid < 0
    error('type1:OpenIQFile', 'Could not open %s.', fileName);
end
cleanup = onCleanup(@() fclose(fid));

raw = fread(fid, inf, 'single=>single');
if mod(numel(raw), 2 * nChannels) ~= 0
    error('type1:IQFileSize', ...
        'File length is not divisible by 2*nChannels: %s', fileName);
end

iq = complex(raw(1:2:end), raw(2:2:end));
nSamples = numel(iq) / nChannels;
x = reshape(iq, nSamples, nChannels);
end

function print_iq_stats(name, x)
rmsPerChannel = sqrt(mean(abs(x).^2, 1));
peakPerChannel = max(abs(x), [], 1);
dcPerChannel = abs(mean(x, 1));
fprintf('%s RMS          : [%s]\n', name, num2str(rmsPerChannel, '%.4g '));
fprintf('%s peak         : [%s]\n', name, num2str(peakPerChannel, '%.4g '));
fprintf('%s DC magnitude : [%s]\n\n', name, num2str(dcPerChannel, '%.4g '));
end

function print_type1_result(result)
fprintf('\n--- Synchronization and PBCH ---\n');
fprintf('PSS best/expected      : %d / %d\n', ...
    result.bestNID2, result.expectedNID2);
fprintf('CFO / CP corr          : %+8.2f Hz / %.4f\n', ...
    result.frequencyOffsetHz, result.cpCorrelation);
fprintf('SSS metric             : %.4f\n', result.sssMetric);
fprintf('PBCH CRC OK / MIB match: %d / %d\n', ...
    ~result.pbchCRCError, result.mibMatches);
fprintf('Spatial decode enabled : %d, nRx=%d, nLayer=%d\n', ...
    result.spatialDecodeEnabled, result.nRxChannels, result.nLayers);

fprintf('\n--- BER/EVM against known TX reference bits ---\n');
fprintf('coding mode            : %s\n', result.channelCoding);
fprintf('raw BER per layer      : [%s]\n', ...
    num2str(mean(result.rawBER, 1, 'omitnan'), '%.4g '));
fprintf('decoded BER per layer  : [%s]\n', ...
    num2str(mean(result.decodedBER, 1, 'omitnan'), '%.4g '));
fprintf('decoded errors/layer   : [%s]\n', ...
    num2str(sum(result.decodedBitErrors, 1, 'omitnan'), '%.0f '));
fprintf('null SNR per RX dB     : [%s]\n', ...
    num2str(result.snrNullDb, '%.2f '));
fprintf('DM-RS SNR per RX dB    : [%s]\n', ...
    num2str(result.snrDmrsDb, '%.2f '));
fprintf('median EVM per layer %% : [%s]\n', ...
    num2str(median(result.evmRMSPercent, 1, 'omitnan'), '%.2f '));
fprintf('cond(H) med/p95/max    : [%s]\n\n', ...
    num2str(result.conditionStats, '%.2f '));
print_h_matrices(result);
end

function print_h_matrices(result)
fprintf('--- Representative channel matrix H_ij ---\n');
fprintf('Convention: H_ij = channel from TX/layer i to RX antenna j.\n');
fprintf('Rows: TX1...TX%d / Layer1...Layer%d; columns: RX1...RX%d.\n', ...
    result.nLayers, result.nLayers, result.nRxChannels);
fprintf('H_txrx_mean_complex:\n');
print_complex_matrix(result.channelMatrixTxRxMean);
fprintf('|H_txrx|_mean over data REs and slots:\n');
disp(result.channelMatrixTxRxMagnitudeMean);
fprintf('\n');
end

function print_complex_matrix(H)
for r = 1:size(H, 1)
    for c = 1:size(H, 2)
        fprintf('%+.4f%+.4fj  ', real(H(r,c)), imag(H(r,c)));
    end
    fprintf('\n');
end
end

function plot_type1_result(result, figureName)
maxPoints = 3000;
colors = lines(result.nLayers);

figure('Name', figureName, 'NumberTitle', 'off', ...
    'Color', 'w', 'Position', [80 80 1150 520]);
layout = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

before = normalize_symbols(result.preCompData(:));
before = decimate_symbols(before, maxPoints);
nexttile(layout);
scatter(real(before), imag(before), 8, [0.25 0.25 0.25], ...
    'filled', 'MarkerFaceAlpha', 0.25);
format_constellation_axis('Before compensation: selected RX data RE mixture');

nexttile(layout);
hold on;
if result.spatialDecodeEnabled
    for layer = 1:result.nLayers
        after = normalize_symbols(result.postCompData(:, :, layer));
        after = decimate_symbols(after(:), maxPoints);
        scatter(real(after), imag(after), 8, colors(layer,:), ...
            'filled', 'MarkerFaceAlpha', 0.25, ...
            'DisplayName', sprintf('Layer %d', layer));
    end
end
ideal = exp(1j * (pi/4 + (0:3)*pi/2));
plot(real(ideal), imag(ideal), 'kx', 'MarkerSize', 10, 'LineWidth', 1.5, ...
    'DisplayName', 'ideal QPSK');
legend('Location', 'best');
format_constellation_axis('After Type-1 DM-RS channel compensation + MIMO separation');
end

function y = normalize_symbols(x)
y = x(:);
y = y(isfinite(real(y)) & isfinite(imag(y)));
scale = sqrt(mean(abs(y).^2));
if scale > 0, y = y / scale; end
end

function y = decimate_symbols(x, maxPoints)
y = x(:);
if numel(y) > maxPoints
    index = round(linspace(1, numel(y), maxPoints));
    y = y(index);
end
end

function format_constellation_axis(titleText)
grid on; box on; axis equal;
xlim([-2 2]); ylim([-2 2]);
xlabel('In-phase'); ylabel('Quadrature');
title(titleText);
end
