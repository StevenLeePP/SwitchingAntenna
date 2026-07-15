function report = type1_run_phase2_rx_lo_full_stack()
%TYPE1_RUN_PHASE2_RX_LO_FULL_STACK One bounded main-stack RX-LO increment check.
p=type1_load_package(); base=main_config(); seed=20261001; loSeed=20261291;
names=["off" "common" "commonCPE" "independent" "independentCPE"];
modes=["off" "common" "independent"]; links=cell(1,3); analyzed=cell(1,3);
for k=1:3
    sim=with_lo(base,modes(k),2,100e3,loSeed);
    links{k}=type1_offline_link(p,sim,RandStream('mt19937ar','Seed',seed));
    analyzed{k}=type1_analyze_user_cfo(links{k}.virtualRx30,p,true);
end
each={analyzed{1},analyzed{2},type1_apply_symbol_cpe(analyzed{2},p), ...
    analyzed{3},type1_apply_symbol_cpe(analyzed{3},p)};
bits=numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers;
errors=zeros(1,5); ber=zeros(1,5); evm=zeros(1,5);
for k=1:5
    errors(k)=sum(each{k}.infoBitErrors,'all'); ber(k)=errors(k)/bits;
    evm(k)=rms(each{k}.evmRMSPercent,'all');
end
report=struct('seed',seed,'loSeed',loSeed,'simBase',base,'receiverNames',names, ...
    'errors',errors,'bits',bits,'ber',ber,'evmRmsPercent',evm, ...
    'boundedConfirmationOnly',true,'doesNotReopenBLine',true);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_rx_lo_full_stack_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_rx_lo_full_stack.mat'),'report','-v7.3');
fprintf('RX-LO full-stack errors=[%s], BER=[%s], EVM=[%s], saved: %s\n', ...
    num2str(errors),num2str(ber,'%.5g '),num2str(evm,'%.3f '),out);
end

function s=main_config()
s=type1_offline_multiuser_config(); s.frames=1; s.snrDb=20; s.channelModel="tdl-a";
s.userCfoHz=.5*s.userCfoHz; s.tdl.delaySpreadNs=100; s.tdl.dopplerHz=0;
s.tdl.rxCorrelation=.3; s.tdl.txCorrelation=.3;
s.userTimingSamples=min(max(s.userTimingSamples,-4),4);
s.switch.isolationDb=25; s.switch.settlingRiseNs=20;
s.switch.transitionJitterStdPs=20; s.switch.samplingBoundaryJitterStdPs=100;
s.switch.settlingFastJitterStdFraction=0; s.switch.settlingFastJitterCorrelationSec=1e-6;
s.switch.recordTimeSeries=false; cfg=type1_config();
s.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
end

function s=with_lo(s,mode,sigmaDeg,bandwidthHz,seed)
s.rxLo=struct('mode',string(mode),'phaseRmsDeg',sigmaDeg,'bandwidthHz',bandwidthHz, ...
    'seed',seed,'recordTimeSeries',false);
end
