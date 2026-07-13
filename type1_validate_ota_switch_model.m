function report = type1_validate_ota_switch_model(rawFile)
%TYPE1_VALIDATE_OTA_SWITCH_MODEL Compare paired OTA and offline deltas.
%   This wrapper deliberately delegates the OTA half to the explicit paired
%   raw122 bridge.  It refuses to label the OTA/simulation comparison valid
%   unless that same OTA raw segment passes the ideal PSS/PBCH/EVM gate.

arguments
    rawFile = ""
end

ota = type1_analyze_raw122_switch_pair(rawFile);
if ~ota.idealBaselineUsable
    report = struct('ota', ota, 'idealModel', ota.idealModel, ...
        'impairedModel', ota.impairedModel, 'simIdeal', [nan nan], ...
        'simImpaired', [nan nan], 'otaDelta', [nan nan], ...
        'simDelta', [nan nan], 'crossValidationValid', false);
    fprintf(['OTA/sim comparison is NOT RUN: the shared OTA raw segment failed ' ...
        'the ideal PSS/PBCH/EVM baseline gate.\n']);
    return;
end
p = type1_load_package();
sim = type1_offline_sim_config();
ideal = sim.switch;
impaired = ota.impairedModel;
stream = RandStream('mt19937ar', 'Seed', sim.seed);
idealLink = type1_offline_link(p, sim, stream);
simIdeal = type1_analyze(idealLink.virtualRx30, p);
sim.switch = impaired;
stream = RandStream('mt19937ar', 'Seed', sim.seed);
impairedLink = type1_offline_link(p, sim, stream);
simImpaired = type1_analyze(impairedLink.virtualRx30, p);
metric = @(x) [mean(x.evmRMSPercent, 'all', 'omitnan') x.conditionStats(2)];
simDelta = metric(simImpaired) - metric(simIdeal);
otaDelta = [ota.delta.delta_meanEVMPercent ota.delta.delta_condP95];

report = struct('ota', ota, 'idealModel', ideal, 'impairedModel', impaired, ...
    'simIdeal', metric(simIdeal), 'simImpaired', metric(simImpaired), ...
    'otaDelta', otaDelta, 'simDelta', simDelta, ...
    'crossValidationValid', ota.idealBaselineUsable);
fprintf('OTA/sim paired delta [mean EVM%% condP95] = [%s] / [%s]\n', ...
    num2str(otaDelta, '%.3f '), num2str(simDelta, '%.3f '));
end
