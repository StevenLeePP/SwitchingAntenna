function result = type1_analyze_user_cfo(rx30, package)
%TYPE1_ANALYZE_USER_CFO DM-RS cross-slot residual-CFO RZF baseline.
%   Synchronization and common CFO come from the established full receiver.
%   Residual CFO is estimated per layer from consecutive slot DM-RS channel
%   phases, then applied as a time-varying column phase in the RZF channel.
%   Adjacent 0.5 ms slots give a principal-angle unambiguous range of
%   +/-1 kHz.  A warning is emitted well before that boundary; an exact
%   integer multiple of the ambiguity range cannot be detected after phase
%   wrapping and needs a different estimator/DM-RS spacing.

assert(strcmp(package.channelCoding,'none'), ...
    'type1:UserCFOCoding','Current baseline is defined for uncoded QPSK.');
base = type1_analyze(rx30, package); cfg = package.cfg; nRx=size(rx30,2);
fs=cfg.txSampleRate; frameN=round(cfg.frameDurationSec*fs);
frame=double(rx30(base.timingOffset+(1:frameN),:));
frame=frame.*exp(-1j*2*pi*base.frequencyOffsetHz*(0:frameN-1).'/fs);
carrier=type1_carrier_config(cfg,0);
grid=nrOFDMDemodulate(carrier,frame,'Nfft',cfg.nfft,'SampleRate',fs,'CarrierFrequency',0);
grid=grid(:,1:cfg.symbolsPerFrame,:); nSlots=numel(cfg.dataSlots); nData=package.nDataREPerSlotLayer;
hDmrs=complex(zeros(12*cfg.nRB,nRx,cfg.nLayers,nSlots)); channels=cell(nSlots,1);
for s=1:nSlots
    slot=cfg.dataSlots(s); rxSlot=grid(:,slot*14+(1:14),:);
    channels{s}=nrChannelEstimate(rxSlot,double(package.dmrsIndices(:,:,s)), ...
        double(package.dmrsSymbols(:,:,s)),'CDMLengths',package.dmrsCDMLengths);
    hDmrs(:,:,:,s)=squeeze(channels{s}(:,cfg.dmrsTypeAPosition+1,:,:));
end
residual=zeros(1,cfg.nLayers); slotDt=cfg.frameDurationSec/cfg.slotsPerFrame;
unambiguousCfoHz=1/(2*slotDt); warningCfoHz=0.75*unambiguousCfoHz;
for p=1:cfg.nLayers
    phase=zeros(1,nSlots-1);
    for s=1:nSlots-1
        a=hDmrs(:,:,p,s); b=hDmrs(:,:,p,s+1);
        phase(s)=angle(sum(conj(a(:)).*b(:)));
    end
    residual(p)=median(phase)/(2*pi*slotDt);
end
if any(abs(residual)>=warningCfoHz)
    warning('type1:UserCFOAmbiguity', ['Residual CFO estimate [%s] Hz is within ' ...
        'the %.0f Hz guard of the +/-%.0f Hz adjacent-slot ambiguity range. ' ...
        'Do not use this estimator for a wider-CFO claim without unwrapping ' ...
        'or an additional time spacing.'], num2str(residual,'%.1f '), ...
        warningCfoHz, unambiguousCfoHz);
end
lengths=package.ofdmInfo.SymbolLengths(:);
% nrOFDMModulate may report one or two slots of symbol lengths.  The normal
% CP pattern repeats across this frame, so expand it before indexing slots 1:10.
lengths=repmat(lengths,ceil(cfg.symbolsPerFrame/numel(lengths)),1);
lengths=lengths(1:cfg.symbolsPerFrame); starts=[0;cumsum(lengths(1:end-1))]; centers=starts+lengths/2;
errors=zeros(nSlots,cfg.nLayers); evm=zeros(nSlots,cfg.nLayers);
for s=1:nSlots
    slot=cfg.dataSlots(s); ch=channels{s}; idx=double(package.dataIndices(:,1,s));
    [k,l]=ind2sub([12*cfg.nRB cfg.symbolsPerSlot cfg.nLayers],idx); id2=sub2ind([12*cfg.nRB cfg.symbolsPerSlot],k,l);
    received=complex(zeros(nData,nRx)); h=complex(zeros(nData,nRx,cfg.nLayers));
    dmrsTime=centers(slot*14+cfg.dmrsTypeAPosition+1);
    dt=centers(slot*14+l)-dmrsTime;
    for r=1:nRx
        plane=grid(:,slot*14+(1:14),r); received(:,r)=plane(id2);
        for p=1:cfg.nLayers
            hp=ch(:,:,r,p); h(:,r,p)=hp(id2).*exp(1j*2*pi*residual(p)*dt/fs);
        end
    end
    hp=permute(h,[2 3 1]); yp=permute(received,[2 3 1]); hh=pagectranspose(hp);
    gram=pagemtimes(hh,hp); matched=pagemtimes(hh,yp); power=sum(abs(hp).^2,[1 2])/cfg.nLayers;
    lambda=cfg.rzfRegularization*max(power,eps); x=pagemldivide(gram+reshape(eye(cfg.nLayers),cfg.nLayers,cfg.nLayers,1).*lambda,matched);
    x=permute(x,[3 2 1]);
    for p=1:cfg.nLayers
        bits=logical(nrSymbolDemodulate(x(:,1,p),cfg.modulation,'DecisionType','hard'));
        expected=package.codedBits(:,s,p); errors(s,p)=sum(bits~=expected);
        ref=double(package.dataQPSK(:,s,p)); evm(s,p)=100*rms(x(:,1,p)-ref)/rms(ref);
    end
end
result=struct('base',base,'residualCfoHz',residual,'rawBitErrors',errors, ...
    'rawBER',errors/package.nCodedBitsPerSlotLayer,'infoBitErrors',errors, ...
    'infoBER',errors/package.nInfoBitsPerSlotLayer,'evmRMSPercent',evm, ...
    'residualCfoUnambiguousHz',unambiguousCfoHz, ...
    'residualCfoWarningHz',warningCfoHz);
end
