function out=type1_phase3_power_breakdown(p,architecture,M,N,sampleRateMsps,scanFrames,updateSec,scenario)
%TYPE1_PHASE3_POWER_BREAKDOWN Common RX energy accounting for R22.
arguments
    p (1,1) struct
    architecture (1,1) string {mustBeMember(architecture, ...
        ["ProposedD1" "GreenMOLike" "DBF" "PCHBF" "FCHBF"])}
    M (1,1) double {mustBeInteger,mustBePositive}
    N (1,1) double {mustBeInteger,mustBePositive}
    sampleRateMsps (1,1) double {mustBePositive}
    scanFrames (1,1) double {mustBeNonnegative,mustBeInteger}
    updateSec (1,1) double {mustBePositive}
    scenario (1,1) double {mustBeInteger,mustBePositive}
end
assert(scenario<=numel(p.scenarioNames),'type1:R22PowerScenario','Unknown scenario.');
switch architecture
    case {"ProposedD1","GreenMOLike"}
        rfPower=p.rfSingleW;adcMsps=N*sampleRateMsps;switches=M;phase=0;digitalInputs=N;
    case "DBF"
        rfPower=M*p.rfSynchronizedW;adcMsps=M*sampleRateMsps;switches=0;phase=0;digitalInputs=M;scanFrames=0;
    case "PCHBF"
        rfPower=N*p.rfSynchronizedW;adcMsps=N*sampleRateMsps;switches=0;phase=M;digitalInputs=N;
    case "FCHBF"
        rfPower=N*p.rfSynchronizedW;adcMsps=N*sampleRateMsps;switches=0;phase=M*N;digitalInputs=N;
end
rfPower=rfPower*p.rfScale(scenario);adcPower=adcMsps*p.adcWPerMsps*p.adcScale(scenario);
switchPower=switches*p.switchW*p.switchScale(scenario);
phasePower=phase*p.phaseShifterW*p.phaseScale(scenario);
frontPower=rfPower+adcPower+switchPower+phasePower;
bbData=(digitalInputs*p.bbFftPerDigitalInputW+ ...
    p.bbSolveAtFourStreamsW*(N/4)^p.bbSolveExponent)*p.bbScale(scenario);
bbScan=p.scanComputeMultiplier*bbData;
scanSec=min(.99*updateSec,scanFrames*p.frameDurationSec);payloadSec=updateSec-scanSec;
frontEnergy=frontPower*updateSec;bbPayloadEnergy=bbData*payloadSec;
bbScanEnergy=bbScan*scanSec;totalEnergy=frontEnergy+bbPayloadEnergy+bbScanEnergy;
scanEnergy=(frontPower+bbScan)*scanSec;
out=struct('architecture',architecture,'scenario',p.scenarioNames(scenario), ...
    'rfPowerW',rfPower,'adcPowerW',adcPower,'switchPowerW',switchPower, ...
    'phaseShifterPowerW',phasePower,'frontPowerW',frontPower, ...
    'bbDataPowerW',bbData,'bbScanPowerW',bbScan,'averagePowerW',totalEnergy/updateSec, ...
    'totalEnergyPerUpdateJ',totalEnergy,'scanEnergyPerUpdateJ',scanEnergy, ...
    'scanFraction',scanSec/updateSec,'payloadFraction',payloadSec/updateSec, ...
    'scanFrames',scanFrames,'nDigitalInputs',digitalInputs,'adcAggregateMsps',adcMsps, ...
    'loAccounting',"included in RFIC; not double counted");
end
