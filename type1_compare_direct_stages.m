function report = type1_compare_direct_stages()
%TYPE1_COMPARE_DIRECT_STAGES One-frame OTA ablation against MATLAB baseline.
% Every variant uses the same PSS-selected IQ and CFO.  Differences therefore
% identify the cost of native-ring extraction/FFT, OFDM window selection, or
% the C DM-RS/RZF/hard-decision kernel separately.

p=type1_load_package(); c=p.cfg;
if exist('type1_yunsdr_rx_mex','file')~=3, type1_build_rx_mex(); end
if exist('type1_decode_frame_grid_mex','file')~=3, type1_build_frame_mex(); end
block=round(c.rxSampleRate*1e-3); ring=round(env_positive('TYPE1_FIFO_RING_BLOCKS',2048));
type1_yunsdr_rx_mex('open',c.deviceString,c.rxSampleRate,c.centerFrequencyHz,c.rxGain);
cleanup=onCleanup(@close_radio); %#ok<NASGU>
type1_yunsdr_rx_mex('start',block,ring); wait_blocks(40);
[iq,timestamps]=type1_yunsdr_rx_mex('snapshotvirtual',40);
acq=type1_analyze_fast(iq,p,c.dataSlots(1),'forcePSS',true, ...
    'snapshotStartRawTimestamp',timestamps(1),'computeSNR',false,'computeCondition',false);
assert(acq.syncState.valid,'type1:StageCompare','PSS acquisition failed.');

slotSamples=round(c.frameDurationSec*c.txSampleRate/c.slotsPerFrame);
activeSamples=(max(c.dataSlots)+1)*slotSamples;
start=acq.timingOffset+1;
assert(start>=1 && start+activeSamples-1<=size(iq,1),'type1:StageCompare','Short PSS frame.');
rawFrame=single(iq(start:start+activeSamples-1,:));
cfo=double(acq.frequencyOffsetHz);
n=single(mod((0:activeSamples-1).',slotSamples));
compensated=rawFrame.*exp(single(-1j*2*pi*cfo/c.txSampleRate).*n);
carrier=type1_carrier_config(c,0);
matlabDefault=single(nrOFDMDemodulate(carrier,compensated, ...
    'Nfft',c.nfft,'SampleRate',c.txSampleRate,'CarrierFrequency',0));
matlabEnd=single(nrOFDMDemodulate(carrier,compensated, ...
    'Nfft',c.nfft,'SampleRate',c.txSampleRate,'CarrierFrequency',0, ...
    'CyclicPrefixFraction',1));
[nativeGrid,nativeTimingMs]=type1_yunsdr_rx_mex('directgrid', ...
    acq.syncState.frameStartRawTimestamp,cfo);
args={double(c.dataSlots(:)),p.dmrsIndices,p.dmrsSymbols,p.dataIndices, ...
    p.dataQPSK,p.codedBits,c.rzfRegularization};
[defaultErrors,defaultEvm,~,defaultH]=type1_decode_frame_grid_mex(matlabDefault,args{:});
[endErrors,endEvm,~,endH]=type1_decode_frame_grid_mex(matlabEnd,args{:});
[nativeErrors,nativeEvm,~,nativeH]=type1_decode_frame_grid_mex(nativeGrid,args{:});

% This is the original toolbox DM-RS/RZF/hard-decision reference.  It may
% select a frame-equivalent PSS peak independently; report its own result
% rather than force it through the optimized C timing path.
standard=type1_analyze(iq,p);

report=struct;
report.acq=acq;
report.nativeTimingMs=nativeTimingMs;
report.matlabStandard=pack_standard(standard);
report.matlabDefault_CPHY=pack_c(defaultErrors,defaultEvm);
report.matlabEnd_CPHY=pack_c(endErrors,endEvm);
report.nativeEnd_CPHY=pack_c(nativeErrors,nativeEvm);
report.gridNmse=struct('nativeVsMatlabEndDb',nmse_db(nativeGrid,matlabEnd), ...
    'matlabEndVsDefaultDb',nmse_db(matlabEnd,matlabDefault));
report.hNmse=struct('nativeVsMatlabEndDb',nmse_db(nativeH,endH), ...
    'matlabEndVsDefaultDb',nmse_db(endH,defaultH));
report.evmMaxDiff=struct('nativeVsMatlabEnd',max(abs(nativeEvm-endEvm),[],'all'), ...
    'matlabEndVsDefault',max(abs(endEvm-defaultEvm),[],'all'));

fprintf('\n========== Type-A direct stage comparison ==========\n');
print_stage('MATLAB standard PHY',report.matlabStandard);
print_stage('MATLAB default CP + C PHY',report.matlabDefault_CPHY);
print_stage('MATLAB CP-end + C PHY',report.matlabEnd_CPHY);
print_stage('native ring CP-end + C PHY',report.nativeEnd_CPHY);
fprintf('grid NMSE native/end=%.2f dB; end/default=%.2f dB\n', ...
    report.gridNmse.nativeVsMatlabEndDb,report.gridNmse.matlabEndVsDefaultDb);
fprintf('H NMSE native/end=%.2f dB; end/default=%.2f dB\n', ...
    report.hNmse.nativeVsMatlabEndDb,report.hNmse.matlabEndVsDefaultDb);
fprintf('EVM max difference native/end=%.6g%%; end/default=%.6g%%\n', ...
    report.evmMaxDiff.nativeVsMatlabEnd,report.evmMaxDiff.matlabEndVsDefault);
assert(report.gridNmse.nativeVsMatlabEndDb<-75,'type1:StageCompare','Native FFT grid mismatch.');
assert(isequal(nativeErrors,endErrors),'type1:StageCompare','Native and MATLAB-end C-PHY bits differ.');
    function close_radio()
        try,type1_yunsdr_rx_mex('stop');catch,end
        try,type1_yunsdr_rx_mex('close');catch,end
    end
end
function value=pack_c(errors,evm)
value=struct('rawBitErrors',errors,'rawErrorTotal',sum(errors,'all'), ...
    'evmRMSPercent',evm,'evmMeanPercent',mean(evm,'all'));
end
function value=pack_standard(result)
value=struct('rawBitErrors',result.rawBitErrors, ...
    'rawErrorTotal',sum(result.rawBitErrors,'all'), ...
    'evmRMSPercent',result.evmRMSPercent, ...
    'evmMeanPercent',mean(result.evmRMSPercent,'all'), ...
    'frequencyOffsetHz',result.frequencyOffsetHz,'timingOffset',result.timingOffset);
end
function print_stage(name,value)
fprintf('%-31s errors=%g EVMmean=%.6g%%\n',name,value.rawErrorTotal,value.evmMeanPercent);
end
function value=nmse_db(a,b)
value=10*log10(sum(abs(double(a(:))-double(b(:))).^2)/(sum(abs(double(b(:))).^2)+eps));
end
function wait_blocks(n)
t=tic;
while true
    status=type1_yunsdr_rx_mex('status');
    if status(2)>=n, return; end
    if toc(t)>10,error('type1:StageCompare','RX ring did not fill.');end
    pause(.005);
end
end
function value=env_positive(name,defaultValue)
value=str2double(getenv(name));
if ~isfinite(value)||value<=0,value=defaultValue;end
end
