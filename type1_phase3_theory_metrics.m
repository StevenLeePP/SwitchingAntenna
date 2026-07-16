function metrics=type1_phase3_theory_metrics(H,S,noiseVariance,E)
%TYPE1_PHASE3_THEORY_METRICS Closed-form LMMSE SINR/rate with residual Ex.
%   y=Gx+Ex+n, G=S.'*H, Rn=sigma2*S.'*S.  The residual Ex is treated as
%   uncorrelated Gaussian self-interference with covariance E*E'.  This is
%   a conservative achievable-rate model, not a claim that coherent model
%   mismatch is statistically independent of x.

arguments
    H {mustBeNumeric}
    S {mustBeNumericOrLogical}
    noiseVariance (1,1) double {mustBePositive}
    E {mustBeNumeric}=[]
end
[M,N,K]=size(H);assert(isequal(size(S),[M N]),'type1:R21Shape', ...
    'S must be M-by-N for H of size M-by-N-by-K.');
if isempty(E),E=complex(zeros(N,N,K));end
assert(isequal(size(E),[N N K]),'type1:R21ResidualShape', ...
    'E must be an N-by-N-by-K post-switch residual channel.');
S=double(S);Rn=noiseVariance*(S.'*S);
assert(rcond(Rn)>1e-12,'type1:R21NoiseRank','S produces singular virtual noise.');
L=chol(Rn,'lower');sinr=zeros(N,K);eigLower=zeros(1,K);eigUpper=eigLower;
robustLower=eigLower;capacity=eigLower;mmseSumRate=eigLower;
for k=1:K
    G=S.'*H(:,:,k);Ek=E(:,:,k);Rz=Rn+Ek*Ek';
    B=G'*(Rz\G);B=(B+B')/2;
    C=(eye(N)+B)\eye(N);diagonal=max(real(diag(C)),realmin);
    sinr(:,k)=max(1./diagonal-1,realmin);
    eigenvalues=max(real(eig(B)),0);eigLower(k)=min(eigenvalues);
    eigUpper(k)=max(eigenvalues);capacity(k)=sum(log2(1+eigenvalues));
    mmseSumRate(k)=sum(log2(1+sinr(:,k)));
    F=L\G;D=L\Ek;
    robustLower(k)=min(svd(F))^2/(1+norm(D,2)^2);
end
sinrDb=10*log10(sinr);perUserRate=mean(log2(1+sinr),2).';
metrics=struct('objectiveDb',min(mean(sinrDb,2)), ...
    'perUserMeanSinrDb',mean(sinrDb,2).','sinrLinear',sinr, ...
    'perUserRate',perUserRate,'minUserRate',min(perUserRate), ...
    'sumMmseRate',mean(mmseSumRate),'capacityLogDet',mean(capacity), ...
    'capacityPerTone',capacity,'mmseSumRatePerTone',mmseSumRate, ...
    'eigenSinrLower',eigLower,'eigenSinrUpper',eigUpper, ...
    'robustSinrLower',robustLower,'robustMinUserRate',mean(log2(1+robustLower)), ...
    'noiseCovariance',Rn,'residualInterpretation', ...
    "Ex is conservatively treated as Gaussian self-interference");
end
