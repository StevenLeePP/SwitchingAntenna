function type1_plot_phase2_r14_results(resultFile)
%TYPE1_PLOT_PHASE2_R14_RESULTS Replot accepted R14 MAT without rerunning links.
if nargin<1 || strlength(string(resultFile))==0
    resultFile=getenv('TYPE1_R14_RESULT_MAT');
end
assert(isfile(resultFile),'type1:R14PlotInput','A valid R14 result MAT is required.');
loaded=load(resultFile,'report');report=loaded.report;out=report.outputDir;

f=figure('Visible','off','Color','w','Position',[100 100 1250 850]);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
q=report.core(1:4);nexttile;plot([q.q],100*[q.relativeReduction],'o-','LineWidth',1.4);
grid on;xlabel('Q');ylabel('conditional BER reduction (%)');title('TDL Q sweep');
it=report.core([3 5 6]);nexttile;plot([it.iterations],100*[it.relativeReduction],'o-','LineWidth',1.4);
grid on;xlabel('DF iterations');ylabel('conditional BER reduction (%)');title('TDL iteration sweep');
nexttile;yyaxis left;
semilogy(report.snrGridDb,[report.snrPoints.standardBER],'o-','LineWidth',1.3);hold on;
semilogy(report.snrGridDb,[report.snrPoints.dfBER],'s-','LineWidth',1.3);
ylabel('conditional aggregate BER');yyaxis right;
plot(report.snrGridDb,[report.snrPoints.outageRate],'k--','LineWidth',1.2);
ylim([0 1]);ylabel('acquisition outage rate');grid on;xlabel('SNR (dB)');
legend('standard','soft DF','outage','Location','best');title('TDL SNR: BER and explicit outage');
nexttile;pick=[report.envelopePoints.tauC]==1e-6;p=report.envelopePoints(pick);
[~,order]=sort([p.fastFraction]);p=p(order);semilogy([p.fastFraction],[p.standardBER],'o-','LineWidth',1.2);hold on;
semilogy([p.fastFraction],[p.dfBER],'s-','LineWidth',1.2);semilogy([p.fastFraction],[p.genieBER],'^-','LineWidth',1.2);
grid on;xlabel('fast-jitter std fraction');ylabel('conditional BER');
legend('standard','soft DF','genie beta','Location','best');title('TDL device envelope, tau_c=1 us');
exportgraphics(f,fullfile(out,'phase2_r14_final_curves.png'),'Resolution',180);close(f);

f=figure('Visible','off','Color','w','Position',[100 100 1200 450]);
tiledlayout(1,2,'Padding','compact');isolated=report.core(6);nexttile;hold on;
for k=1:isolated.validCount
    semilogy([1 2],[isolated.standardBerPerSeed(k) isolated.dfBerPerSeed(k)],'-o','Color',[.5 .5 .5]);
end
xlim([.8 2.2]);xticks([1 2]);xticklabels({'standard','soft DF'});grid on;
ylabel('BER per TDL realization');title('Isolated settling ICI: TDL transfer');
prior=report.receivedDrivePrior;nexttile;hold on;indices=[2 3 4 5];
for k=1:size(prior.ber,1),semilogy(1:4,prior.ber(k,indices),'-o','LineWidth',1.2);end
xticks(1:4);xticklabels({'L1','DDCE','received','L3'});grid on;
ylabel('BER per full-stack realization');title('Integration boundary: observable state is not stable gain');
exportgraphics(f,fullfile(out,'phase2_r14_integration_boundary.png'),'Resolution',180);close(f);

if ~isempty(report.switchAttribution)
    s=report.switchAttribution;y=s.successRate;lo=y-s.wilson95Low;hi=s.wilson95High-y;
    f=figure('Visible','off','Color','w','Position',[100 100 720 480]);
    errorbar(1:3,y,lo,hi,'o','LineWidth',1.5,'MarkerSize',8);grid on;ylim([0 1]);
    xlim([.5 3.5]);xticks(1:3);xticklabels({'switch off','ideal switch on','impaired switch on'});
    ylabel('P_{acq} at 20 dB');title('R14 switch acquisition cost attribution');
    text(1.5,.92,sprintf('structure: %+.1f pp, p=%.3g',s.structureCostPercentagePoints,s.structureMcnemarP), ...
        'HorizontalAlignment','center');
    text(2.5,.86,sprintf('modeled impairments: %+.1f pp, p=%.3g', ...
        s.impairmentCostPercentagePoints,s.impairmentMcnemarP),'HorizontalAlignment','center');
    exportgraphics(f,fullfile(out,'phase2_r14_switch_attribution.png'),'Resolution',180);close(f);
end
end
