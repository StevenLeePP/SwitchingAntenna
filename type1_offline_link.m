function link = type1_offline_link(package, sim, stream)
%TYPE1_OFFLINE_LINK Build one hardware-free reference-to-virtual-RX window.
%   Reference layers receive independently configurable CFO, timing and
%   power terms, then pass through a flat MIMO channel and AWGN.  With
%   useSwitchEmulation=true the four full-rate physical RX streams are
%   upsampled and fed through type1_digital_switch, yielding one stitched
%   single-chain stream plus four virtual 30.72-MS/s streams.

arguments
    package (1,1) struct
    sim (1,1) struct
    stream (1,1) RandStream
end

cfg = package.cfg;
nLayers = cfg.nLayers;
assert(isequal(size(sim.channel), [cfg.nRxChannels nLayers]), ...
    'type1:OfflineChannel', 'sim.channel must be nRxChannels-by-nLayers.');
assert(numel(sim.userCfoHz) == nLayers && ...
    numel(sim.userTimingSamples) == nLayers && ...
    numel(sim.userPowerDb) == nLayers && ...
    numel(sim.userPhaseNoiseStdRadPerSample) == nLayers, ...
    'type1:OfflineUsers', 'Per-user impairment vectors must have nLayers elements.');
assert(sim.switchOversample == 4, ...
    'type1:OfflineSwitch', 'The current four-phase model requires 4x oversampling.');

tx = double(package.txWaveform);
nSamples = size(tx, 1);
n = (0:nSamples-1).';
impairedTx = complex(zeros(size(tx)));
for layer = 1:nLayers
    x = tx(:, layer) * 10^(sim.userPowerDb(layer) / 20);
    x = fractional_delay(x, sim.userTimingSamples(layer));
    frequencyHz = sim.commonCfoHz + sim.userCfoHz(layer);
    phaseNoise = wiener_phase_noise(nSamples, ...
        sim.userPhaseNoiseStdRadPerSample(layer), stream);
    impairedTx(:, layer) = x .* exp(1j * ( ...
        2*pi * frequencyHz * n / cfg.txSampleRate + phaseNoise));
end

if sim.channelModel=="flat"
    physicalRx30 = impairedTx * sim.channel.';
    channelModel = struct('profile','deterministic flat','matrix',sim.channel);
else
    [physicalRx30,channelModel] = type1_make_tdl_a_channel(impairedTx,cfg,sim.tdl,stream);
end
signalPower = mean(abs(physicalRx30).^2, 'all');
noiseVariance = signalPower / 10^(sim.snrDb / 10);
noise = sqrt(noiseVariance / 2) .* ( ...
    randn(stream, size(physicalRx30)) + 1j * randn(stream, size(physicalRx30)));
physicalRx30 = physicalRx30 + noise;

prefix = complex(zeros(sim.prefixSamples, cfg.nRxChannels));
suffixLength = min(sim.suffixSamples, size(physicalRx30, 1));
rxWindow30 = [prefix; physicalRx30; physicalRx30(1:suffixLength, :)];

if sim.useSwitchEmulation
    raw122 = complex(zeros(sim.switchOversample * size(rxWindow30, 1), ...
        cfg.nRxChannels));
    for rx = 1:cfg.nRxChannels
        raw122(:, rx) = resample(rxWindow30(:, rx), sim.switchOversample, 1);
    end
    [stitched122, virtualRx30, switchMeta] = ...
        type1_apply_switch_impairments(raw122, sim.switch, stream);
else
    raw122 = complex(zeros(0, cfg.nRxChannels));
    stitched122 = complex(zeros(0, 1));
    virtualRx30 = rxWindow30;
    switchMeta = struct('leakageAmplitude', 0, 'leakageMatrix', eye(4), ...
        'settlingBetaMean', 1, 'settlingBetaStd', 0, 'settlingRiseNs', 0, ...
        'transitionJitterStdPs', 0, 'isolationDb', Inf);
end

link = struct('virtualRx30', single(virtualRx30), ...
    'physicalRx30', single(physicalRx30), 'raw122', single(raw122), ...
    'stitched122', single(stitched122), 'noiseVariance', noiseVariance, ...
    'simulatedChannel', channelModel, 'impairedTx', single(impairedTx), ...
    'userCfoHz', sim.userCfoHz, 'userTimingSamples', sim.userTimingSamples, ...
    'userPowerDb', sim.userPowerDb, ...
    'userPhaseNoiseStdRadPerSample', sim.userPhaseNoiseStdRadPerSample, ...
    'switchMeta', switchMeta);
end

function y = fractional_delay(x, delaySamples)
% Positive delay means y[n]=x[n-delay].  A zero-padded DFT shift is used
% instead of linear interpolation, whose high-frequency roll-off would be
% an unintended amplitude impairment in this 18.36-MHz occupied waveform.
if delaySamples == 0
    y = x;
    return;
end
n = numel(x);
nfft = 2^nextpow2(2*n);
frequency = ifftshift((-floor(nfft/2):ceil(nfft/2)-1).' / nfft);
yFull = ifft(fft(x, nfft) .* exp(-1j * 2*pi * frequency * delaySamples));
y = yFull(1:n);
end

function phase = wiener_phase_noise(nSamples, incrementStd, stream)
if incrementStd == 0
    phase = zeros(nSamples, 1);
    return;
end
assert(isfinite(incrementStd) && incrementStd >= 0, ...
    'type1:OfflinePhaseNoise', 'Phase-noise increment standard deviation must be finite and nonnegative.');
phase = cumsum(incrementStd * randn(stream, nSamples, 1));
end
