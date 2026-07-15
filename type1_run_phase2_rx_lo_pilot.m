function report = type1_run_phase2_rx_lo_pilot()
%TYPE1_RUN_PHASE2_RX_LO_PILOT Validate then run the preregistered isolated point.
validation=type1_validate_rx_lo_phase_noise(); p=type1_load_package();
baseSim=isolated_config(); seed=20261201; loSeed=20261291;
names=["off" "common" "commonCPE" "independent" "independentCPE"];
simOff=with_lo(baseSim,"off",0,100e3,loSeed);
simCommon=with_lo(baseSim,"common",2,100e3,loSeed);
simIndependent=with_lo(baseSim,"independent",2,100e3,loSeed);
lOff=type1_offline_link(p,simOff,RandStream('mt19937ar','Seed',seed));
lCommon=type1_offline_link(p,simCommon,RandStream('mt19937ar','Seed',seed));
lIndependent=type1_offline_link(p,simIndependent,RandStream('mt19937ar','Seed',seed));
rOff=type1_analyze(lOff.virtualRx30,p); rCommon=type1_analyze(lCommon.virtualRx30,p);
rIndependent=type1_analyze(lIndependent.virtualRx30,p);
rCommonCpe=type1_apply_symbol_cpe(rCommon,p); rIndependentCpe=type1_apply_symbol_cpe(rIndependent,p);
each={rOff rCommon rCommonCpe rIndependent rIndependentCpe};
errors=zeros(1,numel(each)); ber=zeros(size(errors)); evm=zeros(size(errors));
bits=numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers;
for k=1:numel(each)
    errors(k)=sum(each{k}.infoBitErrors,'all'); ber(k)=errors(k)/bits;
    evm(k)=rms(each{k}.evmRMSPercent,'all');
end
hLo1=errors(2)<=errors(4);
hLo2=ber(3)<=max(ber(1),3/bits) && evm(3)-evm(1)<=1;
assert(all([rOff.bestNID2 rCommon.bestNID2 rIndependent.bestNID2]==mod(p.cfg.pci,3)), ...
    'type1:RxLoPilotAcquisition','Pilot PSS selected an incorrect NID2.');
report=struct('validation',validation,'seed',seed,'loSeed',loSeed,'simBase',baseSim, ...
    'receiverNames',names,'errors',errors,'bits',bits,'ber',ber,'evmRmsPercent',evm, ...
    'hLo1AtPilot',hLo1,'hLo2AtPilot',hLo2,'hLo2BerLimit',max(ber(1),3/bits), ...
    'hLo2EvmExcessLimitPercentagePoint',1);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_rx_lo_pilot_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_rx_lo_pilot.mat'),'report','-v7.3');
fprintf('RX-LO pilot errors=[%s], BER=[%s], EVM=[%s], H-LO1/2=%d/%d, saved: %s\n', ...
    num2str(errors),num2str(ber,'%.4g '),num2str(evm,'%.3f '),hLo1,hLo2,out);
end

function s=isolated_config()
s=type1_offline_sim_config(); s.frames=1; s.snrDb=20; s.commonCfoHz=0;
s.userCfoHz=zeros(1,4); s.userTimingSamples=zeros(1,4); s.userPowerDb=zeros(1,4);
s.userPhaseNoiseStdRadPerSample=zeros(1,4); s.channelModel="flat";
s.switch.isolationDb=Inf; s.switch.settlingRiseNs=0; s.switch.transitionJitterStdPs=0;
s.switch.samplingBoundaryJitterStdPs=0; s.switch.settlingFastJitterStdFraction=0;
cfg=type1_config(); s.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
end

function s=with_lo(s,mode,sigmaDeg,bandwidthHz,seed)
s.rxLo=struct('mode',string(mode),'phaseRmsDeg',sigmaDeg,'bandwidthHz',bandwidthHz, ...
    'seed',seed,'recordTimeSeries',false);
end
