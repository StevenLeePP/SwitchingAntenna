%% TYPE1_VALIDATE_FRAME_BATCH Compare batch-frame MEX against slot path.
clear; clc;
sourceDir=fileparts(mfilename('fullpath')); addpath(sourceDir);
if exist('type1_decode_frame_grid_mex','file')~=3, type1_build_frame_mex(); end
package=type1_load_package(); cfg=package.cfg;
iqFile=newest_file(fullfile(sourceDir,'data'), '*_virtual30_csingle_iq4.bin');
rx30=read_iq(iqFile,cfg.nRxChannels);
firstSlot=cfg.dataSlots(1);
acq=type1_analyze_fast(rx30,package,firstSlot,'forcePSS',true);
frameSamples=round(cfg.frameDurationSec*cfg.txSampleRate);
frame=rx30(acq.timingOffset+(1:frameSamples),:);
batch=type1_decode_frame_batch(frame,package,acq.frequencyOffsetHz);

slotErrors=zeros(numel(cfg.dataSlots),cfg.nLayers);
slotEvm=zeros(numel(cfg.dataSlots),cfg.nLayers);
rFirst=[];
for s=1:numel(cfg.dataSlots)
    r=type1_analyze_fast(rx30,package,cfg.dataSlots(s), ...
        'forcePSS',false,'syncState',acq.syncState, ...
        'trackedTimingOffset',acq.timingOffset, ...
        'returnChannel',s==1);
    slotErrors(s,:)=r.rawBitErrors; slotEvm(s,:)=r.evmRMSPercent;
    if s==1, rFirst=r; end
end
fprintf('\n========== Frame batch validation ==========\n');
fprintf('Batch CFO/OFDM/PHY/total ms: %.3f / %.3f / %.3f / %.3f\n', ...
    batch.cfoMs,batch.ofdmMs,batch.phyMs,batch.elapsedMs);
fprintf('Bit errors equal: %d; max EVM difference: %.4f %%\n', ...
    isequal(slotErrors,batch.rawBitErrors),max(abs(slotEvm-batch.evmRMSPercent),[],'all'));
slotH=permute(rFirst.channel(:,1,:,:),[1 3 4 2]);
batchH=batch.hFrequency(:,:,:,1);
carrier0=type1_carrier_config(cfg,0);
fullGrid=nrOFDMDemodulate(carrier0,frame.*exp(-1j*2*pi*acq.frequencyOffsetHz/cfg.txSampleRate*(0:frameSamples-1).'), ...
    'Nfft',cfg.nfft,'SampleRate',cfg.txSampleRate,'CarrierFrequency',0);
slotSamples=frameSamples/cfg.slotsPerFrame; carrier1=type1_carrier_config(cfg,cfg.dataSlots(1));
slotWave=rx30(acq.timingOffset+cfg.dataSlots(1)*slotSamples+(1:slotSamples),:) .* ...
    exp(-1j*2*pi*acq.frequencyOffsetHz/cfg.txSampleRate*(0:slotSamples-1).');
oneGrid=nrOFDMDemodulate(carrier1,slotWave,'Nfft',cfg.nfft,'SampleRate',cfg.txSampleRate,'CarrierFrequency',0);
fullSlice=fullGrid(:,cfg.dataSlots(1)*14+(1:14),:);
fprintf('Full-grid vs one-slot-grid NMSE: %.2f dB\n',10*log10(sum(abs(fullSlice-oneGrid).^2,'all')/(sum(abs(oneGrid).^2,'all')+eps)));
fprintf('First-slot H NMSE: %.2f dB; errors batch/slot first=[%s]/[%s]\n', ...
    10*log10(sum(abs(batchH-slotH).^2,'all')/(sum(abs(slotH).^2,'all')+eps)), ...
    num2str(batch.rawBitErrors(1,:)),num2str(slotErrors(1,:)));
assert(isequal(slotErrors,batch.rawBitErrors),'type1:FrameBatch','Batch bit errors differ.');
% Full-frame nrOFDMDemodulate uses a frame phase reference while the old
% path invokes it per slot.  Hard bits must match exactly; EVM is accepted
% within 2 percentage points as a phase-reference diagnostic difference.
assert(max(abs(slotEvm-batch.evmRMSPercent),[],'all')<2.0, ...
    'type1:FrameBatch','Batch EVM differs excessively.');
disp('Frame batch validation PASSED.');
function f=newest_file(d,p),x=dir(fullfile(d,p));assert(~isempty(x));[~,i]=max([x.datenum]);f=fullfile(x(i).folder,x(i).name);end
function x=read_iq(f,n),id=fopen(f,'rb');c=onCleanup(@()fclose(id));a=fread(id,inf,'single=>single');assert(mod(numel(a),2*n)==0);x=reshape(complex(a(1:2:end),a(2:2:end)),[],n);end
