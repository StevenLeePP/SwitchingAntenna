function result = type1_apply_symbol_cpe(base,package,trackingMode)
%TYPE1_APPLY_SYMBOL_CPE One-real-parameter decision-directed CPE per symbol.
%   Hard QPSK decisions from the existing equalizer estimate
%   theta_l=angle(sum(conj(xhat)*xeq)) jointly over all layers/subcarriers in
%   one OFDM symbol.  Only a common scalar rotation is removed; this cannot
%   cancel independent per-RX phase noise or within-symbol ICI.

assert(isfield(base,'postCompData'),'type1:CPEInput', ...
    'Analyzer result must expose postCompData.');
assert(strcmp(package.channelCoding,'none'),'type1:CPECoding', ...
    'Current CPE tracker is defined for uncoded QPSK.');
if nargin<3, trackingMode="tracked"; end
trackingMode=lower(string(trackingMode));
assert(any(trackingMode==["tracked" "memoryless"]),'type1:CPEMode', ...
    'trackingMode must be tracked or memoryless.');
cfg=package.cfg; corrected=base.postCompData; nSlots=numel(cfg.dataSlots);
cpeRawRad=nan(cfg.symbolsPerSlot,nSlots); cpeRad=nan(cfg.symbolsPerSlot,nSlots);
errors=zeros(nSlots,cfg.nLayers);
evm=zeros(nSlots,cfg.nLayers);
for s=1:nSlots
    first=double(package.dataIndices(:,1,s));
    [~,symbol]=ind2sub([12*cfg.nRB cfg.symbolsPerSlot cfg.nLayers],first);
    dataSymbols=unique(symbol).';
    for l=dataSymbols
        rows=find(symbol==l); z=reshape(corrected(rows,s,:),[],1);
        bits=logical(nrSymbolDemodulate(z,cfg.modulation,'DecisionType','hard'));
        decision=nrSymbolModulate(bits,cfg.modulation);
        cpeRawRad(l,s)=angle(sum(conj(decision).*z));
    end
    cpeRad(:,s)=cpeRawRad(:,s);
    if trackingMode=="tracked"
        % The DM-RS-estimated H already anchors residual CPE to zero at its
        % symbol.  Resolve the QPSK pi/2 decision ambiguity by continuity,
        % forward and backward from that anchor.  This adds no parameter.
        anchor=cfg.dmrsTypeAPosition+1; previous=0;
        for l=dataSymbols(dataSymbols>anchor)
            cpeRad(l,s)=nearest_quadrant(cpeRawRad(l,s),previous); previous=cpeRad(l,s);
        end
        previous=0;
        for l=fliplr(dataSymbols(dataSymbols<anchor))
            cpeRad(l,s)=nearest_quadrant(cpeRawRad(l,s),previous); previous=cpeRad(l,s);
        end
    end
    for l=dataSymbols
        rows=find(symbol==l); corrected(rows,s,:)=corrected(rows,s,:).*exp(-1j*cpeRad(l,s));
    end
    for p=1:cfg.nLayers
        z=corrected(:,s,p);
        bits=logical(nrSymbolDemodulate(z,cfg.modulation,'DecisionType','hard'));
        errors(s,p)=sum(bits~=package.codedBits(:,s,p));
        reference=double(package.dataQPSK(:,s,p));
        evm(s,p)=100*rms(z-reference)/rms(reference);
    end
end
result=struct('base',base,'postCompData',corrected,'cpeRawRad',cpeRawRad,'cpeRad',cpeRad, ...
    'rawBitErrors',errors,'infoBitErrors',errors, ...
    'rawBER',errors/package.nCodedBitsPerSlotLayer, ...
    'infoBER',errors/package.nInfoBitsPerSlotLayer,'evmRMSPercent',evm, ...
    'trackingMode',trackingMode, ...
    'method','one decision-directed real CPE parameter per OFDM symbol, DM-RS-anchored quadrant continuity');
end

function theta=nearest_quadrant(raw,reference)
theta=raw+round((reference-raw)/(pi/2))*(pi/2);
end
