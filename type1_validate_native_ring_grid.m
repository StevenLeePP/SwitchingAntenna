function result = type1_validate_native_ring_grid()
%TYPE1_VALIDATE_NATIVE_RING_GRID Compare one PSS-locked native C frame
% against MATLAB using the same raw ring data, FFT window and CFO phase.

p=type1_load_package(); c=p.cfg;
if exist('type1_yunsdr_rx_mex','file')~=3, type1_build_rx_mex(); end
if exist('type1_decode_frame_grid_mex','file')~=3, type1_build_frame_mex(); end
ring=round(env_positive('TYPE1_FIFO_RING_BLOCKS',2048));
block=round(c.rxSampleRate*1e-3);
type1_yunsdr_rx_mex('open',c.deviceString,c.rxSampleRate,c.centerFrequencyHz,c.rxGain);
cleanup=onCleanup(@close_radio); %#ok<NASGU>
type1_yunsdr_rx_mex('switchphase',c.switchPhaseOffset);
type1_yunsdr_rx_mex('start',block,ring); wait_blocks(40);

% A 40-ms snapshot leaves several PSS candidates; acquisition chooses one
% that contains all active slots 0:10.  directgrid then finds that exact raw
% timestamp independently in the native ring.
[iq,timestamps]=type1_yunsdr_rx_mex('snapshotvirtual',40);
acq=type1_analyze_fast(iq,p,c.dataSlots(1),'forcePSS',true, ...
    'snapshotStartRawTimestamp',timestamps(1),'computeSNR',false, ...
    'computeCondition',false);
assert(acq.syncState.valid && acq.syncState.frameStartRawTimestamp~=0, ...
    'type1:NativeGrid','PSS did not produce a usable raw timestamp.');
slotSamples=round(c.frameDurationSec*c.txSampleRate/c.slotsPerFrame);
activeSamples=(max(c.dataSlots)+1)*slotSamples;
start=acq.timingOffset+1;
assert(start>=1 && start+activeSamples-1<=size(iq,1), ...
    'type1:NativeGrid','PSS frame is not wholly contained in snapshot.');
cfo=double(acq.frequencyOffsetHz);
frame=single(iq(start:start+activeSamples-1,:));
phase=single((0:activeSamples-1).');
frame=frame.*exp(single(-1j*2*pi*cfo/c.txSampleRate).*phase);
matlabGrid=single(nrOFDMDemodulate(type1_carrier_config(c,0),frame, ...
    'Nfft',c.nfft,'SampleRate',c.txSampleRate,'CarrierFrequency',0, ...
    'CyclicPrefixFraction',1));
[nativeGrid,timingMs]=type1_yunsdr_rx_mex('directgrid', ...
    acq.syncState.frameStartRawTimestamp,cfo);
assert(isequal(size(nativeGrid),size(matlabGrid)), ...
    'type1:NativeGrid','Native and MATLAB grids have different dimensions.');

args={double(c.dataSlots(:)),p.dmrsIndices,p.dmrsSymbols,p.dataIndices, ...
    p.dataQPSK,p.codedBits,c.rzfRegularization};
[nativeErrors,nativeEvm,~,nativeH]=type1_decode_frame_grid_mex(nativeGrid,args{:});
[matlabErrors,matlabEvm,~,matlabH]=type1_decode_frame_grid_mex(matlabGrid,args{:});
gridNmseDb=nmse_db(nativeGrid,matlabGrid);
hNmseDb=nmse_db(nativeH,matlabH);
evmMaxDiff=max(abs(nativeEvm-matlabEvm),[],'all');
errorsEqual=isequal(nativeErrors,matlabErrors);
fprintf(['native-ring grid: grid NMSE=%.2f dB H NMSE=%.2f dB ', ...
    'EVMmaxDiff=%.9g rawBitErrorsEqual=%d extract=%.3fms fft=%.3fms\n'], ...
    gridNmseDb,hNmseDb,evmMaxDiff,errorsEqual,timingMs(1),timingMs(2));
result=struct('acq',acq,'gridNmseDb',gridNmseDb,'hNmseDb',hNmseDb, ...
    'evmMaxDiff',evmMaxDiff,'rawBitErrorsEqual',errorsEqual, ...
    'nativeErrors',nativeErrors,'matlabErrors',matlabErrors, ...
    'nativeEvm',nativeEvm,'matlabEvm',matlabEvm,'timingMs',timingMs);
assert(gridNmseDb < -75,'type1:NativeGrid','Native grid mismatches MATLAB.');
assert(errorsEqual,'type1:NativeGrid','Native-grid raw bit errors differ.');
assert(evmMaxDiff < 1e-4,'type1:NativeGrid','Native-grid EVM differs.');
    function close_radio()
        try,type1_yunsdr_rx_mex('stop');catch,end
        try,type1_yunsdr_rx_mex('close');catch,end
    end
end
function wait_blocks(n)
t=tic;
while true
    s=type1_yunsdr_rx_mex('status');
    if s(2)>=n, return; end
    if toc(t)>10, error('type1:NativeGrid','RX ring did not fill.'); end
    pause(.005);
end
end
function value=nmse_db(a,b)
value=10*log10(sum(abs(a-b).^2,'all')/(sum(abs(b).^2,'all')+eps));
end
function value=env_positive(name,defaultValue)
value=str2double(getenv(name));
if ~isfinite(value)||value<=0, value=defaultValue; end
end
