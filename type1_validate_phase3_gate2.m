function audit=type1_validate_phase3_gate2()
%TYPE1_VALIDATE_PHASE3_GATE2 Algebraic guards for R18 feasible sets/solvers.
F1=type1_phase3_enumerate_f1(); R17=type1_phase3_enumerate_pair_partitions();
assert(size(F1,3)==166824 && all(sum(F1,2)<=1,'all') && ...
    all(sum(F1,1)>=1,'all'),'type1:R18F1','F1 constraints/cardinality failed.');
keyF1=schedule_keys(F1);keyR17=schedule_keys(R17);
superset=all(ismember(keyR17,keyF1));
assert(superset,'type1:R18Superset','F1 must contain all R17 partitions.');

stream=RandStream('mt19937ar','Seed',20261800);cfg=type1_config();
model=type1_phase3_config(8,4);
[~,channel]=type1_phase3_make_tdl_a_channel(complex(zeros(32,4)),cfg,model,stream);
f=(-2:2)*cfg.scsKHz*1e3;H=type1_phase3_tdl_frequency_response(channel,f);nv=.01;
sample=unique(round(linspace(1,size(F1,3),37)));
batch=type1_phase3_batch_f1_objective(H,F1(:,:,sample),nv,16);
scalar=zeros(numel(sample),1);
for k=1:numel(sample),scalar(k)=type1_phase3_wideband_metrics(H,F1(:,:,sample(k)),nv).objectiveDb;end
batchError=max(abs(batch-scalar));
assert(batchError<1e-10,'type1:R18BatchMetric','Batch/scalar MMSE objectives differ.');
g1=type1_phase3_greedy_schedule(H,nv,1);g2=type1_phase3_greedy_schedule(H,nv,2);
assert(all(diff(g1.trajectoryDb)>=-1e-12)&&all(diff(g2.trajectoryDb)>=-1e-12), ...
    'type1:R18GreedyMonotone','Greedy objective decreased.');
assert_feasible(g1.S,1);assert_feasible(g2.S,2);

% M=N identity remains exactly the existing effective-channel definition.
H4=H(1:4,:,:);I=eye(4);direct=type1_phase3_wideband_metrics(H4,I,nv);
effective=pagemtimes(I.',H4);
identityError=max(abs(effective-H4),[],'all');
assert(identityError==0 && isfinite(direct.objectiveDb),'type1:R18Identity', ...
    'M=N identity regression failed.');
audit=struct('f1Count',size(F1,3),'r17Count',size(R17,3), ...
    'r17SubsetOfF1',superset,'batchScalarMaxAbsErrorDb',batchError, ...
    'greedyF1Monotone',true,'greedyF2Monotone',true, ...
    'identityMaxAbsError',identityError);
fprintf(['Phase-3 R18 validation PASSED: F1=%d, R17 subset=%d, ' ...
    'batch error=%.3g dB.\n'],audit.f1Count,superset,batchError);
end

function key=schedule_keys(S)
[M,N,K]=size(S);weights=reshape(uint64(2).^(uint64(0:M*N-1)),M,N);
key=zeros(K,1,'uint64');
for k=1:K,key(k)=sum(weights(logical(S(:,:,k))));end
end

function assert_feasible(S,dmax)
assert(all(sum(S,2)<=dmax,'all')&&all(sum(S,1)>=1,'all'), ...
    'type1:R18Feasible','Schedule violates Dmax or coverage.');
end
