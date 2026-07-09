function carrier = type1_carrier_config(cfg, slot)
%TYPE1_CARRIER_CONFIG Create a standard nrCarrierConfig object.
%  Used by TX waveform construction and RX OFDM demodulation.

if nargin < 2
    slot = 0;
end
carrier = nrCarrierConfig;
carrier.NCellID = cfg.pci;
carrier.NSizeGrid = cfg.nRB;
carrier.SubcarrierSpacing = cfg.scsKHz;
carrier.CyclicPrefix = cfg.cpType;
carrier.NSlot = slot;  % set the current slot number for DM-RS sequence
end
