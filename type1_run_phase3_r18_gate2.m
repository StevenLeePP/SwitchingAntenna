function result=type1_run_phase3_r18_gate2()
%TYPE1_RUN_PHASE3_R18_GATE2 Exact F1 and online F1/F2 paired benchmark.
%   Gate statistics are frozen on 51 RB-centre tones, exactly the R17
%   search objective.  All selected schedules are separately audited over
%   all 612 occupied subcarriers; those transfer results cannot alter gate 2.

validation=type1_validate_phase3_gate2();
profile=lower(string(getenv('TYPE1_R18_PROFILE')));
if strlength(profile)==0,profile="paper";end
if profile=="paper",nSeeds=20;elseif profile=="smoke",nSeeds=3;
else,error('type1:R18Profile','TYPE1_R18_PROFILE must be smoke or paper.');end
cfg=type1_config();model=type1_phase3_config(8,4);model.maxDutyCount=2;
seedValues=20261701+(0:nSeeds-1);snrDb=20;
fullFrequencyHz=(-306:305)*cfg.scsKHz*1e3;searchIndex=6:12:606;
F1=type1_phase3_enumerate_f1();R17=type1_phase3_enumerate_pair_partitions();
baselineS=[eye(4);zeros(4)];fixedS=false(8,4);
for n=1:4,fixedS(2*n-1:2*n,n)=true;end
preRegistration=struct('reviewTarget',"R18 gate 2",'profile',profile, ...
    'nSeeds',nSeeds,'seedValues',seedValues,'snrDb',snrDb, ...
    'f1Count',size(F1,3),'r17Count',size(R17,3),'f1Dmax',1,'f2Dmax',2, ...
    'gateToneCount',numel(searchIndex),'transferToneCount',numel(fullFrequencyHz), ...
    'gateObjective',"51-tone min-user mean noise-aware MMSE SINR in dB", ...
    'transferObjective',"same metric over all 612 occupied subcarriers", ...
    'flatDefinition',"same TDL draw frozen at DC and repeated over frequency", ...
    'greedyRetentionThreshold',.8,'f1MustNeverLoseToM4',true, ...
    'f2IncrementDecision',"positive=headline; nonpositive=honest boundary", ...
    'relaxationSemantics',"local continuous diagnostic, not certified global upper bound", ...
    'impairmentsEnabled',false);

template=struct('seed',nan,'noiseVarianceTdl',nan,'noiseVarianceFlat',nan,'tdl',struct,'flat',struct);
perSeed=repmat(template,nSeeds,1);
for k=1:nSeeds
    seed=seedValues(k);stream=RandStream('mt19937ar','Seed',seed);
    [~,channel]=type1_phase3_make_tdl_a_channel(complex(zeros(64,4)),cfg,model,stream);
    Hfull=type1_phase3_tdl_frequency_response(channel,fullFrequencyHz);
    Hsearch=Hfull(:,:,searchIndex);Hdc=Hfull(:,:,307);
    HflatSearch=repmat(Hdc,1,1,numel(searchIndex));
    HflatFull=repmat(Hdc,1,1,numel(fullFrequencyHz));
    signalPower=mean(sum(abs(Hfull).^2,2),'all');nv=signalPower/10^(snrDb/10);
    flatSignalPower=mean(sum(abs(HflatFull).^2,2),'all');nvFlat=flatSignalPower/10^(snrDb/10);
    tdl=run_one(Hsearch,Hfull,nv,F1,R17,baselineS,fixedS,seed+50000);
    flat=run_one(HflatSearch,HflatFull,nvFlat,F1,R17,baselineS,fixedS,seed+60000);
    perSeed(k)=struct('seed',seed,'noiseVarianceTdl',nv, ...
        'noiseVarianceFlat',nvFlat,'tdl',tdl,'flat',flat);
    fprintf(['R18 %2d/%d seed=%d TDL gate [M4/F1/G1/G2]=%.3f/%.3f/%.3f/%.3f, ' ...
        'F1 retention=%.1f%%, F2-F1=%+.3f dB; flat F2-F1=%+.3f dB.\n'], ...
        k,nSeeds,seed,tdl.search.m4.objectiveDb,tdl.search.f1Exact.objectiveDb, ...
        tdl.search.greedyF1.objectiveDb,tdl.search.greedyF2.objectiveDb, ...
        100*tdl.greedyRetention,tdl.f2IncrementDb,flat.f2IncrementDb);
end

tdlF1=arrayfun(@(x)x.tdl.search.f1Exact.objectiveDb-x.tdl.search.m4.objectiveDb,perSeed).';
tdlG1=arrayfun(@(x)x.tdl.search.greedyF1.objectiveDb-x.tdl.search.m4.objectiveDb,perSeed).';
tdlG2=arrayfun(@(x)x.tdl.f2IncrementDb,perSeed).';
flatG2=arrayfun(@(x)x.flat.f2IncrementDb,perSeed).';
retention=arrayfun(@(x)x.tdl.greedyRetention,perSeed).';
relaxGain=arrayfun(@(x)x.tdl.search.relaxF1.objectiveDb-x.tdl.search.m4.objectiveDb,perSeed).';
relaxRetention=relaxGain./max(tdlF1,1e-12);
relaxF2=arrayfun(@(x)x.tdl.search.relaxF2.objectiveDb-x.tdl.search.f1Exact.objectiveDb,perSeed).';
baselineNames=["fixed" "r17Exact" "fas" "random"];
baselineMedianGainDb=zeros(size(baselineNames));
for b=1:numel(baselineNames)
    name=char(baselineNames(b));
    values=arrayfun(@(x)x.tdl.search.(name).objectiveDb-x.tdl.search.m4.objectiveDb,perSeed);
    baselineMedianGainDb(b)=median(values);
end
f1NeverLoses=all(tdlF1>=-1e-10);greedyWin=sum(tdlG1>=-1e-10);
exactWin=sum(tdlF1>=-1e-10);medianRetention=median(retention);
paperGateEvaluated=profile=="paper";
gatePassed=paperGateEvaluated&&f1NeverLoses&&medianRetention>=.8&&greedyWin>=exactWin;
summary=struct('f1GainDb',tdlF1,'greedyF1GainDb',tdlG1, ...
    'greedyRetention',retention,'medianGreedyRetention',medianRetention, ...
    'relaxF1GainDb',relaxGain,'relaxF1Retention',relaxRetention, ...
    'medianRelaxF1Retention',median(relaxRetention), ...
    'relaxF2MinusF1Db',relaxF2,'relaxF2IncrementMedianDb',median(relaxF2), ...
    'baselineNames',baselineNames,'baselineMedianGainDb',baselineMedianGainDb, ...
    'f1NeverLoses',f1NeverLoses,'f1WinCount',exactWin,'greedyF1WinCount',greedyWin, ...
    'tdlF2MinusF1Db',tdlG2,'tdlF2IncrementMedianDb',median(tdlG2), ...
    'tdlF2PositiveCount',sum(tdlG2>0),'flatF2MinusF1Db',flatG2, ...
    'flatF2IncrementMedianDb',median(flatG2),'flatF2PositiveCount',sum(flatG2>0), ...
    'paperGateEvaluated',paperGateEvaluated,'gatePassed',gatePassed);
root=string(getenv('TYPE1_PHASE3_OUTPUT_ROOT'));if strlength(root)==0,root=fullfile(tempdir,'type1_phase3');end
if ~isfolder(root),mkdir(root);end
out=fullfile(root,['type1_phase3_r18_' char(profile) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);mkdir(out);
result=struct('preRegistration',preRegistration,'validation',validation, ...
    'summary',summary,'perSeed',perSeed,'outputDirectory',out, ...
    'createdAt',datetime('now'),'matlabVersion',version);
save(fullfile(out,'phase3_r18_gate2.mat'),'result','-v7.3');
plot_result(result,fullfile(out,'phase3_r18_gate2.png'));
fprintf(['R18 %s: F1 never loses=%d, greedy wins=%d/%d, median retention=%.1f%%, ' ...
    'TDL F2-F1 median=%+.3f dB (%d/%d positive), flat=%+.3f dB (%d/%d), gate=%d.\n'], ...
    profile,f1NeverLoses,greedyWin,nSeeds,100*medianRetention,median(tdlG2),sum(tdlG2>0), ...
    nSeeds,median(flatG2),sum(flatG2>0),nSeeds,gatePassed);
fprintf('Phase-3 R18 audit saved: %s\n',out);
end

function out=run_one(Hsearch,Hfull,nv,F1,R17,M4,fixed,seed)
f1Objective=type1_phase3_batch_f1_objective(Hsearch,F1,nv,256);
[~,f1Index]=max(f1Objective);f1S=F1(:,:,f1Index);
r17Objective=type1_phase3_batch_f1_objective(Hsearch,R17,nv,256);
[~,r17Index]=max(r17Objective);r17S=R17(:,:,r17Index);
g1=type1_phase3_greedy_schedule(Hsearch,nv,1);
g2=type1_phase3_greedy_schedule(Hsearch,nv,2);
q1=type1_phase3_relax_quantize(Hsearch,nv,1,g1);
q2=type1_phase3_relax_quantize(Hsearch,nv,2,g2);
fas=fas_schedule(Hsearch);random=random_schedule(size(Hsearch,1),size(Hsearch,2),1,seed);
names={'m4','fixed','r17Exact','f1Exact','greedyF1','relaxF1','greedyF2','relaxF2','fas','random'};
schedules={M4,fixed,r17S,f1S,g1.S,q1.S,g2.S,q2.S,fas,random};
search=struct;full=struct;
for k=1:numel(names)
    search.(names{k})=compact(type1_phase3_wideband_metrics(Hsearch,schedules{k},nv),schedules{k});
    full.(names{k})=compact(type1_phase3_wideband_metrics(Hfull,schedules{k},nv),schedules{k});
end
denominator=search.f1Exact.objectiveDb-search.m4.objectiveDb;
if denominator<=1e-10,retention=double(search.greedyF1.objectiveDb>=search.f1Exact.objectiveDb-1e-9);
else,retention=(search.greedyF1.objectiveDb-search.m4.objectiveDb)/denominator;end
out=struct('search',search,'full',full,'f1BestIndex',f1Index,'r17BestIndex',r17Index, ...
    'greedyF1TrajectoryDb',g1.trajectoryDb,'greedyF2TrajectoryDb',g2.trajectoryDb, ...
    'relaxF1ContinuousMinDb',q1.continuousMinObjectiveDb, ...
    'relaxF2ContinuousMinDb',q2.continuousMinObjectiveDb, ...
    'relaxF1Exitflag',q1.exitflag,'relaxF2Exitflag',q2.exitflag, ...
    'greedyRetention',retention, ...
    'f2IncrementDb',search.greedyF2.objectiveDb-search.f1Exact.objectiveDb, ...
    'fullF2IncrementDb',full.greedyF2.objectiveDb-full.f1Exact.objectiveDb);
end

function value=compact(metric,S)
value=rmfield(metric,'sinrLinear');value.S=logical(S);value.activeEdges=nnz(S);
value.activePorts=sum(any(S,2));value.maxDuty=max(sum(S,2));
end

function S=fas_schedule(H)
[M,N,~]=size(H);score=squeeze(mean(abs(H).^2,3));assign=injective(M,N);
value=zeros(size(assign,1),1);
for k=1:size(assign,1),for n=1:N,value(k)=value(k)+score(assign(k,n),n);end,end
[~,best]=max(value);S=false(M,N);for n=1:N,S(assign(best,n),n)=true;end
end

function S=random_schedule(M,N,dmax,seed)
stream=RandStream('mt19937ar','Seed',seed);assign=injective(M,N);
a=assign(randi(stream,size(assign,1)),:);S=false(M,N);
for n=1:N,S(a(n),n)=true;end
order=randperm(stream,M*N);
for index=order
    [m,n]=ind2sub([M N],index);
    if sum(S(m,:))<dmax&&rand(stream)<.35,S(m,n)=true;end
end
end

function a=injective(M,N)
grid=cell(1,N);[grid{:}]=ndgrid(1:M);a=zeros(M^N,N);
for n=1:N,a(:,n)=grid{n}(:);end
a=a(arrayfun(@(k)numel(unique(a(k,:)))==N,(1:size(a,1)).'),:);
end

function plot_result(result,file)
seed=[result.perSeed.seed];m4=arrayfun(@(x)x.tdl.search.m4.objectiveDb,result.perSeed);
f1=arrayfun(@(x)x.tdl.search.f1Exact.objectiveDb,result.perSeed);
g1=arrayfun(@(x)x.tdl.search.greedyF1.objectiveDb,result.perSeed);
g2=arrayfun(@(x)x.tdl.search.greedyF2.objectiveDb,result.perSeed);
flat=arrayfun(@(x)x.flat.f2IncrementDb,result.perSeed);
figure('Visible','off','Position',[100 100 1500 450]);
subplot(1,3,1);plot(seed,m4,'o-');hold on;plot(seed,f1,'s-');plot(seed,g1,'^-');plot(seed,g2,'d-');
grid on;xlabel('paired TDL seed');ylabel('gate min-user SINR (dB)');legend('M4','F1 exact','F1 greedy','F2 greedy','Location','best');
subplot(1,3,2);stem(seed,100*result.summary.greedyRetention,'filled');yline(80,'r--');grid on;
xlabel('paired TDL seed');ylabel('F1 gain retained (%)');title(sprintf('median %.1f%%',100*result.summary.medianGreedyRetention));
subplot(1,3,3);plot(seed,result.summary.tdlF2MinusF1Db,'o-');hold on;plot(seed,flat,'s-');yline(0,'k--');grid on;
xlabel('paired seed');ylabel('F2 greedy - F1 exact (dB)');legend('TDL-A','flat','Location','best');
exportgraphics(gcf,file,'Resolution',180);close(gcf);
end
