function files=type1_plot_phase1_sweeps(input,outputDirectory)
%TYPE1_PLOT_PHASE1_SWEEPS Complete, publication-readable Phase-1 plots.
% input may be the results struct or the saved phase1_sweeps.mat path.  This
% function only redraws stored values; it never reruns the link simulation.
% New-format MAT files produce all stored metrics and paired-factor
% interaction residuals.  Historical MAT files remain redrawable.
if ischar(input)||isstring(input)
    loaded=load(input,'results');results=loaded.results;
    if nargin<2||strlength(string(outputDirectory))==0
        outputDirectory=fileparts(char(input));
    end
else
    results=input;
end
if nargin<2||strlength(string(outputDirectory))==0,outputDirectory=pwd;end
if ~isfolder(outputDirectory),mkdir(outputDirectory);end

curveNames={'isolation','rise','cfo','timing','phaseNoise','jitter','power'};
curveTitles={'Switch isolation','Static settling','Per-user CFO','Fractional timing', ...
    'TX Wiener phase noise','Transition jitter','User power imbalance'};
xLabels={'isolation (dB; ideal shown at 60)','10-90% rise time (ns)', ...
    'stress scale (1 = frozen vector)','stress scale (1 = frozen vector)', ...
    'stress scale (1 = frozen vector)','jitter RMS (ps)', ...
    'stress scale (1 = frozen vector)'};
present=cellfun(@(name)isfield(results.curves,name),curveNames);
curveNames=curveNames(present);curveTitles=curveTitles(present);xLabels=xLabels(present);
nCurve=numel(curveNames);
f=figure('Visible','off','Color','w','Position',[30 30 1650 max(950,285*nCurve)]);
t=tiledlayout(nCurve,3,'TileSpacing','compact','Padding','compact');
for k=1:nCurve
    c=results.curves.(curveNames{k});x=c.values;x(isinf(x))=60;
    nexttile(t);semilogy(x,c.ber,'-o','LineWidth',1.25,'MarkerSize',4);grid on;
    title([curveTitles{k} ': BER']);xlabel(xLabels{k});ylabel('BER / finite-sample floor');
    nexttile(t);plot(x,c.evm,'-s','LineWidth',1.25,'MarkerSize',4);grid on;
    title([curveTitles{k} ': EVM']);xlabel(xLabels{k});ylabel('mean RMS EVM (%)');
    nexttile(t);plot(x,c.estimatedCondP95,'-d','LineWidth',1.25,'MarkerSize',4);grid on;
    title([curveTitles{k} ': cond(Hhat)']);xlabel(xLabels{k});ylabel('cond(Hhat) P95');
end
title(t,sprintf('Phase-1 %s: all metrics from %d single-variable scans (%d frames/point)', ...
    results.profile,nCurve,results.framesPerPoint));
files.singleVariable=fullfile(outputDirectory,'phase1_single_variable_all_metrics.png');
exportgraphics(f,files.singleVariable,'Resolution',180);
files.singleVariableLegacyName=fullfile(outputDirectory,'phase1_single_variable.png');
exportgraphics(f,files.singleVariableLegacyName,'Resolution',180);close(f);

heatNames={'isolationRise','cfoIsolation','powerIsolation','timingIsolation'};
heatTitles={'Isolation x settling','CFO x isolation','Power x isolation','Timing x isolation'};
heatX={'isolation (dB)','CFO stress scale','power stress scale','timing stress scale'};
heatY={'10-90% rise time (ns)','isolation (dB)','isolation (dB)','isolation (dB)'};
present=cellfun(@(name)isfield(results.heatmaps,name),heatNames);
heatNames=heatNames(present);heatTitles=heatTitles(present);
heatX=heatX(present);heatY=heatY(present);nHeat=numel(heatNames);
newFormat=nHeat>0&&isfield(results.heatmaps.(heatNames{1}),'ber');
if newFormat
    metricFields={'ber','evm','estimatedCondP95'};
    metricTitles={'log10(BER / finite-sample floor)','mean RMS EVM (%)','cond(Hhat) P95'};
    f=figure('Visible','off','Color','w','Position',[30 30 1650 max(950,330*nHeat)]);
    t=tiledlayout(nHeat,3,'TileSpacing','compact','Padding','compact');
    for k=1:nHeat
        h=results.heatmaps.(heatNames{k});
        for q=1:numel(metricFields)
            values=h.(metricFields{q});
            if q==1,values=log10(values);end
            nexttile(t);draw_heatmap(h.x,h.y,values,false);
            title([heatTitles{k} ': ' metricTitles{q}]);
            xlabel(heatX{k});ylabel(heatY{k});
        end
    end
    title(t,sprintf('Phase-1 %s: every stored metric for %d paired-factor scans (no interpolation)', ...
        results.profile,nHeat));
    files.heatmaps=fullfile(outputDirectory,'phase1_heatmaps_all_metrics.png');
    exportgraphics(f,files.heatmaps,'Resolution',180);
    files.heatmapsLegacyName=fullfile(outputDirectory,'phase1_heatmaps.png');
    exportgraphics(f,files.heatmapsLegacyName,'Resolution',180);close(f);

    f=figure('Visible','off','Color','w','Position',[30 30 1650 max(950,330*nHeat)]);
    t=tiledlayout(nHeat,3,'TileSpacing','compact','Padding','compact');
    for k=1:nHeat
        h=results.heatmaps.(heatNames{k});
        bx=h.baselineXIndex;by=h.baselineYIndex;
        for q=1:numel(metricFields)
            values=h.(metricFields{q});
            if q==1,values=log10(values);end
            residual=values-values(:,bx)-values(by,:)+values(by,bx);
            nexttile(t);draw_heatmap(h.x,h.y,residual,true);
            title([heatTitles{k} ': interaction residual, ' metricTitles{q}]);
            xlabel(heatX{k});ylabel(heatY{k});
        end
    end
    title(t,['Paired-factor interaction residuals: z(x,y)-z(x,y0)-z(x0,y)+z(x0,y0); ' ...
        'zero means additive main effects']);
    files.interactionResiduals=fullfile(outputDirectory,'phase1_interaction_residuals.png');
    exportgraphics(f,files.interactionResiduals,'Resolution',180);close(f);
else
    f=figure('Visible','off','Color','w','Position',[50 50 1200 820]);
    t=tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    for k=1:nHeat
        h=results.heatmaps.(heatNames{k});nexttile(t);
        draw_heatmap(h.x,h.y,h.values,false);
        title([heatTitles{k} ': ' h.metric]);xlabel(heatX{k});ylabel(heatY{k});
    end
    title(t,sprintf('Phase-1 %s: %d paired-factor maps (legacy stored metrics only)', ...
        results.profile,nHeat));
    files.heatmaps=fullfile(outputDirectory,'phase1_heatmaps.png');
    exportgraphics(f,files.heatmaps,'Resolution',180);close(f);
end
fprintf('Phase-1 figures redrawn: %s | %s\n',files.singleVariable,files.heatmaps);
end

function draw_heatmap(x,y,values,symmetric)
imagesc(x,y,values);axis xy;colorbar;
finiteValues=values(isfinite(values));
if isempty(finiteValues),return;end
lo=min(finiteValues);hi=max(finiteValues);
if symmetric
    span=max(abs([lo hi]));
    if span==0,span=eps;end
    clim([-span span]);
elseif hi==lo
    span=max(abs(lo)*0.02,eps);clim([lo-span lo+span]);
end
end
