function report = type1_run_phase2_rx_lo_statistics()
%TYPE1_RUN_PHASE2_RX_LO_STATISTICS Paper-stop RX-LO topology grid.
p=type1_load_package(); sigmaDeg=[.5 1 2 4 8]; bandwidthHz=[10e3 100e3 1e6];
names=["common" "commonCPE" "independent" "independentCPE"];
maxRealizations=16; minErrors=100; minBits=1e7; bitsPerRealization= ...
    numel(p.cfg.dataSlots)*p.nInfoBitsPerSlotLayer*p.cfg.nLayers;
baseSim=isolated_config(); signalSeeds=20261201+(0:maxRealizations-1);
loSeeds=20261291+(0:maxRealizations-1);

% The off reference is generated once; every grid point uses the same seed prefix.
offErrorByRealization=zeros(maxRealizations,1); offEvmSqByRealization=zeros(maxRealizations,1);
offEvmCountByRealization=zeros(maxRealizations,1);
for n=1:maxRealizations
    sim=with_lo(baseSim,"off",0,100e3,loSeeds(n));
    link=type1_offline_link(p,sim,RandStream('mt19937ar','Seed',signalSeeds(n)));
    r=type1_analyze(link.virtualRx30,p);
    offErrorByRealization(n)=sum(r.infoBitErrors,'all');
    offEvmSqByRealization(n)=sum(r.evmRMSPercent.^2,'all');
    offEvmCountByRealization(n)=numel(r.evmRMSPercent);
end

nSigma=numel(sigmaDeg); nBandwidth=numel(bandwidthHz); nReceiver=numel(names);
errors=zeros(nSigma,nBandwidth,nReceiver); bits=zeros(nSigma,nBandwidth);
evmSq=zeros(nSigma,nBandwidth,nReceiver); evmCount=zeros(nSigma,nBandwidth,nReceiver);
realizations=zeros(nSigma,nBandwidth); acquisitionFailure=false(nSigma,nBandwidth,maxRealizations,2);
for b=1:nBandwidth
    for a=1:nSigma
        localErrors=zeros(1,nReceiver); localEvmSq=zeros(1,nReceiver); localEvmCount=zeros(1,nReceiver);
        used=0;
        while used<maxRealizations && ~(all(localErrors>=minErrors) || used*bitsPerRealization>=minBits)
            used=used+1; commonSim=with_lo(baseSim,"common",sigmaDeg(a),bandwidthHz(b),loSeeds(used));
            independentSim=with_lo(baseSim,"independent",sigmaDeg(a),bandwidthHz(b),loSeeds(used));
            try
                lc=type1_offline_link(p,commonSim,RandStream('mt19937ar','Seed',signalSeeds(used)));
                rc=type1_analyze(lc.virtualRx30,p); rcpe=type1_apply_symbol_cpe(rc,p);
            catch exception
                acquisitionFailure(a,b,used,1)=true;
                error('type1:RxLoGridAcquisition','Common acquisition failed at sigma=%g B=%g seed=%d: %s', ...
                    sigmaDeg(a),bandwidthHz(b),signalSeeds(used),exception.message);
            end
            try
                li=type1_offline_link(p,independentSim,RandStream('mt19937ar','Seed',signalSeeds(used)));
                ri=type1_analyze(li.virtualRx30,p); ricpe=type1_apply_symbol_cpe(ri,p);
            catch exception
                acquisitionFailure(a,b,used,2)=true;
                error('type1:RxLoGridAcquisition','Independent acquisition failed at sigma=%g B=%g seed=%d: %s', ...
                    sigmaDeg(a),bandwidthHz(b),signalSeeds(used),exception.message);
            end
            each={rc rcpe ri ricpe};
            for receiver=1:nReceiver
                localErrors(receiver)=localErrors(receiver)+sum(each{receiver}.infoBitErrors,'all');
                localEvmSq(receiver)=localEvmSq(receiver)+sum(each{receiver}.evmRMSPercent.^2,'all');
                localEvmCount(receiver)=localEvmCount(receiver)+numel(each{receiver}.evmRMSPercent);
            end
            fprintf('B=%g sigma=%g run=%d errors=[%s]\n',bandwidthHz(b),sigmaDeg(a),used,num2str(localErrors));
        end
        errors(a,b,:)=localErrors; bits(a,b)=used*bitsPerRealization;
        evmSq(a,b,:)=localEvmSq; evmCount(a,b,:)=localEvmCount; realizations(a,b)=used;
    end
end
ber=errors./bits; evm=sqrt(evmSq./evmCount); zeroUpper95=-log(.05)./bits;
hLo1EveryPoint=all(errors(:,:,1)<=errors(:,:,3),'all');

% H-LO3 mechanism diagnostic: independent+CPE incremental EVM power vs sigma^2.
hLo3Slope=zeros(1,nBandwidth); hLo3R2=zeros(1,nBandwidth);
for b=1:nBandwidth
    pick=find(sigmaDeg<=4); x=deg2rad(sigmaDeg(pick)).^2; y=zeros(size(x));
    for k=1:numel(pick)
        a=pick(k); n=realizations(a,b);
        offPower=sum(offEvmSqByRealization(1:n))/sum(offEvmCountByRealization(1:n))/1e4;
        y(k)=max((evm(a,b,4)/100)^2-offPower,0);
    end
    hLo3Slope(b)=(x*y')/(x*x'); prediction=hLo3Slope(b)*x;
    hLo3R2(b)=1-sum((y-prediction).^2)/max(sum((y-mean(y)).^2),eps);
end

targetBer=1e-3; independentBracket=nan(nBandwidth,2); commonCpeBracket=nan(nBandwidth,2);
relaxationLowerBound=nan(1,nBandwidth); identifiable=false(1,nBandwidth);
for b=1:nBandwidth
    independentBracket(b,:)=threshold_bracket(sigmaDeg,ber(:,b,3),targetBer);
    commonCpeBracket(b,:)=threshold_bracket(sigmaDeg,ber(:,b,2),targetBer);
    if isfinite(independentBracket(b,2)) && commonCpeBracket(b,1)>0
        relaxationLowerBound(b)=commonCpeBracket(b,1)/independentBracket(b,2);
    end
    identifiable(b)=all(isfinite(independentBracket(b,:))) && all(isfinite(commonCpeBracket(b,:)));
end

report=struct('sigmaDeg',sigmaDeg,'bandwidthHz',bandwidthHz,'receiverNames',names, ...
    'signalSeeds',signalSeeds,'loSeeds',loSeeds,'minErrors',minErrors,'minBits',minBits, ...
    'maxRealizations',maxRealizations,'bitsPerRealization',bitsPerRealization, ...
    'realizations',realizations,'errors',errors,'bits',bits,'ber',ber, ...
    'zeroErrorUpper95',zeroUpper95,'evmRmsPercent',evm, ...
    'offErrorByRealization',offErrorByRealization,'offEvmSqByRealization',offEvmSqByRealization, ...
    'offEvmCountByRealization',offEvmCountByRealization, ...
    'acquisitionFailure',acquisitionFailure,'hLo1EveryPoint',hLo1EveryPoint, ...
    'hLo3Slope',hLo3Slope,'hLo3R2',hLo3R2,'targetBer',targetBer, ...
    'thresholdBracketMeaning','[largest passing sigma, first failing sigma above it]; Inf means no failure through 8 deg', ...
    'independentThresholdBracketDeg',independentBracket, ...
    'commonCpeThresholdBracketDeg',commonCpeBracket, ...
    'relaxationLowerBound',relaxationLowerBound,'relaxationIdentifiable',identifiable, ...
    'simBase',baseSim);
root=getenv('TYPE1_OFFLINE_OUTPUT_ROOT'); if isempty(root),root=tempdir;end
out=fullfile(root,['type1_phase2_rx_lo_statistics_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(out); report.outputDir=out;
plot_topology(report,fullfile(out,'phase2_rx_lo_topology.png'));
save(fullfile(out,'phase2_rx_lo_statistics.mat'),'report','-v7.3');
fprintf('RX-LO grid H-LO1=%d, H-LO3 R2=[%s], brackets independent/common=[%s]/[%s], saved: %s\n', ...
    hLo1EveryPoint,num2str(hLo3R2,'%.3f '),num2str(independentBracket), ...
    num2str(commonCpeBracket),out);
end

function bracket=threshold_bracket(sigma,ber,target)
pass=ber(:).'<target | ber(:).'==target;
if ~any(pass), bracket=[0 min(sigma)]; return; end
lower=max(sigma(pass)); above=sigma(~pass & sigma>lower);
if isempty(above), upper=Inf; else, upper=min(above); end
bracket=[lower upper];
end

function plot_topology(report,path)
f=figure('Visible','off','Position',[100 100 1500 430]);
for b=1:numel(report.bandwidthHz)
    subplot(1,numel(report.bandwidthHz),b); hold on;
    upper=repmat(report.zeroErrorUpper95(:,b),1,3);
    values=[report.ber(:,b,3) report.ber(:,b,1) report.ber(:,b,2)];
    semilogy(report.sigmaDeg,max(values,upper),'-o','LineWidth',1.4);
    yline(report.targetBer,'--k','BER=10^{-3}'); grid on;
    xlabel('\sigma_\phi RMS (degree)'); ylabel('BER / zero-error 95% upper');
    title(sprintf('B_{PLL} = %g kHz',report.bandwidthHz(b)/1e3));
    legend('independent 4-LO','common 1-LO','common 1-LO + CPE','target','Location','northwest');
end
exportgraphics(f,path,'Resolution',180); close(f);
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

function s=with_lo(s,mode,sigmaDeg,bandwidthHz,seed)
s.rxLo=struct('mode',string(mode),'phaseRmsDeg',sigmaDeg,'bandwidthHz',bandwidthHz, ...
    'seed',seed,'recordTimeSeries',false);
end
