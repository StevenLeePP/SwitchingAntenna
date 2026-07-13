function report = type1_run_offline_switch_case()
%TYPE1_RUN_OFFLINE_SWITCH_CASE Controlled core-switch impairment experiment.

sim = type1_offline_sim_config();
sim.assertIdealBaseline = false;
sim.switch.isolationDb = env_number('TYPE1_SWITCH_ISOLATION_DB', 25);
sim.switch.settlingRiseNs = env_number('TYPE1_SWITCH_RISE_NS', 5);
report = type1_run_offline_experiment(sim, 'switch_case');
end

function value = env_number(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value < 0, value = defaultValue; end
end
