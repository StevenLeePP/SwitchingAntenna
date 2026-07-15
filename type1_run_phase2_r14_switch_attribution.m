function report = type1_run_phase2_r14_switch_attribution()
%TYPE1_RUN_PHASE2_R14_SWITCH_ATTRIBUTION Split R13 20-dB switch cost.
%   The ideal-on arm retains four-phase interleaved sampling but removes all
%   modeled leakage, settling and jitter.  Regenerated switch-off decisions
%   must match the accepted R13 per-seed matrix before attribution is valid.

priorFile=getenv('TYPE1_R14_R13_MAT');
if isempty(priorFile)
    priorFile='/tmp/type1_phase2/type1_phase2_pss_acquisition_20260715_144558/phase2_pss_acquisition.mat';
end
assert(isfile(priorFile),'type1:R14R13Prior','R14 switch attribution requires the accepted R13 MAT.');
loaded=load(priorFile,'report'); prior=loaded.report;
assert(prior.profile=="paper" && any(prior.snrDb==20),'type1:R14R13Prior', ...
    'Prior MAT must be the accepted R13 paper profile with a 20-dB point.');
profile=lower(string(getenv('TYPE1_R14_PROFILE'))); if strlength(profile)==0,profile="paper";end
if profile=="smoke"
    seedIndices=1:4;
elseif profile=="paper"
    seedIndices=1:numel(prior.seeds);
else
    error('type1:R14Profile','TYPE1_R14_PROFILE must be smoke or paper.');
end
p=type1_load_package(); seeds=prior.seeds(seedIndices); level20=find(prior.snrDb==20,1);
impaired=prior.success(seedIndices,level20,1); acceptedOff=prior.switchOffSuccess(seedIndices);
ideal=false(numel(seeds),1); regeneratedOff=false(numel(seeds),1);
idealTiming=nan(numel(seeds),1); offTiming=nan(numel(seeds),1);
idealNid2=nan(numel(seeds),1); offNid2=nan(numel(seeds),1);
for k=1:numel(seeds)
    [offRx,idealRx,expectedPhase]=make_pair(p,seeds(k),20);
    frame=round(p.cfg.frameDurationSec*p.cfg.txSampleRate);
    off=detect_pss(offRx,p,frame); idealResult=detect_pss(idealRx,p,frame);
    tolerance=max(p.ofdmInfo.CyclicPrefixLengths);
    offTiming(k)=wrap_error(off.peak-expectedPhase,frame);
    idealTiming(k)=wrap_error(idealResult.peak-expectedPhase,frame);
    offNid2(k)=off.nid2; idealNid2(k)=idealResult.nid2;
    regeneratedOff(k)=abs(offTiming(k))<=tolerance && offNid2(k)==mod(p.cfg.pci,3);
    ideal(k)=abs(idealTiming(k))<=tolerance && idealNid2(k)==mod(p.cfg.pci,3);
    if any(k==[1 ceil(numel(seeds)/2) numel(seeds)])
        fprintf('R14 switch checkpoint %d/%d seed=%d off/ideal/impaired=[%d %d %d]\n', ...
            k,numel(seeds),seeds(k),regeneratedOff(k),ideal(k),impaired(k));
    end
end
offRegressionPassed=isequal(regeneratedOff,acceptedOff) && ...
    isequal(offNid2,prior.switchOffNid2(seedIndices)) && ...
    max(abs(offTiming-prior.switchOffTimingErrorSamples(seedIndices)))<1e-9;
assert(offRegressionPassed,'type1:R14OffRegression', ...
    'Regenerated switch-off acquisition does not match accepted R13 per-seed data.');
names=["switchOff" "idealSwitchOn" "impairedSwitchOn"];
matrix=[regeneratedOff ideal impaired]; counts=sum(matrix,1); rate=counts/numel(seeds);
[low,high]=wilson_interval(counts,numel(seeds),.05);
[structureRescue,structureLoss,structureP]=paired_test(ideal,regeneratedOff);
[impairmentRescue,impairmentLoss,impairmentP]=paired_test(impaired,ideal);
[totalRescue,totalLoss,totalP]=paired_test(impaired,regeneratedOff);
report=struct('profile',profile,'priorR13File',priorFile,'seeds',seeds, ...
    'armNames',names,'success',matrix,'successCount',counts,'successRate',rate, ...
    'wilson95Low',low,'wilson95High',high,'timingToleranceSamples', ...
    max(p.ofdmInfo.CyclicPrefixLengths),'regeneratedOffTimingErrorSamples',offTiming, ...
    'idealTimingErrorSamples',idealTiming,'regeneratedOffNid2',offNid2, ...
    'idealNid2',idealNid2,'offRegressionPassed',offRegressionPassed, ...
    'structureCostPercentagePoints',100*(rate(1)-rate(2)), ...
    'structureOffRescuesOverIdeal',structureRescue,'structureOffLossesVsIdeal',structureLoss, ...
    'structureMcnemarP',structureP, ...
    'impairmentCostPercentagePoints',100*(rate(2)-rate(3)), ...
    'idealRescuesOverImpaired',impairmentRescue,'idealLossesVsImpaired',impairmentLoss, ...
    'impairmentMcnemarP',impairmentP, ...
    'totalCostPercentagePoints',100*(rate(1)-rate(3)), ...
    'offRescuesOverImpaired',totalRescue,'offLossesVsImpaired',totalLoss, ...
    'totalMcnemarP',totalP,'interpretationOrder', ...
    ["off-ideal = interleaving structure net cost" ...
     "ideal-impaired = modeled analog impairment net cost"]);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT');if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_r14_switch_attribution_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out);report.outputDir=out;save(fullfile(out,'phase2_r14_switch_attribution.mat'),'report','-v7.3');
fprintf(['R14 switch counts off/ideal/impaired=[%s], structure %.1f pp (%d/%d,p=%.4g), ' ...
    'impairment %.1f pp (%d/%d,p=%.4g), saved: %s\n'],num2str(counts), ...
    report.structureCostPercentagePoints,structureRescue,structureLoss,structureP, ...
    report.impairmentCostPercentagePoints,impairmentRescue,impairmentLoss,impairmentP,out);
end

function [offRx,idealRx,expectedPhase]=make_pair(p,seed,snrDb)
cfg=p.cfg; sim=r13_config(); sim.useSwitchEmulation=false;sim.snrDb=Inf;
sim.prefixSamples=0;sim.suffixSamples=0;p5=p;p5.txWaveform=repmat(p.txWaveform,5,1);
link=type1_offline_link(p5,sim,RandStream('mt19937ar','Seed',seed));
signal=double(link.physicalRx30);signalPower=mean(abs(signal).^2,'all');
noiseStream=RandStream('mt19937ar','Seed',seed+10000);
noise=(randn(noiseStream,size(signal))+1j*randn(noiseStream,size(signal)))/sqrt(2);
amplitude=sqrt(signalPower/10^(snrDb/10));prefix=round(cfg.txSampleRate*cfg.frameDurationSec/20);
frame=round(cfg.frameDurationSec*cfg.txSampleRate);
[~,reference]=type1_pss_complex_correlation(complex(zeros(1,1)),p,mod(cfg.pci,3));
nRef=numel(reference);record=[complex(zeros(prefix,4));signal+amplitude*noise];
offRx=record(1:frame+nRef-1,:);raw=complex(zeros(4*size(offRx,1),4));
for r=1:4,raw(:,r)=resample(offRx(:,r),4,1);end
idealRx=complex(zeros(size(offRx)));
for r=1:4,idealRx(:,r)=raw(r:4:end,r);end
expectedPhase=prefix;
end

function result=detect_pss(rx,p,nSearch)
cfg=p.cfg;carrier=type1_carrier_config(cfg,0);nSC=12*cfg.nRB;rx=double(rx);
for r=1:size(rx,2),scale=rms(rx(:,r));if scale>0,rx(:,r)=rx(:,r)/scale;end,end
bestMetric=-inf;result=struct('peak',0,'nid2',0,'metric',0);
for nid2=0:2
    ssb=complex(zeros(240,4));ssb(nrPSSIndices)=nrPSS(nid2);
    grid=complex(zeros(nSC,cfg.symbolsPerSlot));grid(p.ssbSubcarriers,p.ssbSymbols)=ssb;
    [~,magnitude]=nrTimingEstimate(carrier,rx,grid,'Nfft',cfg.nfft, ...
        'SampleRate',cfg.txSampleRate,'CarrierFrequency',0);
    power=sum(abs(magnitude(1:nSearch,:)).^2,2);
    [metric,peakIndex]=max(power);
    if metric>bestMetric
        bestMetric=metric;result=struct('peak',peakIndex-1,'nid2',nid2,'metric',metric);
    end
end
end

function [rescue,loss,p]=paired_test(candidate,reference)
rescue=sum(~candidate & reference);loss=sum(candidate & ~reference);p=mcnemar_exact(rescue,loss);
end

function p=mcnemar_exact(a,b)
n=a+b;if n==0,p=1;return;end;m=min(a,b);term=2^(-n);cumulative=term;
for k=1:m,term=term*(n-k+1)/k;cumulative=cumulative+term;end
p=min(1,2*cumulative);
end

function [low,high]=wilson_interval(count,n,alpha)
z=-sqrt(2)*erfcinv(2*(1-alpha/2));phat=count/n;denominator=1+z^2/n;
centre=(phat+z^2/(2*n))/denominator;
half=z*sqrt(phat.*(1-phat)/n+z^2/(4*n^2))/denominator;
low=max(0,centre-half);high=min(1,centre+half);
end

function value=wrap_error(value,frame)
value=mod(value+frame/2,frame)-frame/2;
end

function s=r13_config()
s=type1_offline_multiuser_config();s.frames=1;s.snrDb=20;s.channelModel="tdl-a";
s.userCfoHz=.5*s.userCfoHz;s.tdl.delaySpreadNs=100;s.tdl.dopplerHz=0;
s.tdl.rxCorrelation=.3;s.tdl.txCorrelation=.3;s.userTimingSamples=min(max(s.userTimingSamples,-4),4);
s.switch.isolationDb=25;s.switch.settlingRiseNs=20;s.switch.transitionJitterStdPs=20;
s.switch.samplingBoundaryJitterStdPs=100;s.switch.settlingFastJitterStdFraction=0;
s.switch.settlingFastJitterCorrelationSec=1e-6;s.switch.recordTimeSeries=false;s.rxLo.mode="off";
end
