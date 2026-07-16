function report=type1_run_paper_e1_online_selection()
%TYPE1_RUN_PAPER_E1_ONLINE_SELECTION DM-RS estimated-CSI vs oracle selection.
assert(exist('type1_phase3_iir_mex','file')==3,'type1:E1Mex', ...
    'Build type1_phase3_iir_mex.c before E1.');
validation=type1_validate_paper_e1_online_selection();
profile=lower(string(getenv('TYPE1_E1_PROFILE')));if strlength(profile)==0,profile="paper";end
if profile=="paper",nSeeds=20;elseif profile=="smoke",nSeeds=2;else
    error('type1:E1Profile','TYPE1_E1_PROFILE must be paper or smoke.');end
p=type1_load_package();cfg=p.cfg;Mvalues=[8 12 16];N=4;seeds=20262201+(0:nSeeds-1);
snrDb=20;frequency=(-306:305)*cfg.scsKHz*1e3;searchIndex=6:12:606;
switchModel=struct('isolationDb',25,'settlingRiseNs',20, ...
    'rawSampleRateHz',cfg.rxSampleRate,'settlingFastJitterStdFraction',.2, ...
    'settlingFastJitterCorrelationSec',1e-6,'snrDb',snrDb);
armNames=["M4" "M8Oracle" "M8Estimated" "M12Oracle" "M12Estimated" ...
    "M16Oracle" "M16Estimated"];
armM=[4 8 8 12 12 16 16];scanFrames=[0 1 1 2 2 3 3];
preRegistration=struct('reviewTarget',"Paper E1 estimated-CSI selector", ...
    'profile',profile,'nSeeds',nSeeds,'seeds',seeds,'snrDb',snrDb, ...
    'mValues',Mvalues,'dmax',1,'switchModel',switchModel, ...
    'scanRule',"disjoint four-port groups; Type-1 DM-RS average over 10 slots", ...
    'csiRule',"nominal-leakage LS; no true H/tap access; no settling truth correction", ...
    'comparison',"same greedy algorithm on true H versus Hhat; evaluate both on true H/full stack", ...
    'decisionRule',"report retention and AMC sign without a forced pass threshold");
empty=empty_data();data=repmat(empty,nSeeds,numel(armNames));
objectiveDb=nan(nSeeds,numel(armNames));hNmseDb=nan(nSeeds,numel(Mvalues));
retention=nan(nSeeds,numel(Mvalues));schedule=cell(nSeeds,numel(armNames));
scanMeta=cell(nSeeds,numel(Mvalues));
root=string(getenv('TYPE1_PAPER_OUTPUT_ROOT'));if strlength(root)==0
    root=fullfile(tempdir,'type1_paper');end
if ~isfolder(root),mkdir(root);end
out=fullfile(root,['type1_paper_e1_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(out);
frame=round(cfg.frameDurationSec*cfg.txSampleRate);tx6=repmat(double(p.txWaveform),6,1);
for k=1:nSeeds
    seed=seeds(k);model16=type1_phase3_config(16,N);
    [physical,channel]=type1_phase3_make_tdl_a_channel(tx6,cfg,model16, ...
        RandStream('mt19937ar','Seed',seed));
    signalPower=mean(abs(physical).^2,'all');nvWave=signalPower/10^(snrDb/10);
    Hfull=type1_phase3_tdl_frequency_response(channel,frequency);
    nvMetric=mean(sum(abs(Hfull).^2,2),'all')/10^(snrDb/10);
    ns=RandStream('mt19937ar','Seed',seed+70000);
    physical=physical+sqrt(nvWave/2)*(randn(ns,size(physical))+1j*randn(ns,size(physical)));
    nRaw=N*size(physical,1);[beta,~]=type1_phase3_switch_beta(nRaw,switchModel, ...
        RandStream('mt19937ar','Seed',seed+80000));
    S4=eye(4);objectiveDb(k,1)=type1_phase3_wideband_metrics( ...
        Hfull(1:4,:,:),S4,nvMetric).objectiveDb;schedule{k,1}=S4;
    column=2;
    for j=1:numel(Mvalues)
        M=Mvalues(j);Htrue=Hfull(1:M,:,:);Hsearch=Htrue(:,:,searchIndex);
        [Hhat,meta]=type1_phase3_estimate_scan_csi(physical,p,M,beta,switchModel);
        HhatSearch=Hhat(:,:,searchIndex);oracle=type1_phase3_greedy_schedule(Hsearch,nvMetric,1);
        estimated=type1_phase3_greedy_schedule(HhatSearch,meta.estimatedMetricNoiseVariance,1);
        mo=type1_phase3_wideband_metrics(Htrue,oracle.S,nvMetric);
        me=type1_phase3_wideband_metrics(Htrue,estimated.S,nvMetric);
        objectiveDb(k,column:column+1)=[mo.objectiveDb me.objectiveDb];
        schedule(k,column:column+1)={oracle.S,estimated.S};scanMeta{k,j}=meta;
        hNmseDb(k,j)=10*log10(sum(abs(Hhat-Htrue).^2,'all')/sum(abs(Htrue).^2,'all'));
        go=mo.objectiveDb-objectiveDb(k,1);ge=me.objectiveDb-objectiveDb(k,1);
        if go>0,retention(k,j)=ge/go;end
        column=column+2;
    end
    targets=type1_phase3_switch_targets_from_physical(physical,schedule(k,:),switchModel.isolationDb);
    dataRows=4*frame+(1:2*frame);
    for a=1:numel(armNames)
        [~,virtual]=type1_phase3_apply_target(targets(:,a),beta,N);
        data(k,a)=analyze_safe(virtual(dataRows,:),p);
    end
    fprintf('E1 %2d/%d seed=%d retention=[%s], Hnmse=[%s] dB.\n',k,nSeeds,seed, ...
        num2str(retention(k,:),'%+.3f '),num2str(hNmseDb(k,:),'%.1f '));
    checkpoint=struct('preRegistration',preRegistration,'validation',validation, ...
        'objectiveDb',objectiveDb,'hNmseDb',hNmseDb,'retention',retention, ...
        'schedule',{schedule},'scanMeta',{scanMeta},'data',data,'completedSeeds',k);
    save(fullfile(out,'paper_e1_checkpoint.mat'),'checkpoint','-v7.3');
end
summary=summarize(data,objectiveDb,hNmseDb,retention,armNames,armM,scanFrames);
report=struct('preRegistration',preRegistration,'validation',validation, ...
    'objectiveDb',objectiveDb,'hNmseDb',hNmseDb,'retention',retention, ...
    'schedule',{schedule},'scanMeta',{scanMeta},'data',data,'summary',summary, ...
    'outputDirectory',out,'createdAt',datetime('now'),'matlabVersion',version);
save(fullfile(out,'paper_e1_online_selection.mat'),'report','-v7.3');
type1_plot_paper_e1_result(report,fullfile(out,'paper_e1_online_selection.png'));
fprintf('E1 %s: median retention=[%s], AMC gain est=[%s], success=[%s]/%d.\n', ...
    profile,num2str(summary.medianRetention,'%.3f '), ...
    num2str(summary.estimatedAmcGain,'%.3f '),num2str(summary.successCount),nSeeds);
fprintf('Paper E1 audit saved: %s\n',out);
end

function e=empty_data()
e=struct('success',false,'errorIdentifier',"notRun",'decodedBER',nan, ...
    'evmRMSPercent',nan,'qualityDb',nan);
end

function result=analyze_safe(rx,p)
try
    r=type1_analyze(rx,p,"combined");success=~r.pbchCRCError&&r.mibMatches&&r.bestNID2==r.expectedNID2;
    result=struct('success',success,'errorIdentifier',"", ...
        'decodedBER',mean(r.decodedBER,'all','omitnan'), ...
        'evmRMSPercent',median(r.evmRMSPercent,'all','omitnan'), ...
        'qualityDb',-20*log10(median(r.evmRMSPercent,'all','omitnan')/100));
catch exception
    result=empty_data();result.errorIdentifier=string(exception.identifier);
end
end

function s=summarize(data,objective,hNmse,retention,names,M,scanFrames)
amc=type1_phase3_amc_table();[~,nominal]=min(abs(amc.thresholdSensitivityDb));
nArm=numel(names);success=false(size(data));quality=nan(size(data));ber=quality;
for k=1:size(data,1)
    for a=1:nArm
        success(k,a)=data(k,a).success;
        quality(k,a)=data(k,a).qualityDb;
        ber(k,a)=data(k,a).decodedBER;
    end
end
eff=zeros(1,nArm);meanBer=nan(1,nArm);
for a=1:nArm
    q=quality(success(:,a),a);eff(a)=mean(amc_lookup(q,amc,amc.thresholdSensitivityDb(nominal)),'omitnan');
    meanBer(a)=mean(ber(success(:,a),a),'omitnan');
end
pAcq=sum(success,1)/size(success,1);payload=1-scanFrames*.01;
goodput=pAcq.*payload.*eff*amc.targetBlockSuccess;gain=goodput-goodput(1);
oracleIndex=[2 4 6];estimatedIndex=[3 5 7];
oracleObjectiveGain=objective(:,oracleIndex)-objective(:,1);
estimatedObjectiveGain=objective(:,estimatedIndex)-objective(:,1);
estimatedWins=sum(estimatedObjectiveGain>oracleObjectiveGain,1);
estimatedLosses=sum(estimatedObjectiveGain<oracleObjectiveGain,1);
estimatedTies=size(objective,1)-estimatedWins-estimatedLosses;
s=struct('armNames',names,'mPhysical',M,'successCount',sum(success,1), ...
    'meanDecodedBER',meanBer,'medianQualityDb',median(quality,1,'omitnan'), ...
    'medianObjectiveDb',median(objective,1,'omitnan'), ...
    'medianHNmseDb',median(hNmse,1,'omitnan'),'medianRetention',median(retention,1,'omitnan'), ...
    'retentionPositiveCount',sum(retention>0,1),'amcGoodput',goodput,'amcGain',gain, ...
    'medianOracleObjectiveGainDb',median(oracleObjectiveGain,1,'omitnan'), ...
    'medianEstimatedObjectiveGainDb',median(estimatedObjectiveGain,1,'omitnan'), ...
    'estimatedObjectivePositiveCount',sum(estimatedObjectiveGain>0,1), ...
    'estimatedVsOracleWinLossTie',[estimatedWins;estimatedLosses;estimatedTies], ...
    'estimatedAmcGain',gain([3 5 7]),'oracleAmcGain',gain([2 4 6]), ...
    'onlineClaimPositive',median(retention,1,'omitnan')>0 & gain([3 5 7])>0, ...
    'comparisonBoundary',"20-seed static-TDL estimated CSI; not a hardware real-time selector");
end

function eff=amc_lookup(quality,table,shift)
eff=zeros(size(quality));
for k=1:numel(quality),index=sum(quality(k)>=table.thresholdDb+shift);if index>0,eff(k)=table.efficiency(index);end,end
end
