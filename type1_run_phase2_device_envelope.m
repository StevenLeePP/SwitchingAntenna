function report = type1_run_phase2_device_envelope()
%TYPE1_RUN_PHASE2_DEVICE_ENVELOPE R5 20-dB fast-jitter specification sweep.
%   Paired standard RZF, 3-pass soft ICI-DF, and known-beta genie are run on
%   the same link.  Stopping is governed by standard/DF errors only: genie
%   can legitimately remain zero-error and is reported as an upper bound.

profile=lower(string(getenv('TYPE1_PHASE2_ENVELOPE_PROFILE')));
if strlength(profile)==0, profile="pilot"; end
[fastGrid,tauGrid,targetErrors,maxBits]=profile_grid(profile);
p=type1_load_package(); base=type1_offline_sim_config();
base.frames=1; base.assertIdealBaseline=false; base.snrDb=20;
base.switch.settlingRiseNs=20; base.switch.recordTimeSeries=true;
baseSeed=20260901; q=12; iterations=3; feedbackMode="soft"; targetBer=1e-2;
spec=make_grid(fastGrid,tauGrid);
points=repmat(empty_point(),1,numel(spec));
for index=1:numel(spec)
    sim=base; sim.switch.settlingFastJitterStdFraction=spec(index).fastFraction;
    sim.switch.settlingFastJitterCorrelationSec=spec(index).tauC;
    points(index)=run_point(p,sim,spec(index),q,iterations,feedbackMode, ...
        targetErrors,maxBits,baseSeed);
end
report=struct('profile',profile,'config',base,'fastGrid',fastGrid,'tauGrid',tauGrid, ...
    'baseSeed',baseSeed,'q',q,'iterations',iterations,'feedbackMode',feedbackMode, ...
    'targetErrors',targetErrors,'maxBits',maxBits,'targetBer',targetBer, ...
    'points',points,'thresholdBrackets',threshold_brackets(points,tauGrid,targetBer));
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=tempdir; end
out=fullfile(root,['type1_phase2_device_envelope_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; write_figure(report,out);
save(fullfile(out,'phase2_device_envelope.mat'),'report','-v7.3');
print_summary(report); fprintf('Device-envelope result saved: %s\n',out);
end

function [fast,tau,target,maxBits]=profile_grid(profile)
switch profile
    case "smoke"
        fast=[.4 .6]; tau=[0 1e-6]; target=1; maxBits=6.4e5;
    case "pilot"
        fast=[0 .2 .4 .6 .8]; tau=[0 100e-9 1e-6]; target=100; maxBits=1e7;
    case "paper"
        fast=[0 .2 .4 .6 .8]; tau=[0 8e-9 100e-9 1e-6]; target=10000; maxBits=1e7;
    case "refined"
        % R6: resolve the tau_c=1 us BER=1e-2 crossings without spending
        % paper-grid time on unrelated tau_c values.
        fast=[.5 .7 .75]; tau=1e-6; target=10000; maxBits=1e7;
    otherwise
        error('type1:EnvelopeProfile','TYPE1_PHASE2_ENVELOPE_PROFILE must be smoke, pilot, paper, or refined.');
end
end

function spec=make_grid(fast,tau)
[f,t]=ndgrid(fast,tau); spec=struct('fastFraction',num2cell(f(:).'),'tauC',num2cell(t(:).'));
end

function point=run_point(package,sim,spec,q,iterations,feedbackMode,target,maxBits,baseSeed)
cfg=package.cfg; bitsFrame=numel(cfg.dataSlots)*package.nInfoBitsPerSlotLayer*cfg.nLayers;
maxFrames=ceil(maxBits/bitsFrame); errors=zeros(3,cfg.nLayers); evm=zeros(1,3);
floorHits=0; betaSamples=0; seeds=zeros(1,maxFrames); frame=0;
while frame<maxFrames
    frame=frame+1; seed=baseSeed+frame-1; seeds(frame)=seed;
    link=type1_offline_link(package,sim,RandStream('mt19937ar','Seed',seed));
    try
        standard=type1_analyze(link.virtualRx30,package);
        df=type1_analyze_ici_decision_feedback(link.virtualRx30,package,q,iterations,feedbackMode);
        genie=type1_analyze(type1_genie_inverse_settling(link.stitched122,link.switchMeta.settlingBeta),package);
    catch err
        point=empty_point(); point.fastFraction=spec.fastFraction; point.tauC=spec.tauC;
        point.status='receiverFailure'; point.failureIdentifier=err.identifier; point.failureMessage=err.message;
        point.frames=frame; point.seeds=seeds(1:frame); return;
    end
    each={standard df genie};
    for receiver=1:3
        errors(receiver,:)=errors(receiver,:)+sum(each{receiver}.infoBitErrors,1);
        evm(receiver)=evm(receiver)+mean(each{receiver}.evmRMSPercent,'all');
    end
    floorHits=floorHits+link.switchMeta.tauFloorHitCount;
    betaSamples=betaSamples+numel(link.switchMeta.settlingBeta);
    if all(sum(errors(1:2,:),2)>=target), break; end
end
bits=frame*bitsFrame; point=empty_point(); point.fastFraction=spec.fastFraction; point.tauC=spec.tauC;
point.status='ok'; point.frames=frame; point.seeds=seeds(1:frame); point.totalBits=bits;
point.stopReason=iff(bits>=maxBits,'maxBits','targetErrors'); point.errors=errors;
point.ber=sum(errors,2)/bits; point.meanEvmPercent=evm/frame;
zeroErrors=sum(errors,2)==0; point.zeroErrorUpper95=nan(3,1);
point.zeroErrorUpper95(zeroErrors)=-log(.05)/bits;
point.floorHitFraction=floorHits/max(betaSamples,1);
end

function brackets=threshold_brackets(points,tauGrid,targetBer)
names=["standard" "softDF" "genie"]; brackets=repmat(struct('tauC',0,'receiver','', ...
    'maxFastAtOrBelow',NaN,'minFastAbove',NaN),1,numel(tauGrid)*3); index=0;
for tau=tauGrid
    pick=string({points.status})=="ok" & [points.tauC]==tau; chosen=points(pick);
    fast=[chosen.fastFraction];
    bers=reshape([chosen.ber],3,[]);
    for receiver=1:3
        index=index+1; good=fast(bers(receiver,:)<=targetBer); bad=fast(bers(receiver,:)>targetBer);
        brackets(index)=struct('tauC',tau,'receiver',names(receiver), ...
            'maxFastAtOrBelow',max_or_nan(good),'minFastAbove',min_or_nan(bad));
    end
end
end

function value=max_or_nan(x)
if isempty(x), value=NaN; else, value=max(x); end
end

function value=min_or_nan(x)
if isempty(x), value=NaN; else, value=min(x); end
end

function value=iff(test,a,b)
if test, value=a; else, value=b; end
end

function point=empty_point()
point=struct('fastFraction',NaN,'tauC',NaN,'status','notRun','failureIdentifier','', ...
    'failureMessage','', 'frames',0,'seeds',[],'totalBits',0,'stopReason','', ...
    'errors',[],'ber',[NaN;NaN;NaN],'meanEvmPercent',[NaN NaN NaN], ...
    'zeroErrorUpper95',[NaN;NaN;NaN],'floorHitFraction',NaN);
end

function write_figure(report,out)
names=["standard RZF" "soft ICI-DF (3 it)" "known-beta genie"];
f=figure('Visible','off','Color','w','Position',[100 100 1200 360]);
tiledlayout(1,numel(report.tauGrid),'Padding','compact','TileSpacing','compact');
for tau=report.tauGrid
    nexttile; hold on; pick=string({report.points.status})=="ok" & [report.points.tauC]==tau; p=report.points(pick);
    [fast,order]=sort([p.fastFraction]); p=p(order);
    for receiver=1:3, semilogy(fast,arrayfun(@(x)x.ber(receiver),p),'o-','LineWidth',1.2); end
    yline(report.targetBer,'k:','BER=10^{-2}'); grid on; xlabel('fast-jitter std fraction');
    ylabel('aggregate BER'); title(sprintf('tau_c = %.3g ns',tau*1e9));
end
legend(names,'Location','southoutside','Orientation','horizontal');
exportgraphics(f,fullfile(out,'phase2_device_envelope.png'),'Resolution',180); close(f);
end

function print_summary(report)
for p=report.points
    fprintf('fast=%.2f tau=%.3g ns BER std/DF/genie=[%s] floor=%.3g (%s, %.3g bits)\n', ...
        p.fastFraction,p.tauC*1e9,num2str(p.ber','%.3g '),p.floorHitFraction,p.status,p.totalBits);
end
end
