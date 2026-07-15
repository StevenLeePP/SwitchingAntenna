function report = type1_run_phase2_full_stack_pilot()
%TYPE1_RUN_PHASE2_FULL_STACK_PILOT R8 L0--L3 integration/outage gate.
%   Statistical unit: an independently drawn TDL-A channel seed.  No SDR
%   hardware is accessed.  The function never promotes itself to paper mode;
%   report.goNoGo must be true before a separate paper run is authorized.

profile=lower(string(getenv('TYPE1_R7_PROFILE'))); if strlength(profile)==0, profile="pilot"; end
switch profile
    case "smoke", channelSeeds=20261001; targetErrors=1;
    case "pilot", channelSeeds=20261001:20261008; targetErrors=100;
    case "paper", channelSeeds=20261001:20261008; targetErrors=10000;
    otherwise, error('type1:R7Profile','TYPE1_R7_PROFILE must be smoke, pilot, or paper.');
end
p=type1_load_package(); scenario=lower(string(getenv('TYPE1_R8_SCENARIO')));
if strlength(scenario)==0, scenario="main"; end
[s0,s1]=full_stack_configs(scenario); nSeed=numel(channelSeeds);
ber=nan(nSeed,4); errors=nan(nSeed,4); cfo=nan(nSeed,4,p.cfg.nLayers);
errorsByLayer=nan(nSeed,4,p.cfg.nLayers); conditionStats=nan(nSeed,4,3);
iqRelativeError=nan(nSeed,1); invariant=false(nSeed,1); kernelOffCenter=nan(nSeed,1);
status=strings(nSeed,1); failure=strings(nSeed,1); failureClass=strings(nSeed,1);
timingOffset=nan(nSeed,1); timingError=nan(nSeed,1); pssPeakIndices=nan(nSeed,3);
pssMetrics=nan(nSeed,3); nid2Correct=false(nSeed,1); pbchCRCError=true(nSeed,1);
timingTolerance=max(p.ofdmInfo.CyclicPrefixLengths);
bitsPerSeed=numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers;
for k=1:nSeed
    seed=channelSeeds(k); status(k)="running";
    try
        l0=type1_offline_link(p,s0,RandStream('mt19937ar','Seed',seed));
        l1=type1_offline_link(p,s1,RandStream('mt19937ar','Seed',seed));
        r0=type1_analyze_user_cfo(l0.virtualRx30,p,true);
        r1=type1_analyze_user_cfo(l1.virtualRx30,p,true);
        r2=type1_analyze_ici_decision_feedback(l1.virtualRx30,p,12,3,'soft',true,true);
        v3=type1_genie_replace_settling(l1.stitched122,l1.switchMeta.settlingBeta, ...
            l0.switchMeta.settlingBeta);
        r3=type1_analyze_user_cfo(v3,p,true);
        timingOffset(k)=r0.base.timingOffset;
        timingError(k)=wrap_frame_offset(timingOffset(k)-s0.prefixSamples,p.cfg);
        pssPeakIndices(k,:)=r0.base.pssPeakIndices(:).';
        pssMetrics(k,:)=r0.base.pssMetrics(:).';
        nid2Correct(k)=r0.base.bestNID2==r0.base.expectedNID2;
        pbchCRCError(k)=r0.base.pbchCRCError;
        each={r0 r1 r2 r3};
        for level=1:4
            errorsByLayer(k,level,:)=sum(each{level}.infoBitErrors,1);
            errors(k,level)=sum(each{level}.infoBitErrors,'all');
            ber(k,level)=errors(k,level)/bitsPerSeed;
            cfo(k,level,:)=each{level}.residualCfoHz;
            conditionStats(k,level,:)=each{level}.estimatedConditionStats;
        end
        iqRelativeError(k)=norm(double(v3(:))-double(l0.virtualRx30(:)))/max(norm(double(l0.virtualRx30(:))),eps);
        invariant(k)=iqRelativeError(k)<1e-5 && isequal(r3.infoBitErrors,r0.infoBitErrors);
        kernelOffCenter(k)=off_center_energy(r2.kernel);
        if ber(k,1)>.10
            status(k)="outageL0";
            if abs(timingError(k))>timingTolerance || ~nid2Correct(k)
                failureClass(k)="falsePssPeak";
            elseif pbchCRCError(k)
                failureClass(k)="pbchFailure";
            else
                failureClass(k)="postAcquisitionDecodeOutage";
            end
        else
            status(k)="ok";
        end
    catch err
        status(k)="acquisitionFailure"; failure(k)=string(err.identifier)+": "+string(err.message);
        if strcmp(err.identifier,'type1:IncompleteFrame') && s0.suffixSamples>=round(p.cfg.frameDurationSec*p.cfg.txSampleRate)
            failureClass(k)="falsePssPeak";
        else
            failureClass(k)="windowOrReceiverFailure";
        end
    end
end
acquired=status=="ok" | status=="outageL0"; valid=status=="ok";
invariantOnValid=all(invariant(acquired)); allSeedsValid=all(valid); allInvariant=invariantOnValid;
summary=level_summary(ber(valid,:),20261099,2000);
gap=nan(nSeed,1); denom=ber(:,2)-ber(:,4); usable=valid & denom>0;
gap(usable)=(ber(usable,2)-ber(usable,3))./denom(usable);
gapSummary=scalar_summary(gap(usable),20261100,2000);
enoughErrors=sum(errors(valid,2))>=targetErrors && sum(errors(valid,3))>=targetErrors;
ciNonOverlap=summary.ci95(3,2)<summary.ci95(2,1); % upper(L2) < lower(L1)
goNoGo=allInvariant && nnz(valid)>=5 && enoughErrors && summary.median(3)<summary.median(2) && ...
    ciNonOverlap && gapSummary.median>=.30;
report=struct('profile',profile,'scenario',scenario,'channelSeeds',channelSeeds,'targetErrors',targetErrors, ...
    'simL0',s0,'simL1',s1,'levelNames',["L0" "L1" "L2" "L3"], ...
    'bitsPerSeed',bitsPerSeed,'status',status,'failure',failure,'failureClass',failureClass, ...
    'acquisitionTimingToleranceSamples',timingTolerance, ...
    'timingOffset',timingOffset,'timingErrorFromKnownPrefixSamples',timingError, ...
    'pssPeakIndices',pssPeakIndices,'pssMetrics',pssMetrics, ...
    'nid2Correct',nid2Correct,'pbchCRCError',pbchCRCError, ...
    'errors',errors,'ber',ber, ...
    'errorsByLayer',errorsByLayer,'conditionStats',conditionStats,'residualCfoHz',cfo, ...
    'iqRelativeErrorL3L0',iqRelativeError,'invariant',invariant, ...
    'kernelOffCenterEnergyFraction',kernelOffCenter,'summary',summary,'gapClosure',gap, ...
    'gapSummary',gapSummary,'enoughErrors',enoughErrors,'ciNonOverlap',ciNonOverlap, ...
    'validSeeds',channelSeeds(valid),'allSeedsValid',allSeedsValid, ...
    'outageSeeds',channelSeeds(~valid),'outageRate',nnz(~valid)/nSeed, ...
    'l0OutageSeeds',channelSeeds(status=="outageL0"), ...
    'acquisitionFailureSeeds',channelSeeds(status=="acquisitionFailure"), ...
    'invariantOnValid',invariantOnValid,'allInvariant',allInvariant,'goNoGo',goNoGo, ...
    'diagnosticOrder',["kernel-CFO energy" "channel-estimation residual" "deep-fade subcarrier errors"]);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_full_stack_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_full_stack.mat'),'report','-v7.3');
print_report(report); fprintf('R8 full-stack result saved: %s\n',out);
end

function value=wrap_frame_offset(value,cfg)
frame=round(cfg.frameDurationSec*cfg.txSampleRate);
value=mod(value+frame/2,frame)-frame/2;
end

function [s0,s1]=full_stack_configs(scenario)
s0=type1_offline_multiuser_config(); s0.frames=1; s0.snrDb=20; s0.channelModel="tdl-a";
s0.userCfoHz=.5*s0.userCfoHz; % Keep the TDL integration point inside the measured +/-1 kHz estimator range.
s0.tdl.delaySpreadNs=100; s0.tdl.dopplerHz=0;
switch scenario
    case "main"
        s0.tdl.rxCorrelation=.3; s0.tdl.txCorrelation=.3;
        s0.userTimingSamples=min(max(s0.userTimingSamples,-4),4);
    case "stress"
        s0.tdl.rxCorrelation=.5; s0.tdl.txCorrelation=.5;
    otherwise
        error('type1:R8Scenario','TYPE1_R8_SCENARIO must be main or stress.');
end
s0.switch.isolationDb=25; s0.switch.settlingRiseNs=20;
s0.switch.transitionJitterStdPs=20; s0.switch.samplingBoundaryJitterStdPs=100;
s0.switch.settlingFastJitterStdFraction=0; s0.switch.settlingFastJitterCorrelationSec=1e-6;
s0.switch.recordTimeSeries=true; s1=s0;
% R8 main is the recoverable integration point.  The pre-existing R6
% envelope showed fast=0.2 below the BER-sensitive knee; fast=0.6 remains
% the registered stress point and is not diluted by this main-scene choice.
if scenario=="main", s1.switch.settlingFastJitterStdFraction=.2;
else, s1.switch.settlingFastJitterStdFraction=.6; end
cfg=type1_config(); s0.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s0.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
s1.prefixSamples=s0.prefixSamples; s1.suffixSamples=s0.suffixSamples;
end

function fraction=off_center_energy(kernel)
q=(size(kernel,1)-1)/2; power=abs(kernel).^2; center=sum(power(q+1,:,:),'all','omitnan');
fraction=(sum(power,'all','omitnan')-center)/max(sum(power,'all','omitnan'),eps);
end

function summary=level_summary(values,seed,nBoot)
summary=struct('median',nan(1,4),'range',nan(4,2),'ci95',nan(4,2));
if isempty(values), return; end
for level=1:4
    x=values(:,level); summary.median(level)=median(x);
    summary.range(level,:)=[min(x) max(x)]; summary.ci95(level,:)=bootstrap_ci(x,seed+level,nBoot);
end
end

function summary=scalar_summary(x,seed,nBoot)
if isempty(x), summary=struct('median',NaN,'range',[NaN NaN],'ci95',[NaN NaN]); return; end
summary=struct('median',median(x),'range',[min(x) max(x)],'ci95',bootstrap_ci(x,seed,nBoot));
end

function ci=bootstrap_ci(x,seed,nBoot)
n=numel(x); stream=RandStream('mt19937ar','Seed',seed); boot=zeros(nBoot,1);
for b=1:nBoot, boot(b)=median(x(randi(stream,n,n,1))); end
boot=sort(boot); ci=boot([max(1,round(.025*nBoot)) min(nBoot,round(.975*nBoot))]).';
end

function print_report(r)
for k=1:numel(r.channelSeeds)
    fprintf('seed=%d status=%s class=%s timingErr=%.1f BER L0/L1/L2/L3=[%s] gap=%.3g iqNMSE=%.3g kernelOff=%.3g\n', ...
        r.channelSeeds(k),r.status(k),r.failureClass(k),r.timingErrorFromKnownPrefixSamples(k), ...
        num2str(r.ber(k,:),'%.4g '),r.gapClosure(k), ...
        r.iqRelativeErrorL3L0(k),r.kernelOffCenterEnergyFraction(k));
end
fprintf('median=[%s], gap median=%.3g CI=[%s], invariant=%d errors=%d CIsep=%d GO=%d\n', ...
    num2str(r.summary.median,'%.4g '),r.gapSummary.median,num2str(r.gapSummary.ci95,'%.3g '), ...
    r.allInvariant,r.enoughErrors,r.ciNonOverlap,r.goNoGo);
end
