%% Generate the shared Type-A TX/RX MAT reference file
%  Run once before TX or RX. The resulting MAT file contains:
%    - 4-layer resource grids, DM-RS symbols/indices, data QPSK
%    - Reference info bits and coded bits for BER calculation
%    - OFDM-modulated 307200x4 time-domain waveform
clear; clc;
cfg = type1_config();
package = type1_build_package(cfg);
save(cfg.referenceFile, 'package', '-v7.3');
info = dir(cfg.referenceFile);
fprintf('Saved shared reference: %s (%.2f MiB)\n', ...
    cfg.referenceFile, info.bytes / 2^20);
