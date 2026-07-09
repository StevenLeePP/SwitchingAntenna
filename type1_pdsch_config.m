function pdsch = type1_pdsch_config(cfg)
%TYPE1_PDSCH_CONFIG Strict Type-A, Type-1, four-port DM-RS.
%  Returns an nrPDSCHConfig object that the 5G Toolbox uses to
%  determine exact DM-RS / data RE positions, sequences, and OCC.
%
%  Port layout (Type-1, 2 CDM groups, 1-symbol DM-RS):
%    CDM group 0, k mod 4 in {0,1}: ports 1000/1001, OCC[+1,+1]/[+1,-1]
%    CDM group 1, k mod 4 in {2,3}: ports 1002/1003, OCC[+1,+1]/[+1,-1]
%  Per RB: 6 DM-RS RE per port. All 612 subcarriers filled on DM-RS symbol.

pdsch = nrPDSCHConfig;
pdsch.NSizeBWP = cfg.nRB;
pdsch.NStartBWP = 0;
pdsch.PRBSet = 0:(cfg.nRB - 1);       % full-band allocation
pdsch.PRBSetType = 'PRB';
pdsch.SymbolAllocation = cfg.pdschSymbolAllocation;  % [0 14]
pdsch.MappingType = cfg.pdschMappingType;            % 'A'
pdsch.NumLayers = cfg.nLayers;                      % 4
pdsch.Modulation = cfg.modulation;                  % 'QPSK'
pdsch.NID = cfg.pci;                                % scrambling ID
pdsch.RNTI = 1;                                     % dummy RNTI

% Type-1, single-symbol, front-loaded DM-RS at l=2 (pos2)
pdsch.DMRS.DMRSConfigurationType = cfg.dmrsConfigurationType;
pdsch.DMRS.DMRSTypeAPosition = cfg.dmrsTypeAPosition;
pdsch.DMRS.DMRSLength = cfg.dmrsLength;
pdsch.DMRS.DMRSAdditionalPosition = cfg.dmrsAdditionalPosition;
pdsch.DMRS.DMRSPortSet = cfg.dmrsPortSet;          % 0:3 = ports 1000-1003
pdsch.DMRS.NIDNSCID = cfg.pci;
pdsch.DMRS.NSCID = 0;
pdsch.DMRS.NumCDMGroupsWithoutData = ...
    cfg.numCDMGroupsWithoutData;                    % 2 -> no data on DM-RS sym
end
