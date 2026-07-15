function type1_validate_pss_vote()
%TYPE1_VALIDATE_PSS_VOTE Integration checks for optional peak voting.
p=type1_load_package(); s=r11_l0_config(); seeds=[20261002 20261004];
expectedFallback=[true false];
for k=1:2
    link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',seeds(k)));
    r=type1_analyze(link.virtualRx30,p,"vote");
    frame=round(p.cfg.frameDurationSec*p.cfg.txSampleRate);
    timingError=mod(r.timingOffset-s.prefixSamples+frame/2,frame)-frame/2;
    assert(abs(timingError)<=max(p.ofdmInfo.CyclicPrefixLengths) && ...
        r.bestNID2==mod(p.cfg.pci,3),'type1:PSSVoteTiming', ...
        'Vote mode failed the known timing/NID2 truth for seed %d.',seeds(k));
    assert(r.pssVoteUsedFallback==expectedFallback(k),'type1:PSSVoteFallback', ...
        'Unexpected vote fallback state for seed %d.',seeds(k));
end
fprintf('PSS vote integration PASSED: seed 20261002 fallback, seed 20261004 two-chain rescue.\n');
end

function s=r11_l0_config()
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
