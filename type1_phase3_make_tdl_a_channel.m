function [rx, channel] = type1_phase3_make_tdl_a_channel(tx, cfg, model, stream)
%TYPE1_PHASE3_MAKE_TDL_A_CHANNEL M-port TDL-A with geometry-bound correlation.
%   R_rx(m1,m2)=J0(2*pi*distance/lambda) for a ULA in 2-D isotropic
%   scattering.  This prevents an arbitrary correlation coefficient from
%   being tuned independently of aperture and port spacing.

arguments
    tx {mustBeNumeric}
    cfg (1,1) struct
    model (1,1) struct
    stream (1,1) RandStream
end
assert(model.tdl.dopplerHz == 0, 'type1:Phase3TDLDoppler', ...
    'Part A freezes a static TDL realization; Doppler is not yet enabled.');
M = model.nPhysical; N = model.nVirtual;
assert(size(tx, 2) == N, 'type1:Phase3TDLTxShape', ...
    'tx must contain N user/layer columns.');
assert(isequal(size(model.rxCorrelation), [M M]), ...
    'type1:Phase3CorrelationShape', 'Geometry correlation must be M-by-M.');

delayNormalized = [0 .3819 .4025 .5868 .4610 .5375 .6708 .5750 ...
    .7618 1.5375 1.8978 2.2242 2.1718 2.4942 2.5119 3.0582 ...
    4.0810 4.4579 4.7834 4.9410 5.2812 6.6452 7.9317];
powersDb = [-13.4 0 -2.2 -4 -6 -8.2 -9.9 -10.5 -7.5 -15.9 ...
    -6.6 -16.7 -12.4 -15.2 -10.8 -11.3 -12.7 -16.2 -18.3 ...
    -18.9 -16.6 -19.9 -29.7];
powers = 10.^(powersDb/10); powers = powers / sum(powers);

Rrx = (model.rxCorrelation + model.rxCorrelation') / 2;
Rtx = model.tdl.txCorrelation .^ abs((1:N)' - (1:N));
Lrx = psd_factor(Rrx);
Ltx = psd_factor(Rtx);
nTaps = numel(delayNormalized);
gains = complex(zeros(M, N, nTaps));
for k = 1:nTaps
    w = (randn(stream, M, N) + 1j*randn(stream, M, N)) / sqrt(2);
    gains(:, :, k) = sqrt(powers(k)) * Lrx * w * Ltx';
end

fs = cfg.txSampleRate;
delaySamples = delayNormalized * model.tdl.delaySpreadNs * 1e-9 * fs;
nSamples = size(tx, 1);
nfft = 2^nextpow2(nSamples + ceil(max(delaySamples)) + 2);
frequency = ifftshift((-floor(nfft/2):ceil(nfft/2)-1).' / nfft);
X = fft(tx, nfft);
rx = complex(zeros(nSamples, M));
for m = 1:M
    response = complex(zeros(nfft, N));
    for k = 1:nTaps
        response = response + exp(-1j*2*pi*frequency*delaySamples(k)) .* ...
            reshape(gains(m, :, k), 1, N);
    end
    y = ifft(sum(X .* response, 2));
    rx(:, m) = y(1:nSamples);
end

channel = struct('profile', "3GPP TDL-A", ...
    'delaysNormalized', delayNormalized, 'powersDb', powersDb, ...
    'delaySpreadNs', model.tdl.delaySpreadNs, ...
    'positionsLambda', model.positionsLambda, ...
    'apertureLambda', model.apertureLambda, ...
    'correlationModel', model.correlationModel, ...
    'rxCorrelation', Rrx, 'txCorrelation', Rtx, 'gains', gains, ...
    'minimumRxCorrelationEigenvalue', min(real(eig(Rrx))));
end

function L = psd_factor(R)
R = (R + R') / 2;
[V, D] = eig(R, 'vector');
tolerance = 1e-11 * max(1, max(abs(D)));
assert(min(real(D)) >= -tolerance, 'type1:Phase3CorrelationPSD', ...
    'Geometry-derived correlation is not positive semidefinite.');
L = V * diag(sqrt(max(real(D), 0)));
end
