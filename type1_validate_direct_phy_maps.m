function type1_validate_direct_phy_maps()
%TYPE1_VALIDATE_DIRECT_PHY_MAPS Validate persistent-map C PHY dispatch.
sourceDir=fileparts(mfilename('fullpath')); addpath(sourceDir);
type1_build_rx_mex(); type1_build_frame_mex();
p=type1_load_package(); c=p.cfg;
d=dir(fullfile(sourceDir,'data','*_virtual30_csingle_iq4.bin')); assert(~isempty(d));
[~,i]=max([d.datenum]); f=fullfile(d(i).folder,d(i).name);
id=fopen(f,'rb'); z=onCleanup(@()fclose(id)); a=fread(id,inf,'single=>single');
rx=reshape(complex(a(1:2:end),a(2:2:end)),[],c.nRxChannels);
acq=type1_analyze_fast(rx,p,c.dataSlots(1),'forcePSS',true);
slot=round(c.frameDurationSec*c.txSampleRate/c.slotsPerFrame); n=(max(c.dataSlots)+1)*slot;
w=single(rx(acq.timingOffset+(1:n),:)); q=single(mod((0:n-1).',slot));
w=w.*exp(single(-1j*2*pi*acq.frequencyOffsetHz/c.txSampleRate).*q);
g=single(nrOFDMDemodulate(type1_carrier_config(c,0),w,'Nfft',c.nfft,'SampleRate',c.txSampleRate,'CarrierFrequency',0));
type1_yunsdr_rx_mex('directphysetup',p.dmrsIndices,p.dmrsSymbols,p.dataIndices,p.dataQPSK,p.codedBits,c.rzfRegularization);
[e1,v1,~,h1]=type1_yunsdr_rx_mex('directphydecodegrid',g);
[e2,v2,~,h2]=type1_decode_frame_grid_mex(g,double(c.dataSlots(:)),p.dmrsIndices,p.dmrsSymbols,p.dataIndices,p.dataQPSK,p.codedBits,c.rzfRegularization);
fprintf('direct persistent maps: errorsEqual=%d EVMmaxDiff=%.9g HNMSE=%.2f dB\n',isequal(e1,e2),max(abs(v1-v2),[],'all'),10*log10(sum(abs(h1-h2).^2,'all')/(sum(abs(h2).^2,'all')+eps)));
assert(isequal(e1,e2)); assert(isequal(v1,v2)); assert(isequal(h1,h2));
clear type1_yunsdr_rx_mex
end
