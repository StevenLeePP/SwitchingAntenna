function result=type1_phase3_correlation_gain(R,S)
%TYPE1_PHASE3_CORRELATION_GAIN Expected noise-normalized coherent gain.
%   For h~CN(0,R), binary chain vector s has
%       E|s.'h|^2 / ||s||^2 = s.'*R*s / (s.'*s).
%   This finite quadratic form binds port count, aperture and correlation.

arguments
    R {mustBeNumeric}
    S {mustBeNumericOrLogical}
end
M=size(S,1);assert(isequal(size(R),[M M]),'type1:R21CorrelationShape', ...
    'R must match the physical-port dimension of S.');
R=(R+R')/2;S=double(S);loads=sum(S,1);
assert(all(loads>0),'type1:R21CorrelationCoverage','Every virtual chain must be covered.');
gain=real(diag(S.'*R*S)).'./loads;
eigenvalues=real(eig(R));
result=struct('perChainGainLinear',gain,'perChainGainDb',10*log10(max(gain,realmin)), ...
    'meanGainLinear',mean(gain),'minGainLinear',min(gain), ...
    'rayleighLower',min(eigenvalues),'rayleighUpper',max(eigenvalues), ...
    'loads',loads);
end
