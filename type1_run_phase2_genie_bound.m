function report = type1_run_phase2_genie_bound(correlationSec)
%TYPE1_RUN_PHASE2_GENIE_BOUND Compare standard RZF with known-beta upper bound.
%   Uses the same fixed Phase-2 fast-jitter point as the smoke sweep unless
%   overridden below.  The result is offline and truth-aided only through
%   beta[n], not through transmitted QPSK data or channel knowledge.

if nargin < 1
    correlationSec=env_number('TYPE1_PHASE2_TAU_CORR_SEC',0);
end
p=type1_load_package(); s=type1_offline_sim_config();
s.frames=1; s.assertIdealBaseline=false; s.snrDb=20;
s.switch.settlingRiseNs=20; s.switch.settlingFastJitterStdFraction=.6;
s.switch.settlingFastJitterCorrelationSec=correlationSec;
s.switch.recordTimeSeries=true; seed=round(env_number('TYPE1_PHASE2_GENIE_SEED',20260816));
link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',seed));
standard=type1_analyze(link.virtualRx30,p);
genieVirtual=type1_genie_inverse_settling(link.stitched122,link.switchMeta.settlingBeta);
genie=type1_analyze(genieVirtual,p);
frequencyCorrelation=type1_measure_data_residual_frequency_correlation(link.virtualRx30,p);
report=struct('sim',s,'seed',seed,'standard',standard,'genie',genie, ...
    'frequencyCorrelation',frequencyCorrelation,'switchMeta',link.switchMeta);
fprintf('GENIE tauCorr=%g s, standard BER=[%s], genie BER=[%s], lag=[%s].\n', ...
    s.switch.settlingFastJitterCorrelationSec, num2str(mean(standard.infoBER,1),'%.3g '), ...
    num2str(mean(genie.infoBER,1),'%.3g '), ...
    num2str(frequencyCorrelation.magnitudeCorrelation,'%.4g '));
end

function value=env_number(name,defaultValue)
value=str2double(getenv(name));if ~isfinite(value),value=defaultValue;end
end
