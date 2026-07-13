function type1_rx_direct()
%TYPE1_RX_DIRECT Locked-timestamp native-ring C PHY consumer.
% MATLAB performs only initial PSS/CFO acquisition.  Subsequent frame IQ,
% OFDM, DM-RS, RZF, hard decisions and BER accumulation stay in MEX.

close all; clc;
p=type1_load_package(); c=p.cfg;
duration=env_positive('TYPE1_DIRECT_DURATION_SEC',10);
ring=round(env_positive('TYPE1_FIFO_RING_BLOCKS',2048));
block=round(c.rxSampleRate*1e-3);
if exist('type1_yunsdr_rx_mex','file')~=3, type1_build_rx_mex(); end
if exist('type1_decode_frame_grid_mex','file')~=3, type1_build_frame_mex(); end
fprintf('\n========== Type-A direct C PHY RX ==========\n');
fprintf('duration=%.1fs ring=%dms payload slots=[%s]\n',duration,ring,num2str(c.dataSlots));
type1_yunsdr_rx_mex('open',c.deviceString,c.rxSampleRate,c.centerFrequencyHz,c.rxGain);
cleanup=onCleanup(@close_radio); %#ok<NASGU>
type1_yunsdr_rx_mex('start',block,ring); wait_blocks(20);
[iq,ts]=type1_yunsdr_rx_mex('snapshotvirtual',20);
acq=type1_analyze_fast(iq,p,c.dataSlots(1),'forcePSS',true, ...
    'snapshotStartRawTimestamp',ts(1));
assert(acq.syncState.valid && acq.syncState.frameStartRawTimestamp~=0, ...
    'type1:DirectRX','PSS acquisition did not produce a raw frame timestamp.');
type1_yunsdr_rx_mex('directphysetup',p.dmrsIndices,p.dmrsSymbols,p.dataIndices,p.dataQPSK,p.codedBits,c.rzfRegularization);
type1_yunsdr_rx_mex('directstart',acq.syncState.frameStartRawTimestamp,acq.frequencyOffsetHz);
syncState=acq.syncState;
lastCFOHz=double(acq.frequencyOffsetHz); lastTimingAdjust=0;
events0=type1_yunsdr_rx_mex('events'); t=tic; last=-inf; lastHealth=-inf; healthCount=0;
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
        health=type1_analyze_fast(healthIQ,p,c.dataSlots(1), ...
            'forcePSS',false,'validatePSS',true, ...
            'syncState',syncState,'snapshotStartRawTimestamp',healthTs(1), ...
            'computeSNR',false,'computeCondition',false);
        syncState=health.syncState;
        lastCFOHz=double(health.frequencyOffsetHz);
        type1_yunsdr_rx_mex('directsetcfo',lastCFOHz);
        lastTimingAdjust=type1_yunsdr_rx_mex('directsettiming', ...
            syncState.frameStartRawTimestamp);
        lastHealth=toc(t);
    end
    s=type1_yunsdr_rx_mex('directstatus');
    if s(3)<10, pause(0.001); continue; end
    type1_yunsdr_rx_mex('directpoll',1); s=type1_yunsdr_rx_mex('directstatus');
    if s(4)~=0, error('type1:DirectRX','FIFO dropNew=%d',s(4)); end
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
summary=struct('cfg',c,'acq',acq,'durationSec',toc(t),'status',s,'eventsStart',events0,'eventsEnd',events,'eventDelta',events-events0,'timingAudit',audit,'timingAuditInvariant',auditInvariant);
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
