function audit=type1_validate_phase3_energy()
%TYPE1_VALIDATE_PHASE3_ENERGY Algebraic guards for the R22 common model.
p=type1_phase3_power_parameters();
g=type1_phase3_power_breakdown(p,"ProposedD1",8,4,10,0,1,2);
d=type1_phase3_power_breakdown(p,"DBF",4,4,10,0,1,2);
greenmoError=abs(g.frontPowerW-p.greenmoReferenceFrontW);
dbfError=abs(d.frontPowerW-p.dbfReferenceFrontW);
assert(greenmoError<1e-12&&dbfError<1e-12,'type1:R22ReferencePower', ...
    'GreenMO/DBF Table-1 anchors were not reproduced.');

scan=type1_phase3_power_breakdown(p,"ProposedD1",16,4,30.72,3,.1,2);
energyIdentity=abs(scan.totalEnergyPerUpdateJ-scan.averagePowerW*.1);
assert(abs(scan.scanFraction-.3)<1e-12&&scan.scanEnergyPerUpdateJ>0&&energyIdentity<1e-12, ...
    'type1:R22ScanEnergy','Scan energy/fraction accounting failed.');

stream=RandStream('mt19937ar','Seed',20262500);M=8;N=4;K=11;
H=(randn(stream,M,N,K)+1j*randn(stream,M,N,K))/sqrt(2);nv=.1;
S=false(M,N);for m=1:M,S(m,mod(m-1,N)+1)=true;end
a=type1_phase3_frontend_metrics(H,double(S),nv);
b=type1_phase3_theory_metrics(H,S,nv);
frontendError=max(abs(a.sinrLinear-b.sinrLinear),[],'all')/max(abs(b.sinrLinear),[],'all');
assert(frontendError<1e-12,'type1:R22FrontendMetric','Common front-end metric differs from R21.');
pc=type1_phase3_hbf_combiner(H,N,"partial");fc=type1_phase3_hbf_combiner(H,N,"full");
assert(rank(pc)>=N&&rank(fc)>=N,'type1:R22HbfValidation','HBF reference is rank deficient.');
green=type1_phase3_greenmo_like_schedule(H,nv,S);
assert(green.objectiveDb>=green.trajectoryDb(1)-1e-12&&all(sum(green.S,2)<=N), ...
    'type1:R22GreenMOValidation','GreenMO-like additions violate monotonicity/Dmax.');
audit=struct('greenmoReferenceErrorW',greenmoError,'dbfReferenceErrorW',dbfError, ...
    'scanEnergyIdentityErrorJ',energyIdentity,'frontendRelativeError',frontendError, ...
    'greenmoMonotone',true,'allPassed',true);
fprintf(['Phase-3 R22 energy validation PASSED: GreenMO=%.3f W, DBF=%.3f W, ' ...
    'scan=%.1f%%, frontend=%.3g.\n'],g.frontPowerW,d.frontPowerW,100*scan.scanFraction,frontendError);
end
