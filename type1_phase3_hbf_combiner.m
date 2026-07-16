function F=type1_phase3_hbf_combiner(H,nRf,mode)
%TYPE1_PHASE3_HBF_COMBINER Frequency-flat phase-matched HBF reference.
%   This is an optimistic ideal phase-shifter baseline: no quantization or
%   insertion loss is applied in rate; their power is counted separately.

arguments
    H {mustBeNumeric}
    nRf (1,1) double {mustBeInteger,mustBePositive}
    mode (1,1) string {mustBeMember(mode,["partial" "full"])}
end
[M,N,K]=size(H);assert(nRf>=N,'type1:R22HbfRf','HBF needs at least N RF chains.');
reference=H(:,:,ceil(K/2));F=complex(zeros(M,nRf));
if mode=="partial"
    assert(mod(M,nRf)==0,'type1:R22HbfPartition','M must divide evenly across RF chains.');
    width=M/nRf;
    for r=1:nRf
        rows=(r-1)*width+(1:width);user=mod(r-1,N)+1;
        F(rows,r)=exp(1j*angle(reference(rows,user)));
    end
else
    for r=1:nRf
        user=mod(r-1,N)+1;F(:,r)=exp(1j*angle(reference(:,user)));
    end
end
assert(rank(F)>=N,'type1:R22HbfRank','Constructed HBF combiner is rank deficient.');
end
