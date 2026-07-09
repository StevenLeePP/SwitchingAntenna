function cfg = type1_config()
%TYPE1_CONFIG Type-A four-port DM-RS experiment configuration.
%  Returns a struct with all RF, OFDM, MIMO, and coding parameters.
%  This is the single source of truth shared by TX, RX, and selftest.

cfg = struct;
cfg.formatVersion = 'NR4_TYPE1_A_V1';

% ── NR carrier: 20 MHz, mu=1, 30 kHz SCS, 51 RB ──
cfg.scsKHz = 30;               % subcarrier spacing (kHz)
cfg.nRB = 51;                  % resource blocks in BWP
cfg.nfft = 1024;               % OFDM IFFT/FFT size
cfg.cpType = 'normal';         % CP lengths: 88 / 72 samples
cfg.txSampleRate = 30.72e6;    % = NFFT * SCS
cfg.rxSampleRate = 122.88e6;   % 4x oversampling for digital switch
cfg.frameDurationSec = 10e-3;  % one NR frame  - 10ms
cfg.symbolsPerSlot = 14;
cfg.slotsPerFrame = 20;
cfg.symbolsPerFrame = 280;     % 20 × 14

% ── Single cell, single SSB in slot 0 ──
cfg.pci = 0;                   % physical cell ID
cfg.ssbSlot = 0;               % dedicated SSB slot (zero-based)
cfg.ssbFirstSymbol = 2;        % Case-C SSB candidate
cfg.ssbIndex = 0;              % SSB index within burst
cfg.halfFrameBit = 0;          % first 5 ms half-frame
cfg.Lmax = 8;                  % max SSB candidates per half-frame
cfg.kSSB = 0;                  % SSB subcarrier offset (kHz = kSSB*15)
cfg.sfn = 0;                   % system frame number

% ── Slots 1-19: PDSCH Mapping Type A, Type-1 front-loaded DM-RS ──
cfg.dataSlots = 1:19;          % zero-based slot indices
cfg.pdschMappingType = 'A';    % Type A: DM-RS at fixed symbol position
cfg.pdschSymbolAllocation = [0 14];  % full slot
cfg.dmrsTypeAPosition = 2;     % pos2 -> DM-RS at symbol l=2
cfg.dmrsConfigurationType = 1; % Type-1: two CDM groups, FDM multiplexed
cfg.dmrsLength = 1;            % single-symbol (front-loaded only)
cfg.dmrsAdditionalPosition = 0;% no additional DM-RS beyond front-loaded
cfg.dmrsPortSet = 0:3;         % MATLAB ports 0-3 = 3GPP ports 1000-1003
cfg.numCDMGroupsWithoutData = 2; % both CDM groups are DM-RS only (no data)
cfg.nLayers = 4;               % four MIMO spatial streams
cfg.dataSymbolSet = [0 1 3:13];% data symbols within a data slot (13 total)

% ── Custom payload: QPSK + K=7 R=1/2 terminated convolutional code ──
cfg.modulation = 'QPSK';
cfg.convConstraintLength = 7;
cfg.convGeneratorsOctal = [171 133];      % g0=171o, g1=133o
cfg.viterbiTraceback = 35;                % Viterbi traceback depth
cfg.rzfRegularization = 1e-3;             % RZF lambda scaling factor
cfg.channelConditionSamplesPerSlot = 64;  % samples for cond(H) stats
cfg.constellationMaxPoints = 3000;        % max points displayed in scatter

% ── Shared reference file (generated once, used by TX and RX) ──
sourceDir = fileparts(mfilename('fullpath'));
cfg.referenceFile = fullfile(sourceDir, 'nr4_type1_reference.mat');
cfg.outputRoot = fullfile(sourceDir, 'captures');
cfg.dataRoot = fullfile(sourceDir, 'data'); % short raw/virtual IQ dumps

% ── YunSDR hardware ──
cfg.deviceString = 'pciex:0,nsamples_recv_frame:7680';
cfg.centerFrequencyHz = 3.2e9;
cfg.txAttenuationMdB = 0;      % max TX power
cfg.rxGain = 30;               % RX RF gain
cfg.txChannelMask = hex2dec('f');  % all 4 TX channels enabled
cfg.rxChannelMask = hex2dec('f');  % all 4 RX channels enabled
cfg.nTxChannels = 4;
cfg.nRxChannels = 4;
cfg.txDurationSec = inf;       % default: run until interrupted
cfg.txStartLeadSec = 0.050;    % timestamp lead for first frame
cfg.txStatusPeriodSec = 0.500; % status print interval

% ── Live RX monitor ──
cfg.liveDurationSec = 60;      % total run duration
cfg.liveUpdateSec = 1.0;       % analysis/display update period
cfg.liveComputeThreads = 8;    % maxNumCompThreads for parallel pool
cfg.liveAnalysisBlocks = 20;   % snapshot = 20 ms of raw data
cfg.liveRingBlocks = 64;       % ring buffer stores 64 ms
cfg.spectrumNfft = 8192;       % FFT size for live spectrum
cfg.initialIQCaptureSec = 20e-3;% save first 20 ms = 2 frames / 40 slots at RX startup
end
