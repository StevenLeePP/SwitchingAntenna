function anchor = type1_phase_noise_anchor(incrementStdRad, offsetHz, sampleRate)
%TYPE1_PHASE_NOISE_ANCHOR Wiener increment <-> free-running SSB L(f) anchor.
% For independent phase increments with var(delta_phi)=sigma^2,
% S_phi,two-sided(f) ~= sigma^2*Fs/(4*pi^2*f^2).  IEEE SSB phase noise
% is one half of the one-sided phase PSD, hence it equals this two-sided
% value.  This is a free-running small-offset Lorentzian-tail anchor, not
% a locked-PLL mask.
if nargin<3, sampleRate=30.72e6; end
if nargin<2, offsetHz=10e3; end
if nargin<1, incrementStdRad=1.5e-4; end
L=incrementStdRad^2*sampleRate/(4*pi^2*offsetHz^2);
anchor=struct('incrementStdRadPerSample',incrementStdRad,'offsetHz',offsetHz, ...
    'ssbPhaseNoiseDbcPerHz',10*log10(L),'model','free-running Wiener oscillator');
fprintf('Wiener sigma=%g rad/sample -> L(%g Hz)=%.2f dBc/Hz (free-running approximation).\n',incrementStdRad,offsetHz,anchor.ssbPhaseNoiseDbcPerHz);
end
