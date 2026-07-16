function targets=type1_phase3_switch_targets_from_physical(physical30,schedules,isolationDb)
%TYPE1_PHASE3_SWITCH_TARGETS_FROM_PHYSICAL Stream M-port resampling into A scalar targets.
%   This avoids storing an N-times-oversampled M-column raw matrix.  It is
%   algebraically identical because resampling and the per-phase sums are
%   linear.  Each output column remains one scalar RF-switch target.

assert(iscell(schedules)&&~isempty(schedules),'type1:R20Schedules','Schedules must be a cell array.');
A=numel(schedules);N=size(schedules{1},2);Mmax=size(physical30,2);nRaw=N*size(physical30,1);
targets=complex(zeros(nRaw,A,'single'));
if isinf(isolationDb),leak=0;else,leak=10^(-isolationDb/20);end
for m=1:Mmax
    rawm=single(resample(double(physical30(:,m)),N,1));
    for a=1:A
        S=schedules{a};if m>size(S,1),continue;end
        for q=1:N
            if S(m,q),weight=1;else,weight=leak;end
            rows=q:N:nRaw;targets(rows,a)=targets(rows,a)+weight*rawm(rows);
        end
    end
end
end
