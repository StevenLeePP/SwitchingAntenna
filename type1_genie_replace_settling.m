function virtualRF = type1_genie_replace_settling(stitchedDynamic, betaDynamic, betaReference)
%TYPE1_GENIE_REPLACE_SETTLING Replace dynamic settling by reference settling.
%   First invert the known dynamic beta[n] IIR to recover its instantaneous
%   target, then run that target through the reference beta[n] IIR.  For the
%   R7 L0--L3 ladder this removes only the added fast tau jitter while keeping
%   the static rise-time response, leakage, boundary jitter, CFO, phase noise,
%   channel and AWGN common with L0.

assert(isvector(stitchedDynamic) && isvector(betaDynamic) && isvector(betaReference), ...
    'type1:GenieReplaceSettling','Inputs must be vectors.');
assert(numel(stitchedDynamic)==numel(betaDynamic) && numel(betaDynamic)==numel(betaReference), ...
    'type1:GenieReplaceSettling','All inputs must have equal length.');
assert(mod(numel(stitchedDynamic),4)==0 && all(betaDynamic>0 & betaDynamic<=1) && ...
    all(betaReference>0 & betaReference<=1), 'type1:GenieReplaceSettling','Invalid beta sequence.');
s=stitchedDynamic(:); bd=betaDynamic(:); br=betaReference(:);
target=complex(zeros(size(s),'like',s)); target(1)=s(1);
for n=2:numel(s)
    target(n)=(s(n)-(1-bd(n))*s(n-1))/bd(n);
end
reference=complex(zeros(size(s),'like',s)); reference(1)=target(1);
for n=2:numel(s)
    reference(n)=(1-br(n))*reference(n-1)+br(n)*target(n);
end
virtualRF=reshape(reference,4,[]).';
end
