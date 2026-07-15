function report = type1_validate_pss_acquisition()
%TYPE1_VALIDATE_PSS_ACQUISITION Validate R13 complex correlation and pairing.
p=type1_load_package(); sim=r13_config(); sim.snrDb=20;
link=type1_offline_link(p,sim,RandStream('mt19937ar','Seed',20262001));
rx=double(link.virtualRx30);
for r=1:size(rx,2)
    scale=rms(rx(:,r)); if scale>0, rx(:,r)=rx(:,r)/scale; end
end
[complexCorrelation,~]=type1_pss_complex_correlation(rx,p,mod(p.cfg.pci,3));
carrier=type1_carrier_config(p.cfg,0); nSC=12*p.cfg.nRB;
localSSB=complex(zeros(240,4)); localSSB(nrPSSIndices)=nrPSS(mod(p.cfg.pci,3));
referenceGrid=complex(zeros(nSC,p.cfg.symbolsPerSlot));
referenceGrid(p.ssbSubcarriers,p.ssbSymbols)=localSSB;
[~,magnitude]=nrTimingEstimate(carrier,rx,referenceGrid,'Nfft',p.cfg.nfft, ...
    'SampleRate',p.cfg.txSampleRate,'CarrierFrequency',0);
correlationRelativeError=norm(abs(complexCorrelation)-double(magnitude),'fro')/ ...
    max(norm(double(magnitude),'fro'),eps);

% The complete switch model is linear once its random trace is frozen.
n=4096; algebraStream=RandStream('mt19937ar','Seed',20262300);
signal=complex(randn(algebraStream,n,4),randn(algebraStream,n,4));
noise=complex(randn(algebraStream,n,4),randn(algebraStream,n,4));
model=sim.switch; model.recordTimeSeries=false; a=.137;
[sumOutput,~,~]=type1_apply_switch_impairments(signal+a*noise,model, ...
    RandStream('mt19937ar','Seed',20262301));
[signalOutput,~,~]=type1_apply_switch_impairments(signal,model, ...
    RandStream('mt19937ar','Seed',20262301));
[noiseOutput,~,~]=type1_apply_switch_impairments(noise,model, ...
    RandStream('mt19937ar','Seed',20262301));
switchLinearityRelativeError=norm(sumOutput-(signalOutput+a*noiseOutput))/ ...
    max(norm(sumOutput),eps);
fprintf('R13 validation pre-gate: correlation relerr %.6g, switch linearity relerr %.6g\n', ...
    correlationRelativeError,switchLinearityRelativeError);
assert(correlationRelativeError<=1e-5,'type1:R13CorrelationEquivalence', ...
    'Complex PSS correlation does not match nrTimingEstimate magnitude.');
assert(switchLinearityRelativeError<=1e-5,'type1:R13SwitchLinearity', ...
    'Frozen-trace switch split is not linear enough for paired SNR reuse.');
report=struct('correlationRelativeError',correlationRelativeError, ...
    'switchLinearityRelativeError',switchLinearityRelativeError, ...
    'correlationTolerance',1e-5,'switchLinearityTolerance',1e-5, ...
    'passed',true);
fprintf('R13 validation: correlation relerr %.3g, switch linearity relerr %.3g, passed=1\n', ...
    correlationRelativeError,switchLinearityRelativeError);
end

function s=r13_config()
s=type1_offline_multiuser_config(); s.frames=1; s.snrDb=20; s.channelModel="tdl-a";
s.userCfoHz=.5*s.userCfoHz; s.tdl.delaySpreadNs=100; s.tdl.dopplerHz=0;
s.tdl.rxCorrelation=.3; s.tdl.txCorrelation=.3;
s.userTimingSamples=min(max(s.userTimingSamples,-4),4);
s.switch.isolationDb=25; s.switch.settlingRiseNs=20;
s.switch.transitionJitterStdPs=20; s.switch.samplingBoundaryJitterStdPs=100;
s.switch.settlingFastJitterStdFraction=0; s.switch.settlingFastJitterCorrelationSec=1e-6;
s.switch.recordTimeSeries=false; cfg=type1_config();
s.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s.suffixSamples=round(cfg.txSampleRate*cfg.frameDurationSec);
s.rxLo.mode="off";
end
