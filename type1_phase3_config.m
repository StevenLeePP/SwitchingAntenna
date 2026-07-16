function model = type1_phase3_config(nPhysical, nVirtual)
%TYPE1_PHASE3_CONFIG Frozen Part-A geometry and single-chain constraints.
%   Spatial correlation is derived from the physical ULA port positions;
%   it is not an independently tunable exponential coefficient.

if nargin < 1, nPhysical = 8; end
if nargin < 2, nVirtual = 4; end
validateattributes(nPhysical, {'numeric'}, {'scalar','integer','positive'});
validateattributes(nVirtual, {'numeric'}, {'scalar','integer','positive'});
assert(nPhysical >= nVirtual, 'type1:Phase3Dimensions', ...
    'Part A requires M=nPhysical >= N=nVirtual.');

spacingLambda = 0.5;
positionsLambda = (0:nPhysical-1).' * spacingLambda;
distanceLambda = abs(positionsLambda - positionsLambda.');
rxCorrelation = besselj(0, 2*pi*distanceLambda);
rxCorrelation = (rxCorrelation + rxCorrelation') / 2;
rxCorrelation(1:nPhysical+1:end) = 1;

model = struct;
model.nPhysical = nPhysical;
model.nVirtual = nVirtual;
model.codePeriod = nVirtual;
model.virtualSampleRateHz = 30.72e6;
model.rawSampleRateHz = nVirtual * model.virtualSampleRateHz;
model.maxDutyCount = nVirtual;
model.allowEmptyVirtualChain = false;
model.canonicalPhaseOwnership = true;
model.settlingRiseNs = 0;
model.enforceSettlingConstraint = false;
model.maxSettlingUtilization = 1;
model.spacingLambda = spacingLambda;
model.positionsLambda = positionsLambda;
model.apertureLambda = positionsLambda(end) - positionsLambda(1);
model.correlationModel = "isotropic-2d-j0";
model.rxCorrelation = rxCorrelation;
model.tdl = struct('delaySpreadNs', 100, 'txCorrelation', 0.5, ...
    'dopplerHz', 0);
end
