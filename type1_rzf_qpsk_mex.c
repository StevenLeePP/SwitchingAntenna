/*
 * type1_rzf_qpsk_mex.c -- Fixed 4x4 RZF + QPSK hard decision kernel.
 *
 * Input:
 *  received        [NRE x NRx]       complex single
 *  channelAtData   [NRE x NRx x 4]   complex single
 *  expectedQPSK    [NRE x 4]         complex single
 *  expectedBits    [2*NRE x 4]       logical
 *  lambdaScale     scalar             RZF regularisation scale
 *  nSubcarriers    scalar             612 for this experiment
 *  reusePerSC      logical            reuse W[k] over 13 data symbols
 *
 * Output:
 *  equalized       [NRE x 4] complex single
 *  bitErrors       [1 x 4] double
 *  evmPercent      [1 x 4] double
 *
 * The design is intentionally specialised to the fixed Type-A experiment:
 * NRx=NLayer=4 and QPSK.  With one front-loaded DM-RS symbol the channel
 * is time-invariant within a slot model, so reusePerSC computes W[k] only
 * once per subcarrier instead of once per data RE.
 */

#include "mex.h"
#include "matrix.h"
#include <math.h>
#include <string.h>

typedef struct { float re, im; } cf32;

static cf32 cadd(cf32 a, cf32 b) { cf32 z = {a.re+b.re, a.im+b.im}; return z; }
static cf32 csub(cf32 a, cf32 b) { cf32 z = {a.re-b.re, a.im-b.im}; return z; }
static cf32 cmul(cf32 a, cf32 b) {
    cf32 z = {a.re*b.re-a.im*b.im, a.re*b.im+a.im*b.re}; return z;
}
static cf32 cconj(cf32 a) { cf32 z = {a.re, -a.im}; return z; }
static cf32 cscale(cf32 a, float s) { cf32 z = {a.re*s, a.im*s}; return z; }
static float cabs2(cf32 a) { return a.re*a.re + a.im*a.im; }
static cf32 cdivv(cf32 a, cf32 b) {
    float d = cabs2(b) + 1.0e-20f;
    cf32 z = {(a.re*b.re+a.im*b.im)/d, (a.im*b.re-a.re*b.im)/d}; return z;
}
static cf32 from_mx(const mxComplexSingle *x) { cf32 z = {x->real, x->imag}; return z; }
static void to_mx(mxComplexSingle *x, cf32 z) { x->real = z.re; x->imag = z.im; }

static void require_complex_single(const mxArray *a, const char *name)
{
    if (!mxIsSingle(a) || !mxIsComplex(a))
        mexErrMsgIdAndTxt("type1:rzf:Type", "%s must be complex single.", name);
}

/* A*X=B, with A Hermitian positive definite after RZF regularisation.
 * Partial-pivot Gauss-Jordan is robust for the measured condition numbers. */
static int solve4(cf32 a[4][4], cf32 b[4][4], cf32 x[4][4])
{
    int i, j, k, pivot;
    for (i = 0; i < 4; ++i) {
        float largest = -1.0f;
        pivot = i;
        for (k = i; k < 4; ++k) {
            float v = cabs2(a[k][i]);
            if (v > largest) { largest = v; pivot = k; }
        }
        if (largest < 1.0e-16f) return 0;
        if (pivot != i) {
            for (j = 0; j < 4; ++j) {
                cf32 t = a[i][j]; a[i][j] = a[pivot][j]; a[pivot][j] = t;
                t = b[i][j]; b[i][j] = b[pivot][j]; b[pivot][j] = t;
            }
        }
        {
            cf32 invPivot = cdivv((cf32){1.0f,0.0f}, a[i][i]);
            for (j = i; j < 4; ++j) a[i][j] = cmul(a[i][j], invPivot);
            for (j = 0; j < 4; ++j) b[i][j] = cmul(b[i][j], invPivot);
        }
        for (k = 0; k < 4; ++k) {
            cf32 f;
            if (k == i) continue;
            f = a[k][i];
            for (j = i; j < 4; ++j) a[k][j] = csub(a[k][j], cmul(f, a[i][j]));
            for (j = 0; j < 4; ++j) b[k][j] = csub(b[k][j], cmul(f, b[i][j]));
        }
    }
    memcpy(x, b, 16*sizeof(cf32));
    return 1;
}

static void make_weight(const mxComplexSingle *h, mwSize nre, mwSize nrx,
                        mwSize index, float lambdaScale, cf32 w[4][4])
{
    cf32 gram[4][4] = {{{0}}};
    cf32 rhs[4][4] = {{{0}}};
    cf32 solved[4][4];
    float power = 0.0f;
    int r, i, j;
    for (r = 0; r < 4; ++r)
        for (i = 0; i < 4; ++i) {
            cf32 hi = from_mx(h + index + (mwSize)r*nre + (mwSize)i*nre*nrx);
            power += cabs2(hi);
        }
    for (i = 0; i < 4; ++i) {
        for (j = 0; j < 4; ++j) {
            cf32 sum = {0.0f, 0.0f};
            for (r = 0; r < 4; ++r) {
                cf32 hi = from_mx(h + index + (mwSize)r*nre + (mwSize)i*nre*nrx);
                cf32 hj = from_mx(h + index + (mwSize)r*nre + (mwSize)j*nre*nrx);
                sum = cadd(sum, cmul(cconj(hi), hj));
            }
            gram[i][j] = sum;
        }
        gram[i][i].re += lambdaScale * fmaxf(power / 4.0f, 1.0e-20f);
        for (r = 0; r < 4; ++r) {
            cf32 hi = from_mx(h + index + (mwSize)r*nre + (mwSize)i*nre*nrx);
            rhs[i][r] = cconj(hi);
        }
    }
    if (!solve4(gram, rhs, solved)) {
        memset(w, 0, 16*sizeof(cf32));
    } else {
        memcpy(w, solved, 16*sizeof(cf32));
    }
}

void mexFunction(int nlhs, mxArray **plhs, int nrhs, const mxArray **prhs)
{
    const mxComplexSingle *y, *h, *reference;
    const mxLogical *bits;
    mxComplexSingle *out;
    double *errors, *evm;
    mwSize nre, nrx, nbits, nsc, ntime, index, base;
    int reuse, layer, r;
    float lambdaScale;
    cf32 *weights;
    double errorEnergy[4] = {0,0,0,0};
    double referenceEnergy[4] = {0,0,0,0};
    double bitErrorCount[4] = {0,0,0,0};

    if (nrhs != 7 || nlhs < 3)
        mexErrMsgIdAndTxt("type1:rzf:Args", "Expected 7 inputs and 3 outputs.");
    require_complex_single(prhs[0], "received");
    require_complex_single(prhs[1], "channelAtData");
    require_complex_single(prhs[2], "expectedQPSK");
    if (!mxIsLogical(prhs[3]))
        mexErrMsgIdAndTxt("type1:rzf:Bits", "expectedBits must be logical.");
    nre = mxGetM(prhs[0]); nrx = mxGetN(prhs[0]);
    if (nrx != 4 || mxGetM(prhs[2]) != nre || mxGetN(prhs[2]) != 4)
        mexErrMsgIdAndTxt("type1:rzf:Shape", "This kernel requires NRE-by-4 data.");
    if (mxGetNumberOfDimensions(prhs[1]) != 3 || mxGetDimensions(prhs[1])[0] != nre ||
        mxGetDimensions(prhs[1])[1] != 4 || mxGetDimensions(prhs[1])[2] != 4)
        mexErrMsgIdAndTxt("type1:rzf:Shape", "channelAtData must be NRE-by-4-by-4.");
    nbits = mxGetM(prhs[3]);
    if (nbits != 2*nre || mxGetN(prhs[3]) != 4)
        mexErrMsgIdAndTxt("type1:rzf:Shape", "expectedBits must be 2*NRE-by-4.");
    lambdaScale = (float)mxGetScalar(prhs[4]);
    nsc = (mwSize)mxGetScalar(prhs[5]);
    reuse = mxIsLogicalScalarTrue(prhs[6]);
    if (nsc == 0 || nre % nsc != 0)
        mexErrMsgIdAndTxt("type1:rzf:Subcarriers", "NRE must be divisible by nSubcarriers.");
    ntime = nre / nsc;

    y = mxGetComplexSingles(prhs[0]);
    h = mxGetComplexSingles(prhs[1]);
    reference = mxGetComplexSingles(prhs[2]);
    bits = mxGetLogicals(prhs[3]);
    plhs[0] = mxCreateNumericMatrix(nre, 4, mxSINGLE_CLASS, mxCOMPLEX);
    out = mxGetComplexSingles(plhs[0]);
    plhs[1] = mxCreateDoubleMatrix(1, 4, mxREAL);
    plhs[2] = mxCreateDoubleMatrix(1, 4, mxREAL);
    errors = mxGetDoubles(plhs[1]); evm = mxGetDoubles(plhs[2]);
    weights = (cf32 *)mxCalloc((reuse ? nsc : nre) * 16, sizeof(cf32));

    if (reuse) {
        for (base = 0; base < nsc; ++base)
            make_weight(h, nre, nrx, base, lambdaScale,
                        (cf32 (*)[4])(weights + base*16));
    }
    for (index = 0; index < nre; ++index) {
        cf32 localWeight[4][4];
        cf32 *w = reuse ? weights + (index % nsc)*16 : &localWeight[0][0];
        if (!reuse) make_weight(h, nre, nrx, index, lambdaScale, localWeight);
        for (layer = 0; layer < 4; ++layer) {
            cf32 sum = {0.0f, 0.0f};
            cf32 ref;
            float dr, di;
            for (r = 0; r < 4; ++r) {
                cf32 yr = from_mx(y + index + (mwSize)r*nre);
                sum = cadd(sum, cmul(w[layer*4 + r], yr));
            }
            to_mx(out + index + (mwSize)layer*nre, sum);
            ref = from_mx(reference + index + (mwSize)layer*nre);
            dr = sum.re-ref.re; di = sum.im-ref.im;
            errorEnergy[layer] += (double)dr*dr + (double)di*di;
            referenceEnergy[layer] += cabs2(ref);
            /* nrSymbolModulate QPSK: b0 controls I, b1 controls Q. */
            bitErrorCount[layer] += ((sum.re < 0.0f) != bits[2*index + (mwSize)layer*nbits]);
            bitErrorCount[layer] += ((sum.im < 0.0f) != bits[2*index + 1 + (mwSize)layer*nbits]);
        }
    }
    for (layer = 0; layer < 4; ++layer) {
        errors[layer] = bitErrorCount[layer];
        evm[layer] = 100.0 * sqrt(errorEnergy[layer] / fmax(referenceEnergy[layer], 1.0e-30));
    }
    mxFree(weights);
}
