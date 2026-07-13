function type1_validate_channel_models()
%TYPE1_VALIDATE_CHANNEL_MODELS Regression for flat and correlated TDL-A paths.
p=type1_load_package(); s=type1_offline_sim_config(); st=RandStream('mt19937ar','Seed',20260714);
l=type1_offline_link(p,s,st); r=type1_analyze(l.virtualRx30,p); assert(all(r.infoBitErrors==0,'all'));
s.channelModel="tdl-a"; st=RandStream('mt19937ar','Seed',20260715); l=type1_offline_link(p,s,st); r=type1_analyze(l.virtualRx30,p);
assert(~r.pbchCRCError && r.mibMatches,'type1:TDLA','TDL-A PBCH/MIB failed.');
assert(all(isfinite(r.conditionStats)),'type1:TDLA','TDL-A condition statistics invalid.');
fprintf('Channel-model validation PASSED: TDL-A BER=[%s], cond p95=%.3f.\n',num2str(mean(r.infoBER,1),'%.3g '),r.conditionStats(2));
end
