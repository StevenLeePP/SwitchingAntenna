function type1_tx()
%TYPE1_TX YunSDR Type-A four-port cyclic transmitter.
%
% Function-scope cleanup: onCleanup triggers on normal return, Ctrl+C,
% MATLAB Stop, or error, always stopping cyclic TX and closing the device.
%
% Cyclic TX mode: the 307200x4 frame is written once to FPGA/DMA buffer
% and replayed indefinitely. MATLAB only monitors underflow events.

close all; clc;

sourceDir = fileparts(mfilename('fullpath'));
sdkDir = fileparts(sourceDir);
addpath(sdkDir);
package = type1_load_package();
cfg = package.cfg;
durationOverride = str2double(getenv('TYPE1_TX_DURATION_SEC'));
if isfinite(durationOverride) && durationOverride > 0
    cfg.txDurationSec = durationOverride;
end

% Convert complex IQ waveform to interleaved int16 buffer for SDK
[txBuffer, frameSamples] = gen_txbuf(double(package.txWaveform));

% ── Load YunSDR shared library ──
if ~libisloaded('libyunsdr_ss')
    loadlibrary(fullfile(sdkDir, 'libyunsdr_ss.so'), ...
        fullfile(sdkDir, 'yunsdr_api_ss.h'), ...
        'alias', 'libyunsdr_ss');
end
deviceString = libpointer('cstring', cfg.deviceString);
device = calllib('libyunsdr_ss', 'yunsdr_open_device', deviceString);
if isNull(device)
    error('type1:OpenTX', 'Could not open YunSDR TX device.');
end
cleanup = onCleanup(@() close_tx(device));  % guaranteed cleanup on exit

% ── Reset cyclic, configure 2 RF chips (each drives 2 TX channels) ──
check_ret(calllib('libyunsdr_ss', 'yunsdr_tx_cyclic_enable', ...
    device, uint8(0), uint8(0)), 'reset cyclic TX');
for rf = 0:(cfg.nTxChannels / 2 - 1)
    check_ret(calllib('libyunsdr_ss', 'yunsdr_set_tx_sampling_freq', ...
        device, uint8(rf), uint32(cfg.txSampleRate)), 'set TX sample rate');
    check_ret(calllib('libyunsdr_ss', 'yunsdr_set_tx_lo_freq', ...
        device, uint8(rf), uint64(cfg.centerFrequencyHz)), 'set TX LO');
    check_ret(calllib('libyunsdr_ss', 'yunsdr_set_tx1_attenuation', ...
        device, uint8(rf), uint32(cfg.txAttenuationMdB)), 'set TX1 attenuation');
    check_ret(calllib('libyunsdr_ss', 'yunsdr_set_tx2_attenuation', ...
        device, uint8(rf), uint32(cfg.txAttenuationMdB)), 'set TX2 attenuation');
end
pause(1);  % wait for RF PLLs to lock

% ── Hardware timestamp for deterministic frame scheduling ──
check_ret(calllib('libyunsdr_ss', 'yunsdr_enable_timestamp', ...
    device, uint8(0), uint8(0)), 'disable timestamp');
check_ret(calllib('libyunsdr_ss', 'yunsdr_enable_timestamp', ...
    device, uint8(0), uint8(1)), 'enable timestamp');
pause(0.2);

timestamp = libpointer('uint64Ptr', 0);
check_ret(calllib('libyunsdr_ss', 'yunsdr_read_timestamp', ...
    device, uint8(0), timestamp), 'read timestamp');
startTimestamp = timestamp.Value + ...
    uint64(round(cfg.txStartLeadSec * cfg.txSampleRate));  % ~50 ms lead

% ── Cyclic TX: arm -> write one frame -> start ──
% enable=1: arm (prepare buffer), enable=3: start playback
check_ret(calllib('libyunsdr_ss', 'yunsdr_tx_cyclic_enable', ...
    device, uint8(0), uint8(1)), 'arm cyclic TX');
nwrite = calllib('libyunsdr_ss', ...
    'yunsdr_write_samples_multiport_Matlab', ...
    device, txBuffer, uint32(frameSamples), ...
    uint32(cfg.txChannelMask), startTimestamp, uint32(0));
if nwrite < 0
    error('type1:TXWrite', 'Cyclic TX write failed with %d.', nwrite);
end
check_ret(calllib('libyunsdr_ss', 'yunsdr_tx_cyclic_enable', ...
    device, uint8(0), uint8(3)), 'start cyclic TX');

fprintf('\n========== YunSDR Type-A 4-port TX ==========\n');
fprintf('Reference            : %s\n', cfg.referenceFile);
fprintf('LO / sample rate     : %.3f GHz / %.2f MS/s\n', ...
    cfg.centerFrequencyHz / 1e9, cfg.txSampleRate / 1e6);
fprintf('Frame                : %d samples / 10 ms\n', frameSamples);
fprintf('Slot 0               : standard SSB/PBCH from TX1\n');
fprintf('Payload slots         : [%s] (%s mode), Type-A DM-RS l=2\n', ...
    num2str(cfg.dataSlots), cfg.payloadSlotMode);
fprintf('Other slots           : zero (no DM-RS and no payload)\n');
fprintf('DM-RS ports          : 1000, 1001, 1002, 1003\n');
fprintf('Data                 : four telemetry QPSK sources\n');
fprintf('Channel coding       : %s\n', package.channelCoding);
fprintf('Source example       : %s\n', ...
    package.payloadMetadata(1, 1).message);
if isfinite(cfg.txDurationSec)
    fprintf('Run duration          : %.1f s\n\n', cfg.txDurationSec);
else
    fprintf('Run duration          : infinite (Ctrl+C invokes cleanup)\n\n');
end

% ── Monitor loop: read underflow and TX count events ──
startTimer = tic;
while isinf(cfg.txDurationSec) || toc(startTimer) < cfg.txDurationSec
    pause(cfg.txStatusPeriodSec);
    [underflow, count] = query_tx_events(device, cfg.nTxChannels);
    fprintf('type1 TX t=%7.3f s underflow=[%s] TX_COUNT=[%s]\n', ...
        toc(startTimer), num2str(underflow), num2str(count));
end
clear cleanup;  % triggers onCleanup -> close_tx
end

%% Local functions
function [underflow, count] = query_tx_events(device, nChannels)
% Read underflow event (id=31) and TX count event (id=33) per channel.
underflow = zeros(1, nChannels, 'uint32');
count = zeros(1, nChannels, 'uint32');
pointer = libpointer('uint32Ptr', 0);
for channel = 1:nChannels
    ret = calllib('libyunsdr_ss', 'yunsdr_get_channel_event', ...
        device, int32(31), uint8(channel), pointer);
    if ret >= 0, underflow(channel) = pointer.Value; end
    ret = calllib('libyunsdr_ss', 'yunsdr_get_channel_event', ...
        device, int32(33), uint8(channel), pointer);
    if ret >= 0, count(channel) = pointer.Value; end
end
end

function check_ret(ret, operation)
if ret < 0
    error('type1:YunSDR', '%s failed with return code %d.', operation, ret);
end
end

function close_tx(device)
% Graceful shutdown: disable cyclic TX, then close device handle.
disableRet = NaN;
try
    disableRet = calllib('libyunsdr_ss', 'yunsdr_tx_cyclic_enable', ...
        device, uint8(0), uint8(0));
catch
end
try
    calllib('libyunsdr_ss', 'yunsdr_close_device', device);
catch
end
fprintf(['Type-A TX cleanup: cyclic disable ret=%g; ' ...
    'YunSDR device closed.\n'], disableRet);
end
