function type1_validate_ofdmgrid_mex()
%TYPE1_VALIDATE_OFDMGRID_MEX Establish C FFT/grid equivalence offline.
% This test does not open YunSDR.  It uses an existing virtual30 capture,
% the normal MATLAB acquire/CFO baseline, and compares the new C FFT grid
% against the exact grid consumed by type1_decode_frame_batch.

clear; clc;
sourceDir = fileparts(mfilename('fullpath'));
addpath(sourceDir);
type1_build_rx_mex();

package = type1_load_package();
cfg = package.cfg;
iqFile = newest_file(fullfile(sourceDir, 'data'), '*_virtual30_csingle_iq4.bin');
rx30 = read_iq(iqFile, cfg.nRxChannels);
acquire = type1_analyze_fast(rx30, package, cfg.dataSlots(1), 'forcePSS', true);

frameSamples = round(cfg.frameDurationSec * cfg.txSampleRate);
slotSamples = frameSamples / cfg.slotsPerFrame;
activeSlots = max(cfg.dataSlots) + 1;
activeSamples = activeSlots * slotSamples;
frame = single(rx30(acquire.timingOffset + (1:activeSamples), :));
samplePhase = single(mod((0:activeSamples-1).', slotSamples));
matlabWaveform = frame .* exp(single(-1j * 2*pi * acquire.frequencyOffsetHz / ...
    cfg.txSampleRate) .* samplePhase);

carrier = type1_carrier_config(cfg, 0);
matlabGrid = nrOFDMDemodulate(carrier, matlabWaveform, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0);
matlabGridEnd = nrOFDMDemodulate(carrier, matlabWaveform, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0, ...
    'CyclicPrefixFraction', 1);
matlabGridHalf = nrOFDMDemodulate(carrier, matlabWaveform, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0, ...
    'CyclicPrefixFraction', 0.5);
cp = double(package.ofdmInfo.CyclicPrefixLengths(:));
cp = repmat(cp, ceil(activeSlots * cfg.symbolsPerSlot / numel(cp)), 1);
cp = cp(1:activeSlots * cfg.symbolsPerSlot);
endWindowGrid = type1_yunsdr_rx_mex('ofdmgrid', frame, cp, ...
    double(acquire.frequencyOffsetHz), double(slotSamples));
windowOffsets = -floor(cp/2);
cGridCentered = type1_yunsdr_rx_mex('ofdmgrid', frame, cp, ...
    double(acquire.frequencyOffsetHz), double(slotSamples), windowOffsets);
cGrid = endWindowGrid;
matlabGridNoCfo = nrOFDMDemodulate(carrier, frame, ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0);
cGridNoCfo = type1_yunsdr_rx_mex('ofdmgrid', frame, cp, 0, double(slotSamples));
fftInput = frame(cp(1) + (1:cfg.nfft), :);
cFftGrid = type1_yunsdr_rx_mex('ofdmgrid', fftInput, 0, 0, double(cfg.nfft));
matlabFft = fftshift(fft(fftInput, cfg.nfft, 1), 1);
matlabFftGrid = matlabFft(cfg.nfft/2-cfg.nRB*12/2+(1:cfg.nRB*12), :);

gain = sum(conj(double(cGrid(:))) .* double(matlabGrid(:))) / ...
    sum(abs(double(cGrid(:))).^2);
rawNmseDb = nmse_db(cGrid, matlabGrid);
alignedNmseDb = nmse_db(single(gain) .* cGrid, matlabGrid);

[cErrors, cEvm, ~, cH] = type1_decode_frame_grid_mex(cGrid, ...
    double(cfg.dataSlots(:)), package.dmrsIndices, package.dmrsSymbols, ...
    package.dataIndices, package.dataQPSK, package.codedBits, cfg.rzfRegularization);
batch = type1_decode_frame_batch(frame, package, acquire.frequencyOffsetHz);
hGain = sum(conj(double(cH(:))) .* double(batch.hFrequency(:))) / ...
    sum(abs(double(cH(:))).^2);
hAlignedNmseDb = nmse_db(single(hGain) .* cH, batch.hFrequency);

fprintf('\n========== C OFDM-grid validation ==========\n');
fprintf('Grid C->MATLAB gain = %.8g%+.8gi; raw/aligned NMSE = %.2f / %.2f dB\n', ...
    real(gain), imag(gain), rawNmseDb, alignedNmseDb);
fprintf('End-of-CP grid NMSE = %.2f dB; tested CP-centered offsets = [%d %d]\n', ...
    nmse_db(endWindowGrid, matlabGrid), min(windowOffsets), max(windowOffsets));
fprintf('MATLAB default/end/half NMSEs: default-end %.2f dB, default-half %.2f dB; C-centered-default %.2f dB\n', ...
    nmse_db(matlabGridEnd, matlabGrid), nmse_db(matlabGridHalf, matlabGrid), ...
    nmse_db(cGridCentered, matlabGrid));
fprintf('C end vs MATLAB end %.2f dB; C-centered vs MATLAB half %.2f dB\n', ...
    nmse_db(endWindowGrid, matlabGridEnd), nmse_db(cGridCentered, matlabGridHalf));
symbolIndex = cfg.dataSlots(1)*cfg.symbolsPerSlot + 1;
subcarriers = (-cfg.nRB*12/2:cfg.nRB*12/2-1).';
ratio = matlabGrid(:,symbolIndex,1) ./ matlabGridEnd(:,symbolIndex,1);
valid = abs(matlabGridEnd(:,symbolIndex,1)) > 1e-4;
phaseFit = polyfit(subcarriers(valid), unwrap(angle(ratio(valid))), 1);
phaseModel = exp(1j * polyval(phaseFit, subcarriers(valid)));
phaseResidualDb = 10*log10(sum(abs(ratio(valid)-phaseModel).^2) / sum(abs(ratio(valid)).^2));
fprintf('Default CP phase fit: slope %.9g rad/SC (%.6g samples), residual %.2f dB\n', ...
    phaseFit(1), -phaseFit(1)*cfg.nfft/(2*pi), phaseResidualDb);
fractions = [0 0.25 0.5 0.75 1];
fractionNmse = zeros(size(fractions));
for index = 1:numel(fractions)
    testGrid = nrOFDMDemodulate(carrier, matlabWaveform, ...
        'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, 'CarrierFrequency', 0, ...
        'CyclicPrefixFraction', fractions(index));
    fractionNmse(index) = nmse_db(testGrid, matlabGridEnd);
end
fprintf('MATLAB CP fraction vs end NMSE [0 .25 .5 .75 1] = [%s] dB\n', ...
    num2str(fractionNmse, '%.2f '));
fprintf('No-CFO grid NMSE = %.2f dB (isolates FFT/bin/CP from CFO phase)\n', ...
    nmse_db(cGridNoCfo, matlabGridNoCfo));
fprintf('Standalone FFT/bin NMSE = %.2f dB\n', nmse_db(cFftGrid, matlabFftGrid));
fprintf('Grid-decoder errors equal: %d; max EVM difference: %.4f %%\n', ...
    isequal(cErrors, batch.rawBitErrors), max(abs(cEvm-batch.evmRMSPercent), [], 'all'));
fprintf('H C->batch aligned NMSE = %.2f dB\n', hAlignedNmseDb);
assert(isequal(cErrors, batch.rawBitErrors), ...
    'type1:COfdmGrid', 'C-grid hard-decision errors differ from batch baseline.');
assert(alignedNmseDb < -70, 'type1:COfdmGrid', ...
    'C grid differs from MATLAB beyond floating-point tolerance.');
assert(hAlignedNmseDb < -65, 'type1:COfdmGrid', ...
    'C-grid channel estimate differs from batch baseline.');
disp('C OFDM-grid validation PASSED.');
end

function value = nmse_db(actual, reference)
value = 10*log10(sum(abs(double(actual(:))-double(reference(:))).^2) / ...
    (sum(abs(double(reference(:))).^2) + eps));
end

function filename = newest_file(directory, pattern)
files = dir(fullfile(directory, pattern));
assert(~isempty(files), 'type1:COfdmGrid', 'No virtual30 IQ capture found.');
[~, index] = max([files.datenum]);
filename = fullfile(files(index).folder, files(index).name);
end

function values = read_iq(filename, nChannels)
fid = fopen(filename, 'rb');
assert(fid >= 0, 'type1:COfdmGrid', 'Could not open %s.', filename);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
raw = fread(fid, inf, 'single=>single');
assert(mod(numel(raw), 2*nChannels) == 0, 'type1:COfdmGrid', 'Malformed IQ file.');
values = reshape(complex(raw(1:2:end), raw(2:2:end)), [], nChannels);
end
