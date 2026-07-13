/* Fixed NR Type-1, single-symbol DM-RS channel estimator for 4 ports.
 * It uses the actual DM-RS indices/symbols carried in the shared MAT file,
 * so the resource mapping is not reimplemented as hard-coded constants.
 * Ports 0/1 and 2/3 are separated by the standard frequency-domain OCC.
 */
#include "mex.h"
#include "matrix.h"
#include <math.h>
#include <string.h>
#include <stdint.h>
typedef struct { float re, im; } cf;
static cf add(cf a,cf b){cf z={a.re+b.re,a.im+b.im};return z;}
static cf sub(cf a,cf b){cf z={a.re-b.re,a.im-b.im};return z;}
static cf mul(cf a,cf b){cf z={a.re*b.re-a.im*b.im,a.re*b.im+a.im*b.re};return z;}
static cf conjg(cf a){cf z={a.re,-a.im};return z;}
static float ab2(cf a){return a.re*a.re+a.im*a.im;}
static cf divc(cf a,cf b){float d=ab2(b)+1e-20f;cf z={(a.re*b.re+a.im*b.im)/d,(a.im*b.re-a.re*b.im)/d};return z;}
static cf mx_to_cf(const mxComplexSingle*x){cf z={x->real,x->imag};return z;}
static void cf_to_mx(mxComplexSingle*x,cf z){x->real=z.re;x->imag=z.im;}

void mexFunction(int nlhs,mxArray**plhs,int nrhs,const mxArray**prhs)
{
 const mxComplexSingle *rx,*rs; const uint32_t *ix; mxComplexSingle*out;
 mwSize nsc,nsym,nrx,npilot,j,r,p,g,k0,k1,k,lo,hi,l, dimsOut[4];
 const mwSize *d; cf *hp; double noise=0; mwSize nnoise=0;
 if(nrhs!=3||nlhs<2) mexErrMsgIdAndTxt("type1:dmrs:Args","Need rxSlot, dmrsIndices, dmrsSymbols; two outputs.");
 if(!mxIsSingle(prhs[0])||!mxIsComplex(prhs[0])||!mxIsUint32(prhs[1])||!mxIsSingle(prhs[2])||!mxIsComplex(prhs[2]))
   mexErrMsgIdAndTxt("type1:dmrs:Type","Expected complex-single rx/symbols and uint32 indices.");
 if(mxGetNumberOfDimensions(prhs[0])!=3||mxGetM(prhs[1])!=306||mxGetN(prhs[1])!=4||mxGetM(prhs[2])!=306||mxGetN(prhs[2])!=4)
   mexErrMsgIdAndTxt("type1:dmrs:Shape","Expected [Nsc,14,4] rx and [306,4] DM-RS mapping.");
 d=mxGetDimensions(prhs[0]); nsc=d[0]; nsym=d[1]; nrx=d[2]; npilot=mxGetM(prhs[1]);
 if(nsc!=612||nsym!=14||nrx!=4) mexErrMsgIdAndTxt("type1:dmrs:Shape","This kernel is fixed to 612x14x4.");
 rx=mxGetComplexSingles(prhs[0]); ix=(const uint32_t*)mxGetData(prhs[1]); rs=mxGetComplexSingles(prhs[2]);
 dimsOut[0]=nsc; dimsOut[1]=nsym; dimsOut[2]=nrx; dimsOut[3]=4;
 plhs[0]=mxCreateNumericArray(4,dimsOut,mxSINGLE_CLASS,mxCOMPLEX); out=mxGetComplexSingles(plhs[0]);
 plhs[1]=mxCreateDoubleScalar(0); hp=(cf*)mxCalloc((size_t)4*nrx*npilot,sizeof(cf));
 /* CDM pairs: solve two known DM-RS equations for each RX and port pair. */
 for(g=0;g<2;g++) for(j=0;j<npilot;j+=2){
   p=2*g; k0=(ix[j + p*npilot]-1)%nsc; k1=(ix[j+1 + p*npilot]-1)%nsc;
   cf a=mx_to_cf(rs+j+p*npilot), b=mx_to_cf(rs+j+(p+1)*npilot), c=mx_to_cf(rs+j+1+p*npilot), e=mx_to_cf(rs+j+1+(p+1)*npilot);
   cf det=sub(mul(a,e),mul(b,c));
   for(r=0;r<nrx;r++){
     cf y0=mx_to_cf(rx+k0+2*nsc+(r*nsc*nsym)); cf y1=mx_to_cf(rx+k1+2*nsc+(r*nsc*nsym));
     cf h0=divc(sub(mul(y0,e),mul(b,y1)),det); cf h1=divc(sub(mul(a,y1),mul(y0,c)),det);
     hp[((p*nrx+r)*npilot)+j]=h0; hp[((p*nrx+r)*npilot)+j+1]=h0;
     hp[(((p+1)*nrx+r)*npilot)+j]=h1; hp[(((p+1)*nrx+r)*npilot)+j+1]=h1;
   }
 }
 /* Linear frequency interpolation from the 306 comb pilots for every port. */
 for(p=0;p<4;p++) for(r=0;r<nrx;r++) for(k=0;k<nsc;k++){
   float u=(p<2)?0.5f*(float)k:0.5f*((float)k-1.0f); float f=floorf(u), alpha=u-f;
   if(f<0){lo=hi=0;alpha=0;} else if(f>=305){lo=hi=305;alpha=0;} else {lo=(mwSize)f;hi=lo+1;}
   cf a=hp[((p*nrx+r)*npilot)+lo], b=hp[((p*nrx+r)*npilot)+hi]; cf h={a.re+alpha*(b.re-a.re),a.im+alpha*(b.im-a.im)};
   for(l=0;l<nsym;l++) cf_to_mx(out+k+l*nsc+r*nsc*nsym+p*nsc*nsym*nrx,h);
 }
 /* Residual variance on all actual pilot REs. */
 for(g=0;g<2;g++) for(j=0;j<npilot;j++){
   p=2*g; k=(ix[j+p*npilot]-1)%nsc;
   for(r=0;r<nrx;r++){
     cf pred={0,0}, y=mx_to_cf(rx+k+2*nsc+r*nsc*nsym);
     for(mwSize q=p;q<p+2;q++){cf h=mx_to_cf(out+k+2*nsc+r*nsc*nsym+q*nsc*nsym*nrx); pred=add(pred,mul(h,mx_to_cf(rs+j+q*npilot)));}
     noise+=ab2(sub(y,pred)); nnoise++;
   }
 }
 *mxGetDoubles(plhs[1])=noise/fmax((double)nnoise,1.0); mxFree(hp);
}
