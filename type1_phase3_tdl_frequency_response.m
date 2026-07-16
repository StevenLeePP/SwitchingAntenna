function H = type1_phase3_tdl_frequency_response(channel, frequencyHz)
%TYPE1_PHASE3_TDL_FREQUENCY_RESPONSE Evaluate the saved TDL taps at tones.

arguments
    channel (1,1) struct
    frequencyHz (1,:) double
end
assert(isfield(channel, 'gains') && isfield(channel, 'delaysNormalized') && ...
    isfield(channel, 'delaySpreadNs'), 'type1:Phase3TDLMetadata', ...
    'Incomplete Phase-3 TDL metadata.');
gains = channel.gains;
[M, N, nTaps] = size(gains);
delaySec = channel.delaysNormalized(:) * channel.delaySpreadNs * 1e-9;
assert(numel(delaySec) == nTaps, 'type1:Phase3TDLMetadata', ...
    'TDL delay and gain dimensions differ.');
H = complex(zeros(M, N, numel(frequencyHz)));
for k = 1:numel(frequencyHz)
    phase = exp(-1j * 2*pi * frequencyHz(k) * delaySec);
    H(:, :, k) = sum(gains .* reshape(phase, 1, 1, nTaps), 3);
end
end
