function result = type1_decode_frame_batch(frameWaveform, package, frequencyOffsetHz)
%TYPE1_DECODE_FRAME_BATCH Decode configured payload slots in one frame.
% PSS/CFO state is external. Slots after max(cfg.dataSlots) are intentionally
% silent in half mode, so they are not FFT-demodulated at all.

cfg = package.cfg;
assert(strcmp(package.channelCoding,'none'), ...
    'Frame batch MEX currently targets the default uncoded BER mode.');
assert(exist('type1_decode_frame_grid_mex','file') == 3, ...
    'Build type1_decode_frame_grid_mex first.');
frameSamples = round(cfg.frameDurationSec * cfg.txSampleRate);
slotSamples = frameSamples / cfg.slotsPerFrame;
activeSlotCount = max(cfg.dataSlots) + 1;  % includes SSB slot 0
activeSamples = activeSlotCount * slotSamples;
assert(size(frameWaveform,1) >= activeSamples, ...
    'Need IQ through the last configured payload slot.');
frameWaveform = single(frameWaveform(1:activeSamples,:));
timer = tic;

t = tic;
% Keep the same per-slot CFO phase reference as type1_analyze_fast.  A
% constant phase is harmless to BER, but resetting here makes EVM and all
% diagnostics exactly comparable to the established one-slot path.
n = single(mod((0:activeSamples-1).', slotSamples));
frameWaveform = frameWaveform .* exp(single(-1j*2*pi*frequencyOffsetHz/cfg.txSampleRate) .* n);
cfoMs = 1e3*toc(t);

t = tic;
carrier = type1_carrier_config(cfg,0);
rxGrid = nrOFDMDemodulate(carrier, frameWaveform, ...
    'Nfft',cfg.nfft,'SampleRate',cfg.txSampleRate,'CarrierFrequency',0);
ofdmMs = 1e3*toc(t);

t = tic;
[rawErrors,evmPercent,noiseVariance,hFrequency] = type1_decode_frame_grid_mex( ...
    single(rxGrid), double(cfg.dataSlots(:)), package.dmrsIndices, ...
    package.dmrsSymbols, package.dataIndices, package.dataQPSK, ...
    package.codedBits, cfg.rzfRegularization);
phyMs = 1e3*toc(t);

result = struct;
% MEX uses rows=slots, columns=layers, identical to the existing slot path.
result.rawBitErrors = rawErrors;
result.rawBER = result.rawBitErrors / package.nCodedBitsPerSlotLayer;
result.evmRMSPercent = evmPercent;
result.noiseVariance = noiseVariance;
result.hFrequency = hFrequency;
result.activeSamples = activeSamples;
result.activeSlots = activeSlotCount;
result.cfoMs = cfoMs;
result.ofdmMs = ofdmMs;
result.phyMs = phyMs;
result.elapsedMs = 1e3*toc(timer);
end
