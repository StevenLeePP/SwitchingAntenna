function audit=type1_validate_phase3_r20()
%TYPE1_VALIDATE_PHASE3_R20 Algebraic guards for AMC/acquisition/M scaling.
stream=RandStream('mt19937ar','Seed',20262300);M=8;N=4;K=17;
H=randn(stream,M,N,K)+1j*randn(stream,M,N,K);Hpss=reshape(H(:,1,:),M,K);nv=.1;
S1=[eye(4);zeros(4)];S2=false(8,4);S2(1,1)=1;S2(3,2)=1;S2(5,3)=1;S2(7,4)=1;
batch=type1_phase3_batch_pss_score(Hpss,cat(3,S1,S2),nv,2);
scalar=zeros(2,1);sets={S1,S2};
for k=1:2
    S=double(sets{k});g=pagemtimes(S.',reshape(Hpss,M,1,K));Rn=nv*(S.'*S);
    linear=zeros(1,K);for tone=1:K,linear(tone)=real(g(:,:,tone)'*(Rn\g(:,:,tone)));end
    scalar(k)=10*log10(mean(linear));
end
pssError=max(abs(batch-scalar));assert(pssError<1e-10,'type1:R20PssMetric','PSS batch/scalar differ.');
aware=type1_phase3_acquisition_aware_schedule(H,Hpss,nv,S1);
assert(aware.pssMarginDb>=-1e-9&&all(sum(aware.S,2)<=1,'all')&&all(sum(aware.S,1)>=1), ...
    'type1:R20Aware','Acquisition-aware schedule violates its guard.');

physical=randn(stream,128,M)+1j*randn(stream,128,M);
targets=type1_phase3_switch_targets_from_physical(physical,{S1,S2},25);
raw=complex(zeros(4*size(physical,1),M));for m=1:M,raw(:,m)=resample(physical(:,m),4,1);end
reference=complex(zeros(size(targets)));
leak=10^(-25/20);
for a=1:2
    S=sets{a};
    for q=1:N
        rows=q:N:size(raw,1);w=leak*ones(M,1);w(logical(S(:,q)))=1;
        reference(rows,a)=raw(rows,:)*w;
    end
end
targetError=max(abs(double(targets)-reference),[],'all');
assert(targetError<2e-5,'type1:R20Target','Streaming target differs from explicit raw matrix.');
beta=.3+.7*rand(stream,size(targets,1),1);[stitched,~]=type1_phase3_apply_target(targets(:,1),beta,N);
manual=complex(zeros(size(targets,1),1,'single'));manual(1)=targets(1,1);
for n=2:numel(manual),manual(n)=(1-beta(n))*manual(n-1)+beta(n)*targets(n,1);end
iirError=max(abs(stitched-manual));assert(iirError<2e-6,'type1:R20Iir','MEX/fallback IIR differs.');
amc=type1_phase3_amc_table();assert(all(diff(amc.thresholdDb)>0)&&all(diff(amc.efficiency)>0)&& ...
    numel(amc.modulation)==numel(amc.efficiency),'type1:R20Amc','AMC table is not monotone.');
audit=struct('pssBatchScalarMaxAbsErrorDb',pssError,'awarePssMarginDb',aware.pssMarginDb, ...
    'streamingTargetMaxAbsError',targetError,'iirMaxAbsError',iirError, ...
    'amcMonotone',true,'mexUsed',exist('type1_phase3_iir_mex','file')==3,'allPassed',true);
fprintf(['Phase-3 R20 validation PASSED: PSS err=%.3g dB, aware margin=%+.3f dB, ' ...
    'target err=%.3g, IIR err=%.3g, mex=%d.\n'],pssError,aware.pssMarginDb, ...
    targetError,iirError,audit.mexUsed);
end
