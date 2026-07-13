function outputFile = type1_build_frame_mex()
sourceDir = fileparts(mfilename('fullpath'));
mex('-R2018a','-O','CFLAGS=$CFLAGS -O3 -mavx2 -mfma -mpopcnt', ...
    '-output',fullfile(sourceDir,'type1_decode_frame_grid_mex'), ...
    fullfile(sourceDir,'type1_decode_frame_grid_mex.c'));
outputFile = fullfile(sourceDir,['type1_decode_frame_grid_mex.' mexext]);
fprintf('Built %s\n',outputFile);
end
