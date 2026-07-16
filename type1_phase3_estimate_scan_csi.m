function [Hhat,meta]=type1_phase3_estimate_scan_csi(physical,p,M,beta,switchModel)
%TYPE1_PHASE3_ESTIMATE_SCAN_CSI Estimate M-port CSI from single-chain scans.
%   Each 10 ms scan frame observes one disjoint group of four ports.  The
%   effective Type-1 DM-RS channels are inverted through the known nominal
%   leakage matrix.  Settling jitter is deliberately not truth-corrected.
arguments
    physical {mustBeNumeric}
    p (1,1) struct
    M (1,1) double {mustBeInteger,mustBePositive}
    beta {mustBeNumeric}
    switchModel (1,1) struct
end
N=p.cfg.nLayers;[schedules,W]=type1_phase3_scan_matrix(M,N,switchModel.isolationDb);
G=numel(schedules);frame=round(p.cfg.frameDurationSec*p.cfg.txSampleRate);
assert(size(physical,1)>=G*frame&&size(physical,2)>=M,'type1:E1ScanWindow', ...
    'Physical scan capture is shorter than the frozen scan sequence.');
targets=type1_phase3_switch_targets_from_physical(physical(:,1:M),schedules, ...
    switchModel.isolationDb);
nSC=12*p.cfg.nRB;effective=complex(zeros(G*N,N,nSC));noise=zeros(G,1);
for g=1:G
    [~,virtual]=type1_phase3_apply_target(targets(:,g),beta,N);
    rows=(g-1)*frame+(1:frame);
    [Hg,noise(g)]=estimate_frame(virtual(rows,:),p);
    effective((g-1)*N+(1:N),:,:)=Hg;
end
clear targets
Hhat=complex(zeros(M,N,nSC));
for k=1:nSC,Hhat(:,:,k)=W\effective(:,:,k);end
% The frozen reference scales each layer's time waveform independently to
% 0.72 peak after OFDM modulation.  nrChannelEstimate uses the unscaled
% DM-RS symbols, so its output includes that known TX factor.  De-embed it
% before the physical-channel selector; this uses only the shared reference
% package, never the simulated channel truth.
txScale=reference_tx_scale(p);
Hhat=Hhat./reshape(txScale,1,N,1);
signalPower=mean(sum(abs(Hhat).^2,2),'all');
meta=struct('nGroups',G,'scanFrames',G,'additionalScanFrames',G-1, ...
    'schedules',{schedules},'nominalWeightMatrix',W,'weightCondition',cond(W), ...
    'dmrsNoiseByFrame',noise,'dmrsNoiseMedian',median(noise), ...
    'referenceTxLayerScale',txScale, ...
    'estimatedMetricNoiseVariance',signalPower/10^(switchModel.snrDb/10), ...
    'usesTrueChannel',false,'settlingTruthCorrected',false);
end

function scale=reference_tx_scale(p)
persistent cachedScale cachedFormat
format=string(p.formatVersion);
if isempty(cachedScale)||isempty(cachedFormat)||cachedFormat~=format
    carrier=type1_carrier_config(p.cfg,0);
    unscaled=nrOFDMModulate(carrier,double(p.txGrid),'Nfft',p.cfg.nfft, ...
        'SampleRate',p.cfg.txSampleRate,'CarrierFrequency',0,'Windowing',0);
    scale=zeros(1,p.cfg.nLayers);
    for layer=1:p.cfg.nLayers
        keep=abs(unscaled(:,layer))>1e-10*max(abs(unscaled(:,layer)));
        ratio=double(p.txWaveform(keep,layer))./unscaled(keep,layer);
        scale(layer)=real(median(ratio));
    end
    cachedScale=scale;cachedFormat=format;
else
    scale=cachedScale;
end
end

function [H,noiseMedian]=estimate_frame(frameWaveform,p)
carrier=type1_carrier_config(p.cfg,0);
grid=nrOFDMDemodulate(carrier,double(frameWaveform),'Nfft',p.cfg.nfft, ...
    'SampleRate',p.cfg.txSampleRate,'CarrierFrequency',0);
grid=grid(:,1:p.cfg.symbolsPerFrame,:);nSC=size(grid,1);N=p.cfg.nLayers;
nSlot=numel(p.cfg.dataSlots);acc=complex(zeros(N,N,nSC));noise=zeros(nSlot,1);
for s=1:nSlot
    slot=p.cfg.dataSlots(s);symbols=slot*p.cfg.symbolsPerSlot+(1:p.cfg.symbolsPerSlot);
    rxSlot=grid(:,symbols,:);indices=double(p.dmrsIndices(:,:,s));
    pilots=double(p.dmrsSymbols(:,:,s));
    [channel,noise(s)]=nrChannelEstimate(rxSlot,indices,pilots, ...
        'CDMLengths',p.dmrsCDMLengths);
    center=mean(channel,2); % nSC x 1 x nRx x nLayer, static scan frame
    acc=acc+permute(reshape(center,nSC,N,N),[2 3 1]);
end
H=acc/nSlot;noiseMedian=median(noise);
end
