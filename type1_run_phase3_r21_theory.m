function report=type1_run_phase3_r21_theory()
%TYPE1_RUN_PHASE3_R21_THEORY Close R20 numerical results with SINR/rate theory.
validation=type1_validate_phase3_theory();profile=lower(string(getenv('TYPE1_R21_PROFILE')));
if strlength(profile)==0,profile="paper";end
if profile=="paper",nSeeds=50;elseif profile=="smoke",nSeeds=3;else
    error('type1:R21Profile','TYPE1_R21_PROFILE must be paper or smoke.');end
r20Path=string(getenv('TYPE1_R21_R20_MAT'));
if strlength(r20Path)==0
    r20Path="/home/bupt/type1_offline_captures/type1_phase3_r20_paper_20260716_012732/phase3_r20.mat";
end
loaded=load(r20Path,'report');r20=loaded.report;
assert(numel(r20.selection)>=nSeeds,'type1:R21R20Seeds','R20 MAT has too few seeds.');
p=type1_load_package();cfg=p.cfg;N=4;Mvalues=[4 8 12 16];
armFields=["M4" "M8Aware" "M12Aware" "M16Aware"];
storedColumns=[1 3 4 5];frequency=(-306:305)*cfg.scsKHz*1e3;
searchIndex=6:12:606;epsilon=[0 .1 .2 .5 1 2];targetDb=[0 5 10];
preRegistration=struct('reviewTarget',"R21 Part-D theory",'profile',profile, ...
    'r20Mat',r20Path,'nSeeds',nSeeds,'seedValues',r20.preRegistration.seedValues(1:nSeeds), ...
    'mValues',Mvalues,'epsilonWhitened',epsilon,'targetSinrDb',targetDb, ...
    'residualModel',"Rz=Rn+E*E^H; E*x treated as Gaussian self-interference", ...
    'primaryGate',"closed-form reproduces frozen R20 objective within 1e-9 dB", ...
    'correlationModel',"J0(2*pi*distance/lambda), no free rho tuning");

objective=zeros(nSeeds,4);minRate=objective;sumRate=objective;capacity=objective;
arrayMean=objective;arrayMin=objective;lowerRate=zeros(nSeeds,4,numel(epsilon));
epsilonBudget=zeros(nSeeds,4,numel(targetDb));
for k=1:nSeeds
    seed=r20.selection(k).seed;model16=type1_phase3_config(16,N);
    [~,channel]=type1_phase3_make_tdl_a_channel(zeros(2,N),cfg,model16, ...
        RandStream('mt19937ar','Seed',seed));
    Hfull=type1_phase3_tdl_frequency_response(channel,frequency);
    nv=r20.selection(k).noiseVarianceMetric;A=r20.selection(k).arms;
    for a=1:4
        M=Mvalues(a);S=A.(armFields(a)).S;H=Hfull(1:M,:,:);
        search=type1_phase3_theory_metrics(H(:,:,searchIndex),S,nv);
        full=type1_phase3_theory_metrics(H,S,nv);
        objective(k,a)=search.objectiveDb;minRate(k,a)=full.minUserRate;
        sumRate(k,a)=full.sumMmseRate;capacity(k,a)=full.capacityLogDet;
        correlation=type1_phase3_correlation_gain(model16.rxCorrelation(1:M,1:M),S);
        arrayMean(k,a)=correlation.meanGainLinear;arrayMin(k,a)=correlation.minGainLinear;
        base=full.robustSinrLower;
        for j=1:numel(epsilon)
            lowerRate(k,a,j)=mean(log2(1+base/(1+epsilon(j)^2)));
        end
        for j=1:numel(targetDb)
            tolerance=sqrt(max(base/10^(targetDb(j)/10)-1,0));
            epsilonBudget(k,a,j)=median(tolerance);
        end
    end
    fprintf('R21 %2d/%d seed=%d minRate=[%s] bit/s/Hz.\n',k,nSeeds,seed, ...
        num2str(minRate(k,:),'%.3f '));
end
stored=r20.summary.selectionObjectiveDb(1:nSeeds,storedColumns);
reproductionError=max(abs(objective-stored),[],'all');
assert(reproductionError<1e-9,'type1:R21R20Reproduction', ...
    'Closed-form objective does not reproduce frozen R20.');
geometry=geometry_sweep(N);
summary=struct('armNames',armFields,'mValues',Mvalues, ...
    'r20ObjectiveMaxAbsErrorDb',reproductionError, ...
    'medianMinUserRate',median(minRate,1),'medianSumMmseRate',median(sumRate,1), ...
    'medianCapacityLogDet',median(capacity,1), ...
    'medianCapacityGap',median(capacity-sumRate,1), ...
    'medianArrayGainDb',10*log10(median(arrayMean,1)), ...
    'medianMinChainArrayGainDb',10*log10(median(arrayMin,1)), ...
    'epsilonWhitened',epsilon,'medianRobustMinRate',squeeze(median(lowerRate,1)), ...
    'targetSinrDb',targetDb,'medianEpsilonBudget',squeeze(median(epsilonBudget,1)), ...
    'geometry',geometry,'gatePassed',reproductionError<1e-9);
root=string(getenv('TYPE1_PHASE3_OUTPUT_ROOT'));if strlength(root)==0,root=fullfile(tempdir,'type1_phase3');end
if ~isfolder(root),mkdir(root);end
out=fullfile(root,['type1_phase3_r21_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(out);
report=struct('preRegistration',preRegistration,'validation',validation, ...
    'objectiveDb',objective,'minUserRate',minRate,'sumMmseRate',sumRate, ...
    'capacityLogDet',capacity,'arrayMeanLinear',arrayMean,'arrayMinLinear',arrayMin, ...
    'lowerRate',lowerRate,'epsilonBudget',epsilonBudget,'summary',summary, ...
    'outputDirectory',out,'createdAt',datetime('now'),'matlabVersion',version);
save(fullfile(out,'phase3_r21_theory.mat'),'report','-v7.3');
plot_result(report,fullfile(out,'phase3_r21_theory.png'));
fprintf(['R21 %s: R20 objective error=%.3g dB, median min-rate=[%s], ' ...
    'capacity gap=[%s], gate=%d.\n'],profile,reproductionError, ...
    num2str(summary.medianMinUserRate,'%.3f '), ...
    num2str(summary.medianCapacityGap,'%.3f '),summary.gatePassed);
fprintf('Phase-3 R21 theory audit saved: %s\n',out);
end

function geometry=geometry_sweep(N)
Mvalues=[4 8 12 16 20 24];spacing=[.125 .25 .5 1];gain=zeros(numel(Mvalues),numel(spacing));
for i=1:numel(Mvalues)
    M=Mvalues(i);S=false(M,N);for m=1:M,S(m,mod(m-1,N)+1)=true;end
    for j=1:numel(spacing)
        p=(0:M-1).'*spacing(j);R=besselj(0,2*pi*abs(p-p.'));
        x=type1_phase3_correlation_gain(R,S);gain(i,j)=x.meanGainLinear;
    end
end
geometry=struct('mValues',Mvalues,'spacingLambda',spacing, ...
    'apertureLambda',(Mvalues(:)-1).*spacing,'meanGainLinear',gain, ...
    'schedule',"round-robin Dmax=1 partition");
end

function plot_result(report,file)
s=report.summary;figure('Visible','off','Position',[100 100 1600 480]);
subplot(1,3,1);plot(s.mValues,s.medianMinUserRate,'o-','LineWidth',1.4);hold on;
plot(s.mValues,s.medianCapacityLogDet/4,'s--','LineWidth',1.4);grid on;
xlabel('physical ports M');ylabel('bit/s/Hz/user');legend('min-user LMMSE rate','log-det / 4','Location','best');
title('R20 schedules: exact theory');
subplot(1,3,2);hold on;for a=1:4,plot(s.epsilonWhitened,s.medianRobustMinRate(a,:),'o-','LineWidth',1.2);end
grid on;xlabel('whitened residual norm epsilon');ylabel('conservative min-user rate');legend(s.armNames,'Location','best');
title('R_z=R_n+EE^H lower bound');
subplot(1,3,3);hold on;g=s.geometry;
for j=1:numel(g.spacingLambda),plot(g.apertureLambda(:,j),10*log10(g.meanGainLinear(:,j)),'o-','LineWidth',1.2);end
grid on;xlabel('array aperture (lambda)');ylabel('expected noise-normalized gain (dB)');
legend(compose('spacing %.3g lambda',g.spacingLambda),'Location','best');title('J0 geometry / round-robin partition');
exportgraphics(gcf,file,'Resolution',180);close(gcf);
end
