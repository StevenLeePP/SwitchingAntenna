function type1_rx_fifo()
%TYPE1_RX_FIFO Ordered-consumer continuous BER experiment.
% This is intentionally separate from type1_rx_live: it never takes a
% "latest" snapshot. Every decoded frame comes from dequeuevirtual in FIFO
% order, and any software drop invalidates the continuous-run verdict.

close all; clc;
package = type1_load_package();
cfg = apply_fifo_defaults(package.cfg);
cfg.fifoRingBlocks = round(env_positive('TYPE1_FIFO_RING_BLOCKS', cfg.fifoRingBlocks));
fifoDequeueBlocks = round(env_positive('TYPE1_FIFO_DEQUEUE_BLOCKS', 10));
fifoDequeueBlocks = min(max(fifoDequeueBlocks,1),cfg.fifoRingBlocks);
package.cfg = cfg;
durationSec = env_positive('TYPE1_FIFO_DURATION_SEC', 60);
blockSamples = round(cfg.rxSampleRate * 1e-3);
frameSamples = round(cfg.txSampleRate * cfg.frameDurationSec);
slotSamples = frameSamples / cfg.slotsPerFrame;
activeFrameSamples = (max(cfg.dataSlots) + 1) * slotSamples;
framePeriodRaw = round(cfg.rxSampleRate * cfg.frameDurationSec);
maxAcquireBlocks = 20;
assert(cfg.nRxChannels == cfg.nLayers, ...
    'FIFO experiment currently requires 4 RX channels for 4-layer BER.');

if exist('type1_yunsdr_rx_mex', 'file') ~= 3, type1_build_rx_mex(); end
if exist('type1_rzf_qpsk_mex', 'file') ~= 3, type1_build_decode_mex(); end
if exist('type1_dmrs_type1_mex', 'file') ~= 3, type1_build_dmrs_mex(); end
if exist('type1_decode_frame_grid_mex', 'file') ~= 3, type1_build_frame_mex(); end
assert(strcmp(package.channelCoding,'none'), ...
    'Ordered batch FIFO mode currently requires channelCoding=''none''.');

fprintf('\n========== Type-A ordered FIFO RX ==========\n');
fprintf('Payload slots         : [%s] (%s mode)\n', ...
    num2str(cfg.dataSlots), field_or(cfg, 'payloadSlotMode', 'legacy'));
fprintf('FIFO capacity          : %d ms (%d blocks)\n', ...
    cfg.fifoRingBlocks, cfg.fifoRingBlocks);
fprintf('FIFO dequeue quantum   : %d ms per MEX call\n', fifoDequeueBlocks);
fprintf('Policy                 : preserve unread blocks; drop NEW input on full\n');
fprintf('Requirement            : droppedNew must remain zero for valid BER\n\n');

type1_yunsdr_rx_mex('open', cfg.deviceString, cfg.rxSampleRate, ...
    cfg.centerFrequencyHz, cfg.rxGain);
cleanup = onCleanup(@close_fifo_radio);
type1_yunsdr_rx_mex('start', blockSamples, cfg.fifoRingBlocks);
wait_for_blocks(20);
type1_yunsdr_rx_mex('fifostart');
eventsStart = type1_yunsdr_rx_mex('events');
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
outputDir = fullfile(cfg.outputRoot, ['type1_fifo_' stamp]);
if ~exist(outputDir,'dir'), mkdir(outputDir); end

% Fixed FIFO-side assembly storage: steady state writes one 10 ms block,
% decodes it, then advances the head without reallocating/copying a growing
% MATLAB array. This is part of the continuous-real-time data path.
streamCapacity = maxAcquireBlocks * blockSamples / 4 + 2 * frameSamples;
streamIQ = complex(zeros(streamCapacity, cfg.nRxChannels, 'single'));
streamCount = 0;
streamStartRaw = uint64(0);
syncState = struct('valid', false);
nextFrameRaw = uint64(0);
decodedFrames = 0;
decodedSlots = 0;
totalBitErrors = zeros(1, cfg.nLayers);
totalBits = zeros(1, cfg.nLayers);
continuousValid = true;
failureReason = '';
lastPrint = -inf;
lastDiagnostic = -inf;
latestDiagnostic = struct('snrNullDb',nan,'snrDmrsDb',nan, ...
    'conditionStats',[nan nan nan]);
lastBatchMs = nan;
lastBatchPartsMs = [nan nan nan];
frameBatchMs = zeros(0,1);
dequeueMs = zeros(0,1);
runTimer = tic;

while toc(runTimer) < durationSec
    status = type1_yunsdr_rx_mex('fifostatus');
    pending = status(4); dropped = status(6);
    if dropped ~= 0
        fprintf(2, 'FIFO DROP: new blocks dropped=%d at t=%.3f s\n', ...
            dropped, toc(runTimer));
        continuousValid = false;
        failureReason = 'FIFO reached capacity: one or more new blocks were not queued.';
        break;
    end
    if pending < 1
        pause(0.0005);
        continue;
    end

    takeBlocks = min(pending, fifoDequeueBlocks);
    dequeueTimer = tic;
    [block, timestamps] = type1_yunsdr_rx_mex('dequeuevirtual', takeBlocks);
    lastDequeueMs = 1e3 * toc(dequeueTimer);
    dequeueMs(end+1,1) = lastDequeueMs; %#ok<AGROW>
    if isempty(block), continue; end
    expectedBlockTimestamps = timestamps(1) + uint64(blockSamples) .* ...
        uint64((0:numel(timestamps)-1).');
    if ~isequal(timestamps(:), expectedBlockTimestamps)
        fprintf(2, 'FIFO internal timestamp gap within a %d-block dequeue.\n', ...
            numel(timestamps));
        continuousValid = false;
        failureReason = 'FIFO timestamp discontinuity inside a batch dequeue.';
        break;
    end
    if streamCount == 0
        streamStartRaw = timestamps(1);
    else
        expectedRaw = streamStartRaw + uint64(4 * streamCount);
        if timestamps(1) ~= expectedRaw
            fprintf(2, 'FIFO timestamp gap: expected %u, got %u\n', ...
                expectedRaw, timestamps(1));
            continuousValid = false;
            failureReason = 'Ordered FIFO timestamp discontinuity.';
            break;
        end
    end
    nNew = size(block,1);
    if streamCount + nNew > streamCapacity
        error('type1:FifoAssembly', ...
            'MATLAB assembly buffer exhausted before FIFO policy detected a drop.');
    end
    streamIQ(streamCount+(1:nNew),:) = block;
    streamCount = streamCount + nNew;

    % Acquire only from a complete 20 ms ordered history window.
    if ~isfield(syncState, 'valid') || ~syncState.valid
        if streamCount >= maxAcquireBlocks * blockSamples / 4
            try
                firstSlot = cfg.dataSlots(1);
                acquisition = type1_analyze_fast(streamIQ(1:streamCount,:), package, firstSlot, ...
                    'forcePSS', true, 'snapshotStartRawTimestamp', streamStartRaw);
                syncState = acquisition.syncState;
                nextFrameRaw = syncState.frameStartRawTimestamp;
                while nextFrameRaw < streamStartRaw
                    nextFrameRaw = nextFrameRaw + uint64(framePeriodRaw);
                end
                fprintf('FIFO Acquire OK: frame_raw=%u, PSS=%.1f dB\n', ...
                    nextFrameRaw, acquisition.pssPeakToMedianDb);
            catch ME
                % Retain the newest 20 ms and retry on the next ordered block.
                keep = maxAcquireBlocks * blockSamples / 4;
                oldCount = streamCount;
                streamIQ(1:keep,:) = streamIQ(oldCount-keep+(1:keep),:);
                streamCount = keep;
                streamStartRaw = streamStartRaw + uint64(4*(oldCount-keep));
                fprintf(2, 'FIFO Acquire retry: %s\n', ME.message);
            end
        end
    end

    while isfield(syncState, 'valid') && syncState.valid && ...
            nextFrameRaw >= streamStartRaw && ...
            double(nextFrameRaw - streamStartRaw)/4 + activeFrameSamples <= streamCount
        frameOffset = round(double(nextFrameRaw - streamStartRaw) / 4);
        frameAge = floor(double(nextFrameRaw - syncState.frameStartRawTimestamp) / framePeriodRaw);
        try
            % Control path only: one narrow PSS/CFO health check every N
            % frames. The payload itself is always decoded in the batch MEX.
            if frameAge > 0 && mod(frameAge,cfg.fastPSSCheckIntervalFrames) == 0
                health = type1_analyze_fast(streamIQ(1:streamCount,:), package, cfg.dataSlots(1), ...
                    'forcePSS', false, 'validatePSS', true, ...
                    'syncState', syncState, ...
                    'snapshotStartRawTimestamp', streamStartRaw, ...
                    'trackedTimingOffset', frameOffset, ...
                    'computeSNR', false, 'computeCondition', false);
                syncState = health.syncState;
            end
            batch = type1_decode_frame_batch( ...
                streamIQ(frameOffset+(1:activeFrameSamples),:), package, ...
                syncState.frequencyOffsetHz);
            lastBatchMs = batch.elapsedMs;
            lastBatchPartsMs = [batch.cfoMs batch.ofdmMs batch.phyMs];
            frameBatchMs(end+1,1) = lastBatchMs; %#ok<AGROW>
            totalBitErrors = totalBitErrors + sum(batch.rawBitErrors,1);
            totalBits = totalBits + numel(cfg.dataSlots) * package.nInfoBitsPerSlotLayer;
            decodedSlots = decodedSlots + numel(cfg.dataSlots);
            decodedFrames = decodedFrames + 1;
            nextFrameRaw = nextFrameRaw + uint64(framePeriodRaw);

            % Diagnostics are intentionally outside the 10ms data path.
            if toc(runTimer) - lastDiagnostic >= 1
                diagnostic = type1_analyze_fast(streamIQ(1:streamCount,:), package, cfg.dataSlots(1), ...
                    'forcePSS', false, 'syncState', syncState, ...
                    'snapshotStartRawTimestamp', streamStartRaw, ...
                    'trackedTimingOffset', frameOffset, ...
                    'computeSNR', true, 'computeCondition', true);
                latestDiagnostic.snrNullDb = diagnostic.snrNullDb;
                latestDiagnostic.snrDmrsDb = diagnostic.snrDmrsDb;
                latestDiagnostic.conditionStats = diagnostic.conditionStats;
                lastDiagnostic = toc(runTimer);
            end
        catch ME
            fprintf(2, 'FIFO decode lost lock: %s\n', ME.message);
            syncState = struct('valid', false);
            break;
        end
    end

    % Drop only IQ already decoded, never unread FIFO data.
    if nextFrameRaw > streamStartRaw
        discard = min(streamCount, round(double(nextFrameRaw-streamStartRaw)/4));
        if discard > 0
            remain = streamCount - discard;
            if remain > 0
                streamIQ(1:remain,:) = streamIQ(discard+(1:remain),:);
            end
            streamCount = remain;
            streamStartRaw = streamStartRaw + uint64(4*discard);
        end
    end

    if toc(runTimer) - lastPrint >= 0.5
        status = type1_yunsdr_rx_mex('fifostatus');
        fprintf(['fifo t=%6.2f producer=%u consumer=%u pending=%3d ms ' ...
            'high=%3d dropNew=%d decodedFrames=%d BER=[%s] ' ...
            'dequeue=%.2fms decode=%.2fms [CFO/OFDM/PHY=%.2f/%.2f/%.2f]ms ' ...
            'SNRnull=[%s] condMed=%.2f\n'], ...
            toc(runTimer), uint64(status(2)), uint64(status(3)), status(4), ...
            status(7), status(6), decodedFrames, ...
            num2str(totalBitErrors ./ max(totalBits,1), '%.3g '), ...
            lastDequeueMs, ...
            lastBatchMs, lastBatchPartsMs(1), lastBatchPartsMs(2), ...
            lastBatchPartsMs(3), ...
            num2str(latestDiagnostic.snrNullDb, '%.1f '), ...
            latestDiagnostic.conditionStats(1));
        lastPrint = toc(runTimer);
    end
end

status = type1_yunsdr_rx_mex('fifostatus');
events = type1_yunsdr_rx_mex('events');
summary = struct('cfg',cfg,'durationSec',toc(runTimer), ...
    'decodedFrames',decodedFrames,'decodedSlots',decodedSlots, ...
    'totalBitErrors',totalBitErrors,'totalBits',totalBits, ...
    'continuousValid',continuousValid,'failureReason',failureReason, ...
    'latestDiagnostic',latestDiagnostic, ...
    'frameBatchMs',frameBatchMs, ...
    'dequeueMs',dequeueMs, ...
    'fifoStatus',status,'eventsStart',eventsStart,'eventsEnd',events, ...
    'eventDelta',events-eventsStart);
save(fullfile(outputDir,'type1_fifo_results.mat'),'summary','-v7.3');
fprintf('\nFIFO result: frames=%d slots=%d dropNew=%d pending=%d highWater=%d\n', ...
    decodedFrames, decodedSlots, status(6), status(4), status(7));
if ~isempty(frameBatchMs)
    fprintf('Batch decode ms: median/p95/max = %.2f / %.2f / %.2f\n', ...
        median(frameBatchMs), prctile(frameBatchMs,95), max(frameBatchMs));
end
if ~isempty(dequeueMs)
    fprintf('FIFO dequeue ms: median/p95/max = %.2f / %.2f / %.2f\n', ...
        median(dequeueMs), prctile(dequeueMs,95), max(dequeueMs));
end
if continuousValid && status(6) == 0
    fprintf('VALID continuous BER=[%s], events overflow/count/timeout=%s\n', ...
        num2str(totalBitErrors ./ max(totalBits,1), '%.3g '), mat2str(events));
else
    fprintf(2, 'INVALID continuous BER run: %s\n', failureReason);
end
fprintf('Results: %s\n', outputDir);
type1_yunsdr_rx_mex('fifostop');
clear cleanup;

    function close_fifo_radio()
        try
            type1_yunsdr_rx_mex('fifostop');
        catch
        end
        try
            type1_yunsdr_rx_mex('stop');
        catch
        end
        try
            type1_yunsdr_rx_mex('close');
        catch
        end
    end
end

function wait_for_blocks(count)
t = tic;
while true
    s = type1_yunsdr_rx_mex('status');
    if s(3) == 0, error('type1:FifoRX', 'RX worker stopped (%d).', s(4)); end
    if s(2) >= count, return; end
    if toc(t) > 10, error('type1:FifoRX', 'Ring did not fill.'); end
    pause(0.001);
end
end

function value = env_positive(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value <= 0, value = defaultValue; end
end

function value = field_or(s, name, defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end

function cfg = apply_fifo_defaults(cfg)
if ~isfield(cfg,'fifoRingBlocks'), cfg.fifoRingBlocks = 128; end
if ~isfield(cfg,'fastPSSCheckIntervalFrames'), cfg.fastPSSCheckIntervalFrames = 50; end
if ~isfield(cfg,'fastPSSLocalSearchSamples'), cfg.fastPSSLocalSearchSamples = 512; end
if ~isfield(cfg,'fastPSSMinPeakToMedianDb'), cfg.fastPSSMinPeakToMedianDb = 8; end
if ~isfield(cfg,'fastNormalizeRx'), cfg.fastNormalizeRx = false; end
if ~isfield(cfg,'fastCFOCheckIntervalFrames'), cfg.fastCFOCheckIntervalFrames = 50; end
if ~isfield(cfg,'fastEnablePBCH'), cfg.fastEnablePBCH = false; end
if ~isfield(cfg,'fastValidateSSSWithPSS'), cfg.fastValidateSSSWithPSS = true; end
if ~isfield(cfg,'fastUseRZFQPSKMEX'), cfg.fastUseRZFQPSKMEX = true; end
if ~isfield(cfg,'fastUseType1DMRSMEX'), cfg.fastUseType1DMRSMEX = true; end
end
