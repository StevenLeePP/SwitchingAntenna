function [stitched,virtual]=type1_phase3_apply_target(target,beta,nVirtual)
%TYPE1_PHASE3_APPLY_TARGET Apply the causal settling state to one scalar target.
assert(isvector(target)&&numel(target)==numel(beta),'type1:R20TargetShape', ...
    'target and beta must be equal-length vectors.');
target=target(:);beta=beta(:);
if exist('type1_phase3_iir_mex','file')==3
    stitched=type1_phase3_iir_mex(target,beta);
else
    stitched=complex(zeros(size(target),'like',target));state=target(1);stitched(1)=state;
    for n=2:numel(target),state=(1-beta(n))*state+beta(n)*target(n);stitched(n)=state;end
end
virtual=reshape(stitched,nVirtual,[]).';
end
