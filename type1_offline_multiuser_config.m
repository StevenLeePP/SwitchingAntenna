function sim = type1_offline_multiuser_config()
%TYPE1_OFFLINE_MULTIUSER_CONFIG Reproducible independent-user Phase-1 case.
%   Values are deliberately inside the CP for timing and below the very
%   extreme CFO range.  They exercise a receiver that estimates only one
%   common CFO, rather than claiming to model calibrated oscillator masks.

sim = type1_offline_sim_config();
sim.assertIdealBaseline = false;
sim.userCfoHz = [-350, 125, 620, -900];
sim.userTimingSamples = [-12.5, 3.25, 8.5, -6.75];
sim.userPowerDb = [-3, 0, 3, -1.5];
sim.userPhaseNoiseStdRadPerSample = [1.5e-4, 2e-4, 1e-4, 2.5e-4];
end
