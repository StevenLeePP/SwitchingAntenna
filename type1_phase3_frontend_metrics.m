function metrics=type1_phase3_frontend_metrics(H,F,noiseVariance)
%TYPE1_PHASE3_FRONTEND_METRICS Common ideal linear-front-end rate metric.
%   Physical channel H is M-by-N-by-K and analog front end F is M-by-R.
%   The digitized channel/noise are G=F^H H and Rn=sigma2 F^H F.

arguments
    H {mustBeNumeric}
    F {mustBeNumeric}
    noiseVariance (1,1) double {mustBePositive}
end
[M,N,K]=size(H);assert(size(F,1)==M,'type1:R22FrontendShape', ...
    'F and H must share the physical-port dimension.');
R=size(F,2);assert(R>=N&&rank(F)>=N,'type1:R22FrontendRank', ...
    'The front end needs at least N independent digitized dimensions.');
Rn=noiseVariance*(F'*F);assert(rcond(Rn)>1e-12,'type1:R22NoiseRank', ...
    'The digitized noise covariance is singular.');
sinr=zeros(N,K);capacity=zeros(1,K);sumRate=zeros(1,K);
for k=1:K
    G=F'*H(:,:,k);B=G'*(Rn\G);B=(B+B')/2;
    C=(eye(N)+B)\eye(N);sinr(:,k)=max(1./max(real(diag(C)),realmin)-1,realmin);
    lambda=max(real(eig(B)),0);capacity(k)=sum(log2(1+lambda));
    sumRate(k)=sum(log2(1+sinr(:,k)));
end
perUser=mean(log2(1+sinr),2).';
metrics=struct('sinrLinear',sinr,'perUserRate',perUser,'minUserRate',min(perUser), ...
    'sumMmseRate',mean(sumRate),'capacityLogDet',mean(capacity), ...
    'nDigitalInputs',R,'noiseCovariance',Rn);
end
