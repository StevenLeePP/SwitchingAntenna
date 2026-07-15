function report = type1_run_phase2_pss_acquisition_statistics()
%TYPE1_RUN_PHASE2_PSS_ACQUISITION_STATISTICS R13 paired P_acq(SNR).
%   This is acquisition-only: it does not run PBCH, channel estimation,
%   equalization, or BER decoding.  A fixed five-frame TDL realization is
%   reused across SNR, while noise and switch jitter remain independent
%   over the four accumulated frames.

validation=type1_validate_pss_acquisition();
p=type1_load_package(); cfg=p.cfg; profile=lower(string(getenv('TYPE1_R13_PROFILE')));
if strlength(profile)==0, profile="paper"; end
switch profile
    case "paper"
        seeds=20262001:20262100;
        snrDb=[-20 -16 -12 -8 -6 -4 0 8 14 20 26];
    case "smoke"
        seeds=20262001:20262004; snrDb=[-12 -8 20];
    otherwise
        error('type1:R13Profile','TYPE1_R13_PROFILE must be paper or smoke.');
end
arms=["combined1" "vote1" "accum2" "accum4"];
frameCounts=[1 1 2 4]; candidateArms=2:4;
nSeed=numel(seeds); nSnr=numel(snrDb); nArm=numel(arms);
success=false(nSeed,nSnr,nArm); timingError=nan(nSeed,nSnr,nArm);
detectedNid2=nan(nSeed,nSnr,nArm); peakMetric=nan(nSeed,nSnr,nArm);
truthPmrDb=nan(nSeed,nSnr,nArm); failureCode=zeros(nSeed,nSnr,nArm,'uint8');
voteUsedFallback=false(nSeed,nSnr); switchOff20Success=false(nSeed,1);
switchOff20TimingError=nan(nSeed,1); switchOff20Nid2=nan(nSeed,1);
tolerance=max(p.ofdmInfo.CyclicPrefixLengths); expectedNid2=mod(cfg.pci,3);
pmrThresholdDb=cfg.fastPSSMinPeakToMedianDb;

root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_pss_acquisition_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out);
for seedIndex=1:nSeed
    seed=seeds(seedIndex); basis=make_frame_basis(p,seed);
    nFrame=round(cfg.frameDurationSec*cfg.txSampleRate);
    nRef=basis.referenceLength; amplitudes=sqrt(basis.signalPower./10.^(snrDb/10));
    bestMetric=-inf(nSnr,nArm); bestPhase=zeros(nSnr,nArm); bestNid=zeros(nSnr,nArm);
    chainBestMetric=-inf(nSnr,4); chainBestPhase=zeros(nSnr,4); chainBestNid=zeros(nSnr,4);
    pmrCombined=nan(nSnr,3); pmrChains=nan(nSnr,4);
    offBestMetric=-inf; offBestPhase=0; offBestNid=0;
    for nid2=0:2
        cumulativeOn=zeros(nFrame,4,3); cumulativeOff=zeros(nFrame,4,3);
        cumulativeMomentsOn=zeros(4,3); cumulativeMomentsOff=zeros(4,3);
        snapshotIndex=0;
        for repetition=1:4
            onPair=[basis.onSignal{repetition} basis.onNoise{repetition}];
            onCorr=type1_pss_complex_correlation(onPair,p,nid2);
            [onComponent,onMoment]=correlation_components(onCorr(:,1:4), ...
                onCorr(:,5:8),basis.onSignal{repetition},basis.onNoise{repetition},nFrame,nRef);
            cumulativeOn=cumulativeOn+onComponent;
            cumulativeMomentsOn=cumulativeMomentsOn+onMoment;
            if repetition==1
                offPair=[basis.offSignal{repetition} basis.offNoise{repetition}];
                offCorr=type1_pss_complex_correlation(offPair,p,nid2);
                [offComponent,offMoment]=correlation_components(offCorr(:,1:4), ...
                    offCorr(:,5:8),basis.offSignal{repetition},basis.offNoise{repetition},nFrame,nRef);
                cumulativeOff=cumulativeOff+offComponent;
                cumulativeMomentsOff=cumulativeMomentsOff+offMoment;
            end
            if any(repetition==[1 2 4])
                snapshotIndex=snapshotIndex+1;
                arm=([1 3 4]); arm=arm(snapshotIndex);
                for level=1:nSnr
                    chainCurve=scaled_curve(cumulativeOn,cumulativeMomentsOn, ...
                        amplitudes(level),repetition);
                    combinedCurve=sum(chainCurve,2);
                    [metric,phase]=max(combinedCurve);
                    if metric>bestMetric(level,arm)
                        bestMetric(level,arm)=metric; bestPhase(level,arm)=phase-1;
                        bestNid(level,arm)=nid2;
                    end
                    if repetition==1
                        for r=1:4
                            [chainMetric,chainPhase]=max(chainCurve(:,r));
                            if chainMetric>chainBestMetric(level,r)
                                chainBestMetric(level,r)=chainMetric;
                                chainBestPhase(level,r)=chainPhase-1; chainBestNid(level,r)=nid2;
                            end
                        end
                    end
                    if nid2==expectedNid2
                        pmrCombined(level,snapshotIndex)=truth_pmr(combinedCurve, ...
                            basis.expectedPhase,tolerance);
                        if repetition==1
                            for r=1:4
                                pmrChains(level,r)=truth_pmr(chainCurve(:,r), ...
                                    basis.expectedPhase,tolerance);
                            end
                        end
                    end
                end
                if repetition==1
                    offCurve=scaled_curve(cumulativeOff,cumulativeMomentsOff, ...
                        sqrt(basis.signalPower/10^(20/10)),1);
                    offCombined=sum(offCurve,2); [metric,phase]=max(offCombined);
                    if metric>offBestMetric
                        offBestMetric=metric; offBestPhase=phase-1; offBestNid=nid2;
                    end
                end
            end
        end
    end
    for level=1:nSnr
        % Vote requires a same-NID2, circularly consistent >=2-chain cluster.
        combinedError=wrap_error(bestPhase(level,1)-basis.expectedPhase,nFrame);
        chainErrors=wrap_error(chainBestPhase(level,:)-basis.expectedPhase,nFrame);
        [voteError,voteNid,voteFallback,voteMetric]=vote_peaks(chainErrors, ...
            chainBestNid(level,:),chainBestMetric(level,:),combinedError, ...
            bestNid(level,1),bestMetric(level,1),tolerance,nFrame);
        bestMetric(level,2)=voteMetric; bestPhase(level,2)=mod(voteError+basis.expectedPhase,nFrame);
        bestNid(level,2)=voteNid; voteUsedFallback(seedIndex,level)=voteFallback;
        truthPmrDb(seedIndex,level,1)=pmrCombined(level,1);
        sortedPmr=sort(pmrChains(level,:),'descend'); truthPmrDb(seedIndex,level,2)=sortedPmr(2);
        truthPmrDb(seedIndex,level,3)=pmrCombined(level,2);
        truthPmrDb(seedIndex,level,4)=pmrCombined(level,3);
        for arm=1:nArm
            timingError(seedIndex,level,arm)=wrap_error( ...
                bestPhase(level,arm)-basis.expectedPhase,nFrame);
            detectedNid2(seedIndex,level,arm)=bestNid(level,arm);
            peakMetric(seedIndex,level,arm)=bestMetric(level,arm);
            success(seedIndex,level,arm)=abs(timingError(seedIndex,level,arm))<=tolerance && ...
                bestNid(level,arm)==expectedNid2;
            failureCode(seedIndex,level,arm)=classify_failure(success(seedIndex,level,arm), ...
                basis.truthWindowAvailable,truthPmrDb(seedIndex,level,arm),pmrThresholdDb);
        end
    end
    switchOff20TimingError(seedIndex)=wrap_error(offBestPhase-basis.expectedPhase,nFrame);
    switchOff20Nid2(seedIndex)=offBestNid;
    switchOff20Success(seedIndex)=abs(switchOff20TimingError(seedIndex))<=tolerance && ...
        offBestNid==expectedNid2;
    fprintf('R13 %s seed %d (%d/%d): success@20dB on=[%s], off=%d\n',profile,seed, ...
        seedIndex,nSeed,num2str(squeeze(success(seedIndex,snrDb==20,:)).','%d '), ...
        switchOff20Success(seedIndex));
    save(fullfile(out,'phase2_pss_acquisition_checkpoint.mat'),'seeds','snrDb','arms', ...
        'success','timingError','detectedNid2','truthPmrDb','failureCode', ...
        'voteUsedFallback','switchOff20Success','switchOff20TimingError', ...
        'switchOff20Nid2','seedIndex','-v7.3');
end

successCount=reshape(sum(success,1),nSnr,nArm); successRate=successCount/nSeed;
[wilsonLow,wilsonHigh]=wilson_interval(successCount,nSeed,.05);
failureNames=["none" "falsePeak" "miss" "windowClip"];
failureCounts=zeros(nSnr,nArm,3);
for code=1:3, failureCounts(:,:,code)=reshape(sum(failureCode==code,1),nSnr,nArm); end
rescues=zeros(nSnr,numel(candidateArms)); losses=rescues; mcnemarP=ones(size(rescues));
for level=1:nSnr
    base=success(:,level,1);
    for c=1:numel(candidateArms)
        candidate=success(:,level,candidateArms(c));
        rescues(level,c)=sum(~base & candidate); losses(level,c)=sum(base & ~candidate);
        mcnemarP(level,c)=mcnemar_exact(rescues(level,c),losses(level,c));
    end
end
level20=find(snrDb==20,1); on20=success(:,level20,1);
switchRescues=sum(~on20 & switchOff20Success); switchLosses=sum(on20 & ~switchOff20Success);
switchMcnemarP=mcnemar_exact(switchRescues,switchLosses);
report=struct('profile',profile,'seeds',seeds,'snrDb',snrDb,'detectorNames',arms, ...
    'frameCounts',frameCounts,'success',success,'successCount',successCount, ...
    'successRate',successRate,'wilson95Low',wilsonLow,'wilson95High',wilsonHigh, ...
    'timingErrorSamples',timingError,'detectedNid2',detectedNid2, ...
    'peakMetric',peakMetric,'truthPmrDb',truthPmrDb,'pmrThresholdDb',pmrThresholdDb, ...
    'failureCode',failureCode,'failureCodeLegend',failureNames,'failureCounts',failureCounts, ...
    'voteUsedFallback',voteUsedFallback,'pairedCandidateNames',arms(candidateArms), ...
    'pairedRescues',rescues,'pairedLosses',losses,'mcnemarTwoSidedExactP',mcnemarP, ...
    'significantImprovement',rescues>losses & mcnemarP<.05, ...
    'switchCompareSnrDb',20,'switchOnSuccess',on20,'switchOffSuccess',switchOff20Success, ...
    'switchOffTimingErrorSamples',switchOff20TimingError,'switchOffNid2',switchOff20Nid2, ...
    'switchOffRescuesOverOn',switchRescues,'switchOffLossesVsOn',switchLosses, ...
    'switchOnOffMcnemarP',switchMcnemarP,'timingToleranceSamples',tolerance, ...
    'expectedNid2',expectedNid2,'validation',validation,'simTemplate',r13_config(), ...
    'outputDir',out,'acquisitionOnly',true,'fullDecodeExecuted',false);
save(fullfile(out,'phase2_pss_acquisition.mat'),'report','-v7.3');
plot_probability(report,fullfile(out,'phase2_pss_acquisition_probability.png'));
plot_plateau_failures(report,fullfile(out,'phase2_pss_plateau_failures.png'));
fprintf('R13 completed: %s\n',out);
disp(array2table([snrDb(:) successCount], ...
    'VariableNames',["snrDb" cellstr(matlab.lang.makeValidName(arms))]));
end

function basis=make_frame_basis(p,seed)
cfg=p.cfg; sim=r13_config(); sim.useSwitchEmulation=false; sim.snrDb=Inf;
sim.prefixSamples=0; sim.suffixSamples=0;
p5=p; p5.txWaveform=repmat(p.txWaveform,5,1);
link=type1_offline_link(p5,sim,RandStream('mt19937ar','Seed',seed));
physicalSignal=double(link.physicalRx30); signalPower=mean(abs(physicalSignal).^2,'all');
noiseStream=RandStream('mt19937ar','Seed',seed+10000);
physicalNoise=(randn(noiseStream,size(physicalSignal))+1j*randn(noiseStream,size(physicalSignal)))/sqrt(2);
prefix=round(cfg.txSampleRate*cfg.frameDurationSec/20); frame=round(cfg.frameDurationSec*cfg.txSampleRate);
[~,reference]=type1_pss_complex_correlation(complex(zeros(1,1)),p,mod(cfg.pci,3));
nRef=numel(reference); recordSignal=[complex(zeros(prefix,4));physicalSignal];
recordNoise=[complex(zeros(prefix,4));physicalNoise]; warmup=round(frame/20);
onSignal=cell(1,4); onNoise=cell(1,4); offSignal=cell(1,4); offNoise=cell(1,4);
for repetition=1:4
    first=(repetition-1)*frame+1; desired=(first:first+frame+nRef-2).';
    offSignal{repetition}=single(recordSignal(desired,:));
    offNoise{repetition}=single(recordNoise(desired,:));
    pre=max(1,first-warmup); withWarmup=(pre:first+frame+nRef-2).'; discard=first-pre;
    signal30=recordSignal(withWarmup,:); noise30=recordNoise(withWarmup,:);
    rawSignal=complex(zeros(4*size(signal30,1),4)); rawNoise=complex(zeros(size(rawSignal)));
    for r=1:4
        rawSignal(:,r)=resample(signal30(:,r),4,1);
        rawNoise(:,r)=resample(noise30(:,r),4,1);
    end
    switchSeed=seed+20000+repetition;
    [~,virtualSignal]=type1_apply_switch_impairments(rawSignal,sim.switch, ...
        RandStream('mt19937ar','Seed',switchSeed));
    clear rawSignal
    [~,virtualNoise]=type1_apply_switch_impairments(rawNoise,sim.switch, ...
        RandStream('mt19937ar','Seed',switchSeed));
    clear rawNoise
    take=discard+(1:frame+nRef-1);
    onSignal{repetition}=single(virtualSignal(take,:));
    onNoise{repetition}=single(virtualNoise(take,:));
end
basis=struct('onSignal',{onSignal},'onNoise',{onNoise},'offSignal',{offSignal}, ...
    'offNoise',{offNoise},'signalPower',signalPower,'expectedPhase',prefix, ...
    'referenceLength',nRef,'truthWindowAvailable',true);
end

function [component,moment]=correlation_components(signalCorr,noiseCorr,signal,noise,nFrame,nRef)
signalCorr=signalCorr(1:nFrame,:); noiseCorr=noiseCorr(1:nFrame,:);
component=zeros(nFrame,4,3);
component(:,:,1)=abs(signalCorr).^2; component(:,:,2)=abs(noiseCorr).^2;
component(:,:,3)=2*real(signalCorr.*conj(noiseCorr));
nUse=nFrame+nRef-1; signal=double(signal(1:nUse,:)); noise=double(noise(1:nUse,:));
moment=[mean(abs(signal).^2,1).' mean(abs(noise).^2,1).' ...
    2*real(mean(signal.*conj(noise),1)).'];
end

function curve=scaled_curve(component,moments,amplitude,repetitions)
scale2=(moments(:,1)+amplitude^2*moments(:,2)+amplitude*moments(:,3))/repetitions;
curve=component(:,:,1)+amplitude^2*component(:,:,2)+amplitude*component(:,:,3);
curve=max(curve,0)./reshape(max(scale2,eps),1,[]);
end

function value=truth_pmr(curve,expected,tolerance)
n=numel(curve); phase=(0:n-1).'; distance=abs(mod(phase-expected+n/2,n)-n/2);
truth=max(curve(distance<=tolerance)); background=median(curve(distance>tolerance));
value=10*log10(max(truth,realmin)/max(background,realmin));
end

function code=classify_failure(isSuccess,windowAvailable,pmr,threshold)
if isSuccess, code=uint8(0);
elseif ~windowAvailable, code=uint8(3);
elseif pmr<threshold, code=uint8(2);
else, code=uint8(1);
end
end

function [selectedError,selectedNid2,usedFallback,selectedMetric]=vote_peaks( ...
    errors,nid2,metric,combinedError,combinedNid2,combinedMetric,tolerance,frame)
bestScore=-inf; bestCluster=[];
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
    selectedMetric=combinedMetric;
else
    [selectedMetric,local]=max(metric(bestCluster)); chosen=bestCluster(local);
    selectedError=errors(chosen); selectedNid2=nid2(chosen); usedFallback=false;
end
end

function value=wrap_error(value,frame)
value=mod(value+frame/2,frame)-frame/2;
end

function [low,high]=wilson_interval(count,n,alpha)
z=-sqrt(2)*erfcinv(2*(1-alpha/2)); phat=count/n; denominator=1+z^2/n;
centre=(phat+z^2/(2*n))/denominator;
half=z*sqrt(phat.*(1-phat)/n+z^2/(4*n^2))/denominator;
low=max(0,centre-half); high=min(1,centre+half);
end

function p=mcnemar_exact(rescued,lost)
n=rescued+lost; if n==0, p=1; return; end
m=min(rescued,lost); term=2^(-n); cumulative=term;
for k=1:m, term=term*(n-k+1)/k; cumulative=cumulative+term; end
p=min(1,2*cumulative);
end

function plot_probability(report,path)
f=figure('Visible','off','Color','w'); hold on; colours=lines(numel(report.detectorNames));
for arm=1:numel(report.detectorNames)
    y=report.successRate(:,arm); lo=y-report.wilson95Low(:,arm); hi=report.wilson95High(:,arm)-y;
    errorbar(report.snrDb,y,lo,hi,'-o','LineWidth',1.4,'Color',colours(arm,:), ...
        'DisplayName',char(report.detectorNames(arm)));
end
grid on; ylim([0 1.03]); xlabel('SNR (dB)'); ylabel('P_{acq}');
title('R13 PSS acquisition: noise waterfall and high-SNR plateau'); legend('Location','southeast');
exportgraphics(f,path,'Resolution',180); close(f);
end

function plot_plateau_failures(report,path)
indices=find(ismember(report.snrDb,[14 20 26]));
data=squeeze(sum(report.failureCounts(indices,[1 4],:),1));
f=figure('Visible','off','Color','w'); bar(data,'stacked'); grid on;
xticklabels({'combined1','accum4'}); ylabel('Failures across 14/20/26 dB and seeds');
legend({'falsePeak','miss','windowClip'},'Location','northoutside','Orientation','horizontal');
title('R13 high-SNR failure composition'); exportgraphics(f,path,'Resolution',180); close(f);
end

function s=r13_config()
s=type1_offline_multiuser_config(); s.frames=1; s.snrDb=20; s.channelModel="tdl-a";
s.userCfoHz=.5*s.userCfoHz; s.tdl.delaySpreadNs=100; s.tdl.dopplerHz=0;
s.tdl.rxCorrelation=.3; s.tdl.txCorrelation=.3;
s.userTimingSamples=min(max(s.userTimingSamples,-4),4);
s.switch.isolationDb=25; s.switch.settlingRiseNs=20;
s.switch.transitionJitterStdPs=20; s.switch.samplingBoundaryJitterStdPs=100;
s.switch.settlingFastJitterStdFraction=0; s.switch.settlingFastJitterCorrelationSec=1e-6;
s.switch.recordTimeSeries=false; cfg=type1_config();
s.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec); s.rxLo.mode="off";
end
