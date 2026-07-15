function type1_validate_whitened_rzf()
%TYPE1_VALIDATE_WHITENED_RZF Regression before Phase-2 algorithm claims.
p = type1_load_package(); s = type1_offline_sim_config();
s.frames = 1; s.assertIdealBaseline = false;
link = type1_offline_link(p, s, RandStream('mt19937ar', 'Seed', 20260718));
standard = type1_analyze(link.virtualRx30, p);
white = type1_analyze_whitened_rzf(link.virtualRx30, p);
assert(all(standard.infoBitErrors == 0, 'all') && all(white.infoBitErrors == 0, 'all'), ...
    'type1:WhitenedRZF', 'Ideal-link whitened RZF regression failed.');
for k = 1:size(white.residualCovariance, 3)
    assert(all(eig(white.residualCovariance(:, :, k)) > 0), ...
        'type1:WhitenedRZF', 'DM-RS residual covariance is not positive definite.');
end
fprintf('Whitened-RZF ideal regression PASSED (BER standard/white = 0/0).\n');
end
