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
    numel(sim.userPowerDb) == nLayers, ...
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
    impairedTx(:, layer) = x .* exp(1j * 2*pi * frequencyHz * n / cfg.txSampleRate);
end

physicalRx30 = impairedTx * sim.channel.';
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
    [stitched122, virtualRx30] = type1_digital_switch(raw122);
else
    raw122 = complex(zeros(0, cfg.nRxChannels));
    stitched122 = complex(zeros(0, 1));
    virtualRx30 = rxWindow30;
end

link = struct('virtualRx30', single(virtualRx30), ...
    'physicalRx30', single(physicalRx30), 'raw122', single(raw122), ...
    'stitched122', single(stitched122), 'noiseVariance', noiseVariance, ...
    'simulatedChannel', sim.channel, 'impairedTx', single(impairedTx));
end

function y = fractional_delay(x, delaySamples)
% Positive delay means y[n]=x[n-delay].  Interpolation is intentionally
% explicit: it is a controlled research impairment, not a hidden resampler.
if delaySamples == 0
    y = x;
    return;
end
n = (0:numel(x)-1).';
y = interp1(n, x, n-delaySamples, 'linear', 0);
end
