%% TYPE1_VALIDATE_DMRS_MEX Compare fixed Type-1 DM-RS MEX against Toolbox.
clear; clc;
sourceDir = fileparts(mfilename('fullpath')); addpath(sourceDir);
if exist('type1_dmrs_type1_mex','file') ~= 3, type1_build_dmrs_mex(); end
package = type1_load_package();
slot = package.cfg.dataSlots(ceil(numel(package.cfg.dataSlots)/2));
iqFile = newest_file(fullfile(sourceDir,'data'), '*_virtual30_csingle_iq4.bin');
rx30 = read_iq(iqFile, package.cfg.nRxChannels);
acq = type1_analyze_fast(rx30,package,slot,'forcePSS',true);
args = {'collectTiming',true,'forcePSS',false,'syncState',acq.syncState, ...
    'trackedTimingOffset',acq.timingOffset,'returnChannel',true};
basePkg = package; basePkg.cfg.fastUseType1DMRSMEX = false;
base = type1_analyze_fast(rx30,basePkg,slot,args{:});
mexPkg = package; mexPkg.cfg.fastUseType1DMRSMEX = true;
fast = type1_analyze_fast(rx30,mexPkg,slot,args{:});
nmse = mean(abs(base.channel-fast.channel).^2,'all') / mean(abs(base.channel).^2,'all');
fprintf('\n========== Type-A Type-1 DM-RS MEX validation ==========\n');
fprintf('H NMSE dB           : %.2f dB\n',10*log10(nmse+eps));
fprintf('Toolbox/MEX DMRS ms : %.3f / %.3f\n',base.stageTimesMs.dmrsChannelEstimate,fast.stageTimesMs.dmrsChannelEstimate);
fprintf('Toolbox/MEX BER     : [%s] / [%s]\n',num2str(base.rawBER),num2str(fast.rawBER));
fprintf('Toolbox/MEX EVM %%   : [%s] / [%s]\n',num2str(base.evmRMSPercent,'%.3f '),num2str(fast.evmRMSPercent,'%.3f '));
assert(all(fast.rawBER==0),'type1:DMRSValidation','MEX DM-RS BER is nonzero.');
assert(max(abs(fast.evmRMSPercent-base.evmRMSPercent)) < 1.5, ...
    'type1:DMRSValidation','MEX DM-RS EVM differs excessively.');
disp('Type-A Type-1 DM-RS MEX validation PASSED.');
function f=newest_file(d,p),x=dir(fullfile(d,p));assert(~isempty(x));[~,i]=max([x.datenum]);f=fullfile(x(i).folder,x(i).name);end
function x=read_iq(f,n),id=fopen(f,'rb');c=onCleanup(@()fclose(id));a=fread(id,inf,'single=>single');assert(mod(numel(a),2*n)==0);x=reshape(complex(a(1:2:end),a(2:2:end)),[],n);end
