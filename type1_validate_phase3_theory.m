function audit=type1_validate_phase3_theory()
%TYPE1_VALIDATE_PHASE3_THEORY Independent algebra/Monte-Carlo R21 guards.
stream=RandStream('mt19937ar','Seed',20262400);M=8;N=4;K=9;
H=(randn(stream,M,N,K)+1j*randn(stream,M,N,K))/sqrt(2);
S=false(M,N);for m=1:M,S(m,mod(m-1,N)+1)=true;end
nv=.2;closed=type1_phase3_theory_metrics(H,S,nv);
numeric=type1_phase3_wideband_metrics(H,S,nv);
sinrError=max(abs(closed.sinrLinear-numeric.sinrLinear),[],'all')/ ...
    max(abs(numeric.sinrLinear),[],'all');
assert(sinrError<1e-12,'type1:R21ClosedForm','Closed-form/current MMSE differ.');

E=.08*(randn(stream,N,N,K)+1j*randn(stream,N,N,K))/sqrt(2*N);
residual=type1_phase3_theory_metrics(H,S,nv,E);direct=zeros(N,K);
Rn=nv*(double(S).'*double(S));
for k=1:K
    G=double(S).'*H(:,:,k);Rz=Rn+E(:,:,k)*E(:,:,k)';
    W=G'/(G*G'+Rz);
    for u=1:N
        desired=abs(W(u,:)*G(:,u))^2;
        other=sum(abs(W(u,:)*G).^2)-desired;
        direct(u,k)=desired/(other+real(W(u,:)*Rz*W(u,:)'));
    end
end
directError=max(abs(direct-residual.sinrLinear),[],'all')/max(abs(direct),[],'all');
boundSlack=min(residual.eigenSinrLower-residual.robustSinrLower);
capacitySlack=min(residual.capacityPerTone-residual.mmseSumRatePerTone);
assert(directError<1e-11&&boundSlack>-1e-11&&capacitySlack>-1e-11, ...
    'type1:R21Bounds','Direct SINR, robust bound or log-det ordering failed.');

model=type1_phase3_config(M,N);corr=type1_phase3_correlation_gain(model.rxCorrelation,S);
[V,D]=eig((model.rxCorrelation+model.rxCorrelation')/2,'vector');
L=V*diag(sqrt(max(real(D),0)));nDraw=50000;
w=(randn(stream,M,nDraw)+1j*randn(stream,M,nDraw))/sqrt(2);h=L*w;
empirical=zeros(1,N);
for n=1:N,empirical(n)=mean(abs(double(S(:,n)).'*h).^2)/sum(S(:,n));end
correlationError=max(abs(empirical-corr.perChainGainLinear)./corr.perChainGainLinear);
identity=type1_phase3_correlation_gain(eye(N),eye(N));
assert(correlationError<.025&&max(abs(identity.perChainGainLinear-1))<eps, ...
    'type1:R21Correlation','Correlation finite-sum/Monte-Carlo guard failed.');
audit=struct('closedFormRelativeError',sinrError,'directSinrRelativeError',directError, ...
    'robustBoundMinimumSlack',boundSlack,'capacityMinimumSlack',capacitySlack, ...
    'correlationMonteCarloRelativeError',correlationError,'allPassed',true);
fprintf(['Phase-3 R21 theory validation PASSED: closed=%.3g, direct=%.3g, ' ...
    'boundSlack=%.3g, capacitySlack=%.3g, corrMC=%.3g.\n'],sinrError,directError, ...
    boundSlack,capacitySlack,correlationError);
end
