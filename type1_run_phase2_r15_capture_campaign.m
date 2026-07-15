function manifest = type1_run_phase2_r15_capture_campaign(options)
%TYPE1_RUN_PHASE2_R15_CAPTURE_CAMPAIGN Acquire the preregistered OTA set.
%   This function deliberately delegates every segment to the existing
%   PSS/PBCH/EVM-gated capture routine.  Reopening the RX for each segment
%   makes the five segments independent RX-start observations and prevents
%   overlapping snapshots from masquerading as replication.

arguments
    options.rxGains (1,:) double = [25 30 35]
    options.segmentsPerGain (1,1) double {mustBeInteger,mustBePositive} = 5
    options.outputRoot (1,1) string = ""
end
assert(numel(options.rxGains)>=2,'type1:R15GainGrid', ...
    'R15 requires at least two RX-gain settings.');
cfg=type1_config();
if strlength(options.outputRoot)==0
    options.outputRoot=fullfile(cfg.dataRoot, ...
        ['type1_r15_ota_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
end
if ~exist(options.outputRoot,'dir'),mkdir(options.outputRoot);end

entries=repmat(struct('rxGainDb',NaN,'segment',NaN,'raw122File',"", ...
    'metaFile',"",'sequence',NaN,'timestampFirst',NaN,'timestampLast',NaN, ...
    'idealEVMPercent',NaN,'idealRawBER',NaN,'idealSNRNullDb',NaN), ...
    numel(options.rxGains)*options.segmentsPerGain,1);
index=0;
for gain=options.rxGains
    for segment=1:options.segmentsPerGain
        index=index+1;
        tag=sprintf('r15_g%g_s%02d',gain,segment);
        fprintf('\nR15 capture %d/%d: gain %.1f dB, segment %d/%d\n', ...
            index,numel(entries),gain,segment,options.segmentsPerGain);
        capture=type1_capture_ota_valid_raw122(rxGain=gain,fileTag=tag);
        [~,rawName,rawExt]=fileparts(capture.raw122File);
        [~,metaName,metaExt]=fileparts(capture.metaFile);
        rawTarget=fullfile(options.outputRoot,[rawName rawExt]);
        metaTarget=fullfile(options.outputRoot,[metaName metaExt]);
        assert(movefile(capture.raw122File,rawTarget),'type1:R15Move', ...
            'Could not move accepted raw IQ into campaign directory.');
        assert(movefile(capture.metaFile,metaTarget),'type1:R15Move', ...
            'Could not move accepted metadata into campaign directory.');
        result=capture.idealResult;
        entries(index)=struct('rxGainDb',gain,'segment',segment, ...
            'raw122File',string(rawTarget),'metaFile',string(metaTarget), ...
            'sequence',double(capture.sequence), ...
            'timestampFirst',double(capture.timestamps(1)), ...
            'timestampLast',double(capture.timestamps(end)), ...
            'idealEVMPercent',mean(result.evmRMSPercent,'all','omitnan'), ...
            'idealRawBER',mean(result.rawBER,'all','omitnan'), ...
            'idealSNRNullDb',median(result.snrNullDb,'all','omitnan'));
        save(fullfile(options.outputRoot,'r15_capture_manifest.mat'), ...
            'entries','options','-v7.3');
    end
end
manifest=struct('createdAt',datetime('now'),'entries',entries, ...
    'options',options,'outputRoot',options.outputRoot);
save(fullfile(options.outputRoot,'r15_capture_manifest.mat'),'manifest','-v7.3');
fprintf('\nR15 capture campaign complete: %d qualified segments in %s\n', ...
    numel(entries),options.outputRoot);
end
