function type1_plot_paper_e1_result(report,file)
%TYPE1_PLOT_PAPER_E1_RESULT Render the frozen E1 three-panel audit figure.
arguments
    report (1,1) struct
    file {mustBeTextScalar}
end
s=report.summary;figure('Visible','off','Position',[100 100 1500 460]);
order=["M8" "M12" "M16"];
groups=categorical(repelem(order,size(report.retention,1)).',order,'Ordinal',true);
subplot(1,3,1);boxchart(groups,report.retention(:));yline(1,'--');grid on;
ylabel('true-objective gain retention');title('DM-RS estimated CSI vs truth-CSI greedy');
subplot(1,3,2);bar(s.amcGain);grid on;xticklabels(s.armNames);xtickangle(25);
ylabel('1 s AMC gain vs M4 (bit/s/Hz)');title('full-stack goodput');
subplot(1,3,3);boxchart(groups,report.hNmseDb(:));grid on;
ylabel('scan H NMSE (dB)');title('estimated physical CSI');
exportgraphics(gcf,file,'Resolution',180);close(gcf);
end
