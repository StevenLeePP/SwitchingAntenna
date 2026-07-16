function Htilde = type1_phase3_effective_channel(H, S)
%TYPE1_PHASE3_EFFECTIVE_CHANNEL Return Htilde=S.'*H for binary BABF.
%   The transpose is deliberately nonconjugate: S is real binary on/off.

arguments
    H {mustBeNumeric}
    S {mustBeNumericOrLogical}
end
assert(size(S, 1) == size(H, 1), 'type1:Phase3ChannelShape', ...
    'S and H must share the M physical-antenna dimension.');
Htilde = double(S).' * H;
end
