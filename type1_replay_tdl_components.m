function components = type1_replay_tdl_components(tx, cfg, model)
%TYPE1_REPLAY_TDL_COMPONENTS Recreate each noiseless layer of a saved TDL draw.
%   components(:,r,p) is the contribution of TX layer p at physical RX r.
%   The helper consumes the exact gains stored by type1_make_tdl_a_channel;
%   it draws no random values and is intended only for genie diagnostics.

assert(strcmp(model.profile,'3GPP TDL-A'),'type1:ReplayTDLProfile', ...
    'Only saved 3GPP TDL-A draws are supported.');
n=size(tx,1); nRx=cfg.nRxChannels; nTx=cfg.nLayers;
delaySamples=model.delaysNormalized*model.delaySpreadNs*1e-9*cfg.txSampleRate;
nfft=2^nextpow2(n+ceil(max(delaySamples))+2);
f=ifftshift((-floor(nfft/2):ceil(nfft/2)-1).'/nfft); X=fft(tx,nfft);
components=complex(zeros(n,nRx,nTx));
for r=1:nRx
    for p=1:nTx
        response=complex(zeros(nfft,1));
        for tap=1:numel(delaySamples)
            response=response+model.gains(r,p,tap)*exp(-1j*2*pi*f*delaySamples(tap));
        end
        y=ifft(X(:,p).*response); components(:,r,p)=y(1:n);
    end
end
end
