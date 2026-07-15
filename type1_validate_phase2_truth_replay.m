function type1_validate_phase2_truth_replay()
%TYPE1_VALIDATE_PHASE2_TRUTH_REPLAY Algebraic checks for R10 genie helpers.
cfg=type1_config(); stream=RandStream('mt19937ar','Seed',20261020);
tx=(randn(stream,4096,cfg.nLayers)+1j*randn(stream,4096,cfg.nLayers))/sqrt(2);
sim=type1_offline_sim_config(); tdl=sim.tdl; tdl.rxCorrelation=.3; tdl.txCorrelation=.3;
[rx,model]=type1_make_tdl_a_channel(tx,cfg,tdl,stream);
components=type1_replay_tdl_components(tx,cfg,model);
tdlError=norm(sum(components,3)-rx,'fro')/max(norm(rx,'fro'),eps);
assert(tdlError<1e-11,'type1:ReplayTDLMismatch','TDL component replay is not additive.');

raw=(randn(stream,4096,4)+1j*randn(stream,4096,4))/sqrt(2);
switchModel=sim.switch; switchModel.recordTimeSeries=true;
switchModel.settlingRiseNs=20; switchModel.settlingFastJitterStdFraction=.2;
switchModel.settlingFastJitterCorrelationSec=1e-6; switchModel.samplingBoundaryJitterStdPs=100;
[stitched,virtual,meta]=type1_apply_switch_impairments(raw,switchModel,stream);
[replayed,replayedVirtual,target]=type1_replay_switch_trace(raw,meta);
switchError=norm(replayed-stitched)/max(norm(stitched),eps);
assert(switchError<1e-12 && isequal(size(virtual),size(replayedVirtual)), ...
    'type1:ReplaySwitchMismatch','Recorded switch replay is not exact.');
assert(norm(target-meta.settlingTarget)/max(norm(target),eps)<1e-12, ...
    'type1:ReplaySwitchTarget','Recorded settling target is inconsistent.');
fprintf('R10 truth replay PASSED: TDL relative error %.3g, switch relative error %.3g.\n', ...
    tdlError,switchError);
end
