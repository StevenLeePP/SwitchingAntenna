function [stitched, virtualRF] = type1_digital_switch(raw122)
%TYPE1_DIGITAL_SWITCH Four-phase switch and 122.88-to-30.72 de-interleaver.
%
%  Models a high-speed RF switch that polls 4 antennas at 122.88 MS/s:
%    n mod 4 = 0 -> RX1,  1 -> RX2,  2 -> RX3,  3 -> RX4
%
%  Input:  raw122    [N x 4]  four-channel 122.88 MS/s IQ samples
%  Output: stitched  [N x 1]  single-RF-chain 122.88 MS/s stream
%          virtualRF [N/4 x 4] four de-interleaved 30.72 MS/s streams
%
%  The 4-phase de-interleaving introduces a fixed 8.138 ns offset
%  between virtual channels, which appears as a linear phase slope
%  in the frequency domain and is absorbed by DM-RS channel estimation.

arguments
    raw122 {mustBeNumeric}
end
assert(size(raw122, 2) == 4, 'Input must have exactly 4 columns (RX channels).');
assert(mod(size(raw122, 1), 4) == 0, 'Number of samples must be a multiple of 4.');

% Phase 1: Four-phase polling -> single 122.88 MS/s RF chain emulation
stitched = complex(zeros(size(raw122, 1), 1, 'like', raw122));
for phase = 1:4
    indices = phase:4:size(raw122, 1);
    stitched(indices) = raw122(indices, phase);
end

% Phase 2: De-interleave by factor 4 -> four 30.72 MS/s virtual streams
%   virtualRF(m, q) = stitched(4*(m-1) + q),  q=1..4
virtualRF = reshape(stitched, 4, []).';
end
