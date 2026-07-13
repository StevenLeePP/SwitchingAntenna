function [bits, metadata] = type1_make_payload_bits(nBits, slot, layer, cfg)
%TYPE1_MAKE_PAYLOAD_BITS Build meaningful deterministic source data.
%  Each slot/layer starts with an ASCII telemetry record that identifies
%  the virtual source, frame, slot, position, temperature and sequence.
%  The rest is deterministic PRBS so that the OFDM waveform keeps
%  noise-like spectral and PAPR properties.

arguments
    nBits (1,1) double {mustBeInteger,mustBePositive}
    slot (1,1) double {mustBeInteger,mustBeNonnegative}
    layer (1,1) double {mustBeInteger,mustBePositive}
    cfg (1,1) struct
end

positionsCm = [-150 0 100; -50 100 100; 50 -100 100; 150 0 100];
if layer <= size(positionsCm, 1)
    positionCm = positionsCm(layer, :);
else
    positionCm = [100 * (layer - 1), 0, 100];
end
temperatureCentiC = 2250 + 25 * layer;
sequence = uint32(cfg.payloadFrameId * cfg.slotsPerFrame + slot);
message = sprintf([ ...
    'NR4T|VER=2|SRC=%u|FRAME=%04u|SLOT=%02u|' ...
    'T_US=%06u|POS_CM=%+05d,%+05d,%+05d|' ...
    'TEMP_C=%+06.2f|SEQ=%08u|'], ...
    layer, cfg.payloadFrameId, slot, round(slot * 500), ...
    positionCm(1), positionCm(2), positionCm(3), ...
    temperatureCentiC / 100, sequence);

messageBytes = uint8(message);
messageBitMatrix = false(numel(messageBytes), 8);
for bitPosition = 1:8
    messageBitMatrix(:, bitPosition) = ...
        bitget(messageBytes(:), 9 - bitPosition) ~= 0;
end
messageBits = reshape(messageBitMatrix.', [], 1);
headerLength = min(numel(messageBits), nBits);

bits = false(nBits, 1);
bits(1:headerLength) = messageBits(1:headerLength);
if headerLength < nBits
    stream = RandStream('mt19937ar', 'Seed', ...
        cfg.payloadSeedBase + 1000 * slot + layer);
    bits(headerLength + 1:end) = logical(randi( ...
        stream, [0 1], nBits - headerLength, 1));
end

metadata = struct;
metadata.sourceId = layer;
metadata.frameId = cfg.payloadFrameId;
metadata.slotId = slot;
metadata.sequence = double(sequence);
metadata.sampleTimeUs = slot * 500;
metadata.positionCm = positionCm;
metadata.temperatureC = temperatureCentiC / 100;
metadata.message = message;
metadata.headerBits = headerLength;
metadata.totalBits = nBits;
metadata.format = 'ASCII telemetry header (MSB first) + deterministic PRBS';
end
