function report = type1_run_phase2_r10_double_bank()
%TYPE1_RUN_PHASE2_R10_DOUBLE_BANK H1-gated full-stack double-bank test.
%   Run only after the R10 model-upper report has h1Confirmed=true.  The
%   physical point, Q and iteration count remain frozen.
priorFile=getenv('TYPE1_R10_PRIOR_MAT');
assert(~isempty(priorFile) && isfile(priorFile),'type1:R10Prior', ...
    'TYPE1_R10_PRIOR_MAT must point to the H1 decomposition MAT.');
prior=load(priorFile,'report'); assert(prior.report.h1Confirmed,'type1:R10H1Gate', ...
    'Double-bank receiver is forbidden because H1 was not confirmed.');
p=type1_load_package(); [s0,s1]=r10_configs(); seeds=[20261001 20261003];
ber=zeros(2,5); evm=zeros(2,5); gap=zeros(2,2);
for k=1:2
    l0=type1_offline_link(p,s0,RandStream('mt19937ar','Seed',seeds(k)));
    l1=type1_offline_link(p,s1,RandStream('mt19937ar','Seed',seeds(k)));
    r0=type1_analyze_user_cfo(l0.virtualRx30,p,true);
    r1=type1_analyze_user_cfo(l1.virtualRx30,p,true);
    single=type1_analyze_ici_decision_feedback(l1.virtualRx30,p,12,3,'soft',true,true,'single');
    dual=type1_analyze_ici_decision_feedback(l1.virtualRx30,p,12,3,'soft',true,true,'double');
    v3=type1_genie_replace_settling(l1.stitched122,l1.switchMeta.settlingBeta,l0.switchMeta.settlingBeta);
    r3=type1_analyze_user_cfo(v3,p,true);
    each={r0 r1 single dual r3};
    for q=1:5
        ber(k,q)=sum(each{q}.infoBitErrors,'all')/(numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers);
        evm(k,q)=mean(each{q}.evmRMSPercent,'all');
    end
    denominator=ber(k,2)-ber(k,5); gap(k,:)=(ber(k,2)-ber(k,3:4))/max(denominator,eps);
    fprintf('seed=%d BER L0/L1/single/double/L3=[%s] gap single/double=[%s]\n', ...
        seeds(k),num2str(ber(k,:),'%.5g '),num2str(gap(k,:),'%.3f '));
end
gapGain=gap(:,2)-gap(:,1); retain=all(ber(:,4)<ber(:,3)) && all(gapGain>=.15);
report=struct('priorFile',priorFile,'seeds',seeds,'simL0',s0,'simL1',s1, ...
    'receiverNames',["L0" "L1" "singleBank" "doubleBank" "L3"], ...
    'ber',ber,'evmPercent',evm,'gapClosure',gap,'gapGain',gapGain, ...
    'retentionGapGainThreshold',.15,'retainDoubleBank',retain);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_r10_double_bank_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_r10_double_bank.mat'),'report','-v7.3');
fprintf('Double-bank retain=%d, result saved: %s\n',retain,out);
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
