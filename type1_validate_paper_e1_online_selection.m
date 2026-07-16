function audit=type1_validate_paper_e1_online_selection()
%TYPE1_VALIDATE_PAPER_E1_ONLINE_SELECTION Algebraic E1 scan/selector checks.
stream=RandStream('mt19937ar','Seed',20260716);M=16;N=4;
[schedules,W]=type1_phase3_scan_matrix(M,N,25);
H=(randn(stream,M,N,17)+1j*randn(stream,M,N,17))/sqrt(2);
Y=pagemtimes(reshape(W,M,M,1),H);recovered=complex(zeros(size(H)));
for k=1:size(H,3),recovered(:,:,k)=W\Y(:,:,k);end
recoveryError=norm(recovered(:)-H(:))/norm(H(:));
coverage=all(sum(cat(3,schedules{:}),[2 3])==1,'all');
nv=.01;oracle=type1_phase3_greedy_schedule(H,nv,1);
estimated=type1_phase3_greedy_schedule(recovered,nv,1);
objectiveError=abs(type1_phase3_wideband_metrics(H,oracle.S,nv).objectiveDb- ...
    type1_phase3_wideband_metrics(H,estimated.S,nv).objectiveDb);
audit=struct('scanMatrixRank',rank(W),'weightCondition',cond(W), ...
    'disjointCoverage',coverage,'algebraicRecoveryRelativeError',recoveryError, ...
    'idealSelectorObjectiveErrorDb',objectiveError, ...
    'allPassed',rank(W)==M&&coverage&&recoveryError<1e-12&&objectiveError<1e-10);
assert(audit.allPassed,'type1:E1Validation','E1 scan algebra validation failed.');
fprintf('Paper E1 validation PASSED: rank=%d, recovery=%.3g, selector=%.3g dB.\n', ...
    rank(W),recoveryError,objectiveError);
end
