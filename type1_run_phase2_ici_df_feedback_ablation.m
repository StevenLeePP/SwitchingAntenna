function report = type1_run_phase2_ici_df_feedback_ablation()
%TYPE1_RUN_PHASE2_ICI_DF_FEEDBACK_ABLATION R5 hard-vs-soft DF comparison.
%   The first ICI-DF pass is hard in both modes.  This experiment changes
%   only the feedback used to form v=Hhat*xhat for passes 2..N, pairing
%   standard RZF, hard DF and soft DF on every seeded offline link.

p=type1_load_package(); s=type1_offline_sim_config();
s.frames=1; s.assertIdealBaseline=false; s.snrDb=20;
s.switch.settlingRiseNs=20; s.switch.settlingFastJitterStdFraction=.6;
s.switch.settlingFastJitterCorrelationSec=1e-6; s.switch.recordTimeSeries=false;
q=12; iterations=3; baseSeed=20260816; targetErrors=10000; maxBits=1e7;
cfg=p.cfg; bitsPerFrame=numel(cfg.dataSlots)*p.nInfoBitsPerSlotLayer*cfg.nLayers;
maxFrames=ceil(maxBits/bitsPerFrame);
names=["standard" "hard" "soft"]; errors=zeros(3,cfg.nLayers); evm=zeros(1,3);
seeds=zeros(1,maxFrames); frame=0;
while frame<maxFrames
    frame=frame+1; seed=baseSeed+frame-1; seeds(frame)=seed;
    link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',seed));
    standard=type1_analyze(link.virtualRx30,p);
    hard=type1_analyze_ici_decision_feedback(link.virtualRx30,p,q,iterations,'hard');
    soft=type1_analyze_ici_decision_feedback(link.virtualRx30,p,q,iterations,'soft');
    each={standard hard soft};
    for receiver=1:3
        errors(receiver,:)=errors(receiver,:)+sum(each{receiver}.infoBitErrors,1);
        evm(receiver)=evm(receiver)+mean(each{receiver}.evmRMSPercent,'all');
    end
    if all(sum(errors,2)>=targetErrors), break; end
end
totalBits=frame*bitsPerFrame; ber=sum(errors,2)/totalBits;
report=struct('sim',s,'q',q,'iterations',iterations,'baseSeed',baseSeed, ...
    'targetErrors',targetErrors,'maxBits',maxBits,'names',names,'frames',frame, ...
    'seeds',seeds(1:frame),'errors',errors,'totalBits',totalBits,'ber',ber, ...
    'meanEvmPercent',evm/frame, ...
    'relativeReductionVsStandard',(ber(1)-ber)./max(ber(1),eps));
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_ici_df_feedback_ablation_' ...
    char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out;
save(fullfile(out,'phase2_ici_df_feedback_ablation.mat'),'report','-v7.3');
fprintf(['ICI-DF feedback ablation Q=%d it=%d: standard/hard/soft BER=[%s], ' ...
    'errors=[%s], bits=%.0f.\n'],q,iterations,num2str(ber','%.4g '), ...
    num2str(sum(errors,2)','%d '),totalBits);
fprintf('ICI-DF feedback ablation saved: %s\n',out);
end
