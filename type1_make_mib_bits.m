function mib = type1_make_mib_bits(cfg)
%TYPE1_MAKE_MIB_BITS Deterministic 24-bit MIB for the shared SSB.
%  Encodes: SFN(6 MSB), SCS=30kHz, kSSB, dmrs-TypeA=pos2,
%  pdcch-ConfigSIB1=17, cellBarred=notBarred.
%  TX and RX use identical MIB via the shared MAT reference.

mib = zeros(24, 1, 'int8');

% bit 1: MIB choice bit (always 0 for initial BCH)
% bits 2-7: SFN 6 MSBs
sfnMSB6 = bitget(uint16(cfg.sfn), 10:-1:5).';
mib(2:7) = int8(sfnMSB6);

mib(8) = 1;     % subCarrierSpacingCommon = 1 -> 30 kHz (for mu=1)
mib(9:12) = int8(bitget(uint8(cfg.kSSB), 4:-1:1).');  % kSSB LSBs
mib(13) = 0;    % dmrs-TypeA-Position = 0 -> pos2 (3GPP encoding)
mib(14:21) = int8(bitget(uint8(17), 8:-1:1).');       % pdcch-ConfigSIB1 = 17
mib(22) = 0;    % cellBarred = notBarred
mib(23) = 0;    % intraFreqReselection = allowed
mib(24) = 0;    % spare
end
