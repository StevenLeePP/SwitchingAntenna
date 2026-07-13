%% TYPE1_PROFILE_FRAME_BATCH Profile locked 10 ms frame: legacy slots vs batch MEX.
% PSS, SNR and cond(H) are deliberately excluded: they run on their own
% low-frequency control/diagnostic schedule, not in the data-plane budget.
clear; clc;
sourceDir=fileparts(mfilename('fullpath')); addpath(sourceDir);
if exist('type1_decode_frame_grid_mex','file')~=3, type1_build_frame_mex(); end
package=type1_load_package(); cfg=package.cfg;
iqFile=newest_file(fullfile(sourceDir,'data'), '*_virtual30_csingle_iq4.bin');
rx=read_iq(iqFile,cfg.nRxChannels);
acq=type1_analyze_fast(rx,package,cfg.dataSlots(1),'forcePSS',true, ...
    'computeSNR',false,'computeCondition',false);
frameSamples=round(cfg.frameDurationSec*cfg.txSampleRate);
frame=rx(acq.timingOffset+(1:frameSamples),:);
nIter=env_positive('TYPE1_PROFILE_ITERATIONS',7);
nSlots=numel(cfg.dataSlots); legacyMs=zeros(nIter,1); batchMs=zeros(nIter,1);
legacyStage=struct; batchPart=zeros(nIter,3); baselineErrors=[]; batchErrors=[];

% Warm JIT/MEX and 5G Toolbox plan caches before statistics.
warm_legacy(rx,package,acq); type1_decode_frame_batch(frame,package,acq.frequencyOffsetHz);
for it=1:nIter
    total=tic; stage=struct; e=zeros(nSlots,cfg.nLayers);
    for q=1:nSlots
        r=type1_analyze_fast(rx,package,cfg.dataSlots(q), ...
            'forcePSS',false,'syncState',acq.syncState, ...
            'trackedTimingOffset',acq.timingOffset,'collectTiming',true, ...
            'computeSNR',false,'computeCondition',false);
        e(q,:)=r.rawBitErrors; stage=add_stage(stage,r.stageTimesMs);
    end
    legacyMs(it)=1e3*toc(total); legacyStage=add_stage(legacyStage,stage);
    b=type1_decode_frame_batch(frame,package,acq.frequencyOffsetHz);
    batchMs(it)=b.elapsedMs; batchPart(it,:)=[b.cfoMs b.ofdmMs b.phyMs];
    if isempty(baselineErrors), baselineErrors=e; batchErrors=b.rawBitErrors; end
    assert(isequal(e,b.rawBitErrors),'type1:BatchProfile', ...
        'Frame %d changed hard-decision bit errors.',it);
end
legacyStage=scale_stage(legacyStage,1/nIter);
fprintf('\n========== Locked 10 ms data-plane profile (%d payload slots) ==========\n',nSlots);
fprintf('Legacy per-slot: median %.3f ms, p95 %.3f ms\n',median(legacyMs),prctile(legacyMs,95));
fprintf('Batch frame MEX: median %.3f ms, p95 %.3f ms, speedup %.2fx\n', ...
    median(batchMs),prctile(batchMs,95),median(legacyMs)/median(batchMs));
fprintf('Batch partition median [CFO / full-frame OFDM / batch DMRS+RZF+BER] = [%.3f / %.3f / %.3f] ms\n',median(batchPart,1));
fprintf('Legacy stage mean per 10ms frame (diagnostics excluded):\n');
print_stage(legacyStage,{'cfoEstimateAndCompensate','dataOFDM','dmrsChannelEstimate','dataAndChannelExtract','rzfEqualize','berAndEvm','unaccounted'});
fprintf('Hard-decision errors identical; total errors per layer=[%s]\n',num2str(sum(batchErrors,1)));

function warm_legacy(rx,package,acq)
for q=1:numel(package.cfg.dataSlots)
 type1_analyze_fast(rx,package,package.cfg.dataSlots(q),'forcePSS',false,'syncState',acq.syncState,'trackedTimingOffset',acq.timingOffset,'computeSNR',false,'computeCondition',false);
end
end
function out=add_stage(out,in)
f=fieldnames(in); for k=1:numel(f), if ~isfield(out,f{k}),out.(f{k})=0;end;out.(f{k})=out.(f{k})+in.(f{k});end
end
function s=scale_stage(s,a),f=fieldnames(s);for k=1:numel(f),s.(f{k})=s.(f{k})*a;end,end
function print_stage(s,names),for k=1:numel(names),n=names{k};if isfield(s,n),fprintf('  %-28s %8.3f ms\n',n,s.(n));end,end,end
function f=newest_file(d,p),x=dir(fullfile(d,p));assert(~isempty(x),'No virtual30 IQ capture.');[~,i]=max([x.datenum]);f=fullfile(x(i).folder,x(i).name);end
function x=read_iq(f,n),id=fopen(f,'rb');c=onCleanup(@()fclose(id));a=fread(id,inf,'single=>single');assert(mod(numel(a),2*n)==0);x=reshape(complex(a(1:2:end),a(2:2:end)),[],n);end
function v=env_positive(n,d),v=str2double(getenv(n));if ~isfinite(v)||v<=0,v=d;end,end
