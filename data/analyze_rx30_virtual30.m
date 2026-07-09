%% Analyze saved 30.72 MS/s virtual-RX IQ directly.
%
% Purpose:
%   Read the newest *_virtual30_csingle_iq4.bin file, then run the complete
%   Type-1 receiver chain:
%     synchronization -> channel estimation -> channel compensation/RZF
%     -> MIMO layer separation -> BER against the known reference bits.
%
% Run:
%   cd('/home/bupt/tools/matlab_test/nr4x4_type1/data')
%   analyze_rx30_virtual30

clear; close all; clc;

dataDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(dataDir);
addpath(projectDir);

nChannels = 4;
sampleRate = 30.72e6;
iqFile = newest_file(dataDir, '*_virtual30_csingle_iq4.bin');

fprintf('\n========== Analyze virtual30/rx30 IQ ==========\n');
fprintf('IQ file : %s\n', iqFile);

rx30 = read_complex_single_iq(iqFile, nChannels);
fprintf('IQ size : %d samples x %d channels, %.3f ms @ %.2f MS/s\n', ...
    size(rx30, 1), size(rx30, 2), ...
    1e3 * size(rx30, 1) / sampleRate, sampleRate / 1e6);
print_iq_stats('rx30', rx30);

package = type1_load_package();
result = type1_analyze(rx30, package);

print_type1_result(result);
plot_type1_result(result, 'virtual30 direct analysis');

save(fullfile(dataDir, 'analyze_rx30_virtual30_result.mat'), ...
    'iqFile', 'sampleRate', 'result', '-v7.3');
fprintf('Saved result: %s\n', ...
    fullfile(dataDir, 'analyze_rx30_virtual30_result.mat'));

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
fprintf('coded BER per layer    : [%s]\n', ...
    num2str(mean(result.codedBER, 1, 'omitnan'), '%.4g '));
fprintf('info BER per layer     : [%s]\n', ...
    num2str(mean(result.infoBER, 1, 'omitnan'), '%.4g '));
fprintf('info errors per layer  : [%s]\n', ...
    num2str(sum(result.infoBitErrors, 1, 'omitnan'), '%.0f '));
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
