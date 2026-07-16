function result = type1_run_phase3_part_a()
%TYPE1_RUN_PHASE3_PART_A Run and save the frozen R16 Part-A regressions.

report = type1_validate_phase3_part_a();
root = string(getenv('TYPE1_PHASE3_OUTPUT_ROOT'));
if strlength(root) == 0
    root = fullfile(tempdir, 'type1_phase3');
end
if ~isfolder(root), mkdir(root); end
outputDirectory = fullfile(root, ...
    ['type1_phase3_part_a_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(outputDirectory);
result = struct('report', report, 'outputDirectory', outputDirectory, ...
    'createdAt', datetime('now','TimeZone','local'), ...
    'matlabVersion', version);
save(fullfile(outputDirectory, 'phase3_part_a_r16.mat'), 'result', '-v7.3');
fprintf('Phase-3 Part-A R16 audit saved: %s\n', outputDirectory);
end
