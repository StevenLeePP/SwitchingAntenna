function [beta,meta]=type1_phase3_switch_beta(nSamples,model,stream)
%TYPE1_PHASE3_SWITCH_BETA Reproducible M-independent settling trajectory.
%   A single beta[n] trajectory is reused by all paired schedules, so an
%   algorithm cannot benefit from a different jitter realization.

required={'rawSampleRateHz','settlingRiseNs','settlingFastJitterStdFraction', ...
    'settlingFastJitterCorrelationSec'};
for k=1:numel(required),assert(isfield(model,required{k}),'type1:R19SwitchModel', ...
        'Missing switch field %s.',required{k});end
if model.settlingRiseNs==0
    beta=ones(nSamples,1);fast=zeros(nSamples,1);tau=zeros(nSamples,1);
else
    tau0=model.settlingRiseNs*1e-9/log(9);stdFraction=model.settlingFastJitterStdFraction;
    if stdFraction==0
        fast=zeros(nSamples,1);
    else
        assert(~isempty(stream),'type1:R19SwitchStream','Jitter requires a RandStream.');
        tc=model.settlingFastJitterCorrelationSec;
        if tc==0,fast=stdFraction*randn(stream,nSamples,1);
        else
            alpha=exp(-1/(model.rawSampleRateHz*tc));
            innovation=stdFraction*sqrt(1-alpha^2);
            fast=zeros(nSamples,1);fast(1)=stdFraction*randn(stream);
            for n=2:nSamples,fast(n)=alpha*fast(n-1)+innovation*randn(stream);end
        end
    end
    scale=1+fast;floorHit=sum(scale<=.01);tau=tau0*max(scale,.01);
    beta=1-exp(-1/model.rawSampleRateHz./tau);
end
if model.settlingRiseNs==0,floorHit=0;end
meta=struct('betaMean',mean(beta),'betaStd',std(beta), ...
    'tauMeanNs',1e9*mean(tau),'tauStdNs',1e9*std(tau), ...
    'floorHitCount',floorHit,'floorHitFraction',floorHit/nSamples, ...
    'fastLag1',lag1(fast));
end

function value=lag1(x)
if all(x==0),value=nan;return;end
x=x-mean(x);value=real(sum(x(1:end-1).*x(2:end))/sqrt( ...
    sum(abs(x(1:end-1)).^2)*sum(abs(x(2:end)).^2)+eps));
end
