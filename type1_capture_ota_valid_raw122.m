function capture = type1_capture_ota_valid_raw122(options)
%TYPE1_CAPTURE_OTA_VALID_RAW122 Capture a post-settle OTA IQ for pairing.
%   Opens the existing four-RX stream, waits for TX/RX settling, and examines
%   successive *raw122* snapshots through the ideal digital switch.  Only a
%   snapshot with correct PSS identity, PBCH CRC/MIB, and normal ideal EVM is
%   persisted.  This avoids using RX-startup IQ as an OTA model anchor.
%
%   Optional name-value fields:
%     options.rxGain         default type1_config().rxGain
%     options.fileTag        optional filesystem-safe campaign label
%
%   Environment controls:
%     TYPE1_OTA_CAPTURE_SETTLE_SEC   default 5
%     TYPE1_OTA_CAPTURE_TIMEOUT_SEC  default 45
%     TYPE1_OTA_CAPTURE_BLOCKS       default 20 (ms, must be >= 11)
%     TYPE1_OTA_CAPTURE_MAX_EVM_PCT  default 20

arguments
    options.rxGain (1,1) double {mustBeFinite} = type1_config().rxGain
    options.fileTag (1,1) string = ""
end

assert(options.rxGain >= 0 && options.rxGain <= 73, 'type1:OTARxGain', ...
    'RX gain must be in the YunSDR-supported 0--73 dB range.');
assert(strlength(options.fileTag)==0 || ...
    ~isempty(regexp(char(options.fileTag),'^[A-Za-z0-9_-]+$','once')), ...
    'type1:OTAFileTag','fileTag must contain only letters, digits, _ or -.');
package = type1_load_package();
cfg = package.cfg;
cfg.rxGain = options.rxGain;
settleSec = env_nonnegative('TYPE1_OTA_CAPTURE_SETTLE_SEC', 5);
timeoutSec = env_positive('TYPE1_OTA_CAPTURE_TIMEOUT_SEC', 45);
captureBlocks = round(env_positive('TYPE1_OTA_CAPTURE_BLOCKS', 20));
maxEVMPercent = env_positive('TYPE1_OTA_CAPTURE_MAX_EVM_PCT', 20);
assert(captureBlocks >= 11, 'type1:OTACaptureWindow', ...
    'TYPE1_OTA_CAPTURE_BLOCKS must provide at least 10.5 ms of raw IQ.');

if exist('type1_yunsdr_rx_mex', 'file') ~= 3
    type1_build_rx_mex();
end
blockSamples = round(cfg.rxSampleRate * 1e-3);
ringBlocks = max(cfg.liveRingBlocks, captureBlocks + 4);
type1_yunsdr_rx_mex('open', cfg.deviceString, cfg.rxSampleRate, ...
    cfg.centerFrequencyHz, cfg.rxGain);
cleanup = onCleanup(@close_radio);
type1_yunsdr_rx_mex('switchphase', cfg.switchPhaseOffset);
type1_yunsdr_rx_mex('start', blockSamples, ringBlocks);

fprintf('\n========== OTA post-settle raw122 capture ==========\n');
fprintf(['RX gain %.1f dB; settling %.1f s; then inspect %d ms snapshots ' ...
    'for up to %.1f s.\n'],cfg.rxGain,settleSec,captureBlocks,timeoutSec);
pause(settleSec);
deadline = tic;
attempt = 0;
while toc(deadline) < timeoutSec
    status = type1_yunsdr_rx_mex('status');
    assert(status(3) ~= 0, 'type1:OTACaptureRX', ...
        'RX thread stopped with return value %d.', status(4));
    if status(2) < captureBlocks
        pause(0.01);
        continue;
    end
    attempt = attempt + 1;
    [raw122, timestamps, sequence] = type1_yunsdr_rx_mex('snapshot', captureBlocks);
    [~, virtual30] = type1_digital_switch(raw122);
    try
        result = type1_analyze(virtual30, package);
        pssOK = result.bestNID2 == result.expectedNID2;
        pbchOK = ~result.pbchCRCError && result.mibMatches;
        evm = mean(result.evmRMSPercent, 'all', 'omitnan');
        rawBER = mean(result.rawBER, 'all', 'omitnan');
        valid = pssOK && pbchOK && isfinite(evm) && evm <= maxEVMPercent;
        fprintf(['attempt %d: PSS %d/%d, PBCH=%d, EVM=%.3f%%, raw BER=%.3g' ...
            ', valid=%d\n'], attempt, result.bestNID2, result.expectedNID2, ...
            pbchOK, evm, rawBER, valid);
        if valid
            capture = save_capture(raw122, timestamps, sequence, result, cfg, ...
                settleSec, maxEVMPercent, attempt, options.fileTag);
            fprintf('Accepted OTA raw122: %s\n', capture.raw122File);
            return;
        end
    catch err
        fprintf(2, 'attempt %d analysis failed: %s\n', attempt, err.message);
    end
    pause(0.05);
end
error('type1:OTACaptureQuality', ...
    'No PSS/PBCH/EVM-valid OTA raw122 was observed within %.1f s.', timeoutSec);
end

function capture = save_capture(raw122, timestamps, sequence, result, cfg, settleSec, maxEVMPercent, attempt, fileTag)
if ~exist(cfg.dataRoot, 'dir'), mkdir(cfg.dataRoot); end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
if strlength(fileTag)>0,tag=['_' char(fileTag)];else,tag='';end
base = sprintf('type1_valid_ota_iq_%s_gain%g%s_seq%u', ...
    stamp,cfg.rxGain,tag,sequence);
rawFile = fullfile(cfg.dataRoot, [base '_raw122_csingle_iq4.bin']);
metaFile = fullfile(cfg.dataRoot, [base '_meta.mat']);
write_complex_single_iq(rawFile, raw122);
capture = struct('raw122File', rawFile, 'metaFile', metaFile, ...
    'createdAt', datetime('now'), 'rawSampleRateHz', cfg.rxSampleRate, ...
    'durationSec', size(raw122, 1) / cfg.rxSampleRate, 'timestamps', timestamps, ...
    'sequence', sequence, 'attempt', attempt, 'settleSec', settleSec, ...
    'rxGainDb',cfg.rxGain,'fileTag',fileTag, ...
    'maxIdealEVMPercent', maxEVMPercent, 'idealResult', result);
save(metaFile, 'capture', '-v7.3');
end

function write_complex_single_iq(file, x)
fid = fopen(file, 'wb');
assert(fid >= 0, 'type1:OTACaptureWrite', 'Could not open %s.', file);
cleanup = onCleanup(@() fclose(fid));
x = single(x);
packed = zeros(2 * numel(x), 1, 'single');
packed(1:2:end) = real(x(:));
packed(2:2:end) = imag(x(:));
assert(fwrite(fid, packed, 'single') == numel(packed), ...
    'type1:OTACaptureWrite', 'Short write to %s.', file);
end

function close_radio()
try
    type1_yunsdr_rx_mex('stop');
catch
end
try
    type1_yunsdr_rx_mex('close');
catch
end
end

function value = env_positive(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value <= 0, value = defaultValue; end
end

function value = env_nonnegative(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value < 0, value = defaultValue; end
end
