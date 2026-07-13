function type1_rx_direct()
%TYPE1_RX_DIRECT Locked-timestamp native-ring C PHY consumer.
% MATLAB performs only initial PSS/CFO acquisition.  Subsequent frame IQ,
% OFDM, DM-RS, RZF, hard decisions and BER accumulation stay in MEX.

close all; clc;
p=type1_load_package(); c=p.cfg;
duration=env_positive('TYPE1_DIRECT_DURATION_SEC',10);
ring=round(env_positive('TYPE1_FIFO_RING_BLOCKS',2048));
startupMode=lower(string(getenv('TYPE1_DIRECT_STARTUP_MODE')));
if strlength(startupMode)==0, startupMode="two_stage"; end
assert(any(startupMode==["two_stage" "single_stage"]),'type1:DirectRX', ...
    'TYPE1_DIRECT_STARTUP_MODE must be two_stage or single_stage.');
block=round(c.rxSampleRate*1e-3);
if exist('type1_yunsdr_rx_mex','file')~=3, type1_build_rx_mex(); end
if exist('type1_decode_frame_grid_mex','file')~=3, type1_build_frame_mex(); end
fprintf('\n========== Type-A direct C PHY RX ==========\n');
fprintf('duration=%.1fs ring=%dms startup=%s payload slots=[%s]\n',duration,ring,startupMode,num2str(c.dataSlots));
type1_yunsdr_rx_mex('open',c.deviceString,c.rxSampleRate,c.centerFrequencyHz,c.rxGain);
cleanup=onCleanup(@close_radio); %#ok<NASGU>
type1_yunsdr_rx_mex('start',block,ring); wait_blocks(20);
[iq,ts]=type1_yunsdr_rx_mex('snapshotvirtual',20);
acq=type1_analyze_fast(iq,p,c.dataSlots(1),'forcePSS',true, ...
    'snapshotStartRawTimestamp',ts(1));
assert(acq.syncState.valid && acq.syncState.frameStartRawTimestamp~=0, ...
    'type1:DirectRX','PSS acquisition did not produce a raw frame timestamp.');
coarseAcq=acq; startupDiscardBlocks=0;
startupDiscardCoarseBlocks=0; startupDiscardPreStartBlocks=0;
startFrameRaw=acq.syncState.frameStartRawTimestamp;
startupLatestRaw=uint64(0); startupLatestSequence=uint64(0);
if startupMode=="two_stage"
    % Do not decode historical cold-start data.  Flush it explicitly, then
    % use a fresh timestamped snapshot and a narrow PSS check to seed track.
    startupDiscardCoarseBlocks=type1_yunsdr_rx_mex('directflush');
    [trackIQ,trackTs]=type1_yunsdr_rx_mex('snapshotvirtual',20);
    acq=type1_analyze_fast(trackIQ,p,c.dataSlots(1),'forcePSS',false, ...
        'validatePSS',true,'syncState',coarseAcq.syncState, ...
        'snapshotStartRawTimestamp',trackTs(1),'computeSNR',false, ...
        'computeCondition',false);
    assert(acq.syncState.valid && acq.syncState.frameStartRawTimestamp~=0, ...
        'type1:DirectRX','Fresh tracked PSS did not produce a raw frame timestamp.');
    % Map setup can take longer than one frame.  Complete it before the
    % final flush, then choose the newest PSS-aligned frame whose 5.5-ms
    % active half has already reached the DMA ring.
    type1_yunsdr_rx_mex('directphysetup',p.dmrsIndices,p.dmrsSymbols,p.dataIndices,p.dataQPSK,p.codedBits,c.rzfRegularization);
    % Snapshot/PSS work can leave a short burst in the board/driver DMA
    % queue.  It is not yet visible to directflush, so let the native reader
    % drain it to a real-time rate before declaring the final cutover.
    wait_ring_settled();
    startupDiscardPreStartBlocks=type1_yunsdr_rx_mex('directflush');
    [latestRaw,latestSequence]=type1_yunsdr_rx_mex('directlatesttimestamp');
    % Do not reopen any already-received PSS-aligned frame.  Arm the first
    % frame strictly after the final flush and wait until its active half is
    % complete; this makes all pre-start history deliberately disposable.
    [startFrameRaw,startupLatestRaw,startupLatestSequence]=next_complete_frame(acq.syncState.frameStartRawTimestamp,latestRaw,latestSequence,uint64(block),c);
    startupDiscardBlocks=startupDiscardCoarseBlocks+startupDiscardPreStartBlocks;
else
    type1_yunsdr_rx_mex('directphysetup',p.dmrsIndices,p.dmrsSymbols,p.dataIndices,p.dataQPSK,p.codedBits,c.rzfRegularization);
end
% Board-event queries issue multiple device ioctls.  Sample the baseline
% before directstart so their latency cannot become artificial x=0 pending.
events0=type1_yunsdr_rx_mex('events');
[~,startupFoundSequence,startupProducerSequence,startupBlockTimestamp]=type1_yunsdr_rx_mex('directstart',startFrameRaw,acq.frequencyOffsetHz);
syncState=acq.syncState;
lastCFOHz=double(acq.frequencyOffsetHz); lastTimingAdjust=0;
t=tic; last=-inf; lastHealth=-inf; healthCount=0;
traceCapacity=max(256,ceil(duration*150)); traceCount=0;
traceTime=zeros(traceCapacity,1); tracePending=zeros(traceCapacity,1);
traceFrames=zeros(traceCapacity,1); traceDrop=zeros(traceCapacity,1);
% Keep control-plane PSS work out of the first consumer interval.  In
% particular, do not turn the initial x=0 sample into an apparent backlog
% while MATLAB validates PSS before the first directpoll.
lastHealth=toc(t);
s=type1_yunsdr_rx_mex('directstatus');
traceCount=1;
traceTime(1)=0; tracePending(1)=s(3);
traceFrames(1)=s(2); traceDrop(1)=s(4);
while toc(t)<duration
    % This is deliberately a low-rate control plane.  The direct consumer
    % continues to own raw-ring sampling, CFO compensation, FFT and PHY.
    % A fresh timestamped snapshot makes the tracked PSS prediction immune
    % to the MATLAB loop's variable execution time.
    if toc(t)-lastHealth>=0.5
        [healthIQ,healthTs]=type1_yunsdr_rx_mex('snapshotvirtual',20);
        healthCount=healthCount+1;
        % Force a fresh CP-CFO estimate on each health interval rather than
        % inheriting type1_analyze_fast's slower display-monitor cadence.
        syncState.lastCFOFrameStartRawTimestamp=uint64(0);
        healthValid=true;
        try
            health=type1_analyze_fast(healthIQ,p,c.dataSlots(1), ...
                'forcePSS',false,'validatePSS',true, ...
                'syncState',syncState,'snapshotStartRawTimestamp',healthTs(1), ...
                'computeSNR',false,'computeCondition',false);
        catch trackedPssError
            healthValid=false;
            warning('type1:DirectRXTrackHold', ...
                'Tracked PSS failed (%s); retaining last valid timing/CFO.', ...
                trackedPssError.message);
        end
        if healthValid
            syncState=health.syncState;
            lastCFOHz=double(health.frequencyOffsetHz);
            type1_yunsdr_rx_mex('directsetcfo',lastCFOHz);
            lastTimingAdjust=type1_yunsdr_rx_mex('directsettiming', ...
                syncState.frameStartRawTimestamp);
        end
        lastHealth=toc(t);
    end
    s=type1_yunsdr_rx_mex('directstatus');
    if s(3)<10, pause(0.001); continue; end
    type1_yunsdr_rx_mex('directpoll',1); s=type1_yunsdr_rx_mex('directstatus');
    if s(4)~=0, error('type1:DirectRX','FIFO dropNew=%d',s(4)); end
    traceCount=traceCount+1;
    if traceCount>traceCapacity
        traceCapacity=2*traceCapacity;
        traceTime(traceCapacity)=0; tracePending(traceCapacity)=0;
        traceFrames(traceCapacity)=0; traceDrop(traceCapacity)=0;
    end
    traceTime(traceCount)=toc(t); tracePending(traceCount)=s(3);
    traceFrames(traceCount)=s(2); traceDrop(traceCount)=s(4);
    if toc(t)-last>=0.5
        ber=s(6:9)./max(s(10:13),1);
        fprintf('direct t=%6.2f frames=%d pending=%d drop=%d cfo=%+.1fHz timing=%+.0fr BER=[%s] [extract fft phy total]=[%.3f %.3f %.3f %.3f]ms\n', ...
          toc(t),s(2),s(3),s(4),lastCFOHz,lastTimingAdjust,num2str(ber,'%.3g '),s(14),s(15),s(16),s(17));
        last=toc(t);
    end
end
s=type1_yunsdr_rx_mex('directstatus'); events=type1_yunsdr_rx_mex('events');
audit=type1_yunsdr_rx_mex('directaudit');
blockRaw=uint64(block);
auditInvariant=all(audit.nextAfterRaw>=audit.firstTimestampAfter) && ...
    all(audit.nextAfterRaw-audit.firstTimestampAfter<blockRaw) && audit.overflow==0;
assert(auditInvariant,'type1:DirectRX','Timestamp/sequence audit invariant failed.');
out=fullfile(c.outputRoot,['type1_direct_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
if ~exist(out,'dir'),mkdir(out);end
pendingTrace=struct('timeSec',traceTime(1:traceCount),'pendingBlocks',tracePending(1:traceCount), ...
    'frames',traceFrames(1:traceCount),'dropNew',traceDrop(1:traceCount));
startupTimestampAudit=struct('latestRawAfterFlush',startupLatestRaw,'latestSequenceAfterFlush',startupLatestSequence,'startFrameRawTimestamp',startFrameRaw,'foundSequence',startupFoundSequence,'producerSequenceAtStart',startupProducerSequence,'startBlockTimestamp',startupBlockTimestamp,'pendingAtZero',pendingTrace.pendingBlocks(1));
summary=struct('cfg',c,'acq',acq,'coarseAcq',coarseAcq,'startupMode',char(startupMode),'startupDiscardBlocks',startupDiscardBlocks,'startupDiscardCoarseBlocks',startupDiscardCoarseBlocks,'startupDiscardPreStartBlocks',startupDiscardPreStartBlocks,'startFrameRawTimestamp',startFrameRaw,'startupTimestampAudit',startupTimestampAudit,'durationSec',toc(t),'status',s,'eventsStart',events0,'eventsEnd',events,'eventDelta',events-events0,'timingAudit',audit,'timingAuditInvariant',auditInvariant,'pendingTrace',pendingTrace);
save(fullfile(out,'type1_direct_results.mat'),'summary','-v7.3');
fprintf('DIRECT result frames=%d dropNew=%d pending=%d BER=[%s] events=%s\n',s(2),s(4),s(3),num2str(s(6:9)./max(s(10:13),1),'%.3g '),mat2str(events-events0));
type1_yunsdr_rx_mex('directstop');
    function close_radio()
      try,type1_yunsdr_rx_mex('directstop');catch,end
      try,type1_yunsdr_rx_mex('stop');catch,end
      try,type1_yunsdr_rx_mex('close');catch,end
    end
end
function wait_blocks(n)
t=tic; while true; s=type1_yunsdr_rx_mex('status'); if s(2)>=n,return;end; if toc(t)>10,error('type1:DirectRX','RX ring did not fill.');end; pause(.005);end
end
function v=env_positive(n,d),v=str2double(getenv(n));if ~isfinite(v)||v<=0,v=d;end,end
function wait_ring_settled()
% In a 50-ms observation the nominal producer advance is 50 one-ms blocks.
% A substantially larger jump means old DMA descriptors are still draining;
% do not make the final no-history cutover until three observations are sane.
stable=0; deadline=tic;
while stable<3
    [~,s0]=type1_yunsdr_rx_mex('directlatesttimestamp');
    pause(.05);
    [~,s1]=type1_yunsdr_rx_mex('directlatesttimestamp');
    advance=double(s1-s0);
    if advance<=70
        stable=stable+1;
    else
        stable=0;
    end
    if toc(deadline)>5
        error('type1:DirectRX','DMA producer did not settle before final flush.');
    end
end
end
function [frameRaw,latestRaw,latestSequence]=next_complete_frame(pssFrameRaw,latestRaw,latestSequence,blockRaw,cfg)
framePeriodRaw=uint64(round(cfg.frameDurationSec*cfg.rxSampleRate));
activeGuardRaw=uint64(6)*blockRaw; % ceil(5.5 ms) active symbol coverage
% Strictly future relative to the final-flush producer timestamp.  A future
% frame is intentional: waiting about one frame removes old queue history
% instead of trying to recover it with a consumer that is only marginally
% faster than real time.
frameCount=ceil(double(latestRaw+blockRaw-pssFrameRaw)/double(framePeriodRaw));
frameRaw=pssFrameRaw+uint64(frameCount)*framePeriodRaw;
while latestRaw<frameRaw+activeGuardRaw
    pause(.001);
    [latestRaw,latestSequence]=type1_yunsdr_rx_mex('directlatesttimestamp');
end
% The producer may drain a burst of board-DMA descriptors while waiting.
% Rebase once at the end: select the newest PSS-aligned frame whose active
% half is complete now, rather than retaining the earlier provisional one.
frameCount=floor(double(latestRaw-activeGuardRaw-pssFrameRaw)/double(framePeriodRaw));
frameRaw=pssFrameRaw+uint64(frameCount)*framePeriodRaw;
end
