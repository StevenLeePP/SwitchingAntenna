function type1_validate_ici_user_cfo()
%TYPE1_VALIDATE_ICI_USER_CFO Regression for the CFO-aware ICI regressor.
p=type1_load_package(); s=type1_offline_sim_config(); s.frames=1; s.assertIdealBaseline=false;
s.userCfoHz=[-350 125 620 -900]; s.userPhaseNoiseStdRadPerSample=zeros(1,4);
s.userTimingSamples=zeros(1,4); s.userPowerDb=zeros(1,4);
link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',20261000));
reference=type1_analyze_user_cfo(link.virtualRx30,p);
combined=type1_analyze_ici_decision_feedback(link.virtualRx30,p,6,1,'soft',true);
assert(max(abs(reference.residualCfoHz-combined.residualCfoHz))<1e-9, ...
    'type1:ICIDFCFO','Combined receiver changed the residual-CFO estimator.');
assert(max(abs(combined.residualCfoHz))>=combined.residualCfoWarningHz, ...
    'type1:ICIDFCFO','The preregistered 750-Hz ambiguity warning was not exercised.');
assert(all(isfinite(combined.infoBER),'all'), 'type1:ICIDFCFO','Combined BER is not finite.');
fprintf('CFO-aware ICI regression PASSED: residual=[%s] Hz, warning=%.0f Hz.\n', ...
    num2str(combined.residualCfoHz,'%.1f '),combined.residualCfoWarningHz);
end
