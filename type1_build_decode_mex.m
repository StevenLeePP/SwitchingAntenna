function outputFile = type1_build_decode_mex()
%TYPE1_BUILD_DECODE_MEX Build the fixed 4x4 RZF/QPSK AVX2/FMA kernel.
sourceDir = fileparts(mfilename('fullpath'));
sourceFile = fullfile(sourceDir, 'type1_rzf_qpsk_mex.c');
outputFile = fullfile(sourceDir, ['type1_rzf_qpsk_mex.' mexext]);
mex('-R2018a', '-O', ...
    'CFLAGS=$CFLAGS -O3 -mavx2 -mfma -mpopcnt', ...
    '-output', fullfile(sourceDir, 'type1_rzf_qpsk_mex'), sourceFile);
fprintf('Built %s\n', outputFile);
end
