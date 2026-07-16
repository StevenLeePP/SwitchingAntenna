function scoreDb=type1_phase3_batch_pss_score(Hpss,schedules,noiseVariance,batchSize)
%TYPE1_PHASE3_BATCH_PSS_SCORE Oracle PSS MRC-SNR proxy for F1 schedules.
%   PSS is transmitted only by layer 1.  For Dmax=1, virtual-chain noise
%   covariance is diagonal with entries sigma2*portsPerChain.

if nargin<4,batchSize=512;end
[M,K]=size(Hpss);[Ms,N,Ball]=size(schedules);
assert(M==Ms&&all(sum(schedules,2)<=1,'all')&&all(sum(schedules,1)>=1,'all'), ...
    'type1:R20PssSchedule','PSS batch score requires covered Dmax=1 schedules.');
scoreDb=zeros(Ball,1);Hp=reshape(Hpss,M,1,K,1);
for first=1:batchSize:Ball
    last=min(Ball,first+batchSize-1);B=last-first+1;
    Sb=double(schedules(:,:,first:last));St=permute(Sb,[2 1 4 3]);
    g=pagemtimes(St,Hp);counts=reshape(sum(Sb,1),N,B);
    scale=reshape(1./sqrt(noiseVariance*counts),N,1,1,B);
    gw=g.*scale;linear=reshape(sum(abs(gw).^2,1),K,B);
    scoreDb(first:last)=10*log10(max(mean(linear,1),realmin)).';
end
end
