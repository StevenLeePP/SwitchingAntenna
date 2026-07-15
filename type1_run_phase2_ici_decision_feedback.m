function report = type1_run_phase2_ici_decision_feedback()
%TYPE1_RUN_PHASE2_ICI_DECISION_FEEDBACK R3 comparison at tau_c=1 us.
p=type1_load_package(); s=type1_offline_sim_config();
s.frames=1;s.assertIdealBaseline=false;s.snrDb=20;s.switch.settlingRiseNs=20;
s.switch.settlingFastJitterStdFraction=.6;s.switch.settlingFastJitterCorrelationSec=1e-6;
s.switch.recordTimeSeries=true; seed=20260816;
link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',seed));
standard=type1_analyze(link.virtualRx30,p);
decisionFeedback=type1_analyze_ici_decision_feedback(link.virtualRx30,p,6);
genieVirtual=type1_genie_inverse_settling(link.stitched122,link.switchMeta.settlingBeta);
genie=type1_analyze(genieVirtual,p);
report=struct('sim',s,'seed',seed,'standard',standard, ...
    'decisionFeedback',decisionFeedback,'genie',genie);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_ici_df_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out;
save(fullfile(out,'phase2_ici_decision_feedback.mat'),'report','-v7.3');
fprintf('ICI-DF Q=6 BER standard=[%s], DF=[%s], genie=[%s].\n', ...
    num2str(mean(standard.infoBER,1),'%.3g '), ...
    num2str(mean(decisionFeedback.infoBER,1),'%.3g '), ...
    num2str(mean(genie.infoBER,1),'%.3g '));
fprintf('ICI-DF result saved: %s\n',out);
end
