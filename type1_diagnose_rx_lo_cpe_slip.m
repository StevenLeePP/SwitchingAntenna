function report = type1_diagnose_rx_lo_cpe_slip()
%TYPE1_DIAGNOSE_RX_LO_CPE_SLIP Genie-only diagnosis of the slow-LO outlier.
p=type1_load_package(); s=isolated_config(); signalSeed=20261215; loSeed=20261305;
s.rxLo=struct('mode',"common",'phaseRmsDeg',8,'bandwidthHz',10e3, ...
    'seed',loSeed,'recordTimeSeries',false);
link=type1_offline_link(p,s,RandStream('mt19937ar','Seed',signalSeed));
base=type1_analyze(link.virtualRx30,p);
memoryless=type1_apply_symbol_cpe(base,p,"memoryless");
tracked=type1_apply_symbol_cpe(base,p,"tracked");
cfg=p.cfg; oracle=nan(cfg.symbolsPerSlot,numel(cfg.dataSlots));
phaseError=nan(size(oracle)); errorsBySymbol=zeros(size(oracle)); bitsBySymbol=zeros(size(oracle));
oracleErrorsBySymbol=zeros(size(oracle));
for slotIndex=1:numel(cfg.dataSlots)
    first=double(p.dataIndices(:,1,slotIndex));
    [~,symbol]=ind2sub([12*cfg.nRB cfg.symbolsPerSlot cfg.nLayers],first);
    for l=unique(symbol).'
        rows=find(symbol==l); z=reshape(base.postCompData(rows,slotIndex,:),[],1);
        reference=reshape(double(p.dataQPSK(rows,slotIndex,:)),[],1);
        oracle(l,slotIndex)=angle(sum(conj(reference).*z));
        phaseError(l,slotIndex)=wrap_pi(memoryless.cpeRad(l,slotIndex)-oracle(l,slotIndex));
        for layer=1:cfg.nLayers
            corrected=memoryless.postCompData(rows,slotIndex,layer);
            bits=logical(nrSymbolDemodulate(corrected,cfg.modulation,'DecisionType','hard'));
            bitRows=reshape([2*rows-1 2*rows].',[],1);
            expected=p.codedBits(bitRows,slotIndex,layer);
            errorsBySymbol(l,slotIndex)=errorsBySymbol(l,slotIndex)+sum(bits~=expected);
            oracleCorrected=base.postCompData(rows,slotIndex,layer).*exp(-1j*oracle(l,slotIndex));
            oracleBits=logical(nrSymbolDemodulate(oracleCorrected,cfg.modulation,'DecisionType','hard'));
            oracleErrorsBySymbol(l,slotIndex)=oracleErrorsBySymbol(l,slotIndex)+sum(oracleBits~=expected);
            bitsBySymbol(l,slotIndex)=bitsBySymbol(l,slotIndex)+numel(bits);
        end
    end
end
valid=isfinite(phaseError); slip=valid & abs(phaseError)>pi/4;
totalErrors=sum(errorsBySymbol,'all'); slipErrors=sum(errorsBySymbol(slip),'all');
report=struct('signalSeed',signalSeed,'loSeed',loSeed,'sigmaDeg',8,'bandwidthHz',10e3, ...
    'baseErrors',sum(base.infoBitErrors,'all'), ...
    'memorylessErrors',sum(memoryless.infoBitErrors,'all'), ...
    'trackedErrors',sum(tracked.infoBitErrors,'all'), ...
    'memorylessCpeRad',memoryless.cpeRad,'trackedCpeRad',tracked.cpeRad, ...
    'oracleCpeRad',oracle,'memorylessMinusOracleRad',phaseError, ...
    'slipThresholdRad',pi/4,'slipMask',slip,'validSymbolCount',sum(valid,'all'), ...
    'slipSymbolCount',sum(slip,'all'),'errorsBySymbol',errorsBySymbol, ...
    'oracleErrorsBySymbol',oracleErrorsBySymbol,'oracleTrackedErrors',sum(oracleErrorsBySymbol,'all'), ...
    'bitsBySymbol',bitsBySymbol,'errorsInSlipSymbols',slipErrors, ...
    'fractionErrorsInSlipSymbols',slipErrors/max(totalErrors,1),'genieDiagnosticOnly',true);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_rx_lo_cpe_slip_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out; save(fullfile(out,'phase2_rx_lo_cpe_slip.mat'),'report','-v7.3');
fprintf('RX-LO CPE slip: base/memoryless/tracked/oracle errors=%d/%d/%d/%d, slips=%d/%d symbols, errors in slips=%d/%d (%.3f), saved: %s\n', ...
    report.baseErrors,report.memorylessErrors,report.trackedErrors,report.oracleTrackedErrors, ...
    report.slipSymbolCount,report.validSymbolCount, ...
    slipErrors,totalErrors,report.fractionErrorsInSlipSymbols,out);
end

function value=wrap_pi(value)
value=mod(value+pi,2*pi)-pi;
end

function s=isolated_config()
s=type1_offline_sim_config(); s.frames=1; s.snrDb=20; s.commonCfoHz=0;
s.userCfoHz=zeros(1,4); s.userTimingSamples=zeros(1,4); s.userPowerDb=zeros(1,4);
s.userPhaseNoiseStdRadPerSample=zeros(1,4); s.channelModel="flat";
s.switch.isolationDb=Inf; s.switch.settlingRiseNs=0; s.switch.transitionJitterStdPs=0;
s.switch.samplingBoundaryJitterStdPs=0; s.switch.settlingFastJitterStdFraction=0;
cfg=type1_config(); s.prefixSamples=round(cfg.txSampleRate*cfg.frameDurationSec/20);
s.suffixSamples=0;
end
