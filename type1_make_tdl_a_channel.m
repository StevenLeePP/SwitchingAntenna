function [rx, model] = type1_make_tdl_a_channel(tx, cfg, tdl, stream)
%TYPE1_MAKE_TDL_A_CHANNEL Static 3GPP TDL-A PDP with Kronecker correlation.
%   Delays/powers are TS 38.901 TDL-A normalized values.  A static draw is
%   intentional for the current DM-RS/CFO study; Doppler is retained as an
%   explicit future model parameter, not silently approximated.

assert(tdl.dopplerHz==0,'type1:TDLDoppler','Time-varying TDL is not yet enabled.');
d=[0 .3819 .4025 .5868 .4610 .5375 .6708 .5750 .7618 1.5375 1.8978 ...
   2.2242 2.1718 2.4942 2.5119 3.0582 4.0810 4.4579 4.7834 4.9410 ...
   5.2812 6.6452 7.9317];
p=[-13.4 0 -2.2 -4 -6 -8.2 -9.9 -10.5 -7.5 -15.9 -6.6 -16.7 ...
   -12.4 -15.2 -10.8 -11.3 -12.7 -16.2 -18.3 -18.9 -16.6 -19.9 -29.7];
nRx=cfg.nRxChannels; nTx=cfg.nLayers; nTap=numel(d); fs=cfg.txSampleRate;
Rr=tdl.rxCorrelation.^abs((1:nRx)'-(1:nRx)); Rt=tdl.txCorrelation.^abs((1:nTx)'-(1:nTx));
Lr=chol(Rr,'lower'); Lt=chol(Rt,'lower'); gains=complex(zeros(nRx,nTx,nTap));
pow=10.^(p/10); pow=pow/sum(pow);
for k=1:nTap
    w=(randn(stream,nRx,nTx)+1j*randn(stream,nRx,nTx))/sqrt(2);
    gains(:,:,k)=sqrt(pow(k))*Lr*w*Lt';
end
delaySamples=d*tdl.delaySpreadNs*1e-9*fs; n=size(tx,1); nfft=2^nextpow2(n+ceil(max(delaySamples))+2);
f=ifftshift((-floor(nfft/2):ceil(nfft/2)-1).'/nfft); X=fft(tx,nfft); rx=complex(zeros(n,nRx));
for r=1:nRx
    h=complex(zeros(nfft,nTx));
    for k=1:nTap, h=h+exp(-1j*2*pi*f*delaySamples(k))*reshape(gains(r,:,k),1,nTx); end
    y=ifft(sum(X.*h,2)); rx(:,r)=y(1:n);
end
model=struct('profile','3GPP TDL-A','delaysNormalized',d,'powersDb',p, ...
    'delaySpreadNs',tdl.delaySpreadNs,'rxCorrelation',tdl.rxCorrelation, ...
    'txCorrelation',tdl.txCorrelation,'gains',gains);
end
