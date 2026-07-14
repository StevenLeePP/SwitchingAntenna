function report = type1_run_offline_multiuser()
%TYPE1_RUN_OFFLINE_MULTIUSER Phase-1 independent-user reference experiment.
%   This is a controlled stress case, not an OTA claim.  It reports the
%   BER of the existing common-CFO/DM-RS/RZF receiver before any proposed
%   impairment-aware detector is introduced.

sim = type1_offline_multiuser_config();
% The adjacent-slot residual-CFO estimator is fundamentally ambiguous above
% +/-1 kHz.  Keep this controlled baseline outside its 80%% guard so an
% offline stress sweep cannot silently use an aliased compensation result.
residualBudgetHz = sim.userCfoHz - mean(sim.userCfoHz);
assert(max(abs(residualBudgetHz)) < 800, 'type1:UserCFOAmbiguity', ...
    ['Configured differential CFO [%s] Hz exceeds the +/-800 Hz safety ' ...
    'guard of the adjacent-slot estimator; use a wider-range estimator.'], ...
    num2str(residualBudgetHz, '%.1f '));
report = type1_run_offline_experiment(sim, 'multiuser');
package=type1_load_package(); stream=RandStream('mt19937ar','Seed',sim.seed);
compErrors=zeros(1,package.cfg.nLayers); compEvm=zeros(1,package.cfg.nLayers); estimates=zeros(sim.frames,package.cfg.nLayers);
for frame=1:sim.frames
    compensated=type1_analyze_user_cfo(type1_offline_link(package,sim,stream).virtualRx30,package);
    compErrors=compErrors+sum(compensated.infoBitErrors,1); compEvm=compEvm+mean(compensated.evmRMSPercent,1);
    estimates(frame,:)=compensated.residualCfoHz;
end
bits=sim.frames*numel(package.cfg.dataSlots)*package.nInfoBitsPerSlotLayer;
report.userCfoCompensation=struct('infoBitErrors',compErrors,'infoBER',compErrors/bits, ...
    'meanEvmPercent',compEvm/sim.frames,'estimatedResidualCfoHz',estimates);
save(fullfile(report.outputDir,'type1_offline_multiuser_results.mat'),'report','-v7.3');
fprintf('USER-CFO compensated BER=[%s], estimated residual CFO=[%s] Hz\n', ...
    num2str(report.userCfoCompensation.infoBER,'%.3g '),num2str(mean(estimates,1),'%.1f '));
end
