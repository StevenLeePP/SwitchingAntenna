function diagnostic = type1_measure_data_residual_frequency_correlation(rx30, package)
%TYPE1_MEASURE_DATA_RESIDUAL_FREQUENCY_CORRELATION Truth-aided ICI diagnostic.
%   Uses known simulation QPSK symbols only to measure e=y-Hhat*x on data
%   REs.  It is not a deployable receiver estimator.  Lag statistics average
%   adjacent active subcarriers within each payload OFDM symbol and RX branch.

base = type1_analyze(rx30, package); cfg = package.cfg; fs = cfg.txSampleRate;
frameN = round(cfg.frameDurationSec * fs);
frame = double(rx30(base.timingOffset + (1:frameN), :));
frame = frame .* exp(-1j*2*pi*base.frequencyOffsetHz*(0:frameN-1).'/fs);
carrier = type1_carrier_config(cfg, 0);
grid = nrOFDMDemodulate(carrier, frame, 'Nfft', cfg.nfft, ...
    'SampleRate', fs, 'CarrierFrequency', 0);
grid = grid(:, 1:cfg.symbolsPerFrame, :);
nSC = 12*cfg.nRB; nRx = size(grid,3); nLayers = cfg.nLayers;
lags = [1 5]; numerator = zeros(size(lags)); denominator = 0; samples = zeros(size(lags));
for s = 1:numel(cfg.dataSlots)
    slot = cfg.dataSlots(s); rxSlot = grid(:,slot*14+(1:14),:);
    channel = nrChannelEstimate(rxSlot,double(package.dmrsIndices(:,:,s)), ...
        double(package.dmrsSymbols(:,:,s)),'CDMLengths',package.dmrsCDMLengths);
    first = double(package.dataIndices(:,1,s));
    [k,l] = ind2sub([nSC cfg.symbolsPerSlot nLayers],first);
    index2D = sub2ind([nSC cfg.symbolsPerSlot],k,l);
    x = complex(zeros(numel(first),nLayers));
    for p=1:nLayers, x(:,p)=double(package.dataQPSK(:,s,p)); end
    for r=1:nRx
        yPlane=rxSlot(:,:,r); y=yPlane(index2D); prediction=complex(zeros(size(y)));
        for p=1:nLayers
            hPlane=channel(:,:,r,p); prediction=prediction+hPlane(index2D).*x(:,p);
        end
        e=y-prediction;
        for symbol=unique(l).'
            pick=find(l==symbol); [kSorted,order]=sort(k(pick)); eSorted=e(pick(order));
            denominator=denominator+sum(abs(eSorted).^2);
            for q=1:numel(lags)
                lag=lags(q); adjacent=find(kSorted(1:end-lag)+lag==kSorted(1+lag:end));
                numerator(q)=numerator(q)+sum(conj(eSorted(adjacent)).*eSorted(adjacent+lag));
                samples(q)=samples(q)+numel(adjacent);
            end
        end
    end
end
diagnostic=struct('lag',lags,'complexCorrelation',numerator/max(denominator,eps), ...
    'magnitudeCorrelation',abs(numerator/max(denominator,eps)), ...
    'residualPower',denominator/max(sum(samples),1), ...
    'pairCount',samples,'base',base, ...
    'truthAided',true,'definition','e=y-Hhat*x_true on data REs');
end
