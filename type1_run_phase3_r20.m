function report=type1_run_phase3_r20()
%TYPE1_RUN_PHASE3_R20 AMC/acquisition-aware/M-scaling Gate-3 retest.
%   Acquisition uses 50 paired TDL seeds and one-vs-four-frame PSS
%   noncoherent accumulation.  Full decode/EVM uses the first 20 of those
%   seeds.  A frozen CQI-style abstraction converts measured EVM-quality
%   to AMC spectral efficiency; thresholds are also shifted +/-2 dB.

assert(exist('type1_phase3_iir_mex','file')==3,'type1:R20Mex', ...
    'Build type1_phase3_iir_mex.c before the paper run.');
validation=type1_validate_phase3_r20();profile=lower(string(getenv('TYPE1_R20_PROFILE')));
if strlength(profile)==0,profile="paper";end
if profile=="paper"
    nSeeds=50;nDataSeeds=20;
elseif profile=="smoke"
    nSeeds=2;nDataSeeds=2;
else
    error('type1:R20Profile','TYPE1_R20_PROFILE must be paper or smoke.');
end
p=type1_load_package();cfg=p.cfg;model16=type1_phase3_config(16,4);
seeds=20262201+(0:nSeeds-1);snrDb=20;frequency=(-306:305)*cfg.scsKHz*1e3;
searchIndex=6:12:606;armNames=["M4" "M8Data" "M8Aware" "M12Aware" "M16Aware"];
armM=[4 8 8 12 16];scanFrames=[0 1 1 2 3];updateSec=[.05 .1 .2 .5 1 2 5 10];
amc=type1_phase3_amc_table();switchModel=struct('isolationDb',25, ...
    'settlingRiseNs',20,'rawSampleRateHz',cfg.rxSampleRate, ...
    'settlingFastJitterStdFraction',.2,'settlingFastJitterCorrelationSec',1e-6);
preRegistration=struct('reviewTarget',"R20 Gate-3 retest",'profile',profile, ...
    'nAcquisitionSeeds',nSeeds,'nDataSeeds',nDataSeeds,'seedValues',seeds, ...
    'snrDb',snrDb,'mValues',[4 8 12 16],'dmax',1, ...
    'acquisitionFrames',[1 4],'pssGuard',"oracle PSS MRC-SNR >= paired M4", ...
    'amcTable',amc,'scanUpdateSec',updateSec,'scanFrames',scanFrames, ...
    'primaryUpdateSec',1,'primaryThresholdShiftDb',0, ...
    'gateRule',"M12Aware or M16Aware AMC goodput > M4 at 1 s and nominal thresholds", ...
    'switchModel',switchModel,'channelPairing', ...
    "one M16 TDL draw per seed; M4/M8/M12 are leading-port subsets", ...
    'noiseDefinitions',"frequency metric uses mean(sum(abs(H)^2))/SNR; waveform AWGN uses time-domain mean(abs(rx)^2)/SNR");

emptyData=empty_data();data=repmat(emptyData,nDataSeeds,numel(armNames));
acq1=false(nSeeds,numel(armNames));acq4=acq1;acqDetail=cell(nSeeds,numel(armNames));
selection=repmat(struct('seed',nan,'noiseVarianceMetric',nan, ...
    'noiseVarianceWaveform',nan,'arms',struct),nSeeds,1);
root=string(getenv('TYPE1_PHASE3_OUTPUT_ROOT'));if strlength(root)==0,root=fullfile(tempdir,'type1_phase3');end
if ~isfolder(root),mkdir(root);end
out=fullfile(root,['type1_phase3_r20_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(out);
frame=round(cfg.frameDurationSec*cfg.txSampleRate);tx5=repmat(double(p.txWaveform),5,1);
for k=1:nSeeds
    seed=seeds(k);[physical,channel]=type1_phase3_make_tdl_a_channel( ...
        tx5,cfg,model16,RandStream('mt19937ar','Seed',seed));
    signalPower=mean(abs(physical).^2,'all');nvWaveform=signalPower/10^(snrDb/10);
    Hfull=type1_phase3_tdl_frequency_response(channel,frequency);Hsearch=Hfull(:,:,searchIndex);
    metricSignalPower=mean(sum(abs(Hfull).^2,2),'all');
    nvMetric=metricSignalPower/10^(snrDb/10);
    [schedules,armAudit]=make_schedules(Hsearch,Hfull,nvMetric,p);
    selection(k)=struct('seed',seed,'noiseVarianceMetric',nvMetric, ...
        'noiseVarianceWaveform',nvWaveform,'arms',armAudit);
    ns=RandStream('mt19937ar','Seed',seed+70000);
    physical=physical+sqrt(nvWaveform/2)*(randn(ns,size(physical))+1j*randn(ns,size(physical)));
    targets=type1_phase3_switch_targets_from_physical(physical,schedules,switchModel.isolationDb);
    clear physical Hfull Hsearch channel
    [beta,~]=type1_phase3_switch_beta(size(targets,1),switchModel, ...
        RandStream('mt19937ar','Seed',seed+80000));
    for a=1:numel(armNames)
        [~,virtual]=type1_phase3_apply_target(targets(:,a),beta,4);
        d=detect_accum(virtual,p);acq1(k,a)=d.success1;acq4(k,a)=d.success4;acqDetail{k,a}=d;
        if k<=nDataSeeds,data(k,a)=analyze_safe(virtual(1:2*frame,:),p);end
        clear virtual
    end
    clear targets beta
    fprintf(['R20 %2d/%d seed=%d acq1=[%s] acq4=[%s], PSS margin ' ...
        'M8/M12/M16=[%+.2f %+.2f %+.2f] dB.\n'],k,nSeeds,seed, ...
        num2str(acq1(k,:),'%d '),num2str(acq4(k,:),'%d '), ...
        armAudit.M8Aware.pssMarginDb,armAudit.M12Aware.pssMarginDb, ...
        armAudit.M16Aware.pssMarginDb);
    checkpoint=struct('preRegistration',preRegistration,'validation',validation, ...
        'selection',selection,'data',data,'acq1',acq1,'acq4',acq4, ...
        'acqDetail',{acqDetail},'completedSeeds',k);
    save(fullfile(out,'phase3_r20_checkpoint.mat'),'checkpoint','-v7.3');
end
summary=summarize(data,acq1,acq4,selection,armNames,armM,scanFrames,updateSec,amc);
summary.paperGateEvaluated=profile=="paper";
summary.gatePassed=summary.paperGateEvaluated&&any(summary.primaryAmcGain(4:5)>0);
report=struct('preRegistration',preRegistration,'validation',validation, ...
    'selection',selection,'data',data,'acq1',acq1,'acq4',acq4, ...
    'acqDetail',{acqDetail},'summary',summary,'outputDirectory',out, ...
    'createdAt',datetime('now'),'matlabVersion',version);
save(fullfile(out,'phase3_r20.mat'),'report','-v7.3');
plot_result(report,fullfile(out,'phase3_r20.png'));
fprintf(['R20 %s: acq4=[%s]/%d, primary AMC gain=[%s] bit/s/Hz, ' ...
    'M8 aware McNemar %d/%d p=%.4g, gate=%d.\n'],profile, ...
    num2str(summary.acq4Count),nSeeds,num2str(summary.primaryAmcGain,'%.3f '), ...
    summary.m8AwareRescues,summary.m8AwareLosses,summary.m8AwareMcnemarP,summary.gatePassed);
fprintf('Phase-3 R20 audit saved: %s\n',out);
end

function [schedules,audit]=make_schedules(Hsearch,Hfull,nv,p)
S4=eye(4);schedules=cell(1,5);schedules{1}=S4;
audit=struct;pssIndex=p.ssbSubcarriers;
for M=[8 12 16]
    H=Hsearch(1:M,:,:);Hpss=reshape(Hfull(1:M,1,pssIndex),M,[]);
    baseline=[eye(4);zeros(M-4,4)];data=type1_phase3_greedy_schedule(H,nv,1);
    aware=type1_phase3_acquisition_aware_schedule(H,Hpss,nv,baseline);
    name=sprintf('M%dData',M);audit.(name)=compact_selection(data,Hpss,nv,baseline);
    name=sprintf('M%dAware',M);audit.(name)=aware;
    if M==8
        schedules{2}=data.S;schedules{3}=aware.S;
    elseif M==12
        schedules{4}=aware.S;
    else
        schedules{5}=aware.S;
    end
end
audit.M4=struct('S',S4,'objectiveDb',type1_phase3_wideband_metrics( ...
    Hsearch(1:4,:,:),S4,nv).objectiveDb,'pssMarginDb',0);
end

function out=compact_selection(data,Hpss,nv,baseline)
score=type1_phase3_batch_pss_score(Hpss,data.S,nv,1);
base=type1_phase3_batch_pss_score(Hpss,baseline,nv,1);
out=struct('S',data.S,'objectiveDb',data.objectiveDb,'pssScoreDb',score, ...
    'baselinePssScoreDb',base,'pssMarginDb',score-base, ...
    'trajectoryDb',data.trajectoryDb);
end

function d=detect_accum(virtual,p)
frame=round(p.cfg.frameDurationSec*p.cfg.txSampleRate);
[~,reference]=type1_pss_complex_correlation(complex(zeros(1,1)),p,mod(p.cfg.pci,3));
nRef=numel(reference);best1=[-inf 0 0];best4=[-inf 0 0];
for nid2=0:2
    cumulative=zeros(frame,1);
    for repetition=1:4
        first=(repetition-1)*frame+1;segment=double(virtual(first:first+frame+nRef-2,:));
        for r=1:size(segment,2),scale=rms(segment(:,r));if scale>0,segment(:,r)=segment(:,r)/scale;end,end
        corr=type1_pss_complex_correlation(segment,p,nid2);
        cumulative=cumulative+sum(abs(corr(1:frame,:)).^2,2);
        if repetition==1,[metric,phase]=max(cumulative);if metric>best1(1),best1=[metric phase-1 nid2];end,end
        if repetition==4,[metric,phase]=max(cumulative);if metric>best4(1),best4=[metric phase-1 nid2];end,end
    end
end
tolerance=max(p.ofdmInfo.CyclicPrefixLengths);expected=mod(p.cfg.pci,3);
e1=wrap(best1(2),frame);e4=wrap(best4(2),frame);
d=struct('success1',abs(e1)<=tolerance&&best1(3)==expected, ...
    'success4',abs(e4)<=tolerance&&best4(3)==expected, ...
    'timingError1',e1,'timingError4',e4,'nid2_1',best1(3),'nid2_4',best4(3), ...
    'metric1',best1(1),'metric4',best4(1));
end

function result=analyze_safe(rx,p)
try
    r=type1_analyze(rx,p,"combined");success=~r.pbchCRCError&&r.mibMatches&&r.bestNID2==r.expectedNID2;
    result=struct('success',success,'errorIdentifier',"", ...
        'decodedBER',mean(r.decodedBER,'all','omitnan'), ...
        'rawBER',mean(r.rawBER,'all','omitnan'), ...
        'evmRMSPercent',median(r.evmRMSPercent,'all','omitnan'), ...
        'qualityDb',-20*log10(median(r.evmRMSPercent,'all','omitnan')/100), ...
        'conditionMedian',r.estimatedConditionStats(1));
catch exception
    result=empty_data();result.errorIdentifier=string(exception.identifier);
end
end

function e=empty_data()
e=struct('success',false,'errorIdentifier',"notRun",'decodedBER',nan, ...
    'rawBER',nan,'evmRMSPercent',nan,'qualityDb',nan,'conditionMedian',nan);
end

function s=summarize(data,acq1,acq4,selection,names,M,scanFrames,periods,amc)
nArm=numel(names);nPeriod=numel(periods);nShift=numel(amc.thresholdSensitivityDb);
count1=sum(acq1,1);count4=sum(acq4,1);p4=count4/size(acq4,1);
quality=nan(size(data));ber=quality;valid=false(size(data));
for k=1:size(data,1)
    for a=1:nArm
        valid(k,a)=data(k,a).success;quality(k,a)=data(k,a).qualityDb;
        ber(k,a)=data(k,a).decodedBER;
    end
end
meanEfficiency=zeros(nArm,nShift);modulationCounts=cell(nArm,nShift);
for a=1:nArm
    for j=1:nShift
        values=quality(valid(:,a),a);
        [eff,mod]=amc_lookup(values,amc,amc.thresholdSensitivityDb(j));
        meanEfficiency(a,j)=mean(eff,'omitnan');
        modulationCounts{a,j}=groupcounts(categorical(mod));
    end
end
throughput=zeros(nArm,nPeriod,nShift);
for a=1:nArm
    for t=1:nPeriod
        scan=min(.99,scanFrames(a)*.01/periods(t));
        for j=1:nShift
            throughput(a,t,j)=p4(a)*(1-scan)*meanEfficiency(a,j)*amc.targetBlockSuccess;
        end
    end
end
[~,nominal]=min(abs(amc.thresholdSensitivityDb));[~,primary]=min(abs(periods-1));
gain=throughput-throughput(1,:,:);primaryGain=reshape(gain(:,primary,nominal),1,nArm);
selectionObjective=zeros(numel(selection),nArm);pssMargin=selectionObjective;
for k=1:numel(selection)
    A=selection(k).arms;selectionObjective(k,:)=[A.M4.objectiveDb A.M8Data.objectiveDb ...
        A.M8Aware.objectiveDb A.M12Aware.objectiveDb A.M16Aware.objectiveDb];
    pssMargin(k,:)=[0 A.M8Data.pssMarginDb A.M8Aware.pssMarginDb ...
        A.M12Aware.pssMarginDb A.M16Aware.pssMarginDb];
end
[rescue,loss,p]=paired_test(acq4(:,3),acq4(:,2));
meanBer=zeros(1,nArm);
for a=1:nArm,meanBer(a)=mean(ber(valid(:,a),a),'omitnan');end
fixedQpsk=p4.*(1-scanFrames*.01/1).*(1-meanBer)*2;
s=struct('armNames',names,'mPhysical',M,'acq1Count',count1,'acq4Count',count4, ...
    'acq4Rate',p4,'m8AwareRescues',rescue,'m8AwareLosses',loss,'m8AwareMcnemarP',p, ...
    'dataValidCount',sum(valid,1),'medianQualityDb',median(quality,1,'omitnan'), ...
    'meanDecodedBER',meanBer,'meanAmcEfficiency',meanEfficiency, ...
    'modulationCounts',{modulationCounts},'updateSec',periods, ...
    'thresholdShiftDb',amc.thresholdSensitivityDb,'amcThroughput',throughput, ...
    'amcGain',gain,'primaryUpdateSec',1,'primaryAmcGain',primaryGain, ...
    'fixedQpskAt1Sec',fixedQpsk,'fixedQpskGainAt1Sec',fixedQpsk-fixedQpsk(1), ...
    'selectionObjectiveDb',selectionObjective,'medianSelectionObjectiveDb',median(selectionObjective,1), ...
    'pssMarginDb',pssMargin,'medianPssMarginDb',median(pssMargin,1));
end

function [eff,mod]=amc_lookup(quality,table,shift)
eff=zeros(size(quality));mod=strings(size(quality));
for k=1:numel(quality)
    index=sum(quality(k)>=table.thresholdDb+shift);
    if index>0,eff(k)=table.efficiency(index);mod(k)=table.modulation(index);
    else,mod(k)="outage";end
end
end

function [rescue,loss,p]=paired_test(candidate,reference)
rescue=sum(candidate&~reference);loss=sum(~candidate&reference);n=rescue+loss;
if n==0,p=1;return;end;m=min(rescue,loss);term=2^(-n);cdf=term;
for k=1:m,term=term*(n-k+1)/k;cdf=cdf+term;end;p=min(1,2*cdf);
end

function value=wrap(value,frame),value=mod(value+frame/2,frame)-frame/2;end

function plot_result(report,file)
s=report.summary;[~,nominal]=min(abs(s.thresholdShiftDb));
figure('Visible','off','Position',[100 100 1600 480]);
subplot(1,3,1);bar([s.acq1Count(:) s.acq4Count(:)]);grid on;xticklabels(s.armNames);
ylabel('PSS acquisitions');legend('1 frame','4 frames','Location','best');title('50-seed acquisition');
subplot(1,3,2);hold on;
for a=1:numel(s.armNames)
    semilogx(s.updateSec,squeeze(s.amcThroughput(a,:,nominal)),'o-','LineWidth',1.2);
end
grid on;xlabel('selection update period (s)');ylabel('AMC goodput (bit/s/Hz)');legend(s.armNames,'Location','best');
subplot(1,3,3);groups=categorical(repmat(s.armNames,size(s.selectionObjectiveDb,1),1));
boxchart(groups(:),s.selectionObjectiveDb(:));
grid on;ylabel('ideal min-user SINR (dB)');title('paired M scaling / PSS-aware sacrifice');
exportgraphics(gcf,file,'Resolution',180);close(gcf);
end
