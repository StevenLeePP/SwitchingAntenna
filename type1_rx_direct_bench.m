function type1_rx_direct_bench()
%TYPE1_RX_DIRECT_BENCH Native-ring direct-consumer performance gate.
% This intentionally does not report BER.  It proves whether C-side switch
% extraction plus the 154 required OFDM FFTs can sustain the FIFO before
% DM-RS/RZF/BER is attached to the same persistent loop.

close all; clc;
cfg = type1_config();
durationSec = env_positive('TYPE1_DIRECT_BENCH_DURATION_SEC', 10);
ringBlocks = round(env_positive('TYPE1_FIFO_RING_BLOCKS', 2048));
maxFrames = round(env_positive('TYPE1_DIRECT_BENCH_MAX_FRAMES', 1));
blockSamples = round(cfg.rxSampleRate * 1e-3);

type1_build_rx_mex();
fprintf('\n========== Type-A direct native-ring benchmark ==========\n');
fprintf('Duration / ring / max poll: %.1f s / %d ms / %d frames\n', ...
    durationSec, ringBlocks, maxFrames);
fprintf('Data path: ring -> four-phase switch -> 154 FFT symbols -> C statistics\n');

type1_yunsdr_rx_mex('open', cfg.deviceString, cfg.rxSampleRate, ...
    cfg.centerFrequencyHz, cfg.rxGain);
cleanup = onCleanup(@close_radio); %#ok<NASGU>
type1_yunsdr_rx_mex('start', blockSamples, ringBlocks);
wait_for_blocks(20);
type1_yunsdr_rx_mex('directbenchstart');
eventsStart = type1_yunsdr_rx_mex('events');
timer = tic;
lastPrint = -inf;
pollMs = zeros(0,1);
statusHistory = zeros(0,8);

while toc(timer) < durationSec
    status = type1_yunsdr_rx_mex('directbenchstatus');
    if status(2) < 10
        pause(0.001);
        continue;
    end
    t = tic;
    type1_yunsdr_rx_mex('directbenchpoll', maxFrames);
    pollMs(end+1,1) = 1e3*toc(t); %#ok<AGROW>
    status = type1_yunsdr_rx_mex('directbenchstatus');
    statusHistory(end+1,:) = status; %#ok<AGROW>
    if status(3) ~= 0
        fprintf(2, 'DIRECT FIFO DROP: new blocks dropped=%d\n', status(3));
        break;
    end
    if toc(timer) - lastPrint >= 0.5
        fprintf(['direct t=%6.2f frames=%d pending=%4d ms dropNew=%d high=%d ' ...
            'extract=%.3fms fft=%.3fms total=%.3fms poll=%.3fms\n'], ...
            toc(timer), status(1), status(2), status(3), status(4), ...
            status(5), status(6), status(7), pollMs(end));
        lastPrint = toc(timer);
    end
end

status = type1_yunsdr_rx_mex('directbenchstatus');
eventsEnd = type1_yunsdr_rx_mex('events');
summary = struct('cfg',cfg,'durationSec',toc(timer),'status',status, ...
    'pollMs',pollMs,'statusHistory',statusHistory, ...
    'eventsStart',eventsStart,'eventsEnd',eventsEnd, ...
    'eventDelta',eventsEnd-eventsStart);
outputDir = fullfile(cfg.outputRoot, ['type1_direct_bench_' ...
    char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
if ~exist(outputDir,'dir'), mkdir(outputDir); end
save(fullfile(outputDir,'type1_direct_bench_results.mat'),'summary','-v7.3');
fprintf('\nDIRECT summary: frames=%d pending=%d dropNew=%d high=%d\n', ...
    status(1),status(2),status(3),status(4));
fprintf('C average ms/frame [extract FFT total]=[%.3f %.3f %.3f]\n', ...
    status(5),status(6),status(7));
if ~isempty(pollMs)
    fprintf('MEX poll ms median/p95/max=%.3f/%.3f/%.3f\n', ...
        median(pollMs),prctile(pollMs,95),max(pollMs));
end
fprintf('Hardware event delta overflow/count/timeout=%s\n', mat2str(eventsEnd-eventsStart));
type1_yunsdr_rx_mex('directbenchstop');

    function close_radio()
        try, type1_yunsdr_rx_mex('directbenchstop'); catch, end
        try, type1_yunsdr_rx_mex('stop'); catch, end
        try, type1_yunsdr_rx_mex('close'); catch, end
    end
end

function wait_for_blocks(required)
t = tic;
while true
    status = type1_yunsdr_rx_mex('status');
    if status(2) >= required, return; end
    if toc(t) > 10, error('type1:DirectBench', 'Ring did not fill.'); end
    pause(0.005);
end
end

function value = env_positive(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value <= 0, value = defaultValue; end
end
