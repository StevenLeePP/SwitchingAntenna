%% TYPE1_PROFILE_FAST Stage-level and function-level profiler for fast RX
% Run directly in MATLAB:
%   type1_profile_fast
%
% Optional environment controls:
%   TYPE1_PROFILE_REPEATS=10   % timed repetitions after warm-up
%   TYPE1_PROFILE_WARMUPS=2    % JIT/cache warm-up repetitions
%
% Input is the newest saved virtual30 IQ file. The script does not access
% the SDR, so it can be run repeatedly while TX/RX hardware is idle.

clear; clc;

sourceDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(sourceDir, 'data');
addpath(sourceDir);

cfg = type1_config();
package = type1_load_package();
repeats = env_positive('TYPE1_PROFILE_REPEATS', 10);
warmups = env_positive('TYPE1_PROFILE_WARMUPS', 2);
dataSlot = package.cfg.dataSlots(ceil(numel(package.cfg.dataSlots) / 2));

iqFile = newest_file(dataDir, '*_virtual30_csingle_iq4.bin');
rx30 = read_complex_single_iq(iqFile, package.cfg.nRxChannels);
if size(rx30, 1) < round(10.5e-3 * package.cfg.txSampleRate)
    error('type1:ProfileShortIQ', ...
        'Need at least 10.5 ms in %s.', iqFile);
end

fprintf('\n========== Type-A fast-path profiler ==========\n');
fprintf('IQ file             : %s\n', iqFile);
fprintf('IQ size/rate         : %d x %d / %.2f MS/s\n', ...
    size(rx30, 1), size(rx30, 2), package.cfg.txSampleRate / 1e6);
fprintf('Coding / data slot   : %s / %d\n', package.channelCoding, dataSlot);
fprintf('Warm-ups / repeats   : %d / %d\n\n', warmups, repeats);

% Acquire PSS once. The timed loop below emulates the live TRACK state:
% PSS/PBCH are not repeated for every data-frame analysis.
acquisitionResult = type1_analyze_fast(rx30, package, dataSlot, ...
    'collectTiming', true, 'forcePSS', true);
trackingArgs = {'collectTiming', true, 'forcePSS', false, ...
    'syncState', acquisitionResult.syncState, ...
    'trackedTimingOffset', acquisitionResult.timingOffset};
fprintf('One-time PSS acquisition: %.2f ms (PSS stage %.2f ms)\n\n', ...
    acquisitionResult.elapsedMs, acquisitionResult.stageTimesMs.pssTiming);

% JIT compilation, toolbox cache setup and MATLAB allocator growth are not
% part of steady-state TRACK timing.
for k = 1:warmups
    type1_analyze_fast(rx30, package, dataSlot, trackingArgs{:});
end

% The low-rate health check must remain local: it uses nrTimingEstimate,
% but only over +/- cfg.fastPSSLocalSearchSamples around the prediction.
localCheckArgs = [trackingArgs, {'validatePSS', true}];
for k = 1:warmups
    type1_analyze_fast(rx30, package, dataSlot, localCheckArgs{:});
end
localCheckResult = type1_analyze_fast(rx30, package, dataSlot, ...
    localCheckArgs{:});
fprintf(['Local PSS check (+/- %d samples): %.2f ms ' ...
    '(PSS stage %.2f ms)\n\n'], ...
    cfg.fastPSSLocalSearchSamples, localCheckResult.elapsedMs, ...
    localCheckResult.stageTimesMs.pssTiming);

lastResult = type1_analyze_fast(rx30, package, dataSlot, trackingArgs{:});
stageNames = fieldnames(lastResult.stageTimesMs);
stageNames = setdiff(stageNames, {'accounted', 'unaccounted'}, 'stable');
nStages = numel(stageNames);
stageSamplesMs = zeros(repeats, nStages);
totalSamplesMs = zeros(repeats, 1);
accountedSamplesMs = zeros(repeats, 1);
unaccountedSamplesMs = zeros(repeats, 1);

for k = 1:repeats
    result = type1_analyze_fast(rx30, package, dataSlot, trackingArgs{:});
    totalSamplesMs(k) = result.elapsedMs;
    for s = 1:nStages
        stageSamplesMs(k, s) = result.stageTimesMs.(stageNames{s});
    end
    accountedSamplesMs(k) = result.stageTimesMs.accounted;
    unaccountedSamplesMs(k) = result.stageTimesMs.unaccounted;
    lastResult = result;
end

stageMedianMs = median(stageSamplesMs, 1).';
stageP95Ms = prctile(stageSamplesMs, 95, 1).';
stageMaxMs = max(stageSamplesMs, [], 1).';
totalMedianMs = median(totalSamplesMs);
stagePercent = 100 * stageMedianMs / totalMedianMs;
stageTable = table(string(stageNames), stageMedianMs, stageP95Ms, ...
    stageMaxMs, stagePercent, ...
    'VariableNames', {'Stage', 'MedianMs', 'P95Ms', 'MaxMs', 'PercentOfTotal'});
stageTable = sortrows(stageTable, 'MedianMs', 'descend');

fprintf('--- Steady-state stage timing (sorted by median) ---\n');
disp(stageTable);
fprintf('Total / accounted / unaccounted median: %.2f / %.2f / %.2f ms\n', ...
    totalMedianMs, median(accountedSamplesMs), median(unaccountedSamplesMs));
fprintf('PSS acquisition/PBCH/DM-RS/RZF quick view: %.2f / %.2f / %.2f / %.2f ms\n\n', ...
    acquisitionResult.stageTimesMs.pssTiming, ...
    median(stageSamplesMs(:, strcmp(stageNames, 'pbchDecode'))) + ...
        median(stageSamplesMs(:, strcmp(stageNames, 'pbchChannelEstimate'))) + ...
        median(stageSamplesMs(:, strcmp(stageNames, 'pbchEqualizeLoop'))), ...
    median(stageSamplesMs(:, strcmp(stageNames, 'dmrsChannelEstimate'))), ...
    median(stageSamplesMs(:, strcmp(stageNames, 'rzfEqualize'))));

% MATLAB Profiler complements the stage timers by attributing time inside
% 5G Toolbox and built-in functions. One warmed-up call is enough and keeps
% profiler overhead from dominating the run.
profile clear;
try
    profile('-timer', 'real');
catch
end
profile on;
type1_analyze_fast(rx30, package, dataSlot, trackingArgs{:});
profile off;
profileInfo = profile('info');
functionTable = profileInfo.FunctionTable;
totalFunctionTime = [functionTable.TotalTime];
[~, order] = sort(totalFunctionTime, 'descend');
topCount = min(25, numel(order));

fprintf('--- MATLAB Profiler top %d functions (one warmed-up call) ---\n', ...
    topCount);
for k = 1:topCount
    entry = functionTable(order(k));
    fprintf('%2d. %8.4f s  %5d calls  %s\n', k, entry.TotalTime, ...
        entry.NumCalls, entry.FunctionName);
end

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outputDir = fullfile(cfg.outputRoot, ['type1_fast_profile_' stamp]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end
writetable(stageTable, fullfile(outputDir, 'stage_timing.csv'));
try
    profsave(profileInfo, fullfile(outputDir, 'matlab_profiler_html'));
catch ME
    warning('type1:ProfileHtml', 'Could not write profiler HTML: %s', ME.message);
end

report = struct;
report.createdAt = datetime('now');
report.iqFile = iqFile;
report.dataSlot = dataSlot;
report.channelCoding = package.channelCoding;
report.warmups = warmups;
report.repeats = repeats;
report.acquisitionResult = strip_large_result(acquisitionResult);
report.localCheckResult = strip_large_result(localCheckResult);
report.totalSamplesMs = totalSamplesMs;
report.stageSamplesMs = stageSamplesMs;
report.stageNames = stageNames;
report.stageTable = stageTable;
report.accountedSamplesMs = accountedSamplesMs;
report.unaccountedSamplesMs = unaccountedSamplesMs;
report.profileInfo = profileInfo;
report.lastResult = strip_large_result(lastResult);
save(fullfile(outputDir, 'type1_fast_profile.mat'), 'report', '-v7.3');

fprintf('\nSaved stage CSV/MAT/profiler HTML: %s\n', outputDir);

function value = env_positive(name, defaultValue)
value = str2double(getenv(name));
if ~isfinite(value) || value < 1
    value = defaultValue;
else
    value = round(value);
end
end

function fileName = newest_file(dataDir, pattern)
files = dir(fullfile(dataDir, pattern));
if isempty(files)
    error('type1:ProfileNoIQ', ...
        'No %s file under %s. Run type1_rx_live first.', pattern, dataDir);
end
[~, index] = max([files.datenum]);
fileName = fullfile(files(index).folder, files(index).name);
end

function x = read_complex_single_iq(fileName, nChannels)
fid = fopen(fileName, 'rb');
if fid < 0, error('type1:ProfileOpen', 'Could not open %s.', fileName); end
cleanup = onCleanup(@() fclose(fid));
raw = fread(fid, inf, 'single=>single');
if mod(numel(raw), 2 * nChannels) ~= 0
    error('type1:ProfileSize', 'Invalid interleaved-IQ file size: %s', fileName);
end
iq = complex(raw(1:2:end), raw(2:2:end));
x = reshape(iq, [], nChannels);
clear cleanup;
end

function result = strip_large_result(result)
largeFields = {'preCompData', 'postCompData'};
for k = 1:numel(largeFields)
    if isfield(result, largeFields{k}), result = rmfield(result, largeFields{k}); end
end
end
