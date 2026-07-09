%% Read and briefly analyze the startup 2 ms IQ dump.
% The RX live program writes two binary files into ./data:
%   *_raw122_csingle_iq4.bin     : 122.88 MS/s physical 4-RX IQ
%   *_virtual30_csingle_iq4.bin  : 30.72 MS/s virtual 4-RX IQ after switch
%
% Binary format:
%   complex single, MATLAB column-major, interleaved I/Q:
%   I1,Q1,I2,Q2,... for x(:), then reshape back to [nSamples x nChannels].

clear; close all; clc;

thisDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(thisDir, 'data');
nChannels = 4;
rawSampleRate = 122.88e6;
virtualSampleRate = 30.72e6;

rawFile = newest_file(dataDir, '*_raw122_csingle_iq4.bin');
virtualFile = newest_file(dataDir, '*_virtual30_csingle_iq4.bin');

raw122 = read_complex_single_iq(rawFile, nChannels);
virtual30 = read_complex_single_iq(virtualFile, nChannels);

fprintf('\nRead startup IQ dump\n');
fprintf('  raw122    : %s\n', rawFile);
fprintf('  virtual30 : %s\n', virtualFile);
fprintf('  raw122    : %d samples x %d channels, %.3f ms\n', ...
    size(raw122,1), size(raw122,2), 1e3 * size(raw122,1) / rawSampleRate);
fprintf('  virtual30 : %d samples x %d channels, %.3f ms\n\n', ...
    size(virtual30,1), size(virtual30,2), ...
    1e3 * size(virtual30,1) / virtualSampleRate);

print_basic_stats('raw122', raw122);
print_basic_stats('virtual30', virtual30);

% Plot a short time-domain magnitude view and a simple spectrum estimate.
figure('Name', 'Initial 2 ms IQ quick analysis', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [80 80 1200 720]);
layout = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile(layout);
plot((0:size(raw122,1)-1) / rawSampleRate * 1e3, abs(raw122));
grid on; box on;
xlabel('Time (ms)'); ylabel('|IQ|');
title('raw122 magnitude, 122.88 MS/s');
legend(compose('RX%d', 1:nChannels), 'Location', 'best');

nexttile(layout);
plot((0:size(virtual30,1)-1) / virtualSampleRate * 1e3, abs(virtual30));
grid on; box on;
xlabel('Time (ms)'); ylabel('|IQ|');
title('virtual30 magnitude, 30.72 MS/s');
legend(compose('VRX%d', 1:nChannels), 'Location', 'best');

nexttile(layout);
[fRawMHz, psdRawDb] = quick_spectrum(raw122, rawSampleRate, 4096);
plot(fRawMHz, psdRawDb);
grid on; box on;
xlabel('Frequency (MHz)'); ylabel('PSD (dBFS/Hz)');
title('raw122 quick spectrum');

nexttile(layout);
[fVirtualMHz, psdVirtualDb] = quick_spectrum(virtual30, virtualSampleRate, 4096);
plot(fVirtualMHz, psdVirtualDb);
grid on; box on;
xlabel('Frequency (MHz)'); ylabel('PSD (dBFS/Hz)');
title('virtual30 quick spectrum');

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

function print_basic_stats(name, x)
rmsPerChannel = sqrt(mean(abs(x).^2, 1));
peakPerChannel = max(abs(x), [], 1);
dcPerChannel = mean(x, 1);
fprintf('%s stats:\n', name);
fprintf('  RMS  = [%s]\n', num2str(rmsPerChannel, '%.4g '));
fprintf('  Peak = [%s]\n', num2str(peakPerChannel, '%.4g '));
fprintf('  DC magnitude = [%s]\n\n', num2str(abs(dcPerChannel), '%.4g '));
end

function [frequencyMHz, psdDb] = quick_spectrum(x, sampleRate, nfft)
nfft = min(nfft, size(x, 1));
x = double(x(end-nfft+1:end, :));
x = x - mean(x, 1);
n = (0:nfft-1).';
window = 0.5 - 0.5*cos(2*pi*n/nfft);
transform = fftshift(fft(x .* window, nfft, 1), 1);
psd = abs(transform).^2 / (sampleRate * sum(window.^2));
psdDb = 10*log10(psd + realmin);
frequencyMHz = (-nfft/2:nfft/2-1).' * sampleRate / nfft / 1e6;
end
