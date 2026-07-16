function result=type1_phase3_acquisition_aware_schedule(H,Hpss,noiseVariance,baselineS)
%TYPE1_PHASE3_ACQUISITION_AWARE_SCHEDULE Max-data F1 greedy with PSS guard.
%   The PSS proxy must remain at least as high as the paired M=4 identity
%   proxy.  This is an oracle-channel research selector, not yet an online
%   estimator implementation.

[M,N,~]=size(H);assert(size(Hpss,1)==M,'type1:R20PssShape','H/Hpss differ.');
if nargin<4,baselineS=[eye(N);zeros(M-N,N)];end
assign=injective(M,N);B=size(assign,1);initial=false(M,N,B);
for k=1:B,for n=1:N,initial(assign(k,n),n,k)=true;end,end
data=type1_phase3_batch_f1_objective(H,initial,noiseVariance,256);
pss=type1_phase3_batch_pss_score(Hpss,initial,noiseVariance,256);
baselinePss=type1_phase3_batch_pss_score(Hpss,logical(baselineS),noiseVariance,1);
eligible=pss>=baselinePss-1e-10;
assert(any(eligible),'type1:R20PssGuard','No coverage schedule meets M4 PSS guard.');
indices=find(eligible);[current,local]=max(data(indices));index=indices(local);
S=initial(:,:,index);trajectory=current;pssTrajectory=pss(index);
while true
    best=current;bestPss=pssTrajectory(end);bestEdge=[];
    for m=1:M
        if any(S(m,:)),continue;end
        for n=1:N
            trial=S;trial(m,n)=true;
            trialPss=type1_phase3_batch_pss_score(Hpss,trial,noiseVariance,1);
            if trialPss<baselinePss-1e-10,continue;end
            value=type1_phase3_wideband_metrics(H,trial,noiseVariance).objectiveDb;
            if value>best+1e-10,best=value;bestPss=trialPss;bestEdge=[m n];end
        end
    end
    if isempty(bestEdge),break;end
    S(bestEdge(1),bestEdge(2))=true;current=best;
    trajectory(end+1,1)=current;pssTrajectory(end+1,1)=bestPss; %#ok<AGROW>
end
result=struct('S',S,'objectiveDb',current,'pssScoreDb',pssTrajectory(end), ...
    'baselinePssScoreDb',baselinePss,'pssMarginDb',pssTrajectory(end)-baselinePss, ...
    'trajectoryDb',trajectory,'pssTrajectoryDb',pssTrajectory, ...
    'initialEligibleCount',sum(eligible),'isOracleChannelSelector',true);
end

function a=injective(M,N)
grid=cell(1,N);[grid{:}]=ndgrid(1:M);a=zeros(M^N,N);
for n=1:N,a(:,n)=grid{n}(:);end
a=a(arrayfun(@(k)numel(unique(a(k,:)))==N,(1:size(a,1)).'),:);
end
