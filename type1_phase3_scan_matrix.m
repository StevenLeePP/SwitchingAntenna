function [schedules,W]=type1_phase3_scan_matrix(M,N,isolationDb)
%TYPE1_PHASE3_SCAN_MATRIX Disjoint N-port scan groups and nominal weights.
arguments
    M (1,1) double {mustBeInteger,mustBePositive}
    N (1,1) double {mustBeInteger,mustBePositive}
    isolationDb (1,1) double
end
assert(M>=N&&mod(M,N)==0,'type1:E1ScanDimensions', ...
    'E1 freezes M to an integer number of N-port scan groups.');
G=M/N;schedules=cell(1,G);W=zeros(G*N,M);
if isinf(isolationDb),leak=0;else,leak=10^(-isolationDb/20);end
for g=1:G
    S=false(M,N);
    for q=1:N,S((g-1)*N+q,q)=true;end
    schedules{g}=S;
    for q=1:N
        row=(g-1)*N+q;weight=leak*ones(1,M);weight(S(:,q))=1;
        W(row,:)=weight;
    end
end
assert(rank(W)==M,'type1:E1ScanRank','Nominal scan matrix is rank deficient.');
end
