function package = type1_load_package()
% TYPE1_LOAD_PACKAGE Load and validate the shared TX/RX reference MAT file.
%  Errors if the file is missing or its format version mismatches.
%  Run type1_generate_reference first to create the MAT file.

cfg = type1_config();
if ~exist(cfg.referenceFile, 'file')
    error('type1:MissingReference', ...
        'Missing %s. Run type1_generate_reference first.', ...
        cfg.referenceFile);
end
loaded = load(cfg.referenceFile, 'package');
package = loaded.package;

% Cross-check that the MAT file was built with the same source version
assert(strcmp(package.formatVersion, cfg.formatVersion), ...
    'Shared reference format does not match this source version.');
assert(isequal(package.cfg.dmrsPortSet, 0:3));
assert(strcmp(package.cfg.pdschMappingType, 'A'));
assert(isfield(package, 'channelCoding'));
assert(any(strcmp(package.channelCoding, {'none', 'convolutional'})));
end
