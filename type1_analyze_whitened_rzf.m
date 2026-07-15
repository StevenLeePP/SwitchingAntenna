function result = type1_analyze_whitened_rzf(rx30, package)
%TYPE1_ANALYZE_WHITENED_RZF DM-RS-residual covariance weighted 4x4 RZF.
%   Uses the established PSS/common-CFO/PBCH receiver as the control plane.
%   For each payload slot it estimates R_ee from the vector residual between
%   received DM-RS and Hhat*x_DMRS, then applies the R^-1 weighted form
%     (H^H R^-1 H + lambda I)^-1 H^H R^-1 y.
%   This is algebraically equivalent to R^-1/2 pre-whitening followed by
%   standard RZF.  It is an estimated-residual baseline, not oracle E(t).

assert(strcmp(package.channelCoding, 'none'), ...
    'type1:WhitenedRZFCoding', 'Current baseline is defined for uncoded QPSK.');
base = type1_analyze(rx30, package);
cfg = package.cfg; nRx = size(rx30, 2); nLayers = cfg.nLayers;
assert(nRx >= nLayers, 'type1:WhitenedRZFRx', 'Whitened RZF requires nRx >= nLayers.');

fs = cfg.txSampleRate; frameN = round(cfg.frameDurationSec * fs);
frame = double(rx30(base.timingOffset + (1:frameN), :));
frame = frame .* exp(-1j * 2*pi * base.frequencyOffsetHz * ...
    (0:frameN-1).' / fs);
carrier = type1_carrier_config(cfg, 0);
grid = nrOFDMDemodulate(carrier, frame, 'Nfft', cfg.nfft, ...
    'SampleRate', fs, 'CarrierFrequency', 0);
grid = grid(:, 1:cfg.symbolsPerFrame, :);

nSC = 12 * cfg.nRB; nSlots = numel(cfg.dataSlots);
nData = package.nDataREPerSlotLayer;
errors = zeros(nSlots, nLayers); evm = zeros(nSlots, nLayers);
covariances = complex(zeros(nRx, nRx, nSlots));
residualPower = zeros(1, nSlots);
for s = 1:nSlots
    slot = cfg.dataSlots(s);
    rxSlot = grid(:, slot*cfg.symbolsPerSlot + (1:cfg.symbolsPerSlot), :);
    channel = nrChannelEstimate(rxSlot, double(package.dmrsIndices(:, :, s)), ...
        double(package.dmrsSymbols(:, :, s)), 'CDMLengths', package.dmrsCDMLengths);
    R = dmrs_residual_covariance(rxSlot, channel, package, s, nSC, nRx, nLayers);
    covariances(:, :, s) = R;
    residualPower(s) = real(trace(R)) / nRx;

    first = double(package.dataIndices(:, 1, s));
    [subcarrier, symbol] = ind2sub([nSC cfg.symbolsPerSlot nLayers], first);
    indices2D = sub2ind([nSC cfg.symbolsPerSlot], subcarrier, symbol);
    received = complex(zeros(nData, nRx));
    h = complex(zeros(nData, nRx, nLayers));
    for r = 1:nRx
        plane = rxSlot(:, :, r);
        received(:, r) = plane(indices2D);
        for p = 1:nLayers
            hp = channel(:, :, r, p);
            h(:, r, p) = hp(indices2D);
        end
    end
    hPages = permute(h, [2 3 1]);
    yPages = permute(received, [2 3 1]);
    Rpages = repmat(R, 1, 1, nData);
    weightedH = pagemldivide(Rpages, hPages);
    weightedY = pagemldivide(Rpages, yPages);
    hHermitian = pagectranspose(hPages);
    gram = pagemtimes(hHermitian, weightedH);
    matched = pagemtimes(hHermitian, weightedY);
    channelPower = sum(abs(hPages).^2, [1 2]) / nLayers;
    lambda = cfg.rzfRegularization * max(channelPower, eps);
    equalized = pagemldivide(gram + ...
        reshape(eye(nLayers), nLayers, nLayers, 1) .* lambda, matched);
    equalized = permute(equalized, [3 2 1]);
    for p = 1:nLayers
        bits = logical(nrSymbolDemodulate(equalized(:, 1, p), cfg.modulation, ...
            'DecisionType', 'hard'));
        expected = package.codedBits(:, s, p);
        errors(s, p) = sum(bits ~= expected);
        reference = double(package.dataQPSK(:, s, p));
        evm(s, p) = 100 * rms(equalized(:, 1, p) - reference) / rms(reference);
    end
end

result = struct('base', base, 'rawBitErrors', errors, ...
    'rawBER', errors / package.nCodedBitsPerSlotLayer, ...
    'infoBitErrors', errors, ...
    'infoBER', errors / package.nInfoBitsPerSlotLayer, ...
    'evmRMSPercent', evm, 'residualCovariance', covariances, ...
    'residualPower', residualPower, 'covarianceMethod', 'DMRS residual Rhat_ee');
end

function R = dmrs_residual_covariance(rxSlot, channel, package, slotIndex, nSC, nRx, nLayers)
% Build the actual multi-port DM-RS vector at every occupied 2-D RE.
tx = complex(zeros(nSC * size(rxSlot, 2), nLayers));
for p = 1:nLayers
    index3D = double(package.dmrsIndices(:, p, slotIndex));
    % DM-RS indices retain their port/layer plane.  Reducing modulo one
    % slot plane gives the common 2-D RE directly and avoids assuming that
    % every port was stored in plane one.
    index2D = mod(index3D - 1, nSC * size(rxSlot, 2)) + 1;
    tx(index2D, p) = double(package.dmrsSymbols(:, p, slotIndex));
end
active = find(any(abs(tx) > 0, 2));
E = complex(zeros(numel(active), nRx));
for r = 1:nRx
    y = rxSlot(:, :, r); y = y(active);
    prediction = complex(zeros(numel(active), 1));
    for p = 1:nLayers
        hp = channel(:, :, r, p);
        prediction = prediction + hp(active) .* tx(active, p);
    end
    E(:, r) = y - prediction;
end
R = (E' * E) / max(size(E, 1), 1);
R = (R + R') / 2;
power = max(real(trace(R)) / nRx, eps);
% Diagonal loading makes the finite-DM-RS covariance positive definite but
% retains its off-diagonal correlation.  The coefficient is explicit.
R = R + 0.05 * power * eye(nRx);
end
