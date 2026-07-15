function result = type1_analyze_ici_decision_feedback(rx30, package, halfWidth, iterations, feedbackMode, userCfoCompensation, userTimingCompensation, kernelBanks, channelTracking, kernelConstraint, receivedDrive30)
%TYPE1_ANALYZE_ICI_DECISION_FEEDBACK Per-symbol common-kernel ICI cancellation.
%   First-pass standard RZF decisions create v=Hhat*xhat at each virtual RX.
%   Within each data OFDM symbol, fit e=y-v ~= sum_{|u|<=Q} m[u]v[k-u].
%   m is deliberately one common scalar kernel for all four virtual RX, a
%   constrained hypothesis implied by the shared physical switch.  Even/odd
%   subcarrier cross-fitting estimates a kernel on one parity and corrects
%   the other, preventing in-sample residual fitting from being mistaken for
%   BER gain.  The first pass is always hard QPSK feedback.  In later passes,
%   feedbackMode='soft' (the default) uses the RZF equalizer output directly;
%   'hard' remodulates its hard decisions.  Later iterations always reconstruct
%   from the original y (not an already-cancelled y), so the same estimated ICI
%   is not subtracted twice.  This is a research receiver, not OTA code.

if nargin < 3, halfWidth = 6; end
if nargin < 4, iterations = 1; end
if nargin < 5, feedbackMode = "soft"; end
if nargin < 6, userCfoCompensation = false; end
if nargin < 7, userTimingCompensation = false; end
if nargin < 8, kernelBanks = "single"; end
if nargin < 9, channelTracking = "fixed"; end
if nargin < 10, kernelConstraint = "free"; end
if nargin < 11, receivedDrive30 = []; end
assert(isscalar(halfWidth) && halfWidth >= 0 && halfWidth == round(halfWidth), ...
    'type1:ICIDFWidth', 'halfWidth must be a nonnegative integer.');
assert(isscalar(iterations) && iterations >= 1 && iterations == round(iterations), ...
    'type1:ICIDFIterations', 'iterations must be a positive integer.');
feedbackMode=lower(string(feedbackMode));
kernelBanks=lower(string(kernelBanks));
channelTracking=lower(string(channelTracking));
kernelConstraint=lower(string(kernelConstraint));
assert(any(feedbackMode==["soft" "hard"]), 'type1:ICIDFFeedback', ...
    'feedbackMode must be soft or hard.');
assert(any(kernelBanks==["single" "double"]), 'type1:ICIDFBanks', ...
    'kernelBanks must be single or double.');
assert(any(channelTracking==["fixed" "ddce"]), 'type1:ICIDFChannelTracking', ...
    'channelTracking must be fixed or ddce.');
assert(any(kernelConstraint==["free" "physical" "received"]), 'type1:ICIDFKernelConstraint', ...
    'kernelConstraint must be free, physical, or received.');
assert(kernelConstraint~="physical" || kernelBanks=="double", ...
    'type1:ICIDFPhysicalBanks','physical kernelConstraint requires kernelBanks=double.');
assert(kernelConstraint~="received" || kernelBanks=="single", ...
    'type1:ICIDFReceivedBanks','received kernelConstraint requires kernelBanks=single.');
assert(kernelConstraint~="received" || isequal(size(receivedDrive30),size(rx30)), ...
    'type1:ICIDFReceivedDrive','receivedDrive30 must match rx30 for received constraint.');
assert(isscalar(userCfoCompensation) && (islogical(userCfoCompensation) || isnumeric(userCfoCompensation)), ...
    'type1:ICIDFCFO', 'userCfoCompensation must be a scalar logical flag.');
assert(strcmp(package.channelCoding, 'none'), ...
    'type1:ICIDFCoding', 'Current baseline is defined for uncoded QPSK.');
base = type1_analyze(rx30, package);
cfg = package.cfg; nRx = size(rx30, 2); nLayers = cfg.nLayers;
assert(nRx >= nLayers, 'type1:ICIDFRx', 'ICI DF requires nRx >= nLayers.');

fs = cfg.txSampleRate; frameN = round(cfg.frameDurationSec*fs);
frame = double(rx30(base.timingOffset+(1:frameN),:));
frame = frame .* exp(-1j*2*pi*base.frequencyOffsetHz*(0:frameN-1).'/fs);
carrier = type1_carrier_config(cfg,0);
grid = nrOFDMDemodulate(carrier,frame,'Nfft',cfg.nfft, ...
    'SampleRate',fs,'CarrierFrequency',0);
grid = grid(:,1:cfg.symbolsPerFrame,:);
if kernelConstraint=="received"
    driveFrame=double(receivedDrive30(base.timingOffset+(1:frameN),:));
    driveFrame=driveFrame.*exp(-1j*2*pi*base.frequencyOffsetHz*(0:frameN-1).'/fs);
    driveGrid=nrOFDMDemodulate(carrier,driveFrame,'Nfft',cfg.nfft, ...
        'SampleRate',fs,'CarrierFrequency',0);
    driveGrid=driveGrid(:,1:cfg.symbolsPerFrame,:);
else
    driveGrid=[];
end

nSC = 12*cfg.nRB; nSlots = numel(cfg.dataSlots); nData = package.nDataREPerSlotLayer;
est=type1_estimate_user_channels(grid,package,userTimingCompensation,userCfoCompensation);
channels=est.channels; residualCfoHz=est.residualCfoHz; centers=est.symbolCenters;
unambiguousCfoHz=est.residualCfoUnambiguousHz; warningCfoHz=est.residualCfoWarningHz;
errors = zeros(nSlots,nLayers); evm = zeros(nSlots,nLayers);
conditionNumbers=[];
nBanks=1+(kernelBanks=="double");
if any(kernelConstraint==["physical" "received"]), nCoefficients=2*halfWidth+1;
else, nCoefficients=nBanks*(2*halfWidth+1); end
kernel = complex(nan(nCoefficients,cfg.symbolsPerSlot,nSlots));
trainingRows = zeros(2,cfg.symbolsPerSlot,nSlots);
kernelByIteration = complex(nan(nCoefficients,cfg.symbolsPerSlot,nSlots,iterations));
trainingRowsByIteration = zeros(2,cfg.symbolsPerSlot,nSlots,iterations);
ddceRankDeficientCount=0;
for s = 1:nSlots
    slot = cfg.dataSlots(s); channel=channels{s};
    first = double(package.dataIndices(:,1,s));
    [subcarrier,symbol] = ind2sub([nSC cfg.symbolsPerSlot nLayers],first);
    idx2D = sub2ind([nSC cfg.symbolsPerSlot],subcarrier,symbol);
    y = complex(zeros(nData,nRx)); h = complex(zeros(nData,nRx,nLayers));
    driveObservation=complex(zeros(nData,nRx));
    phase=complex(zeros(nData,nLayers));
    dmrsTime=centers(slot*14+cfg.dmrsTypeAPosition+1);
    dt=centers(slot*14+symbol)-dmrsTime;
    for r=1:nRx
        plane=grid(:,slot*14+(1:14),r); y(:,r)=plane(idx2D);
        if kernelConstraint=="received"
            drivePlane=driveGrid(:,slot*14+(1:14),r);
            driveObservation(:,r)=drivePlane(idx2D);
        end
        for p=1:nLayers
            hp=channel(:,:,r,p);
            if r==1
                timingPhase=exp(-1j*2*pi*(subcarrier-1)*est.timingSamples(p)/cfg.nfft);
                phase(:,p)=timingPhase.*exp(1j*2*pi*residualCfoHz(p)*dt/fs);
            end
            h(:,r,p)=hp(idx2D).*phase(:,p);
        end
    end
    % The first-pass decisions must come from the same timing/CFO-aware
    % channel model used by the kernel regressor.  Reusing base.postCompData
    % here would silently mix the legacy receiver decisions with refined h,
    % causing CFO/timing residuals to contaminate the fitted ICI kernel.
    hCurrent=h; channelObservation=y;
    xFirstPass = rzf_equalize(y,hCurrent,cfg,nLayers);
    xEstimate = hard_remodulate(xFirstPass,cfg.modulation,nLayers);
    for iteration = 1:iterations
        if channelTracking=="ddce"
            xDdce=hard_remodulate(xEstimate,cfg.modulation,nLayers);
            [hCurrent,rankFailures]=ddce_update(channelObservation,xDdce,subcarrier,phase,hCurrent,nRx,nLayers);
            ddceRankDeficientCount=ddceRankDeficientCount+rankFailures;
        end
        v = predicted_rx(hCurrent,xEstimate,nRx,nLayers); % H*xhat, [nData x nRx]
        yCorrected = y; % Reconstruct from unmodified measurements each pass.
        for l=unique(symbol).'
            pick=find(symbol==l); [~,order]=sort(subcarrier(pick)); pick=pick(order);
            banks={v(pick,:)};
            if kernelBanks=="double"
                previous=previous_phase_bank(v(pick,:),subcarrier(pick),cfg);
                banks{2}=previous;
            end
            if kernelConstraint=="physical"
                [yCorrected(pick,:),m,rows]=crossfit_physical(y(pick,:),banks{1},banks{1}-banks{2},halfWidth);
            elseif kernelConstraint=="received"
                [yCorrected(pick,:),m,rows]=crossfit_physical(y(pick,:),banks{1},driveObservation(pick,:),halfWidth);
            else
                [yCorrected(pick,:),m,rows]=crossfit_symbol(y(pick,:),banks,halfWidth);
            end
            kernelByIteration(:,l,s,iteration)=m;
            trainingRowsByIteration(:,l,s,iteration)=rows;
        end
        xEqualized = rzf_equalize(yCorrected,hCurrent,cfg,nLayers);
        channelObservation=yCorrected;
        if iteration < iterations && feedbackMode=="hard"
            xEstimate = hard_remodulate(xEqualized,cfg.modulation,nLayers);
        else
            xEstimate = xEqualized;
        end
    end
    kernel(:,:,s)=kernelByIteration(:,:,s,end);
    trainingRows(:,:,s)=trainingRowsByIteration(:,:,s,end);
    sampleCount=min(cfg.channelConditionSamplesPerSlot,nData);
    sampleIndices=unique(round(linspace(1,nData,sampleCount)));
    for q=sampleIndices
        conditionNumbers(end+1)=cond(reshape(hCurrent(q,:,:),nRx,nLayers)); %#ok<AGROW>
    end
    for p=1:nLayers
        bits=logical(nrSymbolDemodulate(xEstimate(:,p),cfg.modulation,'DecisionType','hard'));
        expected=package.codedBits(:,s,p); errors(s,p)=sum(bits~=expected);
        reference=double(package.dataQPSK(:,s,p));
        evm(s,p)=100*rms(xEstimate(:,p)-reference)/rms(reference);
    end
end
result=struct('base',base,'rawBitErrors',errors, ...
    'rawBER',errors/package.nCodedBitsPerSlotLayer, ...
    'infoBitErrors',errors,'infoBER',errors/package.nInfoBitsPerSlotLayer, ...
    'evmRMSPercent',evm,'kernel',kernel,'trainingRows',trainingRows, ...
    'kernelByIteration',kernelByIteration,'trainingRowsByIteration',trainingRowsByIteration, ...
    'halfWidth',halfWidth,'iterations',iterations,'feedbackMode',feedbackMode, ...
    'kernelBanks',kernelBanks,'kernelBankCount',nBanks, ...
    'kernelConstraint',kernelConstraint,'kernelRealDof', ...
    kernel_real_dof(kernelConstraint,nBanks,halfWidth), ...
    'channelTracking',channelTracking,'ddceRankDeficientCount',ddceRankDeficientCount, ...
    'userCfoCompensation',logical(userCfoCompensation),'residualCfoHz',residualCfoHz, ...
    'userTimingCompensation',logical(userTimingCompensation), ...
    'estimatedTimingSamples',est.timingSamples, ...
    'estimatedConditionStats',condition_stats(conditionNumbers), ...
    'residualCfoUnambiguousHz',unambiguousCfoHz,'residualCfoWarningHz',warningCfoHz, ...
    'method','per-symbol parity-crossfit common ICI kernel');
end

function stats=condition_stats(values)
values=sort(values(isfinite(values)));
if isempty(values), stats=[NaN NaN NaN]; return; end
stats=[median(values) values(max(1,ceil(.95*numel(values)))) max(values)];
end

function x = hard_remodulate(postComp, modulation, nLayers)
nData=size(postComp,1); x=complex(zeros(nData,nLayers));
for p=1:nLayers
    if ndims(postComp) == 2
        z=postComp(:,p);
    else
        z=postComp(:,1,p);
    end
    bits=logical(nrSymbolDemodulate(z,modulation,'DecisionType','hard'));
    x(:,p)=nrSymbolModulate(bits,modulation);
end
end

function v = predicted_rx(h,x,nRx,nLayers)
v=complex(zeros(size(x,1),nRx));
for r=1:nRx
    for p=1:nLayers, v(:,r)=v(:,r)+h(:,r,p).*x(:,p); end
end
end

function [corrected, kernelMean, rows] = crossfit_symbol(y,banks,Q)
n=size(y,1); corrected=y; u=-Q:Q;
nCoefficients=numel(u)*numel(banks); kernel=complex(zeros(nCoefficients,2)); rows=zeros(2,1);
if n <= 2*Q+2
    kernelMean=complex(nan(nCoefficients,1)); return;
end
centers=(Q+1):(n-Q);
for parity=0:1
    train=centers(mod(centers,2)==parity); A=[]; b=[];
    for r=1:size(y,2)
        localA=[];
        for bank=1:numel(banks)
            part=complex(zeros(numel(train),numel(u)));
            for q=1:numel(u), part(:,q)=banks{bank}(train-u(q),r); end
            localA=[localA part]; %#ok<AGROW>
        end
        A=[A;localA]; %#ok<AGROW>
        b=[b;y(train,r)-banks{1}(train,r)]; %#ok<AGROW>
    end
    kernel(:,parity+1)=A\b; rows(parity+1)=size(A,1);
    target=centers(mod(centers,2)~=parity);
    for r=1:size(y,2)
        localA=[];
        for bank=1:numel(banks)
            part=complex(zeros(numel(target),numel(u)));
            for q=1:numel(u), part(:,q)=banks{bank}(target-u(q),r); end
            localA=[localA part]; %#ok<AGROW>
        end
        corrected(target,r)=y(target,r)-localA*kernel(:,parity+1);
    end
end
kernelMean=mean(kernel,2);
end

function [corrected,kernelMean,rows]=crossfit_physical(y,current,drive,Q)
% Fit one real-process kernel on D=V_current-V_previous.  Conjugate
% symmetry is imposed by solving 1+2Q real parameters rather than an
% unconstrained complex vector.
n=size(y,1); corrected=y; rows=zeros(2,1);
theta=zeros(1+2*Q,2); kernels=complex(zeros(2*Q+1,2));
if n<=2*Q+2, kernelMean=complex(nan(2*Q+1,1)); return; end
centers=(Q+1):(n-Q);
for parity=0:1
    train=centers(mod(centers,2)==parity); A=[]; b=[];
    for r=1:size(y,2)
        local=conjugate_design(drive,train,Q,r);
        A=[A;local]; b=[b;y(train,r)-current(train,r)]; %#ok<AGROW>
    end
    realSystem=[real(A);imag(A)]; realTarget=[real(b);imag(b)];
    theta(:,parity+1)=realSystem\realTarget;
    kernels(:,parity+1)=theta_to_kernel(theta(:,parity+1),Q);
    rows(parity+1)=size(A,1);
    target=centers(mod(centers,2)~=parity);
    for r=1:size(y,2)
        prediction=conjugate_design(drive,target,Q,r)*theta(:,parity+1);
        corrected(target,r)=y(target,r)-prediction;
    end
end
kernelMean=mean(kernels,2);
end

function A=conjugate_design(drive,rows,Q,r)
A=complex(zeros(numel(rows),1+2*Q)); A(:,1)=drive(rows,r);
for u=1:Q
    lower=drive(rows-u,r); upper=drive(rows+u,r);
    A(:,1+u)=lower+upper;
    A(:,1+Q+u)=1j*(lower-upper);
end
end

function kernel=theta_to_kernel(theta,Q)
kernel=complex(zeros(2*Q+1,1)); kernel(Q+1)=theta(1);
for u=1:Q
    positive=theta(1+u)+1j*theta(1+Q+u);
    kernel(Q+1+u)=positive; kernel(Q+1-u)=conj(positive);
end
end

function dof=kernel_real_dof(constraint,nBanks,Q)
if any(constraint==["physical" "received"]), dof=1+2*Q;
else, dof=2*nBanks*(2*Q+1); end
end

function previous=previous_phase_bank(v,subcarrier,cfg)
% The raw predecessor of phases 2--4 is the preceding virtual chain at the
% same decimated index.  Phase 1 follows phase 4 from the prior decimated
% sample, represented by one-sample OFDM delay.  A constant bin-reference
% phase is immaterial because the fitted bank coefficient is complex.
previous=complex(zeros(size(v))); previous(:,2:4)=v(:,1:3);
previous(:,1)=v(:,4).*exp(-1j*2*pi*(subcarrier-1)/cfg.nfft);
end

function [hUpdated,rankFailures]=ddce_update(y,xHard,subcarrier,phase,hPrevious,nRx,nLayers)
% Decision-directed channel estimation in the de-sloped base-channel domain.
% Hard QPSK decisions are multiplied by the already estimated timing/CFO
% phase.  One constant 4-column base channel is solved per subcarrier/RX
% from all data symbols in the slot, then the phase is reapplied per RE.
hUpdated=hPrevious; rankFailures=0;
for k=unique(subcarrier).'
    rows=find(subcarrier==k); design=xHard(rows,:).*phase(rows,:);
    if size(design,1)<nLayers || rank(design)<nLayers
        rankFailures=rankFailures+1; continue;
    end
    for r=1:nRx
        base=design\y(rows,r);
        for p=1:nLayers, hUpdated(rows,r,p)=base(p).*phase(rows,p); end
    end
end
end

function x = rzf_equalize(y,h,cfg,nLayers)
nData=size(y,1); hPages=permute(h,[2 3 1]); yPages=permute(y,[2 3 1]);
hh=pagectranspose(hPages); gram=pagemtimes(hh,hPages); matched=pagemtimes(hh,yPages);
power=sum(abs(hPages).^2,[1 2])/nLayers; lambda=cfg.rzfRegularization*max(power,eps);
x=pagemldivide(gram+reshape(eye(nLayers),nLayers,nLayers,1).*lambda,matched);
x=permute(x,[3 2 1]); x=reshape(x,nData,nLayers);
end
