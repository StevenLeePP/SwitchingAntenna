function p=type1_phase3_power_parameters()
%TYPE1_PHASE3_POWER_PARAMETERS Frozen GreenMO-anchored R22 component table.
p=struct;
p.rfSingleW=.354;p.rfSynchronizedW=.408;p.adcWPerMsps=.010;
p.switchW=.001;p.phaseShifterW=.010;
p.greenmoReferenceFrontW=.762;p.dbfReferenceFrontW=2.032;
p.bbReferenceW=(.3/.7)*p.greenmoReferenceFrontW;
p.bbFftFraction=.5;p.bbFftPerDigitalInputW=p.bbReferenceW*p.bbFftFraction/4;
p.bbSolveAtFourStreamsW=p.bbReferenceW*(1-p.bbFftFraction);
p.bbSolveExponent=3;p.frameDurationSec=.010;p.scanComputeMultiplier=1;
p.scenarioNames=["low" "nominal" "high"];
p.rfScale=[.8 1 1.2];p.adcScale=[.5 1 1.5];p.switchScale=[.5 1 2];
p.phaseScale=[.5 1 2];p.bbScale=[.5 1 1.5];
p.sources=struct('greenmo',"https://wcsng.ucsd.edu/files/greenmo.pdf", ...
    'max2829',"https://www.analog.com/en/products/max2829.html", ...
    'ad9963',"https://www.analog.com/en/products/ad9963.html", ...
    'hbf',"https://arxiv.org/abs/1807.07201");
p.isBillOfMaterials=false;
end
