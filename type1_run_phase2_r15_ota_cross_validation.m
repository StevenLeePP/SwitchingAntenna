function campaign = type1_run_phase2_r15_ota_cross_validation(manifestFile,options)
%TYPE1_RUN_PHASE2_R15_OTA_CROSS_VALIDATION Paired OTA/matched-SNR R15 gate.
%   Every accepted raw122 segment is processed twice (ideal/impaired), then
%   compared with paired TDL-A realizations at the measured ideal null-band
%   SNR.  EVM residual power is the preregistered primary metric.

arguments
    manifestFile (1,1) string
    options.validSeedsPerCapture (1,1) double {mustBeInteger,mustBePositive} = 10
    options.maxAttemptsPerCapture (1,1) double {mustBeInteger,mustBePositive} = 32
    options.seedBase (1,1) double {mustBeInteger,mustBePositive} = 20261500
end
loaded=load(manifestFile);
if isfield(loaded,'manifest')
    manifest=loaded.manifest;
elseif isfield(loaded,'entries')
    manifest=struct('entries',loaded.entries, ...
        'outputRoot',string(fileparts(manifestFile)));
else
    error('type1:R15Manifest','Manifest has no manifest or entries field.');
end
entries=manifest.entries(:);n=numel(entries);
assert(n>=10 && numel(unique([entries.rxGainDb]))>=2,'type1:R15CampaignSize', ...
    'R15 requires >=10 qualified segments across >=2 RX gains.');

rows=repmat(empty_row(),n,1);offlineDetails=cell(n,1);
for index=1:n
    fprintf('\nR15 paired analysis %d/%d: gain %.1f, segment %d\n', ...
        index,n,entries(index).rxGainDb,entries(index).segment);
    pair=type1_analyze_raw122_switch_pair(entries(index).raw122File, ...
        isolationDb=25,settlingRiseNs=20,transitionJitterStdPs=20, ...
        samplingBoundaryJitterStdPs=100,switchSeed=options.seedBase+index);
    assert(pair.idealBaselineUsable,'type1:R15BaselineGate', ...
        'Previously accepted capture failed paired baseline gate: %s', ...
        entries(index).raw122File);
    idealEvm=pair.ideal.summary.meanEVMPercent;
    impairedEvm=pair.impaired.summary.meanEVMPercent;
    otaIncrement=(impairedEvm^2-idealEvm^2)/idealEvm^2;
    otaCondIncrement=(pair.impaired.summary.condMedian- ...
        pair.ideal.summary.condMedian)/pair.ideal.summary.condMedian;
    snrDb=pair.ideal.summary.snrNullDb;
    [offlineIncrement,offlineCondIncrement,detail]=offline_prediction( ...
        snrDb,options.seedBase+1000*index,options);
    offlineDetails{index}=detail;
    rows(index)=struct('rxGainDb',entries(index).rxGainDb, ...
        'segment',entries(index).segment,'raw122File',entries(index).raw122File, ...
        'snrNullDb',snrDb,'idealEVMPercent',idealEvm, ...
        'impairedEVMPercent',impairedEvm,'otaEvmPowerIncrement',otaIncrement, ...
        'offlineEvmPowerIncrement',offlineIncrement, ...
        'otaCondMedianIncrement',otaCondIncrement, ...
        'offlineCondMedianIncrement',offlineCondIncrement, ...
        'signMatches',sign(otaIncrement)==sign(offlineIncrement), ...
        'offlineValidSeeds',numel(detail.seeds));
end
tableRows=struct2table(rows);
signAgreement=mean(tableRows.signMatches);
otaMedian=median(tableRows.otaEvmPowerIncrement,'omitnan');
offlineMedian=median(tableRows.offlineEvmPowerIncrement,'omitnan');
if otaMedian>0 && offlineMedian>0
    medianRatio=otaMedian/offlineMedian;
else
    medianRatio=NaN;
end
signGate=signAgreement>=.9;
ratioGate=isfinite(medianRatio) && medianRatio>=.5 && medianRatio<=2;
acceptancePassed=signGate && ratioGate;
summary=struct('qualifiedCaptures',n,'gainCount',numel(unique(tableRows.rxGainDb)), ...
    'signAgreement',signAgreement,'otaMedianIncrement',otaMedian, ...
    'offlineMedianIncrement',offlineMedian,'medianRatio',medianRatio, ...
    'signGatePassed',signGate,'ratioGatePassed',ratioGate, ...
    'acceptancePassed',acceptancePassed);
campaign=struct('createdAt',datetime('now'),'manifestFile',manifestFile, ...
    'impairment',struct('isolationDb',25,'settlingRiseNs',20, ...
        'transitionJitterStdPs',20,'samplingBoundaryJitterStdPs',100, ...
        'settlingFastJitterStdFraction',0), ...
    'rows',tableRows,'offlineDetails',{offlineDetails},'summary',summary, ...
    'options',options);
outputRoot=string(manifest.outputRoot);
outFile=fullfile(outputRoot,'type1_phase2_r15_ota_cross_validation.mat');
save(outFile,'campaign','-v7.3');
fprintf('\n========== R15 preregistered gate ==========\n');disp(tableRows(:, ...
    {'rxGainDb','segment','snrNullDb','otaEvmPowerIncrement', ...
    'offlineEvmPowerIncrement','signMatches'}));
fprintf(['sign agreement %.1f%%; median OTA/offline %.4g/%.4g; ratio %.3f; ' ...
    'PASS=%d\n'],100*signAgreement,otaMedian,offlineMedian,medianRatio,acceptancePassed);
fprintf('Saved %s\n',outFile);
end

function [evmIncrement,condIncrement,detail]=offline_prediction(snrDb,seedBase,options)
p=type1_load_package();increments=[];condIncrements=[];seeds=[];failures=[];
for attempt=1:options.maxAttemptsPerCapture
    if numel(seeds)>=options.validSeedsPerCapture,break;end
    seed=seedBase+attempt;
    sim=offline_config(snrDb);
    try
        stream=RandStream('mt19937ar','Seed',seed);
        idealLink=type1_offline_link(p,sim,stream);
        idealResult=type1_analyze(idealLink.virtualRx30,p);
        sim.switch.isolationDb=25;sim.switch.settlingRiseNs=20;
        sim.switch.transitionJitterStdPs=20;
        sim.switch.samplingBoundaryJitterStdPs=100;
        stream=RandStream('mt19937ar','Seed',seed);
        impairedLink=type1_offline_link(p,sim,stream);
        impairedResult=type1_analyze(impairedLink.virtualRx30,p);
        valid=idealResult.bestNID2==idealResult.expectedNID2 && ...
            impairedResult.bestNID2==impairedResult.expectedNID2 && ...
            ~idealResult.pbchCRCError && idealResult.mibMatches && ...
            ~impairedResult.pbchCRCError && impairedResult.mibMatches;
        if ~valid,failures(end+1)=seed;continue;end %#ok<AGROW>
        e0=mean(idealResult.evmRMSPercent,'all','omitnan');
        e1=mean(impairedResult.evmRMSPercent,'all','omitnan');
        increments(end+1)=(e1^2-e0^2)/e0^2; %#ok<AGROW>
        c0=idealResult.conditionStats(1);c1=impairedResult.conditionStats(1);
        condIncrements(end+1)=(c1-c0)/c0;seeds(end+1)=seed; %#ok<AGROW>
    catch
        failures(end+1)=seed; %#ok<AGROW>
    end
end
assert(numel(seeds)>=options.validSeedsPerCapture,'type1:R15OfflineOutage', ...
    'Only %d/%d matched-SNR TDL seeds were valid at %.2f dB.', ...
    numel(seeds),options.validSeedsPerCapture,snrDb);
evmIncrement=median(increments,'omitnan');
condIncrement=median(condIncrements,'omitnan');
detail=struct('snrDb',snrDb,'seeds',seeds,'failedSeeds',failures, ...
    'evmPowerIncrements',increments,'condMedianIncrements',condIncrements, ...
    'medianEvmPowerIncrement',evmIncrement,'medianCondIncrement',condIncrement);
end

function sim=offline_config(snrDb)
sim=type1_offline_sim_config();sim.frames=1;sim.assertIdealBaseline=false;
sim.snrDb=snrDb;sim.channelModel="tdl-a";sim.tdl.delaySpreadNs=100;
sim.tdl.dopplerHz=0;sim.tdl.rxCorrelation=.3;sim.tdl.txCorrelation=.3;
sim.switch.isolationDb=Inf;sim.switch.settlingRiseNs=0;
sim.switch.transitionJitterStdPs=0;sim.switch.samplingBoundaryJitterStdPs=0;
sim.switch.settlingFastJitterStdFraction=0;
cfg=type1_config();sim.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
sim.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
end

function row=empty_row()
row=struct('rxGainDb',NaN,'segment',NaN,'raw122File',"",'snrNullDb',NaN, ...
    'idealEVMPercent',NaN,'impairedEVMPercent',NaN, ...
    'otaEvmPowerIncrement',NaN,'offlineEvmPowerIncrement',NaN, ...
    'otaCondMedianIncrement',NaN,'offlineCondMedianIncrement',NaN, ...
    'signMatches',false,'offlineValidSeeds',0);
end
