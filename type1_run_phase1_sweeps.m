function results = type1_run_phase1_sweeps()
%TYPE1_RUN_PHASE1_SWEEPS Six 1-D and four 2-D offline Phase-1 pilot scans.
%   Zero-error points are plotted as the finite upper bound 1/Nbits, never
%   as a fictitious logarithmic zero.  Set TYPE1_SWEEP_PROFILE=pilot for the
%   denser grid; smoke is the fast structural regression.

cfg = type1_config(); package = type1_load_package();
profile = lower(string(getenv('TYPE1_SWEEP_PROFILE')));
if strlength(profile)==0, profile="smoke"; end
frames = round(env_positive('TYPE1_SWEEP_FRAMES', iff(profile=="smoke",1,3)));
if profile=="smoke"
    oneD = [0 1]; twoD = [0 .5 1]; iso = [15 32.5 50]; rise = [0 5 10];
    isoCurve = [15 Inf]; riseCurve = [0 10]; jitterCurve = [0 100];
else
    oneD = [0 .25 .5 .75 1]; twoD = [0 .25 .5 .75 1]; iso = [15 23.75 32.5 41.25 50]; rise = [0 2.5 5 7.5 10];
    isoCurve = [15 25 35 50 Inf]; riseCurve = [0 1 3 5 10]; jitterCurve = [0 20 50 100 200];
end
names = {'isolation','rise','cfo','phaseNoise','jitter','power'};
curves = struct;
for k=1:numel(names)
    values = oneD;
    if strcmp(names{k},'isolation'), values = isoCurve; end
    if strcmp(names{k},'rise'), values = riseCurve; end
    if strcmp(names{k},'jitter'), values = jitterCurve; end
    curves.(names{k}) = sweep1d(names{k}, values);
end
heatmaps = struct;
heatmaps.isolationRise = sweep2d('isolationRise', iso, rise, 'ber');
heatmaps.cfoIsolation = sweep2d('cfoIsolation', twoD, iso, 'ber');
heatmaps.powerIsolation = sweep2d('powerIsolation', twoD, iso, 'ber');
heatmaps.timingIsolation = sweep2d('timingIsolation', twoD, iso, 'cond');
results = struct('profile',char(profile),'framesPerPoint',frames, ...
    'curves',curves,'heatmaps',heatmaps);
out = output_dir(cfg, profile); save(fullfile(out,'phase1_sweeps.mat'),'results','-v7.3');
plot_results(results,out); fprintf('Phase-1 %s sweeps saved: %s\n',profile,out);

    function entry = sweep1d(name, values)
        entry = struct('values',values,'ber',zeros(size(values)),'evm',zeros(size(values)), ...
            'condP95',zeros(size(values)),'failures',false(size(values)));
        for i=1:numel(values)
            m=measure(apply_case(name,values(i)),i); entry.ber(i)=m.ber; entry.evm(i)=m.evm;
            entry.condP95(i)=m.cond; entry.failures(i)=m.failure;
        end
    end
    function entry = sweep2d(name, x, y, metric)
        entry=struct('x',x,'y',y,'metric',metric,'values',nan(numel(y),numel(x)));
        for ix=1:numel(x), for iy=1:numel(y)
            m=measure(apply_case(name,[x(ix) y(iy)]),100+ix+10*iy);
            if strcmp(metric,'ber'), entry.values(iy,ix)=m.ber; else, entry.values(iy,ix)=m.cond; end
        end,end
    end
    function sim = apply_case(name,value)
        sim=type1_offline_sim_config(); sim.frames=frames; sim.assertIdealBaseline=false;
        u=type1_offline_multiuser_config(); z=zeros(1,4);
        switch name
            case 'isolation', sim.switch.isolationDb=value; sim.switch.settlingRiseNs=0;
            case 'rise', sim.switch.settlingRiseNs=value;
            case 'cfo', sim.userCfoHz=u.userCfoHz*value;
            case 'phaseNoise', sim.userPhaseNoiseStdRadPerSample=u.userPhaseNoiseStdRadPerSample*value;
            case 'jitter', sim.switch.settlingRiseNs=5; sim.switch.transitionJitterStdPs=value;
            case 'power', sim.userPowerDb=u.userPowerDb*value;
            case 'isolationRise', sim.switch.isolationDb=value(1); sim.switch.settlingRiseNs=value(2);
            case 'cfoIsolation', sim.userCfoHz=u.userCfoHz*value(1); sim.switch.isolationDb=value(2);
            case 'powerIsolation', sim.userPowerDb=u.userPowerDb*value(1); sim.switch.isolationDb=value(2);
            case 'timingIsolation', sim.userTimingSamples=u.userTimingSamples*value(1); sim.switch.isolationDb=value(2);
        end
        %#ok<NASGU> z
    end
    function m = measure(sim, seedOffset)
        s=RandStream('mt19937ar','Seed',sim.seed+seedOffset); err=0; evm=0; cond=0; failure=false;
        for f=1:sim.frames
            try
                r=type1_analyze(type1_offline_link(package,sim,s).virtualRx30,package);
                err=err+sum(r.infoBitErrors,'all'); evm=evm+mean(r.evmRMSPercent,'all'); cond=cond+r.conditionStats(2);
            catch exception
                warning('type1:Phase1Sweep','Point failed: %s',exception.message); failure=true; err=NaN; break;
            end
        end
        nbits=sim.frames*numel(cfg.dataSlots)*package.nInfoBitsPerSlotLayer*cfg.nLayers;
        m=struct('ber',max(err/nbits,1/nbits),'evm',evm/max(sim.frames,1),'cond',cond/max(sim.frames,1),'failure',failure);
    end
end

function out=output_dir(cfg,profile)
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=cfg.outputRoot;end
out=fullfile(root,['type1_phase1_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
[ok,~]=mkdir(out); if ~ok, out=fullfile(tempdir,['type1_phase1_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]); mkdir(out); end
end

function plot_results(r,out)
f=figure('Visible','off','Color','w'); t=tiledlayout(2,3,'TileSpacing','compact');
names=fieldnames(r.curves); for k=1:numel(names), c=r.curves.(names{k}); nexttile(t); x=c.values; x(isinf(x))=60; semilogy(x,c.ber,'-o'); grid on; title(names{k}); xlabel('parameter (Inf IS plotted as 60 dB)'); ylabel('BER upper bound'); end
exportgraphics(f,fullfile(out,'phase1_single_variable.png'),'Resolution',160); close(f);
f=figure('Visible','off','Color','w'); t=tiledlayout(2,2,'TileSpacing','compact'); names=fieldnames(r.heatmaps);
for k=1:numel(names), h=r.heatmaps.(names{k}); nexttile(t); imagesc(h.x,h.y,h.values); axis xy; colorbar; title([names{k} ' (' h.metric ')']); xlabel('x'); ylabel('y'); end
exportgraphics(f,fullfile(out,'phase1_heatmaps.png'),'Resolution',160); close(f);
end

function v=env_positive(n,d),v=str2double(getenv(n));if ~isfinite(v)||v<=0,v=d;end,end
function y=iff(c,a,b),if c,y=a;else,y=b;end,end
