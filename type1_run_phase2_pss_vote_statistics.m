function report = type1_run_phase2_pss_vote_statistics()
%TYPE1_RUN_PHASE2_PSS_VOTE_STATISTICS Paired 30-seed x 3-SNR PSS audit.
%   The preregistered default-upgrade rule is: vote rescues at least as many
%   cases as it loses at every SNR, and exact two-sided McNemar p<0.05 with
%   more rescues than losses at one or more SNRs.  No threshold is tuned.
p=type1_load_package(); cfg=p.cfg; seeds=20261101:20261130; snrDb=[14 20 26];
nSeed=numel(seeds); nSnr=numel(snrDb); combined=false(nSeed,nSnr); vote=false(nSeed,nSnr);
combinedTiming=nan(nSeed,nSnr); voteTiming=nan(nSeed,nSnr);
combinedNid2=nan(nSeed,nSnr); voteNid2=nan(nSeed,nSnr); voteFallback=false(nSeed,nSnr);
for level=1:nSnr
    sim=pss_config(snrDb(level));
    for k=1:nSeed
        link=type1_offline_link(p,sim,RandStream('mt19937ar','Seed',seeds(k)));
        dc=detect_pss(link.virtualRx30,p);
        combinedTiming(k,level)=wrap_offset(dc.adjustedPeak-sim.prefixSamples,cfg);
        combinedNid2(k,level)=dc.bestNid2;
        errors=nan(1,4); nid2=nan(1,4); metric=nan(1,4);
        for r=1:4
            d=detect_pss(link.virtualRx30(:,r),p);
            errors(r)=wrap_offset(d.adjustedPeak-sim.prefixSamples,cfg);
            nid2(r)=d.bestNid2; metric(r)=d.metric;
        end
        [voteTiming(k,level),voteNid2(k,level),voteFallback(k,level)]=vote_peaks( ...
            errors,nid2,metric,combinedTiming(k,level),combinedNid2(k,level), ...
            max(p.ofdmInfo.CyclicPrefixLengths),cfg);
        combined(k,level)=is_success(combinedTiming(k,level),combinedNid2(k,level),p);
        vote(k,level)=is_success(voteTiming(k,level),voteNid2(k,level),p);
        fprintf('SNR=%g seed=%d combined/vote=%d/%d err=%.0f/%.0f fallback=%d\n', ...
            snrDb(level),seeds(k),combined(k,level),vote(k,level), ...
            combinedTiming(k,level),voteTiming(k,level),voteFallback(k,level));
    end
end
combinedCount=sum(combined,1); voteCount=sum(vote,1);
rescued=sum(~combined & vote,1); lost=sum(combined & ~vote,1); pValue=nan(1,nSnr);
for level=1:nSnr, pValue(level)=mcnemar_exact(rescued(level),lost(level)); end
noninferiorAll=all(rescued>=lost);
significantlyBetterAny=any(rescued>lost & pValue<.05);
upgradeDefault=noninferiorAll && significantlyBetterAny;
report=struct('seeds',seeds,'snrDb',snrDb,'combinedSuccess',combined, ...
    'voteSuccess',vote,'combinedSuccessCount',combinedCount,'voteSuccessCount',voteCount, ...
    'combinedTimingErrorSamples',combinedTiming,'voteTimingErrorSamples',voteTiming, ...
    'combinedNid2',combinedNid2,'voteNid2',voteNid2,'voteUsedCombinedFallback',voteFallback, ...
    'pairedVoteRescues',rescued,'pairedVoteLosses',lost,'mcnemarTwoSidedExactP',pValue, ...
    'alpha',.05,'noninferiorDefinition','rescues >= losses at every SNR', ...
    'noninferiorAllSnr',noninferiorAll,'significantlyBetterAnySnr',significantlyBetterAny, ...
    'upgradeVoteToDefault',upgradeDefault,'timingToleranceSamples', ...
    max(p.ofdmInfo.CyclicPrefixLengths),'simTemplate',pss_config(20));
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_pss_vote_statistics_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_pss_vote_statistics.mat'),'report','-v7.3');
fprintf('PSS combined=[%s], vote=[%s], rescue/loss=[%s]/[%s], p=[%s], upgrade=%d, saved: %s\n', ...
    num2str(combinedCount),num2str(voteCount),num2str(rescued),num2str(lost), ...
    num2str(pValue,'%.4g '),upgradeDefault,out);
end

function yes=is_success(error,nid2,p)
yes=abs(error)<=max(p.ofdmInfo.CyclicPrefixLengths) && nid2==mod(p.cfg.pci,3);
end

function p=mcnemar_exact(rescued,lost)
n=rescued+lost;
if n==0, p=1; return; end
m=min(rescued,lost); terms=zeros(1,m+1);
for k=0:m, terms(k+1)=nchoosek(n,k); end
p=min(1,2*sum(terms)/2^n);
end

function [selectedError,selectedNid2,usedFallback]=vote_peaks(errors,nid2,metric,combinedError,combinedNid2,tolerance,cfg)
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
[bestMetric,index]=max(metric); adjusted=peak(index); frame=round(cfg.frameDurationSec*cfg.txSampleRate);
while adjusted+frame>size(rx,1), adjusted=adjusted-frame; end
d=struct('bestNid2',index-1,'metric',bestMetric,'adjustedPeak',adjusted);
end

function value=wrap_offset(value,cfg)
frame=round(cfg.frameDurationSec*cfg.txSampleRate);
value=mod(value+frame/2,frame)-frame/2;
end

function s=pss_config(snrDb)
s=type1_offline_multiuser_config(); s.frames=1; s.snrDb=snrDb; s.channelModel="tdl-a";
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
