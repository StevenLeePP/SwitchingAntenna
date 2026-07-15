function [correlation, reference] = type1_pss_complex_correlation(rx, package, nid2)
%TYPE1_PSS_COMPLEX_CORRELATION Complex PSS matched-filter output.
%   nrTimingEstimate returns abs(xcorr) and therefore cannot be reused for
%   an exactly paired signal-plus-scaled-noise SNR sweep.  This helper keeps
%   the complex correlation until after signal and noise have been combined.
%   Its absolute value is regression-checked against nrTimingEstimate.

arguments
    rx {mustBeNumeric}
    package (1,1) struct
    nid2 (1,1) double {mustBeInteger,mustBeGreaterThanOrEqual(nid2,0),mustBeLessThanOrEqual(nid2,2)}
end

cfg=package.cfg; carrier=type1_carrier_config(cfg,0); nSC=12*cfg.nRB;
localSSB=complex(zeros(240,4)); localSSB(nrPSSIndices)=nrPSS(nid2);
referenceGrid=complex(zeros(nSC,cfg.symbolsPerSlot));
referenceGrid(package.ssbSubcarriers,package.ssbSymbols)=localSSB;
reference=nrOFDMModulate(carrier,referenceGrid,'Nfft',cfg.nfft, ...
    'SampleRate',cfg.txSampleRate,'CarrierFrequency',0,'Windowing',0);

rx=double(rx); reference=double(reference); n=size(rx,1); m=size(reference,1);
nfft=2^nextpow2(n+m-1);
kernel=fft(conj(flipud(reference)),nfft);
filtered=ifft(fft(rx,nfft,1).*kernel,nfft,1);
correlation=filtered(m:m+n-1,:);
end
