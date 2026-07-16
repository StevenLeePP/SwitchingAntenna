function report=type1_run_phase3_r19_gate3()
%TYPE1_RUN_PHASE3_R19_GATE3 Full-waveform TDL + switch + acquisition NetGain.
%   The primary NetGain is effective decoded goodput, not a subtraction of
%   unlike units: P_acq*(1-scanFraction)*(1-BER).  EVM-quality dB is kept as
%   an attribution view and cannot override the pre-registered gate.

validation=type1_validate_phase3_gate3();profile=lower(string(getenv('TYPE1_R19_PROFILE')));
if strlength(profile)==0,profile="paper";end
if profile=="paper",nSeeds=20;elseif profile=="smoke",nSeeds=3;
else,error('type1:R19Profile','TYPE1_R19_PROFILE must be paper or smoke.');end
r18File=find_r18(profile);loaded=load(r18File,'result');r18=loaded.result;
assert(numel(r18.perSeed)>=nSeeds,'type1:R19R18','R18 MAT has too few paired seeds.');
p=type1_load_package();cfg=p.cfg;model8=type1_phase3_config(8,4);snrDb=20;
armNames=["M4" "F1Exact" "F1Greedy" "F2Greedy"];
primaryUpdateSec=.1;sensitivityUpdateSec=1;frameSec=cfg.frameDurationSec;
scanFrames=[0 1 1 1];primaryScanFraction=scanFrames*frameSec/primaryUpdateSec;
sensitivityScanFraction=scanFrames*frameSec/sensitivityUpdateSec;
switchModel=struct('isolationDb',25,'settlingRiseNs',20, ...
    'rawSampleRateHz',cfg.rxSampleRate,'settlingFastJitterStdFraction',.2, ...
    'settlingFastJitterCorrelationSec',1e-6);
preRegistration=struct('reviewTarget',"R19 gate 3",'profile',profile, ...
    'nSeeds',nSeeds,'seedValues',[r18.perSeed(1:nSeeds).seed], ...
    'snrDb',snrDb,'channel',"same paired geometry-correlated TDL-A draw as R18", ...
    'switchModel',switchModel,'otherUserImpairmentsEnabled',false, ...
    'arms',armNames,'primaryMetric',"P_acq*(1-scanFraction)*(1-decodedBER)", ...
    'primaryUpdateSec',primaryUpdateSec,'primaryScanFraction',primaryScanFraction, ...
    'sensitivityUpdateSec',sensitivityUpdateSec, ...
    'sensitivityScanFraction',sensitivityScanFraction, ...
    'gateRule',"at least one M=8 arm has positive primary effective-goodput gain", ...
    'qualityAttribution',"Q=-20log10(median RMS-EVM fraction); not the primary gate", ...
    'r18File',r18File);
empty=empty_result();ideal=repmat(empty,nSeeds,numel(armNames));impaired=ideal;
betaTemplate=struct('betaMean',nan,'betaStd',nan,'tauMeanNs',nan, ...
    'tauStdNs',nan,'floorHitCount',nan,'floorHitFraction',nan,'fastLag1',nan);
betaMeta=repmat(betaTemplate,nSeeds,1);
root=string(getenv('TYPE1_PHASE3_OUTPUT_ROOT'));if strlength(root)==0,root=fullfile(tempdir,'type1_phase3');end
if ~isfolder(root),mkdir(root);end
out=fullfile(root,['type1_phase3_r19_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(out);
for k=1:nSeeds
    seed=r18.perSeed(k).seed;schedules=cell(1,4);schedules{1}=eye(4);
    schedules{2}=r18.perSeed(k).tdl.search.f1Exact.S;
    schedules{3}=r18.perSeed(k).tdl.search.greedyF1.S;
    schedules{4}=r18.perSeed(k).tdl.search.greedyF2.S;
    tx=repmat(double(p.txWaveform),2,1);
    [physical,channel]=type1_phase3_make_tdl_a_channel(tx,cfg,model8, ...
        RandStream('mt19937ar','Seed',seed)); %#ok<ASGLU>
    signalPower=mean(abs(physical).^2,'all');noiseVariance=signalPower/10^(snrDb/10);
    ns=RandStream('mt19937ar','Seed',seed+70000);
    physical=physical+sqrt(noiseVariance/2)*(randn(ns,size(physical))+1j*randn(ns,size(physical)));
    raw=complex(zeros(4*size(physical,1),8,'single'));
    for m=1:8,raw(:,m)=single(resample(physical(:,m),4,1));end
    clear physical tx
    idealBeta=ones(size(raw,1),1);
    [damagedBeta,betaMeta(k)]=type1_phase3_switch_beta(size(raw,1),switchModel, ...
        RandStream('mt19937ar','Seed',seed+80000));
    for a=1:numel(armNames)
        if a==1,useRaw=raw(:,1:4);else,useRaw=raw;end
        [~,vIdeal]=type1_phase3_apply_switch_impairments(useRaw,schedules{a}, ...
            struct('isolationDb',Inf),idealBeta);
        ideal(k,a)=analyze_safe(vIdeal,p);
        clear vIdeal
        [~,vImpaired]=type1_phase3_apply_switch_impairments(useRaw,schedules{a}, ...
            switchModel,damagedBeta);
        impaired(k,a)=analyze_safe(vImpaired,p);
        clear vImpaired
    end
    clear raw idealBeta damagedBeta
    fprintf(['R19 %2d/%d seed=%d acq ideal=[%s] impaired=[%s], ' ...
        'decoded BER impaired=[%s].\n'],k,nSeeds,seed, ...
        num2str([ideal(k,:).success],'%d '),num2str([impaired(k,:).success],'%d '), ...
        num2str([impaired(k,:).decodedBER],'%.3g '));
    checkpoint=struct('preRegistration',preRegistration,'validation',validation, ...
        'ideal',ideal,'impaired',impaired,'betaMeta',betaMeta,'completedSeeds',k);
    save(fullfile(out,'phase3_r19_checkpoint.mat'),'checkpoint','-v7.3');
end
summary=summarize(ideal,impaired,armNames,primaryScanFraction,sensitivityScanFraction);
paperGateEvaluated=profile=="paper";gatePassed=paperGateEvaluated&&any(summary.primaryGoodputGain(2:end)>0);
summary.paperGateEvaluated=paperGateEvaluated;summary.gatePassed=gatePassed;
report=struct('preRegistration',preRegistration,'validation',validation,'ideal',ideal, ...
    'impaired',impaired,'betaMeta',betaMeta,'summary',summary, ...
    'outputDirectory',out,'createdAt',datetime('now'),'matlabVersion',version);
save(fullfile(out,'phase3_r19_gate3.mat'),'report','-v7.3');
plot_result(report,fullfile(out,'phase3_r19_gate3.png'));
fprintf(['R19 %s: impaired acq=[%s]/%d, primary goodput gain=[%s], ' ...
    'net EVM-quality=[%s] dB, gate=%d.\n'],profile,num2str(summary.impairedSuccessCount), ...
    nSeeds,num2str(summary.primaryGoodputGain,'%.4f '), ...
    num2str(summary.netQualityDb,'%.3f '),gatePassed);
fprintf('Phase-3 R19 audit saved: %s\n',out);
end

function result=analyze_safe(rx,p)
try
    r=type1_analyze(rx,p,"combined");
    success=~r.pbchCRCError&&r.mibMatches&&r.bestNID2==r.expectedNID2;
    result=struct('success',success,'errorIdentifier',"",'timingOffset',r.timingOffset, ...
        'bestNID2',r.bestNID2,'pbchCRCError',r.pbchCRCError,'mibMatches',r.mibMatches, ...
        'rawBER',mean(r.rawBER,'all','omitnan'),'decodedBER',mean(r.decodedBER,'all','omitnan'), ...
        'rawBitErrors',sum(r.rawBitErrors,'all','omitnan'), ...
        'decodedBitErrors',sum(r.decodedBitErrors,'all','omitnan'), ...
        'evmRMSPercent',median(r.evmRMSPercent,'all','omitnan'), ...
        'conditionMedian',r.estimatedConditionStats(1));
catch exception
    result=empty_result();result.errorIdentifier=string(exception.identifier);
end
end

function e=empty_result()
e=struct('success',false,'errorIdentifier',"notRun",'timingOffset',nan, ...
    'bestNID2',nan,'pbchCRCError',true,'mibMatches',false,'rawBER',nan, ...
    'decodedBER',nan,'rawBitErrors',nan,'decodedBitErrors',nan, ...
    'evmRMSPercent',nan,'conditionMedian',nan);
end

function s=summarize(ideal,impaired,names,scanPrimary,scanSensitivity)
nArm=numel(names);idealSuccess=sum(reshape([ideal.success],size(ideal)),1);
impairedSuccess=sum(reshape([impaired.success],size(impaired)),1);
idealQ=nan(1,nArm);impairedQ=nan(1,nArm);ber=nan(1,nArm);
for a=1:nArm
    use=[ideal(:,a).success];evm=[ideal(use,a).evmRMSPercent];
    if ~isempty(evm),idealQ(a)=-20*log10(median(evm)/100);end
    use=[impaired(:,a).success];evm=[impaired(use,a).evmRMSPercent];
    if ~isempty(evm),impairedQ(a)=-20*log10(median(evm)/100);end
    values=[impaired(use,a).decodedBER];if ~isempty(values),ber(a)=mean(values,'omitnan');end
end
nSeed=size(ideal,1);pAcq=impairedSuccess/nSeed;
primary=pAcq.*(1-scanPrimary).*(1-ber);sensitivity=pAcq.*(1-scanSensitivity).*(1-ber);
selectionQuality=idealQ-idealQ(1);impairmentCost=idealQ-impairedQ;
differentialCost=impairmentCost-impairmentCost(1);
syncDb=10*log10(max(pAcq,realmin)/max(pAcq(1),realmin));
scanDb=10*log10((1-scanPrimary)/(1-scanPrimary(1)));
netQuality=(impairedQ-impairedQ(1))+syncDb+scanDb;
s=struct('armNames',names,'idealSuccessCount',idealSuccess, ...
    'impairedSuccessCount',impairedSuccess,'impairedAcquisitionRate',pAcq, ...
    'idealQualityDb',idealQ,'impairedQualityDb',impairedQ, ...
    'selectionQualityGainDb',selectionQuality,'impairmentCostDb',impairmentCost, ...
    'differentialImpairmentCostDb',differentialCost,'syncContributionDb',syncDb, ...
    'primaryScanContributionDb',scanDb,'netQualityDb',netQuality, ...
    'impairedDecodedBER',ber,'primaryEffectiveGoodput',primary, ...
    'primaryGoodputGain',primary-primary(1), ...
    'sensitivityEffectiveGoodput',sensitivity, ...
    'sensitivityGoodputGain',sensitivity-sensitivity(1));
end

function path=find_r18(profile)
path=string(getenv('TYPE1_R19_R18_MAT'));if strlength(path)>0
    assert(isfile(path),'type1:R19R18','TYPE1_R19_R18_MAT does not exist.');return;end
root=string(getenv('TYPE1_PHASE3_OUTPUT_ROOT'));if strlength(root)==0,root=fullfile(tempdir,'type1_phase3');end
listing=dir(fullfile(root,['type1_phase3_r18_' char(profile) '_*'],'phase3_r18_gate2.mat'));
assert(~isempty(listing),'type1:R19R18','No matching R18 MAT found; set TYPE1_R19_R18_MAT.');
[~,index]=max([listing.datenum]);path=string(fullfile(listing(index).folder,listing(index).name));
end

function plot_result(report,file)
s=report.summary;x=1:numel(s.armNames);figure('Visible','off','Position',[100 100 1450 450]);
subplot(1,3,1);bar(x,[s.idealSuccessCount(:) s.impairedSuccessCount(:)]);grid on;
xticks(x);xticklabels(s.armNames);ylabel('acquisition successes');legend('ideal','impaired');
subplot(1,3,2);bar(x,s.primaryGoodputGain);yline(0,'k--');grid on;xticks(x);xticklabels(s.armNames);
ylabel('effective-goodput gain vs M4');title('100-ms update / scan included');
subplot(1,3,3);bar(x,s.netQualityDb);yline(0,'k--');grid on;xticks(x);xticklabels(s.armNames);
ylabel('net EVM-quality contribution (dB)');title('attribution, not primary gate');
exportgraphics(gcf,file,'Resolution',180);close(gcf);
end
