function audit=type1_validate_phase3_gate3()
%TYPE1_VALIDATE_PHASE3_GATE3 R19 M-port impairment algebraic guards.
stream=RandStream('mt19937ar','Seed',20261900);raw=randn(stream,4096,8)+1j*randn(stream,4096,8);
S=[eye(4);zeros(4)];ideal=model_template(Inf,0,0,0);
[beta,bmeta]=type1_phase3_switch_beta(size(raw,1),ideal,[]);
[stitched,virtual,meta]=type1_phase3_apply_switch_impairments(raw,S,ideal,beta);
expected=complex(zeros(size(stitched)));for q=1:4,expected(q:4:end)=raw(q:4:end,q);end
identityError=max(abs(stitched-expected));reshapeError=max(abs(virtual-reshape(expected,4,[]).'),[],'all');
assert(identityError==0&&reshapeError==0&&meta.digitizedOutputColumns==1, ...
    'type1:R19Identity','M=8 with only identity ports active must select exactly those ports.');
S2=[eye(4);eye(4)];[~,v2]=type1_phase3_apply_switch_impairments(raw,S2,ideal,beta);
direct=zeros(size(v2));for q=1:4,direct(:,q)=raw(q:4:end,q)+raw(q:4:end,q+4);end
sumError=max(abs(v2-direct),[],'all');assert(sumError<1e-12,'type1:R19Sum','Ideal phase sum differs.');
damaged=model_template(25,20,.2,1e-6);[bd,dm]=type1_phase3_switch_beta(size(raw,1),damaged,stream);
assert(all(bd>0&bd<=1)&&abs(dm.fastLag1-exp(-1/(damaged.rawSampleRateHz*1e-6)))<.02, ...
    'type1:R19Beta','Settling beta trajectory is invalid.');
audit=struct('identityMaxAbsError',identityError,'reshapeMaxAbsError',reshapeError, ...
    'idealSumMaxAbsError',sumError,'scalarOutputColumns',meta.digitizedOutputColumns, ...
    'idealBetaMean',bmeta.betaMean,'damagedBetaMean',dm.betaMean, ...
    'damagedFastLag1',dm.fastLag1,'allPassed',true);
fprintf('Phase-3 R19 validation PASSED: identity=%g, sum=%g, beta lag1=%.6f.\n', ...
    identityError,sumError,dm.fastLag1);
end

function m=model_template(iso,rise,fast,tc)
m=struct('isolationDb',iso,'settlingRiseNs',rise,'rawSampleRateHz',122.88e6, ...
    'settlingFastJitterStdFraction',fast,'settlingFastJitterCorrelationSec',tc);
end
