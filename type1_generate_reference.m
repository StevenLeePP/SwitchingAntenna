function package = type1_generate_reference(channelCoding)
%TYPE1_GENERATE_REFERENCE Generate the shared Type-A TX/RX MAT package.
%  type1_generate_reference() builds the default uncoded waveform.
%  type1_generate_reference('none') explicitly selects uncoded QPSK.
%  type1_generate_reference('convolutional') selects the legacy K=7 R=1/2
%  terminated convolutional code. TX and RX then load the same MAT file.

cfg = type1_config();
if nargin >= 1 && ~isempty(channelCoding)
    cfg.channelCoding = validatestring(lower(string(channelCoding)), ...
        {'none', 'convolutional'});
    cfg.channelCoding = char(cfg.channelCoding);
end
package = type1_build_package(cfg);
save(cfg.referenceFile, 'package', '-v7.3');
info = dir(cfg.referenceFile);
fprintf('Saved shared reference: %s (%.2f MiB)\n', ...
    cfg.referenceFile, info.bytes / 2^20);
end
