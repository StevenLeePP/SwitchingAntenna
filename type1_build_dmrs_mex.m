function outputFile = type1_build_dmrs_mex()
sourceDir = fileparts(mfilename('fullpath'));
mex('-R2018a','-O','CFLAGS=$CFLAGS -O3 -mavx2 -mfma', ...
    '-output',fullfile(sourceDir,'type1_dmrs_type1_mex'), ...
    fullfile(sourceDir,'type1_dmrs_type1_mex.c'));
outputFile = fullfile(sourceDir,['type1_dmrs_type1_mex.' mexext]);
fprintf('Built %s\n',outputFile);
end
