function report = type1_run_phase2_r10_decomposition()
%TYPE1_RUN_PHASE2_R10_DECOMPOSITION Preregistered R10 four-branch audit.
%   Stage 'decompose' runs the model upper bound, genie decisions, genie
%   channel, and deep-fade error localization.  Stage 'weighted' is a
%   separate, conditional inverse-power LS test and must only be launched if
%   the saved decompose report confirms H2.  No SDR hardware is accessed.

stage=lower(string(getenv('TYPE1_R10_STAGE'))); if strlength(stage)==0, stage="decompose"; end
assert(any(stage==["decompose" "weighted"]),'type1:R10Stage', ...
    'TYPE1_R10_STAGE must be decompose or weighted.');
p=type1_load_package(); seeds=[20261001 20261003]; [s0,s1]=r10_configs();
if stage=="weighted"
    priorFile=getenv('TYPE1_R10_PRIOR_MAT');
    assert(~isempty(priorFile) && isfile(priorFile),'type1:R10Prior', ...
        'Weighted stage requires TYPE1_R10_PRIOR_MAT from the decompose stage.');
    prior=load(priorFile,'report');
    assert(prior.report.h2Confirmed,'type1:R10H2Gate', ...
        'Inverse-power LS is forbidden because the preregistered H2 gate did not pass.');
    report=run_weighted(p,seeds,s0,s1,priorFile);
else
    report=run_decomposition(p,seeds,s0,s1);
end
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_r10_' char(stage) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_r10.mat'),'report','-v7.3');
print_report(report); fprintf('R10 %s result saved: %s\n',stage,out);
end

function report=run_decomposition(p,seeds,s0,s1)
n=numel(seeds); modelSingle=nan(n,1); modelDouble=nan(n,1);
ber=zeros(n,6); evm=zeros(n,6); gap=zeros(n,4); weakErrorShare=nan(n,1);
receiverNames=["L0" "L1" "currentDF" "genieDecision" "genieChannel" "jointGenie"];
for k=1:n
    seed=seeds(k);
    clean0=s0; clean1=s1; clean0.snrDb=200; clean1.snrDb=200;
    c0=type1_offline_link(p,clean0,RandStream('mt19937ar','Seed',seed));
    c1=type1_offline_link(p,clean1,RandStream('mt19937ar','Seed',seed));
    cBase=type1_analyze_user_cfo(c1.virtualRx30,p,true).base;
    [modelSingle(k),modelDouble(k)]=model_capture(c0,c1,p,cBase,12);
    clear c0 c1

    l0=type1_offline_link(p,s0,RandStream('mt19937ar','Seed',seed));
    l1=type1_offline_link(p,s1,RandStream('mt19937ar','Seed',seed));
    r0=type1_analyze_user_cfo(l0.virtualRx30,p,true);
    r1=type1_analyze_user_cfo(l1.virtualRx30,p,true);
    current=type1_analyze_ici_decision_feedback(l1.virtualRx30,p,12,3,'soft',true,true);
    ctx=make_context(l1.virtualRx30,p,r1.base);
    hTrue=make_true_l0_channel(l0,p,ctx);
    currentLocal=run_receiver(ctx,p,{ctx.slots.hHat},"standard",3,"uniform");
    assert(currentLocal.errors==sum(current.infoBitErrors,'all'), ...
        'type1:R10ReceiverMismatch','Local current-DF path does not reproduce the production receiver.');
    genieDecision=run_receiver(ctx,p,{ctx.slots.hHat},"truth",3,"uniform");
    genieChannel=run_receiver(ctx,p,hTrue,"standard",3,"uniform");
    joint=run_receiver(ctx,p,hTrue,"truth",3,"uniform");
    weakErrorShare(k)=deep_fade_error_share(ctx,p);
    ber(k,:)=[aggregate_ber(r0,p) aggregate_ber(r1,p) aggregate_ber(current,p) ...
        genieDecision.ber genieChannel.ber joint.ber];
    evm(k,:)=[mean(r0.evmRMSPercent,'all') mean(r1.evmRMSPercent,'all') ...
        mean(current.evmRMSPercent,'all') genieDecision.evm genieChannel.evm joint.evm];
    denominator=ber(k,2)-ber(k,1);
    gap(k,:)=(ber(k,2)-ber(k,3:6))/max(denominator,eps);
    fprintf(['seed=%d capture single/double=[%.3f %.3f], BER L0/L1/current/xTrue/' ...
        'HTrue/joint=[%s], gap=[%s], weak-decile errors=%.3f\n'],seed, ...
        modelSingle(k),modelDouble(k),num2str(ber(k,:),'%.4g '), ...
        num2str(gap(k,:),'%.3f '),weakErrorShare(k));
    clear l0 l1 ctx hTrue
end
h1Confirmed=all(modelDouble-modelSingle>=.15 & modelDouble>=.30);
kernelClassFailure=all(modelSingle<.20 & modelDouble<.20);
decisionDominant=all(gap(:,2)-gap(:,1)>=.15);
channelDominant=all(gap(:,3)-gap(:,1)>=.15);
h2Confirmed=all(weakErrorShare>=.30);
report=struct('stage','decompose','seeds',seeds,'simL0',s0,'simL1',s1,'q',12,'iterations',3, ...
    'receiverNames',receiverNames,'modelCaptureSingleBank',modelSingle, ...
    'modelCaptureDoubleBank',modelDouble,'h1Confirmed',h1Confirmed, ...
    'kernelClassFailure',kernelClassFailure,'ber',ber,'evmPercent',evm, ...
    'gapNames',["currentDF" "genieDecision" "genieChannel" "jointGenie"], ...
    'gapClosure',gap,'decisionDominant',decisionDominant,'channelDominant',channelDominant, ...
    'weakestDecileErrorShare',weakErrorShare,'h2Confirmed',h2Confirmed, ...
    'thresholds',struct('h1Gain',.15,'h1DoubleCapture',.30,'kernelFailureCapture',.20, ...
    'dominantGapGain',.15,'h2ErrorShare',.30));
end

function report=run_weighted(p,seeds,s0,s1,priorFile)
n=numel(seeds); ber=zeros(n,3); evm=zeros(n,3);
for k=1:n
    l0=type1_offline_link(p,s0,RandStream('mt19937ar','Seed',seeds(k)));
    l1=type1_offline_link(p,s1,RandStream('mt19937ar','Seed',seeds(k)));
    r1=type1_analyze_user_cfo(l1.virtualRx30,p,true); ctx=make_context(l1.virtualRx30,p,r1.base);
    uniform=run_receiver(ctx,p,{ctx.slots.hHat},"standard",3,"uniform");
    weighted=run_receiver(ctx,p,{ctx.slots.hHat},"standard",3,"inversePower");
    r0=type1_analyze_user_cfo(l0.virtualRx30,p,true);
    ber(k,:)=[aggregate_ber(r0,p) uniform.ber weighted.ber];
    evm(k,:)=[mean(r0.evmRMSPercent,'all') uniform.evm weighted.evm];
end
relative=(ber(:,2)-ber(:,3))./max(ber(:,2),eps);
retain=all(ber(:,3)<ber(:,2)) && mean(relative)>=.05;
report=struct('stage','weighted','priorFile',priorFile,'seeds',seeds, ...
    'simL0',s0,'simL1',s1,'receiverNames',["L0" "uniformDF" "inversePowerDF"], ...
    'ber',ber,'evmPercent',evm,'relativeBerReduction',relative, ...
    'meanRelativeBerReduction',mean(relative),'retainCandidate',retain);
end

function [s0,s1]=r10_configs()
s0=type1_offline_multiuser_config(); s0.frames=1; s0.snrDb=20; s0.channelModel="tdl-a";
s0.userCfoHz=.5*s0.userCfoHz; s0.tdl.delaySpreadNs=100; s0.tdl.dopplerHz=0;
s0.tdl.rxCorrelation=.3; s0.tdl.txCorrelation=.3;
s0.userTimingSamples=min(max(s0.userTimingSamples,-4),4);
s0.switch.isolationDb=25; s0.switch.settlingRiseNs=20;
s0.switch.transitionJitterStdPs=20; s0.switch.samplingBoundaryJitterStdPs=100;
s0.switch.settlingFastJitterStdFraction=0; s0.switch.settlingFastJitterCorrelationSec=1e-6;
s0.switch.recordTimeSeries=true; s1=s0; s1.switch.settlingFastJitterStdFraction=.2;
cfg=type1_config(); s0.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s0.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
s1.prefixSamples=s0.prefixSamples; s1.suffixSamples=s0.suffixSamples;
end

function [singleCapture,doubleCapture]=model_capture(l0,l1,p,base,q)
g0=demod_with_base(l0.virtualRx30,p,base); g1=demod_with_base(l1.virtualRx30,p,base);
target=double(l1.switchMeta.settlingTarget(:));
current=reshape(target,4,[]).'; previous=reshape([0;target(1:end-1)],4,[]).';
gc=demod_with_base(current,p,base); gp=demod_with_base(previous,p,base);
powerE=0; residualSingle=0; residualDouble=0;
for s=1:numel(p.cfg.dataSlots)
    [e,k,l]=sample_slot(g1-g0,p,s); currentData=sample_slot(gc,p,s); previousData=sample_slot(gp,p,s);
    [~,ps,pe]=crossfit_predict(e,{currentData},k,l,q,"uniform");
    [~,pd,~]=crossfit_predict(e,{currentData previousData},k,l,q,"uniform");
    powerE=powerE+pe; residualSingle=residualSingle+ps; residualDouble=residualDouble+pd;
end
singleCapture=1-residualSingle/max(powerE,eps);
doubleCapture=1-residualDouble/max(powerE,eps);
end

function ctx=make_context(rx,p,base)
grid=demod_with_base(rx,p,base); est=type1_estimate_user_channels(grid,p,true,true);
cfg=p.cfg; nRx=size(rx,2); slots=repmat(struct('y',[],'hHat',[],'k',[],'l',[], ...
    'xTrue',[],'xFirst',[]),numel(cfg.dataSlots),1);
for s=1:numel(cfg.dataSlots)
    slot=cfg.dataSlots(s); channel=est.channels{s};
    first=double(p.dataIndices(:,1,s)); [k,l]=ind2sub([12*cfg.nRB cfg.symbolsPerSlot cfg.nLayers],first);
    id2=sub2ind([12*cfg.nRB cfg.symbolsPerSlot],k,l); y=complex(zeros(numel(k),nRx));
    h=complex(zeros(numel(k),nRx,cfg.nLayers));
    dmrsTime=est.symbolCenters(slot*14+cfg.dmrsTypeAPosition+1);
    dt=est.symbolCenters(slot*14+l)-dmrsTime;
    for r=1:nRx
        plane=grid(:,slot*14+(1:14),r); y(:,r)=plane(id2);
        for layer=1:cfg.nLayers
            hp=channel(:,:,r,layer);
            timingPhase=exp(-1j*2*pi*(k-1)*est.timingSamples(layer)/cfg.nfft);
            h(:,r,layer)=hp(id2).*timingPhase.*exp(1j*2*pi*est.residualCfoHz(layer)*dt/cfg.txSampleRate);
        end
    end
    xTrue=reshape(double(p.dataQPSK(:,s,:)),numel(k),cfg.nLayers);
    slots(s)=struct('y',y,'hHat',h,'k',k,'l',l,'xTrue',xTrue, ...
        'xFirst',rzf_equalize(y,h,cfg,cfg.nLayers));
end
ctx=struct('base',base,'grid',grid,'estimate',est,'slots',slots);
end

function hTrue=make_true_l0_channel(l0,p,ctx)
cfg=p.cfg; components=type1_replay_tdl_components(double(l0.impairedTx),cfg,l0.simulatedChannel);
nSlots=numel(cfg.dataSlots); hTrue=cell(1,nSlots);
for s=1:nSlots
    hTrue{s}=complex(zeros(size(ctx.slots(s).hHat)));
end
% The link does not store prefix/suffix lengths explicitly; infer them from
% raw and physical sizes, then replay each linear layer through the exact L0
% switch trace.
windowLength=size(l0.raw122,1)/4; extra=windowLength-size(components,1);
prefixLength=round(cfg.txSampleRate*cfg.frameDurationSec/20);
suffixLength=extra-prefixLength;
assert(prefixLength>=0 && suffixLength>=0,'type1:R10Window','Cannot infer replay window lengths.');
for layer=1:cfg.nLayers
    physical=components(:,:,layer);
    window=[complex(zeros(prefixLength,cfg.nRxChannels)); physical; physical(1:suffixLength,:)];
    raw=complex(zeros(4*size(window,1),cfg.nRxChannels));
    for r=1:cfg.nRxChannels, raw(:,r)=resample(window(:,r),4,1); end
    [~,virtual]=type1_replay_switch_trace(raw,l0.switchMeta);
    layerGrid=demod_with_base(virtual,p,ctx.base);
    for s=1:nSlots
        [component]=sample_slot(layerGrid,p,s);
        hTrue{s}(:,:,layer)=component./ctx.slots(s).xTrue(:,layer);
    end
end
end

function result=run_receiver(ctx,p,hCells,feedback,iterations,weightMode)
cfg=p.cfg; totalErrors=0; evmSum=0; evmCount=0;
for s=1:numel(ctx.slots)
    slot=ctx.slots(s); h=hCells{s}; xEstimate=hard_remodulate(slot.xFirst,cfg.modulation,cfg.nLayers);
    for iteration=1:iterations
        if feedback=="truth", xFeedback=slot.xTrue; else, xFeedback=xEstimate; end
        v=predicted_rx(h,xFeedback,size(slot.y,2),cfg.nLayers);
        [prediction]=crossfit_predict(slot.y-v,{v},slot.k,slot.l,12,weightMode);
        corrected=slot.y-prediction; xEqualized=rzf_equalize(corrected,h,cfg,cfg.nLayers);
        if iteration<iterations && feedback~="truth", xEstimate=xEqualized; end
    end
    for layer=1:cfg.nLayers
        bits=logical(nrSymbolDemodulate(xEqualized(:,layer),cfg.modulation,'DecisionType','hard'));
        totalErrors=totalErrors+sum(bits~=p.codedBits(:,s,layer));
        evmSum=evmSum+100*rms(xEqualized(:,layer)-slot.xTrue(:,layer))/rms(slot.xTrue(:,layer));
        evmCount=evmCount+1;
    end
end
bits=numel(cfg.dataSlots)*p.nInfoBitsPerSlotLayer*cfg.nLayers;
result=struct('errors',totalErrors,'ber',totalErrors/bits,'evm',evmSum/evmCount);
end

function share=deep_fade_error_share(ctx,p)
cfg=p.cfg; strength=cell(1,12*cfg.nRB); errors=zeros(12*cfg.nRB,1);
for s=1:numel(ctx.slots)
    slot=ctx.slots(s);
    for re=1:numel(slot.k)
        h=reshape(slot.hHat(re,:,:),size(slot.hHat,2),cfg.nLayers);
        singular=svd(h); strength{slot.k(re)}(end+1)=min(singular);
    end
    for layer=1:cfg.nLayers
        bits=logical(nrSymbolDemodulate(slot.xFirst(:,layer),cfg.modulation,'DecisionType','hard'));
        bitError=reshape(bits~=p.codedBits(:,s,layer),2,[]);
        perRe=sum(bitError,1);
        for re=1:numel(slot.k), errors(slot.k(re))=errors(slot.k(re))+perRe(re); end
    end
end
metric=nan(12*cfg.nRB,1);
for k=1:numel(metric), if ~isempty(strength{k}), metric(k)=median(strength{k}); end, end
valid=find(isfinite(metric)); [~,order]=sort(metric(valid)); bottom=valid(order(1:ceil(.1*numel(valid))));
share=sum(errors(bottom))/max(sum(errors),1);
end

function grid=demod_with_base(rx,p,base)
cfg=p.cfg; frameN=round(cfg.frameDurationSec*cfg.txSampleRate);
frame=double(rx(base.timingOffset+(1:frameN),:)); n=(0:frameN-1).';
frame=frame.*exp(-1j*2*pi*base.frequencyOffsetHz*n/cfg.txSampleRate);
carrier=type1_carrier_config(cfg,0);
grid=nrOFDMDemodulate(carrier,frame,'Nfft',cfg.nfft,'SampleRate',cfg.txSampleRate,'CarrierFrequency',0);
grid=grid(:,1:cfg.symbolsPerFrame,:);
end

function [data,k,l]=sample_slot(grid,p,s)
cfg=p.cfg; slot=cfg.dataSlots(s); first=double(p.dataIndices(:,1,s));
[k,l]=ind2sub([12*cfg.nRB cfg.symbolsPerSlot cfg.nLayers],first);
id2=sub2ind([12*cfg.nRB cfg.symbolsPerSlot],k,l); data=complex(zeros(numel(k),size(grid,3)));
for r=1:size(grid,3), plane=grid(:,slot*14+(1:14),r); data(:,r)=plane(id2); end
end

function [prediction,residualPower,errorPower]=crossfit_predict(errorSignal,banks,k,l,q,weightMode)
prediction=complex(zeros(size(errorSignal))); residualPower=0; errorPower=0;
for symbol=unique(l).'
    pick=find(l==symbol); [~,order]=sort(k(pick)); pick=pick(order);
    [localPrediction,mask]=crossfit_one(errorSignal(pick,:),cellfun(@(x)x(pick,:),banks,'UniformOutput',false),q,weightMode);
    prediction(pick,:)=localPrediction;
    residual=errorSignal(pick,:)-localPrediction;
    residualPower=residualPower+sum(abs(residual(mask,:)).^2,'all');
    errorPower=errorPower+sum(abs(errorSignal(pick(mask),:)).^2,'all');
end
end

function [prediction,mask]=crossfit_one(e,banks,q,weightMode)
n=size(e,1); prediction=complex(zeros(size(e))); mask=false(n,1); u=-q:q;
if n<=2*q+2, return; end
centers=(q+1):(n-q); mask(centers)=true;
for parity=0:1
    train=centers(mod(centers,2)==parity); A=[]; b=[];
    for r=1:size(e,2)
        local=[];
        for bank=1:numel(banks)
            part=complex(zeros(numel(train),numel(u)));
            for tap=1:numel(u), part(:,tap)=banks{bank}(train-u(tap),r); end
            local=[local part]; %#ok<AGROW>
        end
        A=[A;local]; b=[b;e(train,r)]; %#ok<AGROW>
    end
    if weightMode=="inversePower"
        power=sum(abs(A).^2,2); floorPower=.1*median(power);
        weight=1./max(power,floorPower); scale=sqrt(weight/mean(weight));
        coefficients=(A.*scale)\(b.*scale);
    else
        coefficients=A\b;
    end
    target=centers(mod(centers,2)~=parity);
    for r=1:size(e,2)
        local=[];
        for bank=1:numel(banks)
            part=complex(zeros(numel(target),numel(u)));
            for tap=1:numel(u), part(:,tap)=banks{bank}(target-u(tap),r); end
            local=[local part]; %#ok<AGROW>
        end
        prediction(target,r)=local*coefficients;
    end
end
end

function x=hard_remodulate(z,modulation,nLayers)
x=complex(zeros(size(z,1),nLayers));
for layer=1:nLayers
    bits=logical(nrSymbolDemodulate(z(:,layer),modulation,'DecisionType','hard'));
    x(:,layer)=nrSymbolModulate(bits,modulation);
end
end

function v=predicted_rx(h,x,nRx,nLayers)
v=complex(zeros(size(x,1),nRx));
for r=1:nRx, for layer=1:nLayers, v(:,r)=v(:,r)+h(:,r,layer).*x(:,layer); end, end
end

function x=rzf_equalize(y,h,cfg,nLayers)
hPages=permute(h,[2 3 1]); yPages=permute(y,[2 3 1]); hh=pagectranspose(hPages);
gram=pagemtimes(hh,hPages); matched=pagemtimes(hh,yPages);
power=sum(abs(hPages).^2,[1 2])/nLayers; lambda=cfg.rzfRegularization*max(power,eps);
x=pagemldivide(gram+reshape(eye(nLayers),nLayers,nLayers,1).*lambda,matched);
x=reshape(permute(x,[3 2 1]),size(y,1),nLayers);
end

function value=aggregate_ber(result,p)
value=sum(result.infoBitErrors,'all')/(numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers);
end

function print_report(r)
if strcmp(r.stage,'decompose')
    fprintf('H1 single/double capture:\n'); disp([r.modelCaptureSingleBank r.modelCaptureDoubleBank]);
    fprintf('H1=%d kernelClassFailure=%d decisionDominant=%d channelDominant=%d H2=%d\n', ...
        r.h1Confirmed,r.kernelClassFailure,r.decisionDominant,r.channelDominant,r.h2Confirmed);
else
    fprintf('weighted relative BER reduction=[%s], mean=%.3f retain=%d\n', ...
        num2str(r.relativeBerReduction.','%.3f '),r.meanRelativeBerReduction,r.retainCandidate);
end
end
