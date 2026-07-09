function type1_rx_live()
%TYPE1_RX_LIVE YunSDR Type-A live receiver with selectable RX channels.
%
% Architecture:
%   C MEX background thread:  continuous 122.88 MS/s 4-ch ring buffer (64 ms)
%   MATLAB foreground loop:   periodic snapshot -> digital switch ->
%                             type1_analyze_fast (one slot) -> live plots
%
% The function scope ensures proper cleanup of the radio device on
% normal exit, Ctrl+C, error, or MATLAB Stop.

close all; clc;

package = type1_load_package();
cfg = apply_runtime_rx_config(package.cfg);
package.cfg = cfg;
durationSec = env_number('TYPE1_LIVE_DURATION_SEC', cfg.liveDurationSec);
updatePeriodSec = env_number('TYPE1_LIVE_UPDATE_SEC', 0.10);
computeThreads = round(env_number('TYPE1_LIVE_COMPUTE_THREADS', ...
    cfg.liveComputeThreads));
visible = getenv('TYPE1_LIVE_VISIBLE');
if isempty(visible), visible = 'on'; end

% Limit MATLAB worker threads to avoid contention with MEX RX thread
previousComputeThreads = maxNumCompThreads;
maxNumCompThreads(computeThreads);
computeCleanup = onCleanup(@() maxNumCompThreads(previousComputeThreads));

% ── Ring buffer parameters ──
blockDurationSec = 1e-3;                                  % 1 ms per block
blockSamples = round(cfg.rxSampleRate * blockDurationSec); % 122880 samples
analysisBlocks = cfg.liveAnalysisBlocks;                  % 20 ms snapshot
initialIQBlocks = max(1, round(cfg.initialIQCaptureSec / blockDurationSec));
ringBlocks = cfg.liveRingBlocks;                          % 64 ms ring
fastDataSlot = cfg.dataSlots(ceil(numel(cfg.dataSlots) / 2));  % slot 10
fastSpectrumNfft = 2048;
fastConstellationPoints = 500;
signalPresenceThresholdDb = 8;  % in-band vs guard-band PSD difference

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

% Create live figure (spectrum + two constellation panels)
[figureHandle, spectrumLines, beforeScatter, afterScatter] = ...
    create_live_figure(visible, cfg);

fprintf('\n========== YunSDR Type-A live RX ==========\n');
fprintf('Reference              : %s\n', cfg.referenceFile);
fprintf('Raw / virtual rates    : %.2f / %.2f MS/s\n', ...
    cfg.rxSampleRate / 1e6, cfg.txSampleRate / 1e6);
fprintf('Hardware / active RX   : %d captured / %d used, select=[%s]\n', ...
    cfg.nHardwareRxChannels, cfg.nRxChannels, num2str(cfg.rxChannelSelect));
fprintf('TX layers / DM-RS ports: %d / [%s]\n', ...
    cfg.nLayers, num2str(cfg.dmrsPortSet));
if cfg.nRxChannels < cfg.nLayers
    fprintf(2, ['WARNING: active RX channels (%d) < TX layers (%d). ' ...
        'The receiver will monitor spectrum/PSS/SSS/PBCH only; ' ...
        'spatial data RZF, BER, and EVM are disabled.\n'], ...
        cfg.nRxChannels, cfg.nLayers);
end
fprintf('Background block/ring  : 1 ms / %d ms\n', ringBlocks);
fprintf('Analysis window/update : %d ms / %.2f s\n', ...
    analysisBlocks, updatePeriodSec);
fprintf('Initial IQ dump        : %.1f ms raw122 + virtual30 into %s\n', ...
    1e3 * initialIQBlocks * blockDurationSec, cfg.dataRoot);
fprintf('Fast data slot         : %d (one of 19 slots/update)\n', fastDataSlot);
fprintf('Constellation points   : %d per layer\n', fastConstellationPoints);
fprintf('MATLAB compute threads : %d\n', computeThreads);
fprintf('Reported HW buf depth  : %u vendor units\n\n', hardwareDepth);

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

%% ═══ Main live loop ═══
runTimer = tic;
lastUpdate = -inf;
lastSequence = [];
lastTimestamp = [];
totalTimestampGap = 0;
updates = 0;
analysisTimes = [];
snapshotTimes = [];
lastResult = struct;

while toc(runTimer) < durationSec && isgraphics(figureHandle)
    % Wait for next update interval
    if toc(runTimer) - lastUpdate < updatePeriodSec
        drawnow limitrate nocallbacks;
        pause(0.01);
        continue;
    end

    % ── Snapshot from ring buffer: N*122880 x 4 complex single ──
    snapshotTimer = tic;
    [raw122, timestamps, sequence] = ...
        type1_yunsdr_rx_mex('snapshot', analysisBlocks);
    snapshotMs = 1e3 * toc(snapshotTimer);
    if size(raw122, 1) < analysisBlocks * blockSamples
        pause(0.01);
        continue;
    end

    % ── Timestamp continuity check ──
    newestTimestamp = timestamps(end);
    if ~isempty(lastSequence)
        expectedAdvance = uint64(double(sequence - lastSequence) * blockSamples);
        actualAdvance = newestTimestamp - lastTimestamp;
        timestampGap = double(actualAdvance) - double(expectedAdvance);
        if timestampGap ~= 0
            totalTimestampGap = totalTimestampGap + max(timestampGap, 0);
            fprintf(2, ...
                'RX timestamp discontinuity: %+d raw samples at seq %u\n', ...
                timestampGap, sequence);
        end
    end
    lastSequence = sequence;
    lastTimestamp = newestTimestamp;

    % ── Cheap spectrum check: is there any signal? ──
    % Uses the last 1 ms of raw data for a fast Hann-windowed periodogram.
    [frequencyMHz, spectrumDb] = live_spectrum( ...
        raw122(end-blockSamples+1:end, cfg.rxChannelSelect), ...
        cfg.rxSampleRate, fastSpectrumNfft);
    update_spectrum(spectrumLines, frequencyMHz, spectrumDb);
    presenceDb = signal_presence_db(frequencyMHz, spectrumDb);
    if presenceDb < signalPresenceThresholdDb
        clear_constellations(beforeScatter, afterScatter);
        updates = updates + 1;
        fprintf(['type1 t=%6.2f s seq=%7u spectrum=%5.1f ms ' ...
            'presence=%+.1f dB: NO SIGNAL, constellation cleared\n'], ...
            toc(runTimer), sequence, snapshotMs, presenceDb);
        drawnow;
        lastUpdate = toc(runTimer);
        continue;
    end
    drawnow limitrate;

    % ── Digital switch + fast one-slot analysis ──
    [~, virtualRF] = type1_digital_switch(raw122);
    virtualRF = virtualRF(:, cfg.rxChannelSelect);
    try
        result = type1_analyze_fast(virtualRF, package, fastDataSlot);
    catch ME
        fprintf(2, 'Type-A analysis skipped: %s\n', ME.message);
        lastUpdate = toc(runTimer);
        continue;
    end
    lastResult = result;

    % ── Recheck: TX might have been turned off during analysis ──
    [freshRaw, ~, ~] = type1_yunsdr_rx_mex('snapshot', 1);
    [freshFrequencyMHz, freshSpectrumDb] = live_spectrum( ...
        freshRaw(:, cfg.rxChannelSelect), cfg.rxSampleRate, fastSpectrumNfft);
    update_spectrum(spectrumLines, freshFrequencyMHz, freshSpectrumDb);
    freshPresenceDb = signal_presence_db(freshFrequencyMHz, freshSpectrumDb);
    if freshPresenceDb < signalPresenceThresholdDb
        clear_constellations(beforeScatter, afterScatter);
        fprintf(['type1 t=%6.2f s TX disappeared during analysis; ' ...
            'stale constellation suppressed\n'], toc(runTimer));
        drawnow;
        lastUpdate = toc(runTimer);
        continue;
    end

    % ── Update constellation displays ──
    before = normalize_symbols(result.preCompData(:));
    before = decimate_symbols(before, fastConstellationPoints);
    show_constellations(beforeScatter);
    set(beforeScatter, 'XData', real(before), 'YData', imag(before));
    if result.spatialDecodeEnabled
        for layer = 1:cfg.nLayers
            after = normalize_symbols(result.postCompData(:, layer));
            after = decimate_symbols(after(:), fastConstellationPoints);
            set(afterScatter(layer), 'XData', real(after), 'YData', imag(after));
        end
    else
        clear_after_constellation(afterScatter);
    end

    % ── Terminal printout ──
    updates = updates + 1;
    analysisTimes(end+1) = result.elapsedMs; %#ok<SAGROW>
    snapshotTimes(end+1) = snapshotMs; %#ok<SAGROW>
    codedBER = result.codedBER;
    infoBER = result.infoBER;
    infoErrors = result.infoBitErrors;
    absolutePSSTimestamp = timestamps(1) + uint64(4 * result.timingOffset);

    fprintf(['type1 t=%6.2f s seq=%7u snapshot=%5.1f ms ' ...
        'analysis=%6.1f ms presence=%+.1f dB slot=%d\n' ...
        '  PSS_peak=%g peak/median=%.1f dB raw_ts=%u\n' ...
        '  CFO=%+.1f Hz CP_corr=%.3f SSS_metric=%.4f ' ...
        'PBCH_CRC_OK=%d MIB_match=%d\n' ...
        '  coded_BER=[%s] info_BER=[%s] info_errors=[%s]\n' ...
        '  EVM_pct=[%s] cond(H) med/p95/max=[%s] spatial_decode=%d\n'], ...
        toc(runTimer), sequence, snapshotMs, result.elapsedMs, ...
        freshPresenceDb, result.dataSlot, result.pssPeak, ...
        result.pssPeakToMedianDb, absolutePSSTimestamp, ...
        result.frequencyOffsetHz, result.cpCorrelation, ...
        result.sssMetric, ~result.pbchCRCError, result.mibMatches, ...
        num2str(codedBER, '%.3g '), ...
        num2str(infoBER, '%.3g '), ...
        num2str(infoErrors, '%d '), ...
        num2str(result.evmRMSPercent, '%.1f '), ...
        num2str(result.conditionStats, '%.1f '), ...
        result.spatialDecodeEnabled);
    drawnow;
    lastUpdate = toc(runTimer);
end

%% ═══ Shutdown and save ═══
type1_yunsdr_rx_mex('stop');
events = type1_yunsdr_rx_mex('events');

imageFile = '';
figureFile = '';
if isgraphics(figureHandle)
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
summary.totalTimestampGapSamples = totalTimestampGap;
summary.events = events;
summary.lastResult = lastResult;
summary.imageFile = imageFile;
summary.figureFile = figureFile;
save(fullfile(outputDir, 'type1_live_results.mat'), 'summary', '-v7.3');

fprintf('\nType-A live RX stopped.\n');
fprintf('Updates / median analysis : %d / %.1f ms\n', ...
    updates, median(analysisTimes));
fprintf('Timestamp gap total        : %.0f raw samples\n', totalTimestampGap);
fprintf('RX overflow/count/timeout  : [%s] / [%s] / [%s]\n', ...
    num2str(events(:,1).'), num2str(events(:,2).'), num2str(events(:,3).'));
fprintf('Results                    : %s\n', outputDir);

clear radioCleanup;
clear computeCleanup;
end

%% ═══ Local helper functions ═══

function value = env_number(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value <= 0, value = defaultValue; end
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
