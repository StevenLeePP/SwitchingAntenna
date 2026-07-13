function package = type1_build_package(cfg)
%TYPE1_BUILD_PACKAGE Build the shared TX/RX MAT package and waveform.
%
%  Frame structure (one 10 ms frame, 30.72 MS/s, 307200 samples):
%    Slot 0:  SS/PBCH block (symbols 2-5, centre 240 SC) from TX1 only.
%             PSS/SSS for sync, PBCH+DM-RS for MIB verification.
%    Slots 1-19:  Type-A PDSCH with one Type-1 front-loaded DM-RS symbol
%             (l=2) and 13 QPSK data symbols per slot.
%    Four layers share the same time-frequency REs (spatial multiplexing).
%
%  Data mapping is selected by cfg.channelCoding:
%    none:          source bits -> QPSK (default, raw PHY BER)
%    convolutional: source bits -> terminated K=7 R=1/2 code -> QPSK
%  Every source begins with a readable telemetry header and uses a
%  deterministic PRBS body. Each slot can be decoded independently.

arguments
    cfg (1,1) struct
end

nSC = 12 * cfg.nRB;                % 612 effective subcarriers
nSlots = numel(cfg.dataSlots);     % 19 data slots
nSym = cfg.symbolsPerFrame;        % 280
nLayers = cfg.nLayers;             % 4
carrier = type1_carrier_config(cfg, 0);
pdsch = type1_pdsch_config(cfg);

grid = complex(zeros(nSC, nSym, nLayers, 'single'));

% ══════════════════════════════════════════════════════════════
%  Slot 0: Standard SS/PBCH block (TX1 only)
%  SSB occupies symbols 2-5, subcarriers 186-425 (240 SC total).
%  Written only to layer 1 -> physical TX1. TX2-TX4 are zeros.
% ══════════════════════════════════════════════════════════════
ssbSC = (floor((nSC - 240) / 2) + 1) + (0:239);  % centre 240 subcarriers
ssbSym = cfg.ssbFirstSymbol + (1:4);              % symbols 2,3,4,5

ssbGrid = complex(zeros(240, 4));
% PSS: 127-length m-sequence, depends on NID2 = PCI mod 3
ssbGrid(nrPSSIndices) = nrPSS(cfg.pci);
% SSS: 127-length Gold sequence, depends on full PCI = 3*NID1 + NID2
ssbGrid(nrSSSIndices) = nrSSS(cfg.pci);

% BCH: 24-bit MIB -> +8 timing bits + 24-bit CRC -> Polar encode -> rate match
mib = type1_make_mib_bits(cfg);
bchCW = nrBCH(mib, cfg.sfn, cfg.halfFrameBit, cfg.Lmax, ...
    cfg.kSSB, cfg.pci);
% PBCH: scrambling (PCI-dependent) + QPSK modulation
pbchV = mod(cfg.ssbIndex, 8);
ssbGrid(nrPBCHIndices(cfg.pci)) = ...
    nrPBCH(bchCW, cfg.pci, pbchV);
% PBCH DM-RS: Gold sequence, position depends on PCI mod 4
ibarSSB = cfg.ssbIndex + 4 * cfg.halfFrameBit;
ssbGrid(nrPBCHDMRSIndices(cfg.pci)) = ...
    nrPBCHDMRS(cfg.pci, ibarSSB);

grid(ssbSC, ssbSym, 1) = single(ssbGrid);  % layer 1 -> TX1 only

% ══════════════════════════════════════════════════════════════
%  Query Type-1 DM-RS resource sizes from 5G Toolbox.
%  With 2 CDM groups without data, the DM-RS symbol is entirely
%  DM-RS (no data multiplexed on that symbol).
%  306 DM-RS RE per port = 51 RB * 6 RE/RB for Type-1 single-symbol.
% ══════════════════════════════════════════════════════════════
carrier.NSlot = cfg.dataSlots(1);
dmrsSymbolsOne = nrPDSCHDMRS(carrier, pdsch);        % [306 x 4]
dmrsIndicesOne = nrPDSCHDMRSIndices(carrier, pdsch); % [306 x 4]
dataIndicesOne = nrPDSCHIndices(carrier, pdsch);     % [7956 x 4]
assert(isequal(size(dmrsSymbolsOne), [306 nLayers]));
assert(isequal(size(dmrsIndicesOne), [306 nLayers]));
assert(size(dataIndicesOne, 2) == nLayers);

% Data RE count per slot per layer: 612 SC * 13 data symbols = 7956
nDataRE = size(dataIndicesOne, 1);
assert(nDataRE == nSC * numel(cfg.dataSymbolSet));

% Every QPSK RE carries two mapped bits, independent of coding mode.
nCodedBits = 2 * nDataRE;                         % 15912 mapped bits
switch cfg.channelCoding
    case 'none'
        tailLength = 0;
        nInfoBits = nCodedBits;                   % no coding expansion
        trellis = [];
    case 'convolutional'
        tailLength = cfg.convConstraintLength - 1;
        nInfoBits = nDataRE - tailLength;         % 7950 information bits
        trellis = poly2trellis(cfg.convConstraintLength, ...
            cfg.convGeneratorsOctal);
    otherwise
        error('type1:Coding', 'Unsupported coding mode %s.', ...
            cfg.channelCoding);
end

% ══════════════════════════════════════════════════════════════
%  Per-slot, per-layer meaningful deterministic data generation.
%  The shared MAT file lets RX compute exact BER without signalling
%  the expected source data over the air.
% ══════════════════════════════════════════════════════════════
infoBits = false(nInfoBits, nSlots, nLayers);
codedBits = false(nCodedBits, nSlots, nLayers);
dataQPSK = complex(zeros(nDataRE, nSlots, nLayers, 'single'));
dmrsSymbols = complex(zeros(306, nLayers, nSlots, 'single'));
dmrsIndices = zeros(306, nLayers, nSlots, 'uint32');
dataIndices = zeros(nDataRE, nLayers, nSlots, 'uint32');
[~, metadataTemplate] = type1_make_payload_bits( ...
    1, cfg.dataSlots(1), 1, cfg);
payloadMetadata = repmat(metadataTemplate, nSlots, nLayers);

for s = 1:nSlots
    slot = cfg.dataSlots(s);
    carrier.NSlot = slot;
    slotGrid = complex(zeros(nSC, cfg.symbolsPerSlot, nLayers));

    % Query MATLAB's exact Type-1 DM-RS symbols and indices for this slot
    localDMRSSymbols = nrPDSCHDMRS(carrier, pdsch);
    localDMRSIndices = nrPDSCHDMRSIndices(carrier, pdsch);
    localDataIndices = nrPDSCHIndices(carrier, pdsch);
    slotGrid(localDMRSIndices) = localDMRSSymbols;

    for layer = 1:nLayers
        [localInfo, localMetadata] = type1_make_payload_bits( ...
            nInfoBits, slot, layer, cfg);
        switch cfg.channelCoding
            case 'none'
                localCoded = localInfo;
            case 'convolutional'
                % Terminated convolutional encoding: append K-1 zeros.
                encoderInput = [localInfo; false(tailLength, 1)];
                localCoded = logical(convenc(double(encoderInput), trellis));
        end
        localQPSK = nrSymbolModulate(int8(localCoded), cfg.modulation);
        assert(numel(localCoded) == nCodedBits);
        assert(numel(localQPSK) == nDataRE);

        infoBits(:, s, layer) = localInfo;
        codedBits(:, s, layer) = localCoded;
        dataQPSK(:, s, layer) = single(localQPSK);
        payloadMetadata(s, layer) = localMetadata;
        slotGrid(localDataIndices(:, layer)) = localQPSK;
    end

    % Insert slot grid into the full-frame grid
    globalSymbols = slot * cfg.symbolsPerSlot + (1:cfg.symbolsPerSlot);
    grid(:, globalSymbols, :) = single(slotGrid);
    dmrsSymbols(:, :, s) = single(localDMRSSymbols);
    dmrsIndices(:, :, s) = uint32(localDMRSIndices);
    dataIndices(:, :, s) = uint32(localDataIndices);
end

% ══════════════════════════════════════════════════════════════
%  OFDM modulate: 612x280x4 freq-domain grid -> 307200x4 time-domain
%  Scale each channel to 0.72 of full-scale for int16 headroom.
% ══════════════════════════════════════════════════════════════
carrier.NSlot = 0;
[waveform, ofdmInfo] = nrOFDMModulate(carrier, double(grid), ...
    'Nfft', cfg.nfft, 'SampleRate', cfg.txSampleRate, ...
    'CarrierFrequency', 0, 'Windowing', 0);
assert(size(waveform, 1) == round( ...
    cfg.txSampleRate * cfg.frameDurationSec));  % 307200

% Equal peak headroom across all four channels
for layer = 1:nLayers
    waveform(:, layer) = waveform(:, layer) / ...
        max(abs(waveform(:, layer))) * 0.72;
end

% ══════════════════════════════════════════════════════════════
%  Bundle everything into the shared package struct.
%  This MAT file is the single reference for both TX and RX.
% ══════════════════════════════════════════════════════════════
package = struct;
package.formatVersion = cfg.formatVersion;
package.generatedAt = datetime('now');
package.cfg = cfg;
package.channelCoding = cfg.channelCoding;
package.mib = mib;
package.bchCodeword = bchCW;
package.ssbSubcarriers = ssbSC;
package.ssbSymbols = ssbSym;
package.infoBits = infoBits;                % [7950 x 19 x 4] logical
package.sourceBits = infoBits;              % explicit pre-code source bits
package.codedBits = codedBits;              % [15912 x 19 x 4] logical
package.payloadMetadata = payloadMetadata;  % readable source identity/telemetry
package.dataQPSK = dataQPSK;                % [7956 x 19 x 4] single
package.dmrsSymbols = dmrsSymbols;          % [306 x 4 x 19] single
package.dmrsIndices = dmrsIndices;          % [306 x 4 x 19] uint32
package.dataIndices = dataIndices;          % [7956 x 4 x 19] uint32
package.dmrsCDMLengths = pdsch.DMRS.CDMLengths;        % [2 1]
package.dmrsCDMGroups = pdsch.DMRS.CDMGroups;          % [0 0 1 1]
package.dmrsFrequencyWeights = pdsch.DMRS.FrequencyWeights;  % [+1 +1 +1 +1; +1 -1 +1 -1]
package.txGrid = grid;                      % [612 x 280 x 4] single
package.txWaveform = single(waveform);      % [307200 x 4] single
package.ofdmInfo = ofdmInfo;                % CP lengths, symbol lengths
package.trellis = trellis;                  % conv. code trellis
package.nDataREPerSlotLayer = nDataRE;      % 7956
package.nInfoBitsPerSlotLayer = nInfoBits;  % 7950
package.nCodedBitsPerSlotLayer = nCodedBits;% 15912

fprintf(['Built Type-A package: one SSB slot + %d data slots, ' ...
    '%d QPSK RE/slot/layer.\n'], nSlots, nDataRE);
fprintf('Channel coding: %s, source/mapped bits=%d/%d per slot/layer.\n', ...
    cfg.channelCoding, nInfoBits, nCodedBits);
fprintf('Source example: %s\n', payloadMetadata(1, 1).message);
fprintf(['DM-RS: Type %d, symbol l=%d, ports 1000...1003, ' ...
    'CDM groups=[%s], CDM lengths=[%s].\n'], ...
    cfg.dmrsConfigurationType, cfg.dmrsTypeAPosition, ...
    num2str(package.dmrsCDMGroups), ...
    num2str(package.dmrsCDMLengths));
end
