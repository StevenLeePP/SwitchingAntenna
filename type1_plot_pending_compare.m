function outputFile=type1_plot_pending_compare(baselineFile,twoStageFile,outputFile)
%TYPE1_PLOT_PENDING_COMPARE Render two direct-consumer pending traces.
arguments
    baselineFile (1,:) char
    twoStageFile (1,:) char
    outputFile (1,:) char
end
a=load(baselineFile,'summary'); b=load(twoStageFile,'summary');
assert(isfield(a.summary,'pendingTrace')&&isfield(b.summary,'pendingTrace'), ...
    'type1:PendingPlot','Both results must contain pendingTrace.');
figure('Visible','off','Color','w','Position',[100 100 1100 560]); hold on; grid on;
plot(a.summary.pendingTrace.timeSec,a.summary.pendingTrace.pendingBlocks, ...
    'LineWidth',1.4,'DisplayName','single-stage startup');
plot(b.summary.pendingTrace.timeSec,b.summary.pendingTrace.pendingBlocks, ...
    'LineWidth',1.4,'DisplayName','two-stage startup');
yline(0,'k-','HandleVisibility','off');
xlim([0,max([a.summary.pendingTrace.timeSec; b.summary.pendingTrace.timeSec])]);
xlabel('RX elapsed time (s)'); ylabel('pending raw DMA blocks (1 block = 1 ms)');
title('Direct consumer queue backlog during 10 s OTA'); legend('Location','northeast');
exportgraphics(gcf,outputFile,'Resolution',160); close(gcf);
end
