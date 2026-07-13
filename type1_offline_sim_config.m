function sim = type1_offline_sim_config()
%TYPE1_OFFLINE_SIM_CONFIG Reproducible, hardware-free Type-A link baseline.
%   The model intentionally starts from the same shared reference waveform
%   used by OTA TX.  It represents a full-digital 4-RX anchor followed by a
%   causal four-phase single-RF-chain switch emulation.  It must not be
%   described as a physical single-RF-chain measurement.

cfg = type1_config();
sim = struct;
sim.frames = round(env_positive('TYPE1_OFFLINE_FRAMES', 3));
sim.seed = round(env_positive('TYPE1_OFFLINE_SEED', 20260713));
sim.snrDb = env_number('TYPE1_OFFLINE_SNR_DB', 32);
sim.commonCfoHz = env_number('TYPE1_OFFLINE_COMMON_CFO_HZ', 850);
sim.prefixSamples = round(env_positive('TYPE1_OFFLINE_PREFIX_SAMPLES', 5000));
sim.suffixSamples = round(env_positive('TYPE1_OFFLINE_SUFFIX_SAMPLES', 50000));
sim.useSwitchEmulation = true;
sim.switchOversample = round(cfg.rxSampleRate / cfg.txSampleRate);
sim.assertIdealBaseline = true;

% Rows are physical RX antennas; columns are TX layers/users.  This
% deterministic, full-rank channel is the stable regression anchor.  TDL,
% spatial correlation and M>N are added as separate channel-model choices.
sim.channel = [1.00, 0.12+0.05i, 0.08-0.04i, 0.05+0.02i; ...
               0.06-0.03i, 0.95, 0.10+0.04i, 0.07-0.02i; ...
               0.09+0.02i, 0.05-0.03i, 1.05, 0.11+0.01i; ...
               0.04+0.01i, 0.08+0.03i, 0.06-0.04i, 0.98];

% Phase-1 interfaces.  Defaults deliberately preserve the coherent OTA
% anchor; each item is applied per TX layer before the MIMO channel.
sim.userCfoHz = zeros(1, cfg.nLayers);
sim.userTimingSamples = zeros(1, cfg.nLayers);
sim.userPowerDb = zeros(1, cfg.nLayers);
end

function value = env_positive(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value <= 0, value = defaultValue; end
end

function value = env_number(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value), value = defaultValue; end
end
