function results = type1_run_phase2_timevarying_switch()
%TYPE1_RUN_PHASE2_TIMEVARYING_SWITCH Phase-2 A1/A2 smoke/pilot sweep.
%   Separates slow tau drift, fast tau jitter, and sampling-boundary jitter.
%   Static settling is deliberately retained as the first control: Type-1
%   DM-RS should absorb it, whereas sample-scale tau jitter changes H within
%   the DM-RS-to-data interval and may create residual interference.
%
%   TYPE1_PHASE2_PROFILE=smoke (default) runs one frame/point; pilot runs
%   three.  These are structural scans, not paper-grade stopping statistics.

cfg = type1_config(); package = type1_load_package();
profile = lower(string(getenv('TYPE1_PHASE2_PROFILE')));
if strlength(profile) == 0, profile = "smoke"; end
assert(any(profile == ["smoke" "pilot"]), 'type1:Phase2Profile', ...
    'TYPE1_PHASE2_PROFILE must be smoke or pilot.');
frames = round(env_positive('TYPE1_PHASE2_FRAMES', iff(profile=="smoke", 1, 3)));
snrDb = env_number('TYPE1_PHASE2_SNR_DB', 20);
riseNs = env_positive('TYPE1_PHASE2_RISE_NS', 20);
if profile == "smoke"
    fastTau = [0 .3 .6 1.0]; boundaryPs = [0 300 600 1000]; slowTau = [0 .25 .5];
else
    fastTau = [0 .1 .2 .4 .6 .8 1.0]; boundaryPs = [0 100 300 600 800 1000]; slowTau = [0 .1 .25 .5 .75];
end

base = type1_offline_sim_config();
base.frames = frames; base.snrDb = snrDb; base.assertIdealBaseline = false;
base.switch.settlingRiseNs = riseNs;
results = struct('profile', char(profile), 'framesPerPoint', frames, ...
    'seed', base.seed, 'snrDb', snrDb, 'baseRiseNs', riseNs, ...
    'staticControl', measure(base, 1), ...
    'fastTau', sweep_fast(fastTau), 'boundary', sweep_boundary(boundaryPs), ...
    'slowTau', sweep_slow(slowTau));
out = output_dir(cfg, profile);
save(fullfile(out, 'phase2_timevarying_switch.mat'), 'results', '-v7.3');
plot_results(results, out);
fprintf('Phase-2 time-varying-switch %s sweep saved: %s\n', profile, out);

    function entry = sweep_fast(values)
        entry = make_entry(values, 'settlingFastJitterStdFraction');
        for k=1:numel(values)
            sim=base; sim.switch.settlingFastJitterStdFraction=values(k);
            entry.metrics(k)=measure(sim, 100+k);
        end
    end
    function entry = sweep_boundary(values)
        entry = make_entry(values, 'samplingBoundaryJitterStdPs');
        for k=1:numel(values)
            sim=base; sim.switch.settlingRiseNs=0; sim.switch.samplingBoundaryJitterStdPs=values(k);
            entry.metrics(k)=measure(sim, 200+k);
        end
    end
    function entry = sweep_slow(values)
        entry = make_entry(values, 'settlingSlowDriftFraction');
        for k=1:numel(values)
            sim=base; sim.frames=max(3,frames); sim.switch.settlingSlowDriftFraction=values(k);
            sim.switch.settlingSlowDriftHz=10; % seconds-scale drift, not ICI forcing
            entry.metrics(k)=measure(sim, 300+k);
        end
    end
    function metric = measure(sim, seedOffset)
        stream=RandStream('mt19937ar','Seed',sim.seed+seedOffset);
        errors=zeros(1,cfg.nLayers); evm=0; clips=0; pbchOK=true;
        for frame=1:sim.frames
            frameSim=sim; frameSim.switch.timeOriginSec=sim.switch.timeOriginSec + ...
                (frame-1)*cfg.frameDurationSec;
            link=type1_offline_link(package,frameSim,stream);
            decoded=type1_analyze(link.virtualRx30,package);
            errors=errors+sum(decoded.infoBitErrors,1);
            evm=evm+mean(decoded.evmRMSPercent,'all');
            clips=clips+link.switchMeta.boundaryOffsetClippedCount;
            pbchOK=pbchOK && ~decoded.pbchCRCError && decoded.mibMatches;
        end
        nbits=sim.frames*numel(cfg.dataSlots)*package.nInfoBitsPerSlotLayer;
        metric=struct('infoBER',errors/nbits,'bitErrors',errors, ...
            'meanEVMPercent',evm/sim.frames,'pbchOK',pbchOK, ...
            'boundaryClippedSamples',clips,'frames',sim.frames, ...
            'randomSeed',sim.seed+seedOffset);
    end
end

function entry = make_entry(values, parameter)
empty=struct('infoBER',nan(1,4),'bitErrors',nan(1,4),'meanEVMPercent',nan, ...
    'pbchOK',false,'boundaryClippedSamples',nan,'frames',nan,'randomSeed',nan);
entry=struct('parameter',parameter,'values',values, ...
    'metrics',repmat(empty,1,numel(values)));
end

function out = output_dir(cfg, profile)
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root), root=cfg.outputRoot; end
out=fullfile(root,['type1_phase2_timevarying_' char(profile) '_' ...
    char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
[ok,~]=mkdir(out);
if ~ok
    out=fullfile(tempdir,['type1_phase2_timevarying_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
    mkdir(out);
end
end

function plot_results(results, out)
f=figure('Visible','off','Color','w'); layout=tiledlayout(1,2,'TileSpacing','compact');
series={results.fastTau, results.boundary}; titles={'fast tau jitter fraction','boundary jitter (ps)'};
for k=1:2
    nexttile(layout); hold on; entry=series{k};
    ber=vertcat(entry.metrics.infoBER); semilogy(entry.values, max(mean(ber,2), 1e-12), '-o');
    grid on; xlabel(titles{k}); ylabel('mean layer BER (floor only for display)');
end
exportgraphics(f,fullfile(out,'phase2_timevarying_switch.png'),'Resolution',160); close(f);
end

function v=env_positive(n,d),v=str2double(getenv(n));if ~isfinite(v)||v<=0,v=d;end,end
function v=env_number(n,d),v=str2double(getenv(n));if ~isfinite(v),v=d;end,end
function y=iff(c,a,b),if c,y=a;else,y=b;end,end
