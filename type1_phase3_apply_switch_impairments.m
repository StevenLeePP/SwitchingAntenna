function [stitched,virtual,meta]=type1_phase3_apply_switch_impairments(raw,S,model,beta)
%TYPE1_PHASE3_APPLY_SWITCH_IMPAIRMENTS M-port scalar switch with causal IIR.
%   In phase q the target is the coherent sum of selected ports plus the
%   isolation-limited leakage of every unselected port.  Only one scalar
%   state/output is digitized.  beta[n] is supplied externally for strict
%   paired comparisons across schedules.

[nSamples,M]=size(raw);[Ms,N]=size(S);
assert(M==Ms&&mod(nSamples,N)==0,'type1:R19SwitchShape', ...
    'raw/S dimensions differ or raw length is not divisible by N.');
assert(all(S(:)==0|S(:)==1)&&all(sum(S,1)>=1),'type1:R19Schedule', ...
    'R19 requires binary coverage schedules.');
assert(numel(beta)==nSamples,'type1:R19BetaShape','beta length differs from raw.');
if isinf(model.isolationDb),leak=0;else,leak=10^(-model.isolationDb/20);end
target=complex(zeros(nSamples,1,'like',raw));phaseLoad=sum(S,1);
for q=1:N
    rows=q:N:nSamples;weight=cast(leak*ones(M,1),'like',raw);weight(logical(S(:,q)))=1;
    target(rows)=raw(rows,:)*weight;
end
stitched=complex(zeros(nSamples,1,'like',raw));state=target(1);stitched(1)=state;
for n=2:nSamples,state=(1-beta(n))*state+beta(n)*target(n);stitched(n)=state;end
virtual=reshape(stitched,N,[]).';
meta=struct('nPhysical',M,'nVirtual',N,'digitizedOutputColumns',1, ...
    'isolationDb',model.isolationDb,'leakageAmplitude',leak, ...
    'phaseLoad',phaseLoad,'betaMean',mean(beta),'betaStd',std(beta), ...
    'scalarInvariantPassed',size(stitched,2)==1);
end
