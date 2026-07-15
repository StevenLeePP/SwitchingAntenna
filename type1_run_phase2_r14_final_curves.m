function report = type1_run_phase2_r14_final_curves()
%TYPE1_RUN_PHASE2_R14_FINAL_CURVES Paper-stop TDL averages and boundary plot.
%   The conditional BER denominator contains only seeds for which standard
%   and DF both acquire/decode.  Every attempted acquisition failure remains
%   in the outage statistics; successful seeds are never silently selected.

profile=lower(string(getenv('TYPE1_R14_PROFILE')));if strlength(profile)==0,profile="paper";end
[seeds,minValid,targetErrors,maxBits,snrGrid,envelopeSpec]=profile_spec(profile);
p=type1_load_package();base=isolated_tdl_config();bitsPerSeed= ...
    numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers;
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT');if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_r14_final_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out);

base.snrDb=20;base.switch.settlingRiseNs=20;
base.switch.settlingFastJitterStdFraction=.6;
base.switch.settlingFastJitterCorrelationSec=1e-6;base.switch.recordTimeSeries=false;
variants=[make_variant("Q0I1",0,1) make_variant("Q6I1",6,1) ...
    make_variant("Q12I1",12,1) make_variant("Q24I1",24,1) ...
    make_variant("Q12I2",12,2) make_variant("Q12I3",12,3)];
fprintf('R14 %s core Q/iteration group started (%d maximum seeds).\n',profile,numel(seeds));
core=run_group(p,base,variants,seeds,minValid,targetErrors,maxBits,bitsPerSeed,false);
save(fullfile(out,'phase2_r14_checkpoint.mat'),'profile','core','-v7.3');

snrPoints=repmat(empty_result(),1,numel(snrGrid));
for index=1:numel(snrGrid)
    sim=base;sim.snrDb=snrGrid(index);
    point=run_group(p,sim,make_variant("Q12I3",12,3),seeds, ...
        minValid,targetErrors,maxBits,bitsPerSeed,false);
    snrPoints(index)=point(1);
    fprintf('R14 SNR=%g dB valid/attempted=%d/%d BER=[%.4g %.4g] outage=%.3f criterion=%d\n', ...
        snrGrid(index),snrPoints(index).validCount,snrPoints(index).attemptedCount, ...
        snrPoints(index).standardBER,snrPoints(index).dfBER, ...
        snrPoints(index).outageRate,snrPoints(index).paperCriterionMet);
    save(fullfile(out,'phase2_r14_checkpoint.mat'),'profile','core','snrPoints','-v7.3');
end

envelopePoints=repmat(empty_result(),1,numel(envelopeSpec));
for index=1:numel(envelopeSpec)
    sim=base;sim.snrDb=20;sim.switch.recordTimeSeries=true;
    sim.switch.settlingFastJitterStdFraction=envelopeSpec(index).fastFraction;
    sim.switch.settlingFastJitterCorrelationSec=envelopeSpec(index).tauC;
    point=run_group(p,sim,make_variant("Q12I3",12,3),seeds, ...
        minValid,targetErrors,maxBits,bitsPerSeed,true);
    envelopePoints(index)=point(1);
    envelopePoints(index).fastFraction=envelopeSpec(index).fastFraction;
    envelopePoints(index).tauC=envelopeSpec(index).tauC;
    fprintf('R14 envelope fast=%.2f tau=%.3g ns valid=%d BER std/DF/genie=[%.4g %.4g %.4g] criterion=%d\n', ...
        envelopePoints(index).fastFraction,envelopePoints(index).tauC*1e9, ...
        envelopePoints(index).validCount,envelopePoints(index).standardBER, ...
        envelopePoints(index).dfBER,envelopePoints(index).genieBER, ...
        envelopePoints(index).paperCriterionMet);
    save(fullfile(out,'phase2_r14_checkpoint.mat'),'profile','core','snrPoints','envelopePoints','-v7.3');
end

receivedFile=getenv('TYPE1_R14_RECEIVED_MAT');
if isempty(receivedFile)
    receivedFile='/tmp/type1_phase2/type1_phase2_received_drive_20260715_000817/phase2_received_drive.mat';
end
assert(isfile(receivedFile),'type1:R14ReceivedPrior', ...
    'R14 integration-boundary plot requires the accepted R11 received-drive MAT.');
prior=load(receivedFile,'report');receivedPrior=prior.report;
switchFile=getenv('TYPE1_R14_SWITCH_MAT');switchAttribution=[];
if ~isempty(switchFile)
    assert(isfile(switchFile),'type1:R14SwitchPrior','TYPE1_R14_SWITCH_MAT does not exist.');
    priorSwitch=load(switchFile,'report');switchAttribution=priorSwitch.report;
end
report=struct('profile',profile,'seeds',seeds,'minValidRealizations',minValid, ...
    'targetErrorsPerReceiver',targetErrors,'maxConditionalBits',maxBits, ...
    'bitsPerSeed',bitsPerSeed,'isolatedTdlConfig',base,'coreVariants',variants, ...
    'core',core,'snrGridDb',snrGrid,'snrPoints',snrPoints, ...
    'envelopeSpec',envelopeSpec,'envelopePoints',envelopePoints, ...
    'receivedDrivePriorFile',receivedFile,'receivedDrivePrior',receivedPrior, ...
    'switchAttributionFile',switchFile,'switchAttribution',switchAttribution, ...
    'berIsConditionalOnPairedAcquisition',true,'outageDenominatorIsAllAttemptedSeeds',true, ...
    'doesNotReopenBLine',true,'outputDir',out);
resultFile=fullfile(out,'phase2_r14_final.mat');
save(resultFile,'report','-v7.3');
type1_plot_phase2_r14_results(resultFile);
fprintf('R14 final curves completed: %s\n',out);
end

function results=run_group(p,sim,variants,seeds,minValid,targetErrors,maxBits,bitsPerSeed,withGenie)
results=repmat(empty_result(),1,numel(variants));done=false(1,numel(variants));
for v=1:numel(variants)
    results(v).name=variants(v).name;results(v).q=variants(v).q;
    results(v).iterations=variants(v).iterations;results(v).snrDb=sim.snrDb;
end
for k=1:numel(seeds)
    active=find(~done);if isempty(active),break;end
    seed=seeds(k);standard=[];standardFailure="";link=[];
    try
        link=type1_offline_link(p,sim,RandStream('mt19937ar','Seed',seed));
        standard=type1_analyze(link.virtualRx30,p);
    catch err
        standardFailure=string(err.identifier)+": "+string(err.message);
    end
    for v=active
        results(v).attemptedSeeds(end+1)=seed;results(v).attemptedCount=results(v).attemptedCount+1;
        if isempty(standard)
            results(v).failureSeeds(end+1)=seed;
            results(v).failureMessages(end+1)=standardFailure;
            continue;
        end
        try
            df=type1_analyze_ici_decision_feedback(link.virtualRx30,p, ...
                variants(v).q,variants(v).iterations,'soft');
        catch err
            results(v).failureSeeds(end+1)=seed;
            results(v).failureMessages(end+1)=string(err.identifier)+": "+string(err.message);
            continue;
        end
        results(v)=append_pair(results(v),standard,df,seed,bitsPerSeed);
        if withGenie
            try
                genieRx=type1_genie_inverse_settling(link.stitched122,link.switchMeta.settlingBeta);
                genie=type1_analyze(genieRx,p);
                results(v).genieValidSeeds(end+1)=seed;
                results(v).genieErrorsByLayer=results(v).genieErrorsByLayer+sum(genie.infoBitErrors,1);
                results(v).genieEvmPerSeed(end+1)=mean(genie.evmRMSPercent,'all');
            catch err
                results(v).genieFailureSeeds(end+1)=seed;
                results(v).genieFailureMessages(end+1)=string(err.identifier)+": "+string(err.message);
            end
            results(v).tauFloorHitCount=results(v).tauFloorHitCount+link.switchMeta.tauFloorHitCount;
            results(v).tauSampleCount=results(v).tauSampleCount+numel(link.switchMeta.settlingBeta);
        end
        enoughErrors=sum(results(v).standardErrorsByLayer)>=targetErrors && ...
            sum(results(v).dfErrorsByLayer)>=targetErrors;
        enoughBits=results(v).validCount*bitsPerSeed>=maxBits;
        done(v)=results(v).validCount>=minValid && (enoughErrors || enoughBits);
    end
    clear link standard df genie genieRx
end
for v=1:numel(results)
    results(v)=finalize_result(results(v),numel(seeds),targetErrors,maxBits,bitsPerSeed,done(v));
end
end

function result=append_pair(result,standard,df,seed,bitsPerSeed)
result.validSeeds(end+1)=seed;result.validCount=result.validCount+1;
standardErrors=sum(standard.infoBitErrors,1);dfErrors=sum(df.infoBitErrors,1);
result.standardErrorsByLayer=result.standardErrorsByLayer+standardErrors;
result.dfErrorsByLayer=result.dfErrorsByLayer+dfErrors;
result.standardBerPerSeed(end+1)=sum(standardErrors)/bitsPerSeed;
result.dfBerPerSeed(end+1)=sum(dfErrors)/bitsPerSeed;
result.standardEvmPerSeed(end+1)=mean(standard.evmRMSPercent,'all');
result.dfEvmPerSeed(end+1)=mean(df.evmRMSPercent,'all');
if isfield(standard,'estimatedConditionStats')
    result.conditionStatsPerSeed(end+1,:)=standard.estimatedConditionStats;
else
    result.conditionStatsPerSeed(end+1,:)=[NaN NaN NaN];
end
end

function result=finalize_result(result,maxAttempted,targetErrors,maxBits,bitsPerSeed,criterion)
result.conditionalBits=result.validCount*bitsPerSeed;
result.standardBER=sum(result.standardErrorsByLayer)/max(result.conditionalBits,1);
result.dfBER=sum(result.dfErrorsByLayer)/max(result.conditionalBits,1);
result.relativeReduction=(result.standardBER-result.dfBER)/max(result.standardBER,eps);
result.standardMedianBER=median(result.standardBerPerSeed,'omitnan');
result.dfMedianBER=median(result.dfBerPerSeed,'omitnan');
result.standardBerRange=range_or_nan(result.standardBerPerSeed);
result.dfBerRange=range_or_nan(result.dfBerPerSeed);
result.standardMedianEvm=median(result.standardEvmPerSeed,'omitnan');
result.dfMedianEvm=median(result.dfEvmPerSeed,'omitnan');
result.conditionMedian=median(result.conditionStatsPerSeed,1,'omitnan');
result.conditionP95=percentile_rows(result.conditionStatsPerSeed,.95);
result.outageCount=result.attemptedCount-result.validCount;
result.outageRate=result.outageCount/max(result.attemptedCount,1);
[result.outageWilson95Low,result.outageWilson95High]= ...
    wilson_interval(result.outageCount,max(result.attemptedCount,1),.05);
result.paperCriterionMet=criterion;
result.stopByErrors=sum(result.standardErrorsByLayer)>=targetErrors && ...
    sum(result.dfErrorsByLayer)>=targetErrors && result.validCount>0;
result.stopByBits=result.conditionalBits>=maxBits;
result.exhaustedSeedBudget=~criterion && result.attemptedCount>=maxAttempted;
result.standardZeroErrorUpper95=zero_upper(sum(result.standardErrorsByLayer),result.conditionalBits);
result.dfZeroErrorUpper95=zero_upper(sum(result.dfErrorsByLayer),result.conditionalBits);
result.genieConditionalBits=numel(result.genieValidSeeds)*bitsPerSeed;
if result.genieConditionalBits>0
    result.genieBER=sum(result.genieErrorsByLayer)/result.genieConditionalBits;
else
    result.genieBER=NaN;
end
result.genieZeroErrorUpper95=zero_upper(sum(result.genieErrorsByLayer),result.genieConditionalBits);
if result.tauSampleCount>0,result.tauFloorHitFraction=result.tauFloorHitCount/result.tauSampleCount;end
end

function result=empty_result()
result=struct('name',"",'q',NaN,'iterations',NaN,'snrDb',NaN, ...
    'fastFraction',NaN,'tauC',NaN,'attemptedSeeds',[],'attemptedCount',0, ...
    'validSeeds',[],'validCount',0,'failureSeeds',[],'failureMessages',strings(0,1), ...
    'standardErrorsByLayer',zeros(1,4),'dfErrorsByLayer',zeros(1,4), ...
    'standardBerPerSeed',[],'dfBerPerSeed',[],'standardEvmPerSeed',[], ...
    'dfEvmPerSeed',[],'conditionStatsPerSeed',zeros(0,3), ...
    'conditionalBits',0,'standardBER',NaN,'dfBER',NaN,'relativeReduction',NaN, ...
    'standardMedianBER',NaN,'dfMedianBER',NaN,'standardBerRange',[NaN NaN], ...
    'dfBerRange',[NaN NaN],'standardMedianEvm',NaN,'dfMedianEvm',NaN, ...
    'conditionMedian',nan(1,3),'conditionP95',nan(1,3),'outageCount',0, ...
    'outageRate',NaN,'outageWilson95Low',NaN,'outageWilson95High',NaN, ...
    'paperCriterionMet',false,'stopByErrors',false,'stopByBits',false, ...
    'exhaustedSeedBudget',false,'standardZeroErrorUpper95',NaN,'dfZeroErrorUpper95',NaN, ...
    'genieValidSeeds',[],'genieFailureSeeds',[],'genieFailureMessages',strings(0,1), ...
    'genieErrorsByLayer',zeros(1,4),'genieEvmPerSeed',[],'genieConditionalBits',0, ...
    'genieBER',NaN,'genieZeroErrorUpper95',NaN,'tauFloorHitCount',0, ...
    'tauSampleCount',0,'tauFloorHitFraction',NaN);
end

function variant=make_variant(name,q,iterations)
variant=struct('name',name,'q',q,'iterations',iterations);
end

function sim=isolated_tdl_config()
sim=type1_offline_sim_config();sim.frames=1;sim.assertIdealBaseline=false;
sim.channelModel="tdl-a";sim.tdl.delaySpreadNs=100;sim.tdl.dopplerHz=0;
sim.tdl.rxCorrelation=.3;sim.tdl.txCorrelation=.3;sim.userCfoHz=zeros(1,4);
sim.userTimingSamples=zeros(1,4);sim.userPowerDb=zeros(1,4);
sim.userPhaseNoiseStdRadPerSample=zeros(1,4);sim.rxLo.mode="off";
sim.switch.isolationDb=Inf;sim.switch.transitionJitterStdPs=0;
sim.switch.samplingBoundaryJitterStdPs=0;sim.switch.settlingSlowDriftFraction=0;
cfg=type1_config();sim.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
sim.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
end

function [seeds,minValid,target,maxBits,snr,envelope]=profile_spec(profile)
switch profile
    case "smoke"
        seeds=20263001:20263002;minValid=1;target=1;maxBits=636480;
        snr=[-8 20];fast=[0 .6];tau=[0 1e-6];
    case "paper"
        seeds=20263001:20263032;minValid=10;target=100;maxBits=1e7;
        snr=[-12 -10 -8 -4 0 4 8 12 16 20 24];
        fast=[0 .2 .4 .6 .8];tau=[0 8e-9 100e-9 1e-6];
    otherwise
        error('type1:R14Profile','TYPE1_R14_PROFILE must be smoke or paper.');
end
[f,t]=ndgrid(fast,tau);envelope=struct('fastFraction',num2cell(f(:).'), ...
    'tauC',num2cell(t(:).'));
if profile=="paper"
    extraFast=[.5 .7 .75];extra=repmat(struct('fastFraction',0,'tauC',1e-6),1,numel(extraFast));
    for k=1:numel(extraFast),extra(k).fastFraction=extraFast(k);end
    envelope=[envelope extra];
end
end

function value=range_or_nan(x)
if isempty(x),value=[NaN NaN];else,value=[min(x) max(x)];end
end

function value=percentile_rows(x,p)
if isempty(x),value=nan(1,3);return;end
x=sort(x,1);index=max(1,min(size(x,1),ceil(p*size(x,1))));value=x(index,:);
end

function value=zero_upper(errors,bits)
if errors==0 && bits>0,value=-log(.05)/bits;else,value=NaN;end
end

function [low,high]=wilson_interval(count,n,alpha)
z=-sqrt(2)*erfcinv(2*(1-alpha/2));phat=count/n;denominator=1+z^2/n;
centre=(phat+z^2/(2*n))/denominator;
half=z*sqrt(phat.*(1-phat)/n+z^2/(4*n^2))/denominator;
low=max(0,centre-half);high=min(1,centre+half);
end
