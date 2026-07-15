function [virtualDrive30,beta0] = type1_received_drive(stitched122, settlingRiseNs, rawSampleRateHz)
%TYPE1_RECEIVED_DRIVE Build the observable first-order switch drive.
%   For nominal static beta0, the switch recursion gives the directly
%   observable proxy dHat[n]=(y[n]-y[n-1])/beta0.  This function deliberately
%   uses only the stitched single-chain ADC stream and configured nominal
%   rise time; it never reads settling target/state or dynamic beta truth.

arguments
    stitched122 (:,1) {mustBeNumeric}
    settlingRiseNs (1,1) double {mustBeNonnegative}
    rawSampleRateHz (1,1) double {mustBePositive}
end
assert(mod(numel(stitched122),4)==0,'type1:ReceivedDriveLength', ...
    'stitched122 length must be divisible by four.');
if settlingRiseNs==0
    beta0=1;
else
    tau0=settlingRiseNs*1e-9/log(9);
    beta0=1-exp(-1/(rawSampleRateHz*tau0));
end
previous=[zeros(1,1,'like',stitched122);stitched122(1:end-1)];
drive=(stitched122-previous)/beta0;
virtualDrive30=reshape(drive,4,[]).';
end
