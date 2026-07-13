/* Batch 10 ms Type-A PHY decoder after one MATLAB OFDM demodulation.
 * Fixed: 612 SC, 14 symbols/slot, 4 RX, 4 layers, Type-1 single DM-RS,
 * QPSK, one RZF weight per subcarrier reused over the 13 data symbols. */
#include "mex.h"
#include "matrix.h"
#include <stdint.h>
#include <math.h>
#include <string.h>
typedef struct{float re,im;} cf;
static cf A(cf a,cf b){cf z={a.re+b.re,a.im+b.im};return z;} static cf S(cf a,cf b){cf z={a.re-b.re,a.im-b.im};return z;}
static cf M(cf a,cf b){cf z={a.re*b.re-a.im*b.im,a.re*b.im+a.im*b.re};return z;} static cf C(cf a){cf z={a.re,-a.im};return z;}
static float Q(cf a){return a.re*a.re+a.im*a.im;} static cf D(cf a,cf b){float d=Q(b)+1e-20f;cf z={(a.re*b.re+a.im*b.im)/d,(a.im*b.re-a.re*b.im)/d};return z;}
static cf G(const mxComplexSingle*x){cf z={x->real,x->imag};return z;} static void P(mxComplexSingle*x,cf z){x->real=z.re;x->imag=z.im;}
static int solve(cf a[4][4],cf b[4][4],cf x[4][4]){int i,j,k,p;for(i=0;i<4;i++){float best=-1;p=i;for(k=i;k<4;k++){float v=Q(a[k][i]);if(v>best){best=v;p=k;}}if(best<1e-16f)return 0;if(p!=i)for(j=0;j<4;j++){cf t=a[i][j];a[i][j]=a[p][j];a[p][j]=t;t=b[i][j];b[i][j]=b[p][j];b[p][j]=t;}cf iv=D((cf){1,0},a[i][i]);for(j=i;j<4;j++)a[i][j]=M(a[i][j],iv);for(j=0;j<4;j++)b[i][j]=M(b[i][j],iv);for(k=0;k<4;k++)if(k!=i){cf f=a[k][i];for(j=i;j<4;j++)a[k][j]=S(a[k][j],M(f,a[i][j]));for(j=0;j<4;j++)b[k][j]=S(b[k][j],M(f,b[i][j]));}}memcpy(x,b,16*sizeof(cf));return 1;}
static void W(const cf*h,int k,float lam,cf w[4][4]){cf a[4][4]={{{0}}},b[4][4]={{{0}}},x[4][4];float pw=0;int r,i,j;for(r=0;r<4;r++)for(i=0;i<4;i++)pw+=Q(h[(i*4+r)*612+k]);for(i=0;i<4;i++){for(j=0;j<4;j++){cf z={0,0};for(r=0;r<4;r++)z=A(z,M(C(h[(i*4+r)*612+k]),h[(j*4+r)*612+k]));a[i][j]=z;}a[i][i].re+=lam*fmaxf(pw/4,1e-20f);for(r=0;r<4;r++)b[i][r]=C(h[(i*4+r)*612+k]);}if(!solve(a,b,x))memset(w,0,16*sizeof(cf));else memcpy(w,x,16*sizeof(cf));}
void mexFunction(int nlhs,mxArray**plhs,int nrhs,const mxArray**prhs){
 const mxComplexSingle *grid,*rs,*qpsk;const uint32_t*di,*xi;const mxLogical*bits;mxComplexSingle*hout;double*err,*evm,*noise;mwSize ns,s,j,r,p,g,k,l,pos,nslots,nGridSym;const mwSize*d,*dd,*dr,*dq,*db;float lam;int*map;cf*h,*hp;
 if(nrhs!=8||nlhs<4)mexErrMsgIdAndTxt("type1:frame:Args","Need 8 inputs and 4 outputs.");
 if(!mxIsSingle(prhs[0])||!mxIsComplex(prhs[0])||!mxIsUint32(prhs[2])||!mxIsSingle(prhs[3])||!mxIsComplex(prhs[3])||!mxIsUint32(prhs[4])||!mxIsSingle(prhs[5])||!mxIsComplex(prhs[5])||!mxIsLogical(prhs[6]))mexErrMsgIdAndTxt("type1:frame:Type","Unexpected input types.");
 d=mxGetDimensions(prhs[0]);if(mxGetNumberOfDimensions(prhs[0])!=3||d[0]!=612||d[1]<14||d[2]!=4)mexErrMsgIdAndTxt("type1:frame:Grid","grid must be 612xNsymbolsx4 complex single.");nGridSym=d[1];
 nslots=mxGetNumberOfElements(prhs[1]);if(nslots<1)mexErrMsgIdAndTxt("type1:frame:Slots","No data slots.");
 dd=mxGetDimensions(prhs[2]);dr=mxGetDimensions(prhs[3]);dq=mxGetDimensions(prhs[4]);db=mxGetDimensions(prhs[5]);
 if(mxGetNumberOfDimensions(prhs[2])!=3||dd[0]!=306||dd[1]!=4||dd[2]!=nslots||
    mxGetNumberOfDimensions(prhs[3])!=3||dr[0]!=306||dr[1]!=4||dr[2]!=nslots||
    mxGetNumberOfDimensions(prhs[4])!=3||dq[0]!=7956||dq[1]!=4||dq[2]!=nslots||
    mxGetNumberOfDimensions(prhs[5])!=3||db[0]!=7956||db[1]!=nslots||db[2]!=4||
    mxGetNumberOfDimensions(prhs[6])!=3||mxGetDimensions(prhs[6])[0]!=15912||mxGetDimensions(prhs[6])[1]!=nslots||mxGetDimensions(prhs[6])[2]!=4)
   mexErrMsgIdAndTxt("type1:frame:Map","Unexpected DM-RS/data map shape.");
 grid=mxGetComplexSingles(prhs[0]);xi=(const uint32_t*)mxGetData(prhs[2]);rs=mxGetComplexSingles(prhs[3]);di=(const uint32_t*)mxGetData(prhs[4]);qpsk=mxGetComplexSingles(prhs[5]);bits=mxGetLogicals(prhs[6]);lam=(float)mxGetScalar(prhs[7]);
 plhs[0]=mxCreateDoubleMatrix(nslots,4,mxREAL);plhs[1]=mxCreateDoubleMatrix(nslots,4,mxREAL);plhs[2]=mxCreateDoubleMatrix(nslots,1,mxREAL);mwSize hd[4]={612,4,4,nslots};plhs[3]=mxCreateNumericArray(4,hd,mxSINGLE_CLASS,mxCOMPLEX);err=mxGetDoubles(plhs[0]);evm=mxGetDoubles(plhs[1]);noise=mxGetDoubles(plhs[2]);hout=mxGetComplexSingles(plhs[3]);
 map=(int*)mxMalloc(612*14*sizeof(int));h=(cf*)mxCalloc(612*4*4,sizeof(cf));hp=(cf*)mxCalloc(306*4*4,sizeof(cf));
 for(s=0;s<nslots;s++){double ee[4]={0,0,0,0},pp[4]={0,0,0,0},ne=0;mwSize nc=0;memset(h,0,612*4*4*sizeof(cf));memset(hp,0,306*4*4*sizeof(cf));for(pos=0;pos<612*14;pos++)map[pos]=-1;
  ns=(mwSize)mxGetDoubles(prhs[1])[s];if((ns+1)*14>nGridSym)mexErrMsgIdAndTxt("type1:frame:Grid","Grid does not cover every requested data slot.");
  for(pos=0;pos<7956;pos++){uint32_t z=di[pos+s*7956*4]-1;k=z%612;l=(z/612)%14;map[l*612+k]=(int)pos;}
  /* This is intentionally identical to type1_dmrs_type1_mex: retain its
     pilot-list interpolation order rather than infer a new physical map. */
  for(g=0;g<2;g++)for(j=0;j<306;j+=2){p=2*g;k=(xi[j+p*306+s*306*4]-1)%612;mwSize k1=(xi[j+1+p*306+s*306*4]-1)%612;cf a=G(rs+j+p*306+s*306*4),b=G(rs+j+(p+1)*306+s*306*4),c=G(rs+j+1+p*306+s*306*4),e=G(rs+j+1+(p+1)*306+s*306*4),det=S(M(a,e),M(b,c));for(r=0;r<4;r++){cf y0=G(grid+k+(ns*14+2)*612+r*612*nGridSym),y1=G(grid+k1+(ns*14+2)*612+r*612*nGridSym);cf h0=D(S(M(y0,e),M(b,y1)),det),h1=D(S(M(a,y1),M(y0,c)),det);hp[(p*4+r)*306+j]=h0;hp[(p*4+r)*306+j+1]=h0;hp[((p+1)*4+r)*306+j]=h1;hp[((p+1)*4+r)*306+j+1]=h1;}}
  for(p=0;p<4;p++)for(r=0;r<4;r++)for(k=0;k<612;k++){float u=p<2?.5f*(float)k:.5f*((float)k-1.f),f=floorf(u),al=u-f;mwSize lo,hi;if(f<0){lo=hi=0;al=0;}else if(f>=305){lo=hi=305;al=0;}else{lo=(mwSize)f;hi=lo+1;}cf x=hp[(p*4+r)*306+lo],y=hp[(p*4+r)*306+hi],z={x.re+al*(y.re-x.re),x.im+al*(y.im-x.im)};h[(p*4+r)*612+k]=z;P(hout+k+r*612+p*612*4+s*612*4*4,z);}
  /* Residual variance on actual DM-RS REs.  Keep this output semantically
     identical to type1_dmrs_type1_mex rather than returning an unused zero. */
  for(g=0;g<2;g++)for(j=0;j<306;j++){p=2*g;k=(xi[j+p*306+s*306*4]-1)%612;for(r=0;r<4;r++){cf pred={0,0},y=G(grid+k+(ns*14+2)*612+r*612*nGridSym);for(mwSize q=p;q<p+2;q++)pred=A(pred,M(h[(q*4+r)*612+k],G(rs+j+q*306+s*306*4)));ne+=Q(S(y,pred));nc++;}}
  for(k=0;k<612;k++){cf w[4][4];W(h,k,lam,w);for(l=0;l<14;l++){int m=map[l*612+k];if(m<0)continue;for(p=0;p<4;p++){cf z={0,0},ref=G(qpsk+(mwSize)m+s*7956+p*7956*nslots);for(r=0;r<4;r++)z=A(z,M(w[p][r],G(grid+k+(ns*14+l)*612+r*612*nGridSym)));float dr=z.re-ref.re,dm=z.im-ref.im;ee[p]+=dr*dr+dm*dm;pp[p]+=Q(ref);err[s+p*nslots]+=(z.re<0)!=bits[2*m+s*15912+p*15912*nslots];err[s+p*nslots]+=(z.im<0)!=bits[2*m+1+s*15912+p*15912*nslots];}}}
  for(p=0;p<4;p++)evm[s+p*nslots]=100*sqrt(ee[p]/fmax(pp[p],1e-30));noise[s]=ne/fmax((double)nc,1.0);
 }
 mxFree(map);mxFree(h);mxFree(hp);
}
