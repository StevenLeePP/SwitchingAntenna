function report = type1_analyze_raw122_switch_pair(rawFile, options)
%TYPE1_ANALYZE_RAW122_SWITCH_PAIR Paired ideal/impaired analysis of one OTA IQ.
%   REPORT = TYPE1_ANALYZE_RAW122_SWITCH_PAIR() loads exactly one saved
%   N-by-4 raw122 capture, then applies the ideal and 25 dB/5 ns switch
%   models to that *same* sample array.  It is intentionally a bridge
%   between OTA raw IQ and type1_apply_switch_impairments; it does not make
%   two independent RF captures.
%
%   Optional inputs:
%     rawFile               absolute path, or a basename under data/
%     options.isolationDb   default 25 dB
%     options.settlingRiseNs default 5 ns
%     options.maxIdealEVMPercent default 20; quality gate only, not a model
%                           parameter.  A failed gate forbids an OTA/sim
%                           delta comparison, but the paired measurements
%                           are still saved for diagnosis.
%
%   The report records PSS identity, PBCH CRC/MIB state, BER, EVM and
%   cond(H) for both paths, prints a paired difference table, and saves a
%   MAT file next to the raw IQ.  Use this before claiming an OTA impairment
%   cross-validation result.

arguments
    rawFile = ""
    options.isolationDb (1,1) double {mustBeNonnegative} = 25
    options.settlingRiseNs (1,1) double {mustBeNonnegative} = 5
    options.maxIdealEVMPercent (1,1) double {mustBePositive} = 20
end

cfg = type1_config();
package = type1_load_package();
rawFile = resolve_raw_file(rawFile, cfg.dataRoot);
raw122 = read_complex_single_iq(rawFile, 4);

idealModel = type1_offline_sim_config().switch;
impairedModel = idealModel;
impairedModel.isolationDb = options.isolationDb;
impairedModel.settlingRiseNs = options.settlingRiseNs;

fprintf('\n========== OTA raw122 paired switch injection ==========\n');
fprintf('Raw IQ (shared by both paths): %s\n', rawFile);
fprintf('Capture: %d samples x 4, %.3f ms at %.2f MS/s\n', ...
    size(raw122, 1), 1e3 * size(raw122, 1) / cfg.rxSampleRate, ...
    cfg.rxSampleRate / 1e6);
fprintf('Paired models: ideal [Inf dB, 0 ns] versus impaired [%.1f dB, %.2f ns]\n', ...
    options.isolationDb, options.settlingRiseNs);

[~, virtualIdeal, idealMeta] = type1_apply_switch_impairments(raw122, idealModel);
[~, virtualImpaired, impairedMeta] = type1_apply_switch_impairments(raw122, impairedModel);

ideal = run_case('ideal', virtualIdeal, package);
impaired = run_case('impaired', virtualImpaired, package);
paired = struct2table([ideal.summary impaired.summary]);
paired.Properties.RowNames = {'ideal', 'impaired'};
delta = paired{'impaired', metric_columns()} - paired{'ideal', metric_columns()};
deltaTable = array2table(delta, 'VariableNames', strcat("delta_", metric_columns()));

fprintf('\n--- Paired result table (same OTA raw122) ---\n');
disp(paired(:, ["analysisOK" "bestNID2" "expectedNID2" "pssNID2OK" ...
    "pbchCRCOK" "mibMatches" "pbchOK" "rawBER" "rawBitErrors" ...
    "meanEVMPercent" "condP95"]));
fprintf('--- Impaired - ideal metric deltas ---\n');
disp(deltaTable);

idealUsable = ideal.summary.analysisOK && ideal.summary.pssNID2OK && ...
    ideal.summary.pbchOK && isfinite(ideal.summary.meanEVMPercent) && ...
    ideal.summary.meanEVMPercent <= options.maxIdealEVMPercent;
if idealUsable
    fprintf('OTA baseline gate: PASS (PSS/PBCH valid, ideal EVM <= %.1f%%).\n', ...
        options.maxIdealEVMPercent);
else
    fprintf(['OTA baseline gate: FAIL.  This capture may be used for diagnosis only; ' ...
        'do not compare its impairment deltas with offline simulation.\n']);
end

report = struct('rawFile', rawFile, 'options', options, ...
    'idealModel', idealModel, 'impairedModel', impairedModel, ...
    'idealSwitchMeta', idealMeta, 'impairedSwitchMeta', impairedMeta, ...
    'ideal', ideal, 'impaired', impaired, 'paired', paired, ...
    'delta', deltaTable, 'idealBaselineUsable', idealUsable);
[folder, name] = fileparts(rawFile);
outFile = fullfile(folder, [name '_paired_switch_injection.mat']);
save(outFile, 'report', '-v7.3');
fprintf('Saved paired report: %s\n', outFile);
end

function columns = metric_columns()
columns = ["rawBER" "rawBitErrors" "meanEVMPercent" "condMedian" "condP95" "condMax"];
end

function outcome = run_case(label, virtual30, package)
outcome = struct('label', label, 'result', [], 'error', "", 'summary', []);
try
    outcome.result = type1_analyze(virtual30, package);
    outcome.summary = summarize_result(outcome.result);
catch err
    outcome.error = string(getReport(err, 'basic', 'hyperlinks', 'off'));
    outcome.summary = failed_summary();
    fprintf('%s analysis failed: %s\n', label, outcome.error);
end
end

function summary = summarize_result(result)
summary = struct( ...
    'analysisOK', true, ...
    'bestNID2', result.bestNID2, ...
    'expectedNID2', result.expectedNID2, ...
    'pssNID2OK', result.bestNID2 == result.expectedNID2, ...
    'pssPeakMetric', max(result.pssMetrics), ...
    'pbchCRCOK', ~result.pbchCRCError, ...
    'mibMatches', result.mibMatches, ...
    'pbchOK', ~result.pbchCRCError && result.mibMatches, ...
    'timingOffsetSamples', result.timingOffset, ...
    'frequencyOffsetHz', result.frequencyOffsetHz, ...
    'sssMetric', result.sssMetric, ...
    'rawBER', mean(result.rawBER, 'all', 'omitnan'), ...
    'rawBitErrors', sum(result.rawBitErrors, 'all', 'omitnan'), ...
    'meanEVMPercent', mean(result.evmRMSPercent, 'all', 'omitnan'), ...
    'condMedian', result.conditionStats(1), ...
    'condP95', result.conditionStats(2), ...
    'condMax', result.conditionStats(3));
end

function summary = failed_summary()
summary = struct('analysisOK', false, 'bestNID2', nan, 'expectedNID2', nan, ...
    'pssNID2OK', false, 'pssPeakMetric', nan, ...
    'pbchCRCOK', false, 'mibMatches', false, 'pbchOK', false, ...
    'timingOffsetSamples', nan, 'frequencyOffsetHz', nan, 'sssMetric', nan, ...
    'rawBER', nan, 'rawBitErrors', nan, 'meanEVMPercent', nan, ...
    'condMedian', nan, 'condP95', nan, 'condMax', nan);
end

function file = resolve_raw_file(requested, dataRoot)
if strlength(string(requested)) == 0
    requested = string(getenv('TYPE1_OTA_RAW_FILE'));
end
if strlength(string(requested)) > 0
    file = char(requested);
    if exist(file, 'file') ~= 2
        file = fullfile(dataRoot, file);
    end
    assert(exist(file, 'file') == 2, 'type1:OTAIQ', ...
        'Requested raw122 IQ file does not exist: %s', file);
    return;
end
files = dir(fullfile(dataRoot, '*_raw122_csingle_iq4.bin'));
assert(~isempty(files), 'type1:OTAIQ', ...
    'No saved raw122 OTA IQ is available under %s.', dataRoot);
[~, index] = max([files.datenum]);
file = fullfile(files(index).folder, files(index).name);
end

function x = read_complex_single_iq(file, nChannels)
fid = fopen(file, 'rb');
assert(fid >= 0, 'type1:OpenIQFile', 'Could not open %s.', file);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
raw = fread(fid, inf, 'single=>single');
assert(mod(numel(raw), 2 * nChannels) == 0, 'type1:IQFileSize', ...
    'File length is not divisible by 2*nChannels: %s', file);
x = reshape(complex(raw(1:2:end), raw(2:2:end)), [], nChannels);
end
