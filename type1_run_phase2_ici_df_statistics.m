function report = type1_run_phase2_ici_df_statistics()
%TYPE1_RUN_PHASE2_ICI_DF_STATISTICS R4 paired Q/iteration/SNR DF experiment.
%   Each point uses identical seeded links for standard RZF and ICI-DF.  A
%   point stops only after BOTH receivers accumulate targetErrors aggregate
%   raw errors, or after maxBits aggregate bits.  This avoids claiming a
%   low BER from a one-frame zero-error observation.  The receiver remains
%   an offline research model; no SDR hardware is opened.

profile=lower(string(getenv('TYPE1_PHASE2_DF_PROFILE')));
if strlength(profile)==0, profile="pilot"; end
[targetErrors,maxBits]=profile_limits(profile);
p=type1_load_package(); base=type1_offline_sim_config();
base.frames=1; base.assertIdealBaseline=false; base.snrDb=20;
base.switch.settlingRiseNs=20;
base.switch.settlingFastJitterStdFraction=.6;
base.switch.settlingFastJitterCorrelationSec=1e-6;
base.switch.recordTimeSeries=false;
baseSeed=20260816; feedbackMode="soft";

qSpec=make_spec('Q', [0 6 12 24], ones(1,4), 20);
iterationSpec=make_spec('iterations', 12*ones(1,3), [1 2 3], 20);
snrSpec=make_spec('SNR', 12*ones(1,11), 2*ones(1,11), [-12 -10 -8 -4 0 4 8 12 16 20 24]);
report=struct('profile',profile,'targetErrors',targetErrors,'maxBits',maxBits, ...
    'baseSeed',baseSeed,'feedbackMode',feedbackMode,'config',base,'qSweep',[], 'iterationSweep',[], 'snrSweep',[]);
report.qSweep=run_sweep(p,base,qSpec,targetErrors,maxBits,baseSeed,feedbackMode);
report.iterationSweep=run_sweep(p,base,iterationSpec,targetErrors,maxBits,baseSeed,feedbackMode);
report.snrSweep=run_sweep(p,base,snrSpec,targetErrors,maxBits,baseSeed,feedbackMode);

root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_ici_df_statistics_' ...
    char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out;
write_figures(report,out);
save(fullfile(out,'phase2_ici_df_statistics.mat'),'report','-v7.3');
print_summary(report);
fprintf('ICI-DF statistics saved: %s\n',out);
end

function [targetErrors,maxBits]=profile_limits(profile)
switch profile
    case "smoke"
        targetErrors=1; maxBits=6.042e5;
    case "pilot"
        targetErrors=100; maxBits=1e7;
    case "paper"
        % Stricter than the Phase-2 minimum (100 errors): this forces
        % multiple independently seeded 10-ms windows for the high-SNR DF
        % points while retaining the predeclared 1e7-bit upper limit.
        targetErrors=10000; maxBits=1e7;
    otherwise
        error('type1:ICIDFProfile','TYPE1_PHASE2_DF_PROFILE must be smoke, pilot, or paper.');
end
end

function spec=make_spec(name,q,iterations,snrDb)
spec=struct('name',name,'q',num2cell(q),'iterations',num2cell(iterations), ...
    'snrDb',num2cell(snrDb));
end

function points=run_sweep(package,base,spec,targetErrors,maxBits,baseSeed,feedbackMode)
points=repmat(empty_point(),1,numel(spec));
for point=1:numel(spec)
    sim=base; sim.snrDb=spec(point).snrDb;
    points(point)=run_point(package,sim,spec(point),targetErrors,maxBits,baseSeed,feedbackMode);
end
end

function point=run_point(package,sim,spec,targetErrors,maxBits,baseSeed,feedbackMode)
cfg=package.cfg; bitsPerLayerFrame=numel(cfg.dataSlots)*package.nInfoBitsPerSlotLayer;
bitsPerFrame=bitsPerLayerFrame*cfg.nLayers;
maxFrames=ceil(maxBits/bitsPerFrame);
standardErrors=zeros(1,cfg.nLayers); dfErrors=zeros(1,cfg.nLayers);
standardEvm=0; dfEvm=0; seeds=zeros(1,maxFrames); frame=0;
while frame<maxFrames
    frame=frame+1; seed=baseSeed+frame-1; seeds(frame)=seed;
    link=type1_offline_link(package,sim,RandStream('mt19937ar','Seed',seed));
    try
        standard=type1_analyze(link.virtualRx30,package);
    df=type1_analyze_ici_decision_feedback(link.virtualRx30,package,spec.q,spec.iterations,feedbackMode);
    catch err
        point=empty_point(); point.name=spec.name; point.q=spec.q;
        point.iterations=spec.iterations; point.snrDb=spec.snrDb;
        point.frames=frame; point.totalBits=(frame-1)*bitsPerFrame;
        point.stopReason='receiverFailure'; point.status='acquisitionFailure';
        point.failureIdentifier=err.identifier; point.failureMessage=err.message;
        point.seeds=seeds(1:frame);
        return;
    end
    standardErrors=standardErrors+sum(standard.infoBitErrors,1);
    dfErrors=dfErrors+sum(df.infoBitErrors,1);
    standardEvm=standardEvm+mean(standard.evmRMSPercent,'all');
    dfEvm=dfEvm+mean(df.evmRMSPercent,'all');
    if sum(standardErrors)>=targetErrors && sum(dfErrors)>=targetErrors
        break;
    end
end
bitsPerLayer=frame*bitsPerLayerFrame; totalBits=frame*bitsPerFrame;
standardBer=sum(standardErrors)/totalBits; dfBer=sum(dfErrors)/totalBits;
capture=ici_capture_fraction(spec.q,sim.switch.settlingFastJitterCorrelationSec,cfg);
reduction=(standardBer-dfBer)/max(standardBer,eps);
point=empty_point(); point.name=spec.name; point.q=spec.q; point.iterations=spec.iterations;
point.snrDb=spec.snrDb; point.frames=frame; point.totalBits=totalBits;
point.stopReason=ternary(totalBits>=maxBits,'maxBits','targetErrors'); point.status='ok';
point.seeds=seeds(1:frame); point.standardErrors=standardErrors; point.dfErrors=dfErrors;
point.standardBER=standardBer; point.dfBER=dfBer;
point.standardBERByLayer=standardErrors/bitsPerLayer;
point.dfBERByLayer=dfErrors/bitsPerLayer;
point.standardEVMPercent=standardEvm/frame; point.dfEVMPercent=dfEvm/frame;
point.captureFraction=capture; point.relativeReduction=reduction;
point.eta=reduction/max(capture,eps);
end

function c=ici_capture_fraction(q,tauC,cfg)
if tauC<=0, c=0; return; end
symbolDuration=cfg.frameDurationSec/cfg.symbolsPerFrame;
fc=1/(2*pi*tauC);
c=(2/pi)*atan((q+0.5)/(symbolDuration*fc));
end

function point=empty_point()
point=struct('name','', 'q',NaN, 'iterations',NaN, 'snrDb',NaN, ...
    'frames',0,'totalBits',0,'stopReason','', 'seeds',[], ...
    'status','notRun','failureIdentifier','','failureMessage','', ...
    'standardErrors',[],'dfErrors',[],'standardBER',NaN,'dfBER',NaN, ...
    'standardBERByLayer',[],'dfBERByLayer',[], ...
    'standardEVMPercent',NaN,'dfEVMPercent',NaN, ...
    'captureFraction',NaN,'relativeReduction',NaN,'eta',NaN);
end

function value=ternary(test,yes,no)
if test, value=yes; else, value=no; end
end

function write_figures(report,out)
q=report.qSweep; it=report.iterationSweep; snr=report.snrSweep;
f=figure('Visible','off','Color','w','Position',[100 100 1300 360]);
tiledlayout(1,3,'Padding','compact','TileSpacing','compact');
nexttile;
plot([q.q],100*[q.relativeReduction],'o-','LineWidth',1.5); hold on;
plot([q.q],100*[q.captureFraction]*mean([q.eta],'omitnan'),'--','LineWidth',1.5);
xlabel('ICI kernel half-width Q'); ylabel('BER reduction (%)'); grid on;
legend('measured','C(Q) scaled by mean \eta','Location','southeast'); title('Q capture law');
nexttile;
plot([it.iterations],[it.eta],'o-','LineWidth',1.5); xlabel('DF iterations');
ylabel('\eta = reduction / C(Q)'); grid on; title('Iteration estimate quality');
nexttile;
semilogy([snr.snrDb],[snr.standardBER],'o-','LineWidth',1.5); hold on;
semilogy([snr.snrDb],[snr.dfBER],'s-','LineWidth',1.5); grid on;
xlabel('SNR (dB)'); ylabel('aggregate BER'); legend('standard RZF','ICI-DF','Location','southwest');
title('SNR failure-gate scan');
exportgraphics(f,fullfile(out,'phase2_ici_df_statistics.png'),'Resolution',180);
close(f);
end

function print_summary(report)
fprintf('R4 Q sweep (Q, stdBER, dfBER, C, eta):\n');
for p=report.qSweep
    fprintf('  %2d %.4g %.4g C=%.3f eta=%.3f (%s/%s, %.3g bits)\n', ...
        p.q,p.standardBER,p.dfBER,p.captureFraction,p.eta,p.status,p.stopReason,p.totalBits);
end
fprintf('R4 iteration sweep (iter, stdBER, dfBER, eta):\n');
for p=report.iterationSweep
    fprintf('  %d %.4g %.4g eta=%.3f (%s/%s, %.3g bits)\n', ...
        p.iterations,p.standardBER,p.dfBER,p.eta,p.status,p.stopReason,p.totalBits);
end
fprintf('R4 SNR sweep (dB, stdBER, dfBER, eta):\n');
for p=report.snrSweep
    fprintf('  %2g %.4g %.4g eta=%.3f (%s/%s, %.3g bits)\n', ...
        p.snrDb,p.standardBER,p.dfBER,p.eta,p.status,p.stopReason,p.totalBits);
end
end
