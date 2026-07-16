#include "mex.h"
#include <stdbool.h>

static void require(bool condition, const char *id, const char *message) {
    if (!condition) mexErrMsgIdAndTxt(id, "%s", message);
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    require(nrhs == 2 && nlhs <= 1, "type1:R20IirArgs", "Expected target and beta.");
    const mxArray *target = prhs[0], *betaArray = prhs[1];
    mwSize n = mxGetNumberOfElements(target);
    require(n > 0 && mxGetNumberOfElements(betaArray) == n, "type1:R20IirShape", "Lengths differ.");
    require(mxIsComplex(target) && (mxIsSingle(target) || mxIsDouble(target)),
            "type1:R20IirTarget", "Target must be complex single or double.");
    require(mxIsDouble(betaArray) && !mxIsComplex(betaArray), "type1:R20IirBeta", "Beta must be real double.");
    const double *beta = mxGetDoubles(betaArray);
    plhs[0] = mxCreateNumericMatrix(n, 1, mxGetClassID(target), mxCOMPLEX);
    if (mxIsSingle(target)) {
        const mxComplexSingle *x = mxGetComplexSingles(target);
        mxComplexSingle *y = mxGetComplexSingles(plhs[0]); y[0] = x[0];
        for (mwSize k = 1; k < n; ++k) {
            float b = (float)beta[k], a = 1.0f-b;
            y[k].real = a*y[k-1].real+b*x[k].real;
            y[k].imag = a*y[k-1].imag+b*x[k].imag;
        }
    } else {
        const mxComplexDouble *x = mxGetComplexDoubles(target);
        mxComplexDouble *y = mxGetComplexDoubles(plhs[0]); y[0] = x[0];
        for (mwSize k = 1; k < n; ++k) {
            double b = beta[k], a = 1.0-b;
            y[k].real = a*y[k-1].real+b*x[k].real;
            y[k].imag = a*y[k-1].imag+b*x[k].imag;
        }
    }
}
