function [output,meta] = type1_apply_rx_lo_phase_noise(input,model,sampleRateHz)
%TYPE1_APPLY_RX_LO_PHASE_NOISE Apply a bounded single-pole RX-PLL model.
%   common applies one stationary OU/AR(1) phase process to every input
%   column; independent applies one process per column.  The model owns its
%   RandStream and therefore never changes an enclosing simulation stream.

arguments
    input {mustBeNumeric}
    model (1,1) struct
    sampleRateHz (1,1) double {mustBePositive}
end
model=complete_model(model); mode=lower(string(model.mode));
assert(any(mode==["off" "common" "independent"]),'type1:RxLoMode', ...
    'RX-LO mode must be off, common, or independent.');
assert(isfinite(model.phaseRmsDeg) && model.phaseRmsDeg>=0, ...
    'type1:RxLoSigma','phaseRmsDeg must be finite and nonnegative.');
assert(isfinite(model.bandwidthHz) && model.bandwidthHz>0 && ...
    model.bandwidthHz<sampleRateHz/2,'type1:RxLoBandwidth', ...
    'bandwidthHz must lie strictly between zero and Nyquist.');
assert(isfinite(model.seed) && model.seed>=0 && model.seed==round(model.seed), ...
    'type1:RxLoSeed','seed must be a nonnegative integer.');

sigmaRad=deg2rad(model.phaseRmsDeg); alpha=exp(-2*pi*model.bandwidthHz/sampleRateHz);
if mode=="off" || sigmaRad==0
    output=input; phase=zeros(0,1); measuredStd=0; measuredLag=nan;
else
    nOscillators=1;
    if mode=="independent", nOscillators=size(input,2); end
    stream=RandStream('mt19937ar','Seed',model.seed);
    innovation=sigmaRad*sqrt(1-alpha^2)*randn(stream,size(input,1),nOscillators);
    innovation(1,:)=sigmaRad*randn(stream,1,nOscillators);
    phase=filter(1,[1 -alpha],innovation);
    if mode=="common"
        output=input.*exp(1j*phase);
    else
        output=input.*exp(1j*phase);
    end
    measuredStd=std(phase,0,1); measuredLag=lag1_columns(phase);
end
if logical(model.recordTimeSeries), savedPhase=phase; else, savedPhase=zeros(0,1); end
meta=struct('mode',mode,'phaseRmsDeg',model.phaseRmsDeg, ...
    'bandwidthHz',model.bandwidthHz,'sampleRateHz',sampleRateHz,'seed',model.seed, ...
    'alpha',alpha,'phaseStdRad',measuredStd,'phaseLag1',measuredLag, ...
    'phaseRad',savedPhase,'commonPhaseColumnCount',1+(mode=="independent")*(size(input,2)-1));
end

function model=complete_model(model)
defaults=struct('mode',"off",'phaseRmsDeg',0,'bandwidthHz',100e3, ...
    'seed',20261200,'recordTimeSeries',false);
names=fieldnames(defaults);
for k=1:numel(names)
    if ~isfield(model,names{k}), model.(names{k})=defaults.(names{k}); end
end
end

function value=lag1_columns(x)
value=nan(1,size(x,2));
for k=1:size(x,2)
    z=x(:,k)-mean(x(:,k));
    value(k)=real(sum(z(1:end-1).*z(2:end))/ ...
        sqrt(sum(z(1:end-1).^2)*sum(z(2:end).^2)+eps));
end
end
