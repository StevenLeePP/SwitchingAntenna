function report = type1_validate_timing_precompensation()
%TYPE1_VALIDATE_TIMING_PRECOMPENSATION R8-A fixed-seed acceptance test.
p=type1_load_package(); s=type1_offline_multiuser_config();
s.frames=1; s.snrDb=20; s.channelModel="tdl-a"; s.userCfoHz=.5*s.userCfoHz;
s.tdl.delaySpreadNs=100; s.tdl.rxCorrelation=.5; s.tdl.txCorrelation=.5; s.tdl.dopplerHz=0;
s.switch.isolationDb=25; s.switch.settlingRiseNs=20;
s.switch.transitionJitterStdPs=20; s.switch.samplingBoundaryJitterStdPs=100;
s.switch.settlingFastJitterStdFraction=0; s.switch.settlingFastJitterCorrelationSec=1e-6;
seed=20261001; link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',seed));
legacy=type1_analyze_user_cfo(link.virtualRx30,p,false);
refined=type1_analyze_user_cfo(link.virtualRx30,p,true);
report=struct('seed',seed,'sim',s,'legacy',legacy,'refined',refined, ...
    'configuredTimingSamples',s.userTimingSamples,'estimatedTimingSamples',refined.estimatedTimingSamples, ...
    'legacyBER',mean(legacy.infoBER,1),'refinedBER',mean(refined.infoBER,1), ...
    'legacyConditionStats',legacy.base.estimatedConditionStats, ...
    'refinedConditionStats',refined.estimatedConditionStats);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_timing_precomp_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_timing_precomp.mat'),'report','-v7.3');
fprintf('Timing precomp configured=[%s], estimated=[%s] samples.\n', ...
    num2str(s.userTimingSamples,'%.2f '),num2str(refined.estimatedTimingSamples,'%.2f '));
fprintf('Legacy/refined BER=[%s]/[%s], cond=[%s]/[%s].\n', ...
    num2str(report.legacyBER,'%.4g '),num2str(report.refinedBER,'%.4g '), ...
    num2str(report.legacyConditionStats,'%.2f '),num2str(report.refinedConditionStats,'%.2f '));
fprintf('Timing-precomp result saved: %s\n',out);
end
