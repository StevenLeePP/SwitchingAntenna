%% TYPE1_VALIDATE_RZF_MEX Compare fixed MEX RZF/QPSK against Toolbox path.
% The script leaves cfg.fastUseRZFQPSKMEX unchanged. It must pass before
% enabling the MEX fast path in type1_config.m.

clear; clc;
sourceDir = fileparts(mfilename('fullpath'));
addpath(sourceDir);
if exist('type1_rzf_qpsk_mex', 'file') ~= 3
    type1_build_decode_mex();
end

package = type1_load_package();
dataSlot = package.cfg.dataSlots(ceil(numel(package.cfg.dataSlots)/2));
iqFile = newest_file(fullfile(sourceDir, 'data'), '*_virtual30_csingle_iq4.bin');
rx30 = read_complex_single_iq(iqFile, package.cfg.nRxChannels);

acquire = type1_analyze_fast(rx30, package, dataSlot, 'forcePSS', true);
trackArgs = {'collectTiming', true, 'forcePSS', false, 'syncState', acquire.syncState, ...
    'trackedTimingOffset', acquire.timingOffset};

baselinePackage = package;
baselinePackage.cfg.fastUseRZFQPSKMEX = false;
baseline = type1_analyze_fast(rx30, baselinePackage, dataSlot, trackArgs{:});

mexPackage = package;
mexPackage.cfg.fastUseRZFQPSKMEX = true;
mexResult = type1_analyze_fast(rx30, mexPackage, dataSlot, trackArgs{:});

symbolError = max(abs(baseline.postCompData - mexResult.postCompData), [], 'all');
evmDifference = max(abs(baseline.evmRMSPercent - mexResult.evmRMSPercent));
sameErrors = isequal(baseline.rawBitErrors, mexResult.rawBitErrors);
sameBER = isequal(baseline.rawBER, mexResult.rawBER);

fprintf('\n========== Type-A RZF/QPSK MEX validation ==========\n');
fprintf('IQ                 : %s\n', iqFile);
fprintf('Max |x_toolbox-x_mex|: %.3g\n', symbolError);
fprintf('EVM difference %%    : %.3g\n', evmDifference);
fprintf('Bit errors equal    : %d\n', sameErrors);
fprintf('BER equal           : %d\n', sameBER);
fprintf('Toolbox RZF/BER ms  : %.3f / %.3f\n', ...
    baseline.stageTimesMs.rzfEqualize, baseline.stageTimesMs.berAndEvm);
fprintf('MEX RZF/BER ms      : %.3f / %.3f\n', ...
    mexResult.stageTimesMs.rzfEqualize, mexResult.stageTimesMs.berAndEvm);

assert(symbolError < 2e-3, 'type1:RZFValidation', ...
    'MEX equalized symbols differ from Toolbox beyond tolerance.');
assert(evmDifference < 0.02 && sameErrors && sameBER, ...
    'type1:RZFValidation', 'MEX BER/EVM does not match Toolbox.');
disp('Type-A RZF/QPSK MEX validation PASSED.');

function fileName = newest_file(dataDir, pattern)
files = dir(fullfile(dataDir, pattern));
assert(~isempty(files), 'type1:RZFValidation', 'No saved virtual30 IQ found.');
[~, index] = max([files.datenum]);
fileName = fullfile(files(index).folder, files(index).name);
end

function x = read_complex_single_iq(fileName, nChannels)
fid = fopen(fileName, 'rb');
assert(fid >= 0, 'type1:RZFValidation', 'Cannot open %s.', fileName);
cleanup = onCleanup(@() fclose(fid));
raw = fread(fid, [2*nChannels inf], '*single');
raw = raw(:);
assert(mod(numel(raw), 2*nChannels) == 0, ...
    'type1:RZFValidation', 'Invalid interleaved IQ size.');
x = reshape(complex(raw(1:2:end), raw(2:2:end)), [], nChannels);
end
