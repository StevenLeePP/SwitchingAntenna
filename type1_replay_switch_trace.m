function [stitched, virtualRF, targetTrace] = type1_replay_switch_trace(raw122, meta)
%TYPE1_REPLAY_SWITCH_TRACE Replay one recorded switch realization.
%   This is a truth-only Phase-2 helper.  It applies the recorded sampling
%   boundary offsets, leakage matrix and beta[n] to a new linear component,
%   allowing each transmitted layer to be replayed without drawing another
%   random switch trajectory.  It must not be used by an operational RX.

assert(size(raw122,2)==4 && mod(size(raw122,1),4)==0, ...
    'type1:ReplaySwitchShape','raw122 must be N-by-4 with N divisible by four.');
required={'leakageMatrix','settlingBeta','boundaryOffsetSamples'};
for k=1:numel(required)
    assert(isfield(meta,required{k}) && ~isempty(meta.(required{k})), ...
        'type1:ReplaySwitchMeta','Recorded switch meta is missing %s.',required{k});
end
beta=double(meta.settlingBeta(:)); offset=double(meta.boundaryOffsetSamples(:));
assert(numel(beta)==size(raw122,1) && numel(offset)==size(raw122,1), ...
    'type1:ReplaySwitchLength','Recorded switch traces do not match raw122.');
rawAtBoundary=fractional_boundary_sample(raw122,offset);
nSamples=size(raw122,1); stitched=complex(zeros(nSamples,1,'like',raw122));
targetTrace=complex(zeros(nSamples,1,'like',raw122)); state=zeros(1,1,'like',raw122);
for n=1:nSamples
    phase=mod(n-1,4)+1;
    target=rawAtBoundary(n,:)*meta.leakageMatrix(phase,:).';
    targetTrace(n)=target;
    if n==1, state=target;
    else, state=(1-beta(n))*state+beta(n)*target; end
    stitched(n)=state;
end
virtualRF=reshape(stitched,4,[]).';
end

function y=fractional_boundary_sample(x,offsetSamples)
assert(all(abs(offsetSamples)<.5),'type1:ReplayBoundaryRange', ...
    'Recorded boundary displacement must remain below half a raw sample.');
n=size(x,1); taps=-4:4; window=.54+.46*cos(pi*taps/4);
weights=zeros(n,numel(taps));
for k=1:numel(taps), weights(:,k)=window(k)*sinc(offsetSamples-taps(k)); end
weights=weights./sum(weights,2); y=complex(zeros(size(x),'like',x));
for k=1:numel(taps)
    source=(1:n).'+taps(k); valid=source>=1 & source<=n;
    if any(valid), y(valid,:)=y(valid,:)+x(source(valid),:).*weights(valid,k); end
end
end
