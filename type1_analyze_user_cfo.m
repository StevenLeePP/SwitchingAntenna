function result = type1_analyze_user_cfo(rx30, package, enableTimingCompensation)
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
if nargin<3, enableTimingCompensation=false; end
base = type1_analyze(rx30, package); cfg = package.cfg; nRx=size(rx30,2);
fs=cfg.txSampleRate; frameN=round(cfg.frameDurationSec*fs);
frame=double(rx30(base.timingOffset+(1:frameN),:));
frame=frame.*exp(-1j*2*pi*base.frequencyOffsetHz*(0:frameN-1).'/fs);
carrier=type1_carrier_config(cfg,0);
grid=nrOFDMDemodulate(carrier,frame,'Nfft',cfg.nfft,'SampleRate',fs,'CarrierFrequency',0);
grid=grid(:,1:cfg.symbolsPerFrame,:); nSlots=numel(cfg.dataSlots); nData=package.nDataREPerSlotLayer;
est=type1_estimate_user_channels(grid,package,enableTimingCompensation,true);
channels=est.channels; residual=est.residualCfoHz; centers=est.symbolCenters;
unambiguousCfoHz=est.residualCfoUnambiguousHz; warningCfoHz=est.residualCfoWarningHz;
errors=zeros(nSlots,cfg.nLayers); evm=zeros(nSlots,cfg.nLayers); conditionNumbers=[];
postCompData=complex(zeros(nData,nSlots,cfg.nLayers));
for s=1:nSlots
    slot=cfg.dataSlots(s); ch=channels{s}; idx=double(package.dataIndices(:,1,s));
    [k,l]=ind2sub([12*cfg.nRB cfg.symbolsPerSlot cfg.nLayers],idx); id2=sub2ind([12*cfg.nRB cfg.symbolsPerSlot],k,l);
    received=complex(zeros(nData,nRx)); h=complex(zeros(nData,nRx,cfg.nLayers));
    dmrsTime=centers(slot*14+cfg.dmrsTypeAPosition+1);
    dt=centers(slot*14+l)-dmrsTime;
    for r=1:nRx
        plane=grid(:,slot*14+(1:14),r); received(:,r)=plane(id2);
        for p=1:cfg.nLayers
            hp=ch(:,:,r,p); timingPhase=exp(-1j*2*pi*(k-1)*est.timingSamples(p)/cfg.nfft);
            h(:,r,p)=hp(id2).*timingPhase.*exp(1j*2*pi*residual(p)*dt/fs);
        end
    end
    hp=permute(h,[2 3 1]); yp=permute(received,[2 3 1]); hh=pagectranspose(hp);
    gram=pagemtimes(hh,hp); matched=pagemtimes(hh,yp); power=sum(abs(hp).^2,[1 2])/cfg.nLayers;
    lambda=cfg.rzfRegularization*max(power,eps); x=pagemldivide(gram+reshape(eye(cfg.nLayers),cfg.nLayers,cfg.nLayers,1).*lambda,matched);
    x=permute(x,[3 2 1]);
    postCompData(:,s,:)=x;
    sampleCount=min(cfg.channelConditionSamplesPerSlot,nData);
    sampleIndices=unique(round(linspace(1,nData,sampleCount)));
    for q=sampleIndices, conditionNumbers(end+1)=cond(hp(:,:,q)); end %#ok<AGROW>
    for p=1:cfg.nLayers
        bits=logical(nrSymbolDemodulate(x(:,1,p),cfg.modulation,'DecisionType','hard'));
        expected=package.codedBits(:,s,p); errors(s,p)=sum(bits~=expected);
        ref=double(package.dataQPSK(:,s,p)); evm(s,p)=100*rms(x(:,1,p)-ref)/rms(ref);
    end
end
result=struct('base',base,'residualCfoHz',residual,'rawBitErrors',errors, ...
    'rawBER',errors/package.nCodedBitsPerSlotLayer,'infoBitErrors',errors, ...
    'infoBER',errors/package.nInfoBitsPerSlotLayer,'evmRMSPercent',evm, ...
    'postCompData',postCompData, ...
    'timingCompensationEnabled',logical(enableTimingCompensation), ...
    'estimatedTimingSamples',est.timingSamples,'estimatedConditionStats',condition_stats(conditionNumbers), ...
    'residualCfoUnambiguousHz',unambiguousCfoHz, ...
    'residualCfoWarningHz',warningCfoHz);
end

function stats=condition_stats(values)
values=sort(values(isfinite(values)));
if isempty(values), stats=[NaN NaN NaN]; return; end
stats=[median(values) values(max(1,ceil(.95*numel(values)))) max(values)];
end
