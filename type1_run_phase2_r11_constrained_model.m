function report = type1_run_phase2_r11_constrained_model()
%TYPE1_RUN_PHASE2_R11_CONSTRAINED_MODEL Truth gate for physical B(u).
%   Uses D=t-y0_previous from the recorded L0 state and fits one
%   conjugate-symmetric kernel B(-u)=conj(B(u)).  Q=12 therefore has 25
%   real degrees of freedom.  The comparison double bank uses the exact
%   same target/state regressors without the M2=-M1 constraint.
p=type1_load_package(); [s0,s1]=r11_configs(); seeds=[20261001 20261003]; q=12;
capture=zeros(2,2); ratioMedian=complex(nan(2,2*q+1)); ratioSpread=nan(2,2*q+1);
for k=1:2
    c0=s0; c1=s1; c0.snrDb=200; c1.snrDb=200;
    l0=type1_offline_link(p,c0,RandStream('mt19937ar','Seed',seeds(k)));
    l1=type1_offline_link(p,c1,RandStream('mt19937ar','Seed',seeds(k)));
    base=type1_analyze_user_cfo(l1.virtualRx30,p,true).base;
    [capture(k,1),capture(k,2),ratios]=capture_pair(l0,l1,p,base,q);
    ratioMedian(k,:)=median(ratios,1,'omitnan');
    ratioSpread(k,:)=median(abs(ratios-ratioMedian(k,:)),1,'omitnan');
    fprintf('seed=%d unconstrained/constrained capture=[%.4f %.4f], drop=%.4f\n', ...
        seeds(k),capture(k,1),capture(k,2),capture(k,1)-capture(k,2));
end
drop=capture(:,1)-capture(:,2); pass=all(drop<.05);
ratioCrossSeedDifference=abs(ratioMedian(1,:)-ratioMedian(2,:));
report=struct('seeds',seeds,'simL0',s0,'simL1',s1,'q',q, ...
    'unconstrainedRealDof',4*(2*q+1),'constrainedRealDof',1+2*q, ...
    'captureNames',["unconstrainedTargetStateDouble" "conjugateSymmetricB"], ...
    'capture',capture,'captureDrop',drop,'maximumAllowedDrop',.05, ...
    'constrainedModelPassed',pass,'unconstrainedM2OverM1Median',ratioMedian, ...
    'unconstrainedM2OverM1Mad',ratioSpread, ...
    'ratioCrossSeedAbsoluteDifference',ratioCrossSeedDifference);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_r11_constrained_model_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_r11_constrained_model.mat'),'report','-v7.3');
fprintf('Constrained model pass=%d, result saved: %s\n',pass,out);
end

function [unconCapture,conCapture,ratios]=capture_pair(l0,l1,p,base,q)
g0=demod_with_base(l0.virtualRx30,p,base); g1=demod_with_base(l1.virtualRx30,p,base);
target=double(l1.switchMeta.settlingTarget(:)); previous=[0;double(l0.stitched122(1:end-1))];
gt=demod_with_base(reshape(target,4,[]).',p,base);
gp=demod_with_base(reshape(previous,4,[]).',p,base);
errorPower=0; unconResidual=0; conResidual=0; ratios=[];
for s=1:numel(p.cfg.dataSlots)
    [e,k,l]=sample_slot(g1-g0,p,s); targetData=sample_slot(gt,p,s); previousData=sample_slot(gp,p,s);
    [pu,mask,coefs]=predict_unconstrained(e,{targetData previousData},k,l,q);
    [pc,maskC]=predict_constrained(e,targetData-previousData,k,l,q);
    assert(isequal(mask,maskC),'type1:R11ConstraintMask','Cross-fit masks differ.');
    errorPower=errorPower+sum(abs(e(mask,:)).^2,'all');
    unconResidual=unconResidual+sum(abs(e(mask,:)-pu(mask,:)).^2,'all');
    conResidual=conResidual+sum(abs(e(mask,:)-pc(mask,:)).^2,'all');
    first=coefs(1:2*q+1,:); second=coefs(2*q+2:end,:);
    valid=abs(first)>.05*median(abs(first),'all'); local=second./first; local(~valid)=nan;
    ratios=[ratios;local.']; %#ok<AGROW>
end
unconCapture=1-unconResidual/max(errorPower,eps); conCapture=1-conResidual/max(errorPower,eps);
end

function [prediction,mask,allCoefs]=predict_unconstrained(e,banks,k,l,q)
prediction=complex(zeros(size(e))); mask=false(size(e,1),1); allCoefs=[];
for symbol=unique(l).'
    pick=find(l==symbol); [~,order]=sort(k(pick)); pick=pick(order);
    [local,localMask,coefs]=crossfit_unconstrained(e(pick,:), ...
        cellfun(@(x)x(pick,:),banks,'UniformOutput',false),q);
    prediction(pick,:)=local; mask(pick(localMask))=true;
    allCoefs=[allCoefs coefs]; %#ok<AGROW>
end
end

function [prediction,mask,allTheta]=predict_constrained(e,drive,k,l,q)
prediction=complex(zeros(size(e))); mask=false(size(e,1),1); allTheta=[];
for symbol=unique(l).'
    pick=find(l==symbol); [~,order]=sort(k(pick)); pick=pick(order);
    [local,localMask,theta]=crossfit_conjugate(e(pick,:),drive(pick,:),q);
    prediction(pick,:)=local; mask(pick(localMask))=true;
    allTheta=[allTheta theta]; %#ok<AGROW>
end
end

function [prediction,mask,coefs]=crossfit_unconstrained(e,banks,q)
n=size(e,1); u=-q:q; prediction=complex(zeros(size(e))); mask=false(n,1);
coefs=complex(nan(numel(u)*numel(banks),2)); centers=(q+1):(n-q); mask(centers)=true;
for parity=0:1
    train=centers(mod(centers,2)==parity); [A,b]=bank_design(e,banks,train,u);
    coefs(:,parity+1)=A\b; target=centers(mod(centers,2)~=parity);
    for r=1:size(e,2), prediction(target,r)=bank_rows(banks,target,u,r)*coefs(:,parity+1); end
end
end

function [prediction,mask,theta]=crossfit_conjugate(e,drive,q)
n=size(e,1); prediction=complex(zeros(size(e))); mask=false(n,1);
centers=(q+1):(n-q); mask(centers)=true; theta=nan(1+2*q,2);
for parity=0:1
    train=centers(mod(centers,2)==parity); A=[]; b=[];
    for r=1:size(e,2)
        local=conjugate_design(drive,train,q,r); A=[A;local]; b=[b;e(train,r)]; %#ok<AGROW>
    end
    realSystem=[real(A);imag(A)]; realTarget=[real(b);imag(b)];
    theta(:,parity+1)=realSystem\realTarget;
    target=centers(mod(centers,2)~=parity);
    for r=1:size(e,2), prediction(target,r)=conjugate_design(drive,target,q,r)*theta(:,parity+1); end
end
end

function A=conjugate_design(drive,rows,q,r)
A=complex(zeros(numel(rows),1+2*q)); A(:,1)=drive(rows,r);
for u=1:q
    lower=drive(rows-u,r); upper=drive(rows+u,r);
    A(:,1+u)=lower+upper;
    A(:,1+q+u)=1j*(lower-upper);
end
end

function [A,b]=bank_design(e,banks,rows,u)
A=[]; b=[];
for r=1:size(e,2), A=[A;bank_rows(banks,rows,u,r)]; b=[b;e(rows,r)]; end %#ok<AGROW>
end

function A=bank_rows(banks,rows,u,r)
A=[];
for bank=1:numel(banks)
    part=complex(zeros(numel(rows),numel(u)));
    for tap=1:numel(u), part(:,tap)=banks{bank}(rows-u(tap),r); end
    A=[A part]; %#ok<AGROW>
end
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

function [s0,s1]=r11_configs()
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
