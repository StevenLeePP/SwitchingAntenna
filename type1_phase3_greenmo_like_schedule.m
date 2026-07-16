function result=type1_phase3_greenmo_like_schedule(H,noiseVariance,initialS)
%TYPE1_PHASE3_GREENMO_LIKE_SCHEDULE Add many-to-many code memberships.
%   Starts from the accepted Dmax=1 schedule and greedily adds memberships
%   up to Dmax=N.  It is a GreenMO-like local baseline, not a reproduction
%   of GreenMO's co-phase grouping algorithm or an exhaustive optimum.

[M,N,~]=size(H);assert(isequal(size(initialS),[M N]),'type1:R22GreenMOShape', ...
    'initialS must match H.');
S=logical(initialS);current=safe_metric(H,S,noiseVariance);trajectory=current;
added=zeros(0,2);
while true
    best=current;edge=[];
    for m=1:M
        if sum(S(m,:))>=N,continue;end
        for n=1:N
            if S(m,n),continue;end
            trial=S;trial(m,n)=true;value=safe_metric(H,trial,noiseVariance);
            if value>best+1e-10,best=value;edge=[m n];end
        end
    end
    if isempty(edge),break;end
    S(edge(1),edge(2))=true;current=best;added(end+1,:)=edge; %#ok<AGROW>
    trajectory(end+1,1)=current; %#ok<AGROW>
end
result=struct('S',S,'objectiveDb',current,'trajectoryDb',trajectory, ...
    'addedEdges',added,'dmax',N,'isGreenMOReproduction',false);
end

function value=safe_metric(H,S,noiseVariance)
try
    value=type1_phase3_wideband_metrics(H,S,noiseVariance).objectiveDb;
catch exception
    if strcmp(exception.identifier,'type1:Phase3MetricNoiseRank'),value=-inf;
    else,rethrow(exception);end
end
end
