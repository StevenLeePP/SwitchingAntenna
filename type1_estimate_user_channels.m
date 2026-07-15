function estimate = type1_estimate_user_channels(grid, package, enableTiming, enableCfo)
%TYPE1_ESTIMATE_USER_CHANNELS Two-stage timing/CFO-aware Type-1 estimator.
%   Stage 1 estimates ordinary Type-1 channels.  A weighted circular LS of
%   adjacent-subcarrier phase estimates each user's aggregate timing slope.
%   Stage 2 embeds that slope in each user's known DM-RS symbols and reruns
%   nrChannelEstimate, preventing the slope from breaking OCC despreading.
%   The returned channel excludes the fitted timing phase; callers must
%   reapply timingPhase(k,p) on data REs.  Residual CFO is then estimated
%   from adjacent-slot DM-RS phase using the refined channels.

cfg=package.cfg; nSC=12*cfg.nRB; nSlots=numel(cfg.dataSlots); nRx=size(grid,3);
initial=cell(nSlots,1);
for s=1:nSlots
    slot=cfg.dataSlots(s); rxSlot=grid(:,slot*14+(1:14),:);
    initial{s}=nrChannelEstimate(rxSlot,double(package.dmrsIndices(:,:,s)), ...
        double(package.dmrsSymbols(:,:,s)),'CDMLengths',package.dmrsCDMLengths);
end
timingSamples=zeros(1,cfg.nLayers);
if enableTiming
    for p=1:cfg.nLayers
        phasor=0;
        for s=1:nSlots
            for r=1:nRx
                h=initial{s}(:,cfg.dmrsTypeAPosition+1,r,p);
                product=conj(h(1:end-1)).*h(2:end);
                weight=abs(h(1:end-1)).*abs(h(2:end));
                phasor=phasor+sum(weight.*product./max(abs(product),eps));
            end
        end
        slope=angle(phasor); timingSamples(p)=-slope*cfg.nfft/(2*pi);
    end
end
channels=cell(nSlots,1);
for s=1:nSlots
    slot=cfg.dataSlots(s); rxSlot=grid(:,slot*14+(1:14),:);
    symbols=double(package.dmrsSymbols(:,:,s)); indices=double(package.dmrsIndices(:,:,s));
    [k,~,layer]=ind2sub([nSC cfg.symbolsPerSlot cfg.nLayers],indices(:));
    layerTiming=reshape(timingSamples(layer),[],1);
    correction=exp(-1j*2*pi*(k-1).*layerTiming/cfg.nfft);
    symbols(:)=symbols(:).*correction;
    channels{s}=nrChannelEstimate(rxSlot,indices,symbols,'CDMLengths',package.dmrsCDMLengths);
end
residual=zeros(1,cfg.nLayers); slotDt=cfg.frameDurationSec/cfg.slotsPerFrame;
unambiguous=1/(2*slotDt); warningLevel=.75*unambiguous;
if enableCfo
    for p=1:cfg.nLayers
        phase=zeros(1,nSlots-1);
        for s=1:nSlots-1
            a=channels{s}(:,cfg.dmrsTypeAPosition+1,:,p);
            b=channels{s+1}(:,cfg.dmrsTypeAPosition+1,:,p);
            phase(s)=angle(sum(conj(a(:)).*b(:)));
        end
        residual(p)=median(phase)/(2*pi*slotDt);
    end
end
if any(abs(residual)>=warningLevel)
    warning('type1:UserCFOAmbiguity', ['Residual CFO estimate [%s] Hz is within the %.0f Hz guard of the +/-%.0f Hz ' ...
        'adjacent-slot ambiguity range; do not claim wider CFO operation without unwrapping.'], ...
        num2str(residual,'%.1f '),warningLevel,unambiguous);
end
lengths=package.ofdmInfo.SymbolLengths(:);
lengths=repmat(lengths,ceil(cfg.symbolsPerFrame/numel(lengths)),1); lengths=lengths(1:cfg.symbolsPerFrame);
starts=[0;cumsum(lengths(1:end-1))]; centers=starts+lengths/2;
estimate=struct('channels',{channels},'initialChannels',{initial}, ...
    'timingSamples',timingSamples,'residualCfoHz',residual,'symbolCenters',centers, ...
    'residualCfoUnambiguousHz',unambiguous,'residualCfoWarningHz',warningLevel);
end
