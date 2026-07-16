function result = type1_phase3_greedy_schedule(H, noiseVariance, dmax, initialScore)
%TYPE1_PHASE3_GREEDY_SCHEDULE Coverage initialization then monotone additions.
%   The coverage stage examines all injective one-port-per-chain schedules;
%   later additions may share a port across at most dmax code phases.

if nargin < 4, initialScore = []; end
[M,N,~] = size(H); assert(dmax==1 || dmax==2, 'type1:Phase3Dmax', ...
    'R18 freezes dmax to one or two.');
assignments = perms_n(M,N);
nInitial = size(assignments,1);
initialSchedules = false(M,N,nInitial);
for k=1:nInitial
    for chain=1:N, initialSchedules(assignments(k,chain),chain,k)=true; end
end
if isempty(initialScore)
    initialScore = type1_phase3_batch_f1_objective(H,initialSchedules,noiseVariance,512);
end
[current,index] = max(initialScore); S = initialSchedules(:,:,index);
trajectory = current; addedEdges = zeros(0,2);
while true
    best = current; bestEdge = [];
    for port=1:M
        if sum(S(port,:)) >= dmax, continue; end
        for chain=1:N
            if S(port,chain), continue; end
            trial=S; trial(port,chain)=true;
            metric=safe_metric(H,trial,noiseVariance);
            if metric > best + 1e-10
                best=metric;bestEdge=[port chain];
            end
        end
    end
    if isempty(bestEdge), break; end
    S(bestEdge(1),bestEdge(2))=true; current=best;
    trajectory(end+1,1)=current; %#ok<AGROW>
    addedEdges(end+1,:)=bestEdge; %#ok<AGROW>
end
result=struct('S',S,'objectiveDb',current,'trajectoryDb',trajectory, ...
    'initialIndex',index,'initialObjectiveDb',initialScore(index), ...
    'addedEdges',addedEdges,'dmax',dmax);
end

function value=safe_metric(H,S,noiseVariance)
try
    value=type1_phase3_wideband_metrics(H,S,noiseVariance).objectiveDb;
catch exception
    if strcmp(exception.identifier,'type1:Phase3MetricNoiseRank'),value=-inf;
    else,rethrow(exception);end
end
end

function a=perms_n(M,N)
grid=cell(1,N);[grid{:}]=ndgrid(1:M);a=zeros(M^N,N);
for n=1:N,a(:,n)=grid{n}(:);end
a=a(arrayfun(@(k)numel(unique(a(k,:)))==N,(1:size(a,1)).'),:);
end
