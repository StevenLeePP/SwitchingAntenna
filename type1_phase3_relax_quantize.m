function result = type1_phase3_relax_quantize(H, noiseVariance, dmax, greedy)
%TYPE1_PHASE3_RELAX_QUANTIZE Local continuous relaxation plus feasible projection.
%   The continuous result is a local diagnostic, not a certified global
%   upper bound.  The reported receiver result always uses the quantized,
%   strictly feasible binary schedule.

[M,N,~]=size(H);
if nargin<4||isempty(greedy)
    greedy=type1_phase3_greedy_schedule(H,noiseVariance,dmax);
end
x0=.85*double(greedy.S)+.05;
for m=1:M
    if sum(x0(m,:))>dmax,x0(m,:)=x0(m,:)*dmax/sum(x0(m,:));end
end
A=[kron(ones(1,N),eye(M));-kron(eye(N),ones(1,M))];
b=[dmax*ones(M,1);-ones(N,1)];
options=optimoptions('fmincon','Display','off','Algorithm','sqp', ...
    'MaxIterations',60,'MaxFunctionEvaluations',4000, ...
    'StepTolerance',1e-7,'OptimalityTolerance',1e-5);
objective=@(x)smooth_loss(reshape(x,M,N),H,noiseVariance,.5);
[x,loss,exitflag,output]=fmincon(objective,x0(:),A,b,[],[], ...
    zeros(M*N,1),ones(M*N,1),[],options);
continuous=reshape(x,M,N);
S=project_weights(continuous,dmax);
projected=type1_phase3_wideband_metrics(H,S,noiseVariance).objectiveDb;
% A one-edge local ascent is allowed after quantization, but never a loss.
refined=coordinate_refine(S,H,noiseVariance,dmax);
if refined.objectiveDb>=projected,S=refined.S;projected=refined.objectiveDb;end
result=struct('S',S,'objectiveDb',projected,'continuousS',continuous, ...
    'continuousMinObjectiveDb',type1_phase3_wideband_metrics( ...
    H,continuous,noiseVariance).objectiveDb,'smoothLoss',loss, ...
    'exitflag',exitflag,'solverOutput',output,'dmax',dmax, ...
    'isCertifiedUpperBound',false);
end

function loss=smooth_loss(S,H,nv,temperature)
try
    m=type1_phase3_wideband_metrics(H,S,nv);z=m.perUserMeanSinrDb(:);
catch
    loss=1e6;return;
end
a=-z/temperature;amax=max(a);softmin=-temperature*(amax+log(sum(exp(a-amax))));
loss=-softmin;
end

function S=project_weights(W,dmax)
[M,N]=size(W);assign=injective_assignments(M,N);score=zeros(size(assign,1),1);
for k=1:size(assign,1)
    for n=1:N,score(k)=score(k)+W(assign(k,n),n);end
end
[~,best]=max(score);S=false(M,N);
for n=1:N,S(assign(best,n),n)=true;end
[~,order]=sort(W(:),'descend');
for index=order.'
    [m,n]=ind2sub([M N],index);
    if ~S(m,n)&&sum(S(m,:))<dmax
        trial=S;trial(m,n)=true;
        if rcond(double(trial).'*double(trial))>1e-12,S=trial;end
    end
end
end

function result=coordinate_refine(S,H,nv,dmax)
current=type1_phase3_wideband_metrics(H,S,nv).objectiveDb;changed=true;
while changed
    changed=false;best=current;bestS=S;
    for m=1:size(S,1)
        for n=1:size(S,2)
            T=S;
            if T(m,n)
                if sum(T(:,n))==1,continue;end
                T(m,n)=false;
            elseif sum(T(m,:))<dmax
                T(m,n)=true;
            else
                continue;
            end
            try
                v=type1_phase3_wideband_metrics(H,T,nv).objectiveDb;
            catch
                v=-inf;
            end
            if v>best+1e-10,best=v;bestS=T;changed=true;end
        end
    end
    S=bestS;current=best;
end
result=struct('S',S,'objectiveDb',current);
end

function a=injective_assignments(M,N)
grid=cell(1,N);[grid{:}]=ndgrid(1:M);a=zeros(M^N,N);
for n=1:N,a(:,n)=grid{n}(:);end
a=a(arrayfun(@(k)numel(unique(a(k,:)))==N,(1:size(a,1)).'),:);
end
