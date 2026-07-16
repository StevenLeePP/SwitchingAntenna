function table=type1_phase3_amc_table()
%TYPE1_PHASE3_AMC_TABLE Frozen CQI-style link-abstraction table for R20.
%   Thresholds are a research link abstraction, not a claim of NR MCS
%   conformance.  Spectral efficiencies include modulation and code rate.
table=struct;
table.thresholdDb=[-6.7 -4.7 -2.3 .2 2.4 4.3 5.9 8.1 10.3 11.7 14.1 16.3 18.7 21 22.7];
table.efficiency=[.1523 .2344 .3770 .6016 .8770 1.1758 1.4766 1.9141 ...
    2.4063 2.7305 3.3223 3.9023 4.5234 5.1152 5.5547];
table.modulation=["QPSK" "QPSK" "QPSK" "QPSK" "QPSK" "QPSK" ...
    "16QAM" "16QAM" "16QAM" "64QAM" "64QAM" "64QAM" "64QAM" "64QAM" "64QAM"];
table.targetBlockSuccess=.9;
table.thresholdSensitivityDb=[-2 0 2];
table.isStandardsConformanceClaim=false;
end
