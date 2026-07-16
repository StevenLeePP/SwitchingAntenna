function report=type1_run_phase3_r22_energy()
%TYPE1_RUN_PHASE3_R22_ENERGY GreenMO-anchored power/energy comparison.
validation=type1_validate_phase3_energy();profile=lower(string(getenv('TYPE1_R22_PROFILE')));
if strlength(profile)==0,profile="paper";end
if profile=="paper",nSeeds=50;elseif profile=="smoke",nSeeds=3;else
    error('type1:R22Profile','TYPE1_R22_PROFILE must be paper or smoke.');end
r20Path=string(getenv('TYPE1_R22_R20_MAT'));if strlength(r20Path)==0
    r20Path="/home/bupt/type1_offline_captures/type1_phase3_r20_paper_20260716_012732/phase3_r20.mat";end
r21Path=string(getenv('TYPE1_R22_R21_MAT'));if strlength(r21Path)==0
    r21Path="/home/bupt/type1_offline_captures/type1_phase3_r21_paper_20260716_090554/phase3_r21_theory.mat";end
x=load(r20Path,'report');r20=x.report;y=load(r21Path,'report');r21=y.report;
assert(numel(r20.selection)>=nSeeds&&size(r21.sumMmseRate,1)>=nSeeds, ...
    'type1:R22InputSeeds','R20/R21 inputs have too few seeds.');
p=type1_load_package();cfg=p.cfg;N=4;Mvalues=[4 8 12 16];
armFields=["M4" "M8Aware" "M12Aware" "M16Aware"];
architectures=["ProposedD1" "GreenMOLike" "DBF" "PCHBF" "FCHBF"];
updateSec=[.05 .1 .2 .5 1 2 5 10];sampleRateMsps=cfg.txSampleRate/1e6;
occupiedBandwidthHz=cfg.nRB*12*cfg.scsKHz*1e3;frequency=(-306:305)*cfg.scsKHz*1e3;
searchIndex=6:12:606;params=type1_phase3_power_parameters();
preRegistration=struct('reviewTarget',"R22 Part-C energy",'profile',profile, ...
    'r20Mat',r20Path,'r21Mat',r21Path,'nSeeds',nSeeds,'mValues',Mvalues, ...
    'architectures',architectures,'nStreams',N,'occupiedBandwidthHz',occupiedBandwidthHz, ...
    'sampleRateMspsPerStream',sampleRateMsps,'updateSec',updateSec, ...
    'primaryUpdateSec',1,'powerParameters',params, ...
    'rateRule',"same-channel ideal LMMSE sum-rate for cross-architecture ranking", ...
    'measuredAnchorRule',"R20 AMC/power reported only for ProposedD1", ...
    'scanRule',"scanFrames=ceil(M/N)-1 for reduced-chain front ends; DBF=0", ...
    'primaryGate',"power anchors exact and ProposedD1 rate reproduces R21 within 1e-9");

rate=zeros(nSeeds,4,5);greenAdded=zeros(nSeeds,4);
for k=1:nSeeds
    seed=r20.selection(k).seed;model16=type1_phase3_config(16,N);
    [~,channel]=type1_phase3_make_tdl_a_channel(zeros(2,N),cfg,model16, ...
        RandStream('mt19937ar','Seed',seed));
    Hfull=type1_phase3_tdl_frequency_response(channel,frequency);nv=r20.selection(k).noiseVarianceMetric;
    A=r20.selection(k).arms;
    for a=1:4
        M=Mvalues(a);H=Hfull(1:M,:,:);Hsearch=H(:,:,searchIndex);S=double(A.(armFields(a)).S);
        proposed=type1_phase3_frontend_metrics(H,S,nv);rate(k,a,1)=proposed.sumMmseRate;
        green=type1_phase3_greenmo_like_schedule(Hsearch,nv,S);
        greenRate=type1_phase3_frontend_metrics(H,double(green.S),nv);
        rate(k,a,2)=greenRate.sumMmseRate;greenAdded(k,a)=size(green.addedEdges,1);
        dbf=type1_phase3_frontend_metrics(H,eye(M),nv);rate(k,a,3)=dbf.sumMmseRate;
        pc=type1_phase3_hbf_combiner(Hsearch,N,"partial");
        fc=type1_phase3_hbf_combiner(Hsearch,N,"full");
        rate(k,a,4)=type1_phase3_frontend_metrics(H,pc,nv).sumMmseRate;
        rate(k,a,5)=type1_phase3_frontend_metrics(H,fc,nv).sumMmseRate;
    end
    fprintf('R22 %2d/%d seed=%d M16 rate=[%s], GreenMO additions=%d.\n', ...
        k,nSeeds,seed,num2str(squeeze(rate(k,4,:)).','%.2f '),greenAdded(k,4));
end
reproductionError=max(abs(rate(:,:,1)-r21.sumMmseRate(1:nSeeds,:)),[],'all');
assert(reproductionError<1e-9,'type1:R22R21Reproduction','Proposed rate differs from R21.');
medianRate=squeeze(median(rate,1));nScenario=numel(params.scenarioNames);
ee=zeros(4,5,numel(updateSec),nScenario);power=zeros(4,5,numel(updateSec),nScenario);
scanEnergy=power;payload=power;breakdown=cell(4,5,numel(updateSec),nScenario);
for a=1:4
    M=Mvalues(a);frames=M/N-1;
    for q=1:5
        arch=architectures(q);if arch=="DBF",archFrames=0;else,archFrames=frames;end
        for t=1:numel(updateSec)
            for z=1:nScenario
                b=type1_phase3_power_breakdown(params,arch,M,N,sampleRateMsps,archFrames,updateSec(t),z);
                breakdown{a,q,t,z}=b;power(a,q,t,z)=b.averagePowerW;
                scanEnergy(a,q,t,z)=b.scanEnergyPerUpdateJ;payload(a,q,t,z)=b.payloadFraction;
                ee(a,q,t,z)=occupiedBandwidthHz*medianRate(a,q)*b.payloadFraction/b.averagePowerW;
            end
        end
    end
end
[~,primary]=min(abs(updateSec-1));nominal=2;
r20Columns=[1 3 4 5];[~,r20Nominal]=min(abs(r20.summary.thresholdShiftDb));
r20AmcPerStream=squeeze(r20.summary.amcThroughput(r20Columns,:,r20Nominal));
measuredAnchorEePerStream=zeros(4,numel(updateSec));
measuredAnchorEeAggregate=zeros(4,numel(updateSec));
for a=1:4
    for t=1:numel(updateSec)
        measuredAnchorEePerStream(a,t)=occupiedBandwidthHz*r20AmcPerStream(a,t)/power(a,1,t,nominal);
        measuredAnchorEeAggregate(a,t)=N*measuredAnchorEePerStream(a,t);
    end
end
loadCurve=load_power_curve(params,architectures,Mvalues(end),sampleRateMsps);
summary=struct('architectures',architectures,'mValues',Mvalues, ...
    'medianIdealSumRate',medianRate,'r21ReproductionMaxAbsError',reproductionError, ...
    'greenmoAddedEdgesMedian',median(greenAdded,1),'scenarioNames',params.scenarioNames, ...
    'updateSec',updateSec,'primaryUpdateSec',1, ...
    'primaryPowerW',squeeze(power(:,:,primary,:)), ...
    'primaryEnergyEfficiencyBitsPerJ',squeeze(ee(:,:,primary,:)), ...
    'primaryEnergyEfficiencyMbitPerJ',squeeze(ee(:,:,primary,:))/1e6, ...
    'primaryScanEnergyJ',squeeze(scanEnergy(:,:,primary,:)), ...
    'r20AmcPerStreamBitPerSecPerHz',r20AmcPerStream, ...
    'measuredAnchorEePerStreamBitsPerJ',measuredAnchorEePerStream, ...
    'measuredAnchorEeAggregateBitsPerJ',measuredAnchorEeAggregate, ...
    'energyEfficiencyBitsPerJ',ee,'powerW',power,'payloadFraction',payload, ...
    'loadCurve',loadCurve,'gatePassed',reproductionError<1e-9&&validation.allPassed, ...
    'comparisonBoundary',"ideal cross-architecture rate; only ProposedD1 has R20 AMC anchor");
root=string(getenv('TYPE1_PHASE3_OUTPUT_ROOT'));if strlength(root)==0,root=fullfile(tempdir,'type1_phase3');end
if ~isfolder(root),mkdir(root);end
out=fullfile(root,['type1_phase3_r22_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(out);
report=struct('preRegistration',preRegistration,'validation',validation,'rate',rate, ...
    'greenAddedEdges',greenAdded,'breakdown',{breakdown},'summary',summary, ...
    'outputDirectory',out,'createdAt',datetime('now'),'matlabVersion',version);
save(fullfile(out,'phase3_r22_energy.mat'),'report','-v7.3');
plot_efficiency(report,fullfile(out,'phase3_r22_energy_efficiency.png'));
plot_load(report,fullfile(out,'phase3_r22_energy_proportionality.png'));
fprintf(['R22 %s: R21 rate error=%.3g, M16 nominal power=[%s] W, ' ...
    'EE=[%s] Mbit/J, gate=%d.\n'],profile,reproductionError, ...
    num2str(squeeze(summary.primaryPowerW(4,:,2)),'%.2f '), ...
    num2str(squeeze(summary.primaryEnergyEfficiencyMbitPerJ(4,:,2)),'%.1f '),summary.gatePassed);
fprintf('Phase-3 R22 energy audit saved: %s\n',out);
end

function curve=load_power_curve(p,architectures,M,sampleRateMsps)
Nvalues=1:4;power=zeros(numel(Nvalues),numel(architectures));scan=zeros(size(power));
for i=1:numel(Nvalues)
    N=Nvalues(i);frames=max(ceil(M/N)-1,0);
    for q=1:numel(architectures)
        arch=architectures(q);if arch=="DBF",f=0;else,f=frames;end
        b=type1_phase3_power_breakdown(p,arch,M,N,sampleRateMsps,f,1,2);
        power(i,q)=b.averagePowerW;scan(i,q)=b.scanEnergyPerUpdateJ;
    end
end
curve=struct('nStreams',Nvalues,'mPhysical',M,'powerW',power, ...
    'scanEnergyPerUpdateJ',scan,'updateSec',1);
end

function plot_efficiency(report,file)
s=report.summary;nominal=2;[~,primary]=min(abs(s.updateSec-1));
figure('Visible','off','Position',[100 100 1650 480]);
subplot(1,3,1);plot(s.mValues,squeeze(s.powerW(:,:,primary,nominal)),'o-','LineWidth',1.2);grid on;
xlabel('physical ports M');ylabel('average RX power (W)');legend(s.architectures,'Location','best');title('common component table');
subplot(1,3,2);plot(s.mValues,squeeze(s.energyEfficiencyBitsPerJ(:,:,primary,nominal))/1e6,'o-','LineWidth',1.2);grid on;
xlabel('physical ports M');ylabel('ideal-reference EE (Mbit/J)');legend(s.architectures,'Location','best');title('1 s update / 4 streams');
subplot(1,3,3);hold on;
for a=1:4
    semilogx(s.updateSec,squeeze(s.energyEfficiencyBitsPerJ(a,1,:,nominal))/1e6,'o-','LineWidth',1.2);
end
grid on;xlabel('selection update period (s)');ylabel('ProposedD1 EE (Mbit/J)');
legend(compose('M=%d',s.mValues),'Location','best');title('scan energy + payload loss included');
exportgraphics(gcf,file,'Resolution',180);close(gcf);
end

function plot_load(report,file)
s=report.summary;c=s.loadCurve;figure('Visible','off','Position',[100 100 1100 460]);
subplot(1,2,1);plot(c.nStreams,c.powerW,'o-','LineWidth',1.3);grid on;
xlabel('active streams N');ylabel('average RX power (W)');legend(s.architectures,'Location','best');
title(sprintf('energy proportionality, M=%d',c.mPhysical));
subplot(1,2,2);plot(c.nStreams,c.scanEnergyPerUpdateJ,'o-','LineWidth',1.3);grid on;
xlabel('active streams N');ylabel('scan energy per 1 s update (J)');legend(s.architectures,'Location','best');
title('scan is not free');exportgraphics(gcf,file,'Resolution',180);close(gcf);
end
