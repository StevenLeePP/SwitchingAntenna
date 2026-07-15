function report = type1_run_phase2_received_drive()
%TYPE1_RUN_PHASE2_RECEIVED_DRIVE Final bounded observable-drive experiment.
%   Gate 1 compares exact-state and received-drive truth-residual capture at
%   the preregistered full-stack 20 dB operating point.  The observed proxy
%   dHat=(y[n]-y[n-1])/beta0 uses only stitched ADC samples and nominal beta0.
%   Only if both seeds capture at least 50% does Gate 2 run DDCE versus
%   DDCE+received-drive DF.  This script does not tune Q/fast/iterations.
p=type1_load_package(); [s0,s1]=r11_configs(); seeds=[20261001 20261003]; q=12;
snrDiagnostic=[20 200]; capture=nan(numel(seeds),2,numel(snrDiagnostic)); beta0=nan(size(seeds));
for level=1:numel(snrDiagnostic)
    for k=1:numel(seeds)
        c0=s0; c1=s1; c0.snrDb=snrDiagnostic(level); c1.snrDb=snrDiagnostic(level);
        l0=type1_offline_link(p,c0,RandStream('mt19937ar','Seed',seeds(k)));
        l1=type1_offline_link(p,c1,RandStream('mt19937ar','Seed',seeds(k)));
        base=type1_analyze_user_cfo(l1.virtualRx30,p,true).base;
        [capture(k,1,level),capture(k,2,level),beta0(k)]=capture_pair(l0,l1,p,base,q,s1);
        fprintf('SNR=%g seed=%d exact/received capture=[%.4f %.4f], beta0=%.6f\n', ...
            snrDiagnostic(level),seeds(k),capture(k,1,level),capture(k,2,level),beta0(k));
    end
end
truthGateThreshold=.50; truthGatePassed=all(capture(:,2,1)>=truthGateThreshold);
ber=nan(numel(seeds),5); evm=nan(numel(seeds),5); gap=nan(numel(seeds),2);
receiverGatePassed=false; gapGainOverDdce=nan(numel(seeds),1);
if truthGatePassed
    for k=1:numel(seeds)
        l0=type1_offline_link(p,s0,RandStream('mt19937ar','Seed',seeds(k)));
        l1=type1_offline_link(p,s1,RandStream('mt19937ar','Seed',seeds(k)));
        [drive30,~]=type1_received_drive(l1.stitched122,s1.switch.settlingRiseNs,s1.switch.rawSampleRateHz);
        r0=type1_analyze_user_cfo(l0.virtualRx30,p,true);
        r1=type1_analyze_user_cfo(l1.virtualRx30,p,true);
        ddce=type1_analyze_ici_decision_feedback(l1.virtualRx30,p,q,3,'soft',true,true,'single','ddce','free');
        received=type1_analyze_ici_decision_feedback(l1.virtualRx30,p,q,3,'soft',true,true,'single','ddce','received',drive30);
        v3=type1_genie_replace_settling(l1.stitched122,l1.switchMeta.settlingBeta,l0.switchMeta.settlingBeta);
        r3=type1_analyze_user_cfo(v3,p,true); each={r0 r1 ddce received r3};
        for receiver=1:numel(each)
            ber(k,receiver)=sum(each{receiver}.infoBitErrors,'all')/ ...
                (numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers);
            evm(k,receiver)=mean(each{receiver}.evmRMSPercent,'all');
        end
        denominator=ber(k,2)-ber(k,5);
        gap(k,:)=(ber(k,2)-ber(k,3:4))/max(denominator,eps);
        fprintf('seed=%d BER L0/L1/DDCE/received/L3=[%s], DDCE/received gap=[%s]\n', ...
            seeds(k),num2str(ber(k,:),'%.6g '),num2str(gap(k,:),'%.4f '));
    end
    gapGainOverDdce=gap(:,2)-gap(:,1);
    receiverGatePassed=all(ber(:,4)<ber(:,3)) && all(gapGainOverDdce>=.10);
end
report=struct('seeds',seeds,'simL0',s0,'simL1',s1,'q',q, ...
    'snrDiagnosticDb',snrDiagnostic,'captureNames',["exactStateDrive" "receivedDrive"], ...
    'truthCapture',capture,'nominalBeta0',beta0,'truthGateThreshold',truthGateThreshold, ...
    'truthGatePassed',truthGatePassed, ...
    'receiverNames',["L0" "L1" "DDCE" "DDCEreceivedDrive" "L3"], ...
    'ber',ber,'evmPercent',evm,'gapNames',["DDCE" "DDCEreceivedDrive"], ...
    'gapClosure',gap,'gapGainOverDdce',gapGainOverDdce, ...
    'receiverGapGainThreshold',.10,'receiverGatePassed',receiverGatePassed, ...
    'bLineFrozenAfterThisExperiment',true);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_received_drive_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_received_drive.mat'),'report','-v7.3');
fprintf('Received-drive truth/receiver gates=[%d %d], B-line frozen, saved: %s\n', ...
    truthGatePassed,receiverGatePassed,out);
end

function [exactCapture,receivedCapture,beta0]=capture_pair(l0,l1,p,base,q,sim)
g0=demod_with_base(l0.virtualRx30,p,base); g1=demod_with_base(l1.virtualRx30,p,base);
target=double(l1.switchMeta.settlingTarget(:)); previous=[0;double(l0.stitched122(1:end-1))];
exact=reshape(target-previous,4,[]).';
[received,beta0]=type1_received_drive(double(l1.stitched122), ...
    sim.switch.settlingRiseNs,sim.switch.rawSampleRateHz);
gExact=demod_with_base(exact,p,base); gReceived=demod_with_base(received,p,base);
errorPower=0; exactResidual=0; receivedResidual=0;
for s=1:numel(p.cfg.dataSlots)
    [e,k,l]=sample_slot(g1-g0,p,s);
    exactData=sample_slot(gExact,p,s); receivedData=sample_slot(gReceived,p,s);
    [pe,mask]=predict_constrained(e,exactData,k,l,q);
    [pr,maskR]=predict_constrained(e,receivedData,k,l,q);
    assert(isequal(mask,maskR),'type1:ReceivedDriveMask','Cross-fit masks differ.');
    errorPower=errorPower+sum(abs(e(mask,:)).^2,'all');
    exactResidual=exactResidual+sum(abs(e(mask,:)-pe(mask,:)).^2,'all');
    receivedResidual=receivedResidual+sum(abs(e(mask,:)-pr(mask,:)).^2,'all');
end
exactCapture=1-exactResidual/max(errorPower,eps);
receivedCapture=1-receivedResidual/max(errorPower,eps);
end

function [prediction,mask]=predict_constrained(e,drive,k,l,q)
prediction=complex(zeros(size(e))); mask=false(size(e,1),1);
for symbol=unique(l).'
    pick=find(l==symbol); [~,order]=sort(k(pick)); pick=pick(order);
    [local,localMask]=crossfit_conjugate(e(pick,:),drive(pick,:),q);
    prediction(pick,:)=local; mask(pick(localMask))=true;
end
end

function [prediction,mask]=crossfit_conjugate(e,drive,q)
n=size(e,1); prediction=complex(zeros(size(e))); mask=false(n,1);
centers=(q+1):(n-q); mask(centers)=true;
for parity=0:1
    train=centers(mod(centers,2)==parity); A=[]; b=[];
    for r=1:size(e,2)
        local=conjugate_design(drive,train,q,r);
        A=[A;local]; b=[b;e(train,r)]; %#ok<AGROW>
    end
    realSystem=[real(A);imag(A)]; realTarget=[real(b);imag(b)]; theta=realSystem\realTarget;
    target=centers(mod(centers,2)~=parity);
    for r=1:size(e,2), prediction(target,r)=conjugate_design(drive,target,q,r)*theta; end
end
end

function A=conjugate_design(drive,rows,q,r)
A=complex(zeros(numel(rows),1+2*q)); A(:,1)=drive(rows,r);
for u=1:q
    lower=drive(rows-u,r); upper=drive(rows+u,r);
    A(:,1+u)=lower+upper; A(:,1+q+u)=1j*(lower-upper);
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
