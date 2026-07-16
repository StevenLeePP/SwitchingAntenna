function report=type1_run_paper_e2_fas_diversity()
%TYPE1_RUN_PAPER_E2_FAS_DIVERSITY Single-user FAS selection-diversity study.
%   A geometry-derived J0 correlation matrix drives one nested 16-port
%   Rayleigh realization.  Each M-port receiver selects the strongest one
%   of the first M ports; it never coherently combines ports.
profile=lower(string(getenv('TYPE1_E2_PROFILE')));if strlength(profile)==0,profile="paper";end
if profile=="paper",nRealizations=1e5;elseif profile=="smoke",nRealizations=5e3;else
    error('type1:E2Profile','TYPE1_E2_PROFILE must be paper or smoke.');end
Mvalues=[1 4 8 12 16];spacingLambda=[.125 .25 .5];snrDb=-10:1:20;
outageThresholdLinear=1;targetOutage=.1;seed=20262301;
preRegistration=struct('reviewTarget',"Paper E2 single-user FAS diversity", ...
    'profile',profile,'nRealizations',nRealizations,'seed',seed, ...
    'mValues',Mvalues,'spacingLambda',spacingLambda,'snrDb',snrDb, ...
    'channel',"unit-power Rayleigh with R(i,j)=J0(2*pi*distance/lambda)", ...
    'selection',"strongest single port; no coherent combining", ...
    'targetOutage',targetOutage,'outageThresholdLinear',outageThresholdLinear, ...
    'controls',"same Gaussian draws and nested port prefixes for every M");
stream=RandStream('mt19937ar','Seed',seed);
base=(randn(stream,max(Mvalues),nRealizations)+1j*randn(stream,max(Mvalues),nRealizations))/sqrt(2);
selectedPower=nan(numel(spacingLambda),numel(Mvalues),nRealizations,'single');
outage=nan(numel(spacingLambda),numel(Mvalues),numel(snrDb));
requiredSnrDb=nan(numel(spacingLambda),numel(Mvalues));medianSelectedPowerDb=requiredSnrDb;
minimumEigenvalue=nan(size(spacingLambda));correlationTrace=minimumEigenvalue;
for d=1:numel(spacingLambda)
    position=(0:max(Mvalues)-1)'*spacingLambda(d);distance=abs(position-position');
    R=besselj(0,2*pi*distance);R=(R+R')/2;R(1:size(R,1)+1:end)=1;
    [V,D]=eig(R,'vector');minimumEigenvalue(d)=min(real(D));
    tolerance=1e-11*max(1,max(abs(D)));assert(minimumEigenvalue(d)>=-tolerance, ...
        'type1:E2CorrelationPSD','J0 correlation matrix is not positive semidefinite.');
    L=V*diag(sqrt(max(real(D),0)));h=L*base;correlationTrace(d)=trace(R);
    for m=1:numel(Mvalues)
        power=max(abs(h(1:Mvalues(m),:)).^2,[],1);
        selectedPower(d,m,:)=single(power);
        for s=1:numel(snrDb)
            outage(d,m,s)=mean(10^(snrDb(s)/10)*power<outageThresholdLinear);
        end
        q=quantile(power,targetOutage);
        requiredSnrDb(d,m)=10*log10(outageThresholdLinear/q);
        medianSelectedPowerDb(d,m)=10*log10(median(power));
    end
end
snrGainDb=requiredSnrDb(:,1)-requiredSnrDb;
analyticM1=1-exp(-outageThresholdLinear./10.^(snrDb/10));
analyticError=max(abs(squeeze(outage(:,1,:))-analyticM1),[],2);
nestedOutagePassed=all(diff(outage,1,2)<=1e-12,'all');
validation=struct('m1MaximumAbsoluteOutageError',analyticError, ...
    'nestedOutageNonIncreasing',nestedOutagePassed, ...
    'correlationTrace',correlationTrace,'minimumCorrelationEigenvalue',minimumEigenvalue, ...
    'sameDrawsAcrossM',true,'allPassed',nestedOutagePassed&&all(analyticError<.025));
assert(validation.allPassed,'type1:E2Validation','E2 algebra/statistical validation failed.');
root=string(getenv('TYPE1_PAPER_OUTPUT_ROOT'));if strlength(root)==0,root=fullfile(tempdir,'type1_paper');end
if ~isfolder(root),mkdir(root);end
out=fullfile(root,['type1_paper_e2_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(out);
report=struct('preRegistration',preRegistration,'validation',validation, ...
    'outageProbability',outage,'requiredSnrDbAtTargetOutage',requiredSnrDb, ...
    'snrGainDbAtTargetOutage',snrGainDb,'medianSelectedPowerDb',medianSelectedPowerDb, ...
    'selectedPower',selectedPower,'summary',struct( ...
    'maximumSnrGainDb',max(snrGainDb,[],2),'m16SnrGainDb',snrGainDb(:,end), ...
    'boundary',"single-user flat Rayleigh/J0 selection diversity; not multiuser beamforming"), ...
    'outputDirectory',out,'createdAt',datetime('now'),'matlabVersion',version);
save(fullfile(out,'paper_e2_fas_diversity.mat'),'report','-v7.3');
plot_result(report,fullfile(out,'paper_e2_fas_diversity.png'));
fprintf('E2 %s: M16 SNR gain at Pout=%.2f is [%s] dB for d/lambda=[%s].\n', ...
    profile,targetOutage,num2str(snrGainDb(:,end).','%.3f '),num2str(spacingLambda,'%.3g '));
fprintf('Paper E2 audit saved: %s\n',out);
end

function plot_result(report,file)
p=report.preRegistration;figure('Visible','off','Position',[100 100 1250 480]);
subplot(1,2,1);hold on;
styles={'-','--',':'};
for d=1:numel(p.spacingLambda)
    semilogy(p.snrDb,squeeze(report.outageProbability(d,end,:)),styles{d},'LineWidth',1.7);
end
semilogy(p.snrDb,squeeze(report.outageProbability(1,1,:)),'k-.','LineWidth',1.4);
grid on;ylim([1e-4 1]);xlabel('average SNR (dB)');ylabel('outage probability');
legend(["M=16, d="+string(p.spacingLambda)+" lambda" "M=1 Monte Carlo control"],'Location','southwest');
title('strongest-port FAS outage');
subplot(1,2,2);plot(p.mValues,report.snrGainDbAtTargetOutage,'o-','LineWidth',1.6);
grid on;xlabel('candidate ports M');ylabel('SNR gain at 10% outage (dB)');
legend("d="+string(p.spacingLambda)+" lambda",'Location','southeast');title('selection-diversity gain');
exportgraphics(gcf,file,'Resolution',180);close(gcf);
end
