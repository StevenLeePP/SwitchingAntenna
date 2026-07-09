%% Force YunSDR cyclic TX off and close the hardware descriptor
%  Run after abnormal MATLAB termination or before a noise-floor test.
%  This explicitly disables the cyclic DMA and releases /dev/xdma0_*.
clear; clc;

sourceDir = fileparts(mfilename('fullpath'));
sdkDir = fileparts(sourceDir);
if ~libisloaded('libyunsdr_ss')
    loadlibrary(fullfile(sdkDir, 'libyunsdr_ss.so'), ...
        fullfile(sdkDir, 'yunsdr_api_ss.h'), ...
        'alias', 'libyunsdr_ss');
end

cfg = type1_config();
deviceString = libpointer('cstring', cfg.deviceString);
device = calllib('libyunsdr_ss', 'yunsdr_open_device', deviceString);
if isNull(device)
    error('type1:StopOpen', 'Could not open YunSDR TX device.');
end
cleanup = onCleanup(@() calllib( ...
    'libyunsdr_ss', 'yunsdr_close_device', device));

ret = calllib('libyunsdr_ss', 'yunsdr_tx_cyclic_enable', ...
    device, uint8(0), uint8(0));  % disable cyclic TX
if ret < 0
    error('type1:StopCyclic', ...
        'Could not disable cyclic TX; return code %d.', ret);
end
fprintf('YunSDR cyclic TX is explicitly disabled (ret=%d).\n', ret);
clear cleanup;
