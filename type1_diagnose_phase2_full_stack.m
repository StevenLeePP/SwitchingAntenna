function report = type1_diagnose_phase2_full_stack()
%TYPE1_DIAGNOSE_PHASE2_FULL_STACK Controlled removal audit for R7 failures.
p=type1_load_package(); base=type1_offline_multiuser_config();
base.frames=1; base.snrDb=20; base.channelModel="tdl-a";
base.userCfoHz=.5*base.userCfoHz; base.tdl.delaySpreadNs=100;
base.tdl.rxCorrelation=.5; base.tdl.txCorrelation=.5; base.tdl.dopplerHz=0;
base.switch.isolationDb=25; base.switch.settlingRiseNs=20;
base.switch.transitionJitterStdPs=20; base.switch.samplingBoundaryJitterStdPs=100;
base.switch.settlingFastJitterStdFraction=0; base.switch.settlingFastJitterCorrelationSec=1e-6;
names=["full-L0" "ideal-switch" "zero-CFO" "zero-timing" "zero-power" ...
    "negligible-phase-noise" "no-user-impairments" "TDL-anchor"];
sims=repmat(base,1,numel(names));
sims(2).switch.isolationDb=Inf; sims(2).switch.settlingRiseNs=0;
sims(2).switch.transitionJitterStdPs=0; sims(2).switch.samplingBoundaryJitterStdPs=0;
sims(3).userCfoHz=zeros(1,4); sims(4).userTimingSamples=zeros(1,4); sims(5).userPowerDb=zeros(1,4);
sims(6).userPhaseNoiseStdRadPerSample=eps*ones(1,4);
sims(7).userCfoHz=zeros(1,4); sims(7).userTimingSamples=zeros(1,4); sims(7).userPowerDb=zeros(1,4);
sims(7).userPhaseNoiseStdRadPerSample=eps*ones(1,4);
sims(8)=sims(7); sims(8).switch=sims(2).switch;
seed=20261001; ber=nan(numel(names),4); errors=nan(numel(names),4); cfo=nan(numel(names),4);
condition=nan(numel(names),3);
for k=1:numel(names)
    link=type1_offline_link(p,sims(k),RandStream('mt19937ar','Seed',seed));
    r=type1_analyze_user_cfo(link.virtualRx30,p); errors(k,:)=sum(r.infoBitErrors,1);
    ber(k,:)=mean(r.infoBER,1); cfo(k,:)=r.residualCfoHz; condition(k,:)=r.base.estimatedConditionStats;
    fprintf('%s BER=[%s] CFO=[%s] cond=[%s]\n',names(k),num2str(ber(k,:),'%.3g '), ...
        num2str(cfo(k,:),'%.1f '),num2str(condition(k,:),'%.2f '));
end
report=struct('seed',seed,'names',names,'sims',sims,'errors',errors,'ber',ber, ...
    'residualCfoHz',cfo,'conditionStats',condition);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_full_stack_diagnostic_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_full_stack_diagnostic.mat'),'report','-v7.3');
end
