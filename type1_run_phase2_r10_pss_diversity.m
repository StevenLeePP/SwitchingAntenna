function report = type1_run_phase2_r10_pss_diversity()
%TYPE1_RUN_PHASE2_R10_PSS_DIVERSITY Audit existing four-chain PSS combining.
%   The combined detector is exactly the current noncoherent sum of four
%   nrTimingEstimate magnitudes.  Four fixed single-chain detectors are
%   evaluated on the same L0 windows; this script does not alter acquisition.
p=type1_load_package(); cfg=p.cfg; s=r10_l0_config(); seeds=20261001:20261008;
names=["four-chain noncoherent" "chain1" "chain2" "chain3" "chain4"];
success=false(numel(seeds),5); timingError=nan(numel(seeds),5);
bestNid2=nan(numel(seeds),5); peakMetric=nan(numel(seeds),5); rawPeak=nan(numel(seeds),5);
voteSuccess=false(numel(seeds),1); voteTimingError=nan(numel(seeds),1);
voteNid2=nan(numel(seeds),1); voteUsedFallback=false(numel(seeds),1);
for k=1:numel(seeds)
    link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',seeds(k)));
    inputs=cell(1,5); inputs{1}=link.virtualRx30;
    for r=1:4, inputs{r+1}=link.virtualRx30(:,r); end
    for receiver=1:5
        d=detect_pss(inputs{receiver},p);
        bestNid2(k,receiver)=d.bestNid2; peakMetric(k,receiver)=d.metric;
        rawPeak(k,receiver)=d.rawPeak; timingError(k,receiver)=wrap_offset(d.adjustedPeak-s.prefixSamples,cfg);
        success(k,receiver)=abs(timingError(k,receiver))<=max(p.ofdmInfo.CyclicPrefixLengths) && ...
            d.bestNid2==mod(cfg.pci,3);
    end
    [voteTimingError(k),voteNid2(k),voteUsedFallback(k)]=vote_peaks( ...
        timingError(k,2:5),bestNid2(k,2:5),peakMetric(k,2:5), ...
        timingError(k,1),bestNid2(k,1),max(p.ofdmInfo.CyclicPrefixLengths),cfg);
    voteSuccess(k)=abs(voteTimingError(k))<=max(p.ofdmInfo.CyclicPrefixLengths) && ...
        voteNid2(k)==mod(cfg.pci,3);
    fprintf('seed=%d PSS success combined/c1/c2/c3/c4/vote=[%s %d], timingErr=[%s %.0f], fallback=%d\n', ...
        seeds(k),num2str(success(k,:),'%d '),voteSuccess(k), ...
        num2str(timingError(k,:),'%.0f '),voteTimingError(k),voteUsedFallback(k));
end
expectedCombined=logical([1 1 1 0 1 0 1 0]).';
assert(isequal(success(:,1),expectedCombined),'type1:R10PSSRegression', ...
    'Four-chain detector does not reproduce the accepted R8 acquisition audit.');
successCount=sum(success,1); report=struct('seeds',seeds,'detectorNames',names, ...
    'success',success,'successCount',successCount,'timingErrorSamples',timingError, ...
    'bestNid2',bestNid2,'peakMetric',peakMetric,'rawPeak',rawPeak, ...
    'voteSuccess',voteSuccess,'voteSuccessCount',sum(voteSuccess), ...
    'voteTimingErrorSamples',voteTimingError,'voteNid2',voteNid2, ...
    'voteUsedCombinedFallback',voteUsedFallback,'votePassedSmokeGate',sum(voteSuccess)>=6, ...
    'timingToleranceSamples',max(p.ofdmInfo.CyclicPrefixLengths), ...
    'currentReceiverAlreadyCombinesFourChains',true,'sim',s);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_r10_pss_diversity_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_r10_pss_diversity.mat'),'report','-v7.3');
fprintf('PSS success counts combined/c1/c2/c3/c4=[%s], vote=%d/8 pass=%d, saved: %s\n', ...
    num2str(successCount,'%d '),sum(voteSuccess),sum(voteSuccess)>=6,out);
end

function [selectedError,selectedNid2,usedFallback]=vote_peaks(errors,nid2,metric,combinedError,combinedNid2,tolerance,cfg)
% Pick the strongest >=2-chain cluster with the same NID2 and circularly
% consistent frame timing.  If no such cluster exists, retain the deployed
% four-chain noncoherent detector exactly as preregistered.
frame=round(cfg.frameDurationSec*cfg.txSampleRate); bestScore=-inf; bestCluster=[];
for i=1:numel(errors)
    distance=abs(mod(errors-errors(i)+frame/2,frame)-frame/2);
    cluster=find(distance<=tolerance & nid2==nid2(i));
    if numel(cluster)>=2
        score=sum(metric(cluster));
        if score>bestScore, bestScore=score; bestCluster=cluster; end
    end
end
if isempty(bestCluster)
    selectedError=combinedError; selectedNid2=combinedNid2; usedFallback=true;
else
    [~,local]=max(metric(bestCluster)); chosen=bestCluster(local);
    selectedError=errors(chosen); selectedNid2=nid2(chosen); usedFallback=false;
end
end

function d=detect_pss(rx,p)
cfg=p.cfg; carrier=type1_carrier_config(cfg,0); nSC=12*cfg.nRB; rx=double(rx);
% Match type1_analyze exactly: without per-chain RMS normalization a strong
% branch can dominate the noncoherent sum and this ceases to be an A/B test
% of the deployed acquisition rule.
for r=1:size(rx,2)
    scale=rms(rx(:,r)); if scale>0, rx(:,r)=rx(:,r)/scale; end
end
metric=zeros(3,1); peak=zeros(3,1);
for nid2=0:2
    localSSB=complex(zeros(240,4)); localSSB(nrPSSIndices)=nrPSS(nid2);
    referenceGrid=complex(zeros(nSC,cfg.symbolsPerSlot));
    referenceGrid(p.ssbSubcarriers,p.ssbSymbols)=localSSB;
    [offset,magnitude]=nrTimingEstimate(carrier,rx,referenceGrid, ...
        'Nfft',cfg.nfft,'SampleRate',cfg.txSampleRate,'CarrierFrequency',0);
    peak(nid2+1)=offset; metric(nid2+1)=max(sum(abs(magnitude).^2,2),[],'all');
end
[bestMetric,index]=max(metric); raw=peak(index); adjusted=raw;
frame=round(cfg.frameDurationSec*cfg.txSampleRate);
while adjusted+frame>size(rx,1), adjusted=adjusted-frame; end
d=struct('bestNid2',index-1,'metric',bestMetric,'rawPeak',raw,'adjustedPeak',adjusted, ...
    'allMetrics',metric,'allPeaks',peak);
end

function value=wrap_offset(value,cfg)
frame=round(cfg.frameDurationSec*cfg.txSampleRate);
value=mod(value+frame/2,frame)-frame/2;
end

function s=r10_l0_config()
s=type1_offline_multiuser_config(); s.frames=1; s.snrDb=20; s.channelModel="tdl-a";
s.userCfoHz=.5*s.userCfoHz; s.tdl.delaySpreadNs=100; s.tdl.dopplerHz=0;
s.tdl.rxCorrelation=.3; s.tdl.txCorrelation=.3;
s.userTimingSamples=min(max(s.userTimingSamples,-4),4);
s.switch.isolationDb=25; s.switch.settlingRiseNs=20;
s.switch.transitionJitterStdPs=20; s.switch.samplingBoundaryJitterStdPs=100;
s.switch.settlingFastJitterStdFraction=0; s.switch.settlingFastJitterCorrelationSec=1e-6;
s.switch.recordTimeSeries=false; cfg=type1_config();
s.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
end
