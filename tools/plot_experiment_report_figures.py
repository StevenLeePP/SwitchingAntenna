#!/usr/bin/env python3
"""Regenerate compact figures used only by EXPERIMENT_REPORT.md.

The arrays below are frozen audit values already recorded in EXPERT_REVIEW.md
and REVIEW_VERDICTS.md.  This script does not simulate a waveform and must not
be cited as an independent experiment.  Its purpose is to turn the reviewed
numbers into readable figures without changing their statistical meaning.
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "images"
OUT.mkdir(parents=True, exist_ok=True)


def finish(fig, name):
    fig.suptitle("Frozen audit values — visualization only", fontsize=9, color="0.35")
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(OUT / name, dpi=180, bbox_inches="tight")
    plt.close(fig)


def realtime():
    fig, ax = plt.subplots(1, 2, figsize=(10, 3.7))
    stages = np.array([2.142, 5.141, 1.943])
    ax[0].barh(["extract", "FFT", "PHY"], stages, color=["#4c78a8", "#f58518", "#54a24b"])
    ax[0].axvline(10, color="black", ls="--", label="10 ms frame budget")
    ax[0].set_xlabel("time per decoded frame (ms)")
    ax[0].set_title("60 s direct-RX stage timing")
    ax[0].legend(fontsize=8)
    for i, v in enumerate(stages):
        ax[0].text(v + 0.12, i, f"{v:.3f}", va="center", fontsize=8)
    labels = ["start", "peak", "final"]
    old = [482, 558, 214]
    two = [84, 103, 15]
    x = np.arange(3)
    ax[1].bar(x - 0.18, old, 0.36, label="old startup", color="#e45756")
    ax[1].bar(x + 0.18, two, 0.36, label="two-stage", color="#72b7b2")
    ax[1].set_xticks(x, labels)
    ax[1].set_ylabel("pending 1 ms DMA blocks")
    ax[1].set_title("10 s startup queue summary")
    ax[1].legend(fontsize=8)
    finish(fig, "experiment_realtime_queue.png")


def phase0():
    fig, ax = plt.subplots(1, 2, figsize=(10, 3.7))
    evm = [2.718, 2.775, 2.714, 2.738]
    ax[0].bar(np.arange(1, 5), evm, color="#4c78a8")
    ax[0].set_xticks(np.arange(1, 5))
    ax[0].set_xlabel("layer")
    ax[0].set_ylabel("RMS EVM (%)")
    ax[0].set_ylim(0, 3.2)
    ax[0].set_title("Phase-0 four-layer baseline")
    ax[0].text(0.03, 0.93, "BER: 0 errors in 3 frames", transform=ax[0].transAxes, fontsize=8)
    ax[1].axhline(850, color="black", ls="--", label="configured 850 Hz")
    ax[1].errorbar([1], [862.5], yerr=[[1.5], [1.5]], fmt="o", capsize=6, color="#f58518", label="observed range 861–864 Hz")
    ax[1].axhspan(825, 875, color="#54a24b", alpha=0.14, label="predefined ±25 Hz gate")
    ax[1].set_xlim(0.5, 1.5)
    ax[1].set_xticks([])
    ax[1].set_ylabel("common CFO (Hz)")
    ax[1].set_title("CP-based CFO regression")
    ax[1].legend(fontsize=8, loc="lower right")
    finish(fig, "experiment_phase0_baseline.png")


def multiuser_and_ota():
    fig, ax = plt.subplots(1, 3, figsize=(13, 3.8))
    before = np.array([0, 0.0136501, 0.2730664, 0.2586895])
    after = np.array([0, 5.8656e-5, 9.4897e-4, 0])
    floor = 1e-7
    x = np.arange(1, 5)
    ax[0].semilogy(x, np.maximum(before, floor), "o-", label="common CFO only")
    ax[0].semilogy(x, np.maximum(after, floor), "o-", label="per-user CFO")
    ax[0].set_xticks(x)
    ax[0].set_xlabel("layer")
    ax[0].set_ylabel("BER (zero shown at plot floor)")
    ax[0].set_title("Independent-user CFO")
    ax[0].legend(fontsize=8)
    residual = [-171.4, 300.9, 792.9, -737.5]
    ax[1].bar(x, residual, color=["#4c78a8", "#f58518", "#54a24b", "#e45756"])
    ax[1].axhline(1000, color="black", ls="--")
    ax[1].axhline(-1000, color="black", ls="--", label="±1 kHz ambiguity")
    ax[1].axhspan(750, 1000, color="#e45756", alpha=0.12)
    ax[1].axhspan(-1000, -750, color="#e45756", alpha=0.12, label="warning region")
    ax[1].set_xticks(x)
    ax[1].set_xlabel("layer")
    ax[1].set_ylabel("estimated residual CFO (Hz)")
    ax[1].set_title("Estimator operating margin")
    ax[1].legend(fontsize=8)
    metrics = ["EVM (%)", "cond(H) P95"]
    ideal = [2.1778, 4.4739]
    impaired = [2.2569, 5.6021]
    z = np.arange(2)
    ax[2].bar(z - 0.18, ideal, 0.36, label="ideal")
    ax[2].bar(z + 0.18, impaired, 0.36, label="25 dB / 5 ns")
    ax[2].set_xticks(z, metrics)
    ax[2].set_title("Same-capture OTA replay")
    ax[2].legend(fontsize=8)
    finish(fig, "experiment_multiuser_cfo_ota.png")


def switch_dynamics():
    fig, ax = plt.subplots(1, 3, figsize=(13, 3.8))
    fast = [0, 0.6, 1.0]
    ber = [0, np.mean([1.722e-3, 9.427e-4, 8.547e-4, 9.175e-4]), np.mean([9.835e-3, 7.648e-3, 7.567e-3, 7.604e-3])]
    ax[0].semilogy(fast, np.maximum(ber, 1e-7), "o-")
    ax[0].set_xlabel("fast settling fraction")
    ax[0].set_ylabel("mean four-layer BER")
    ax[0].set_title("Time-varying settling creates BER")
    tc = [0, 8, 100, 1000]
    mid = [1.7e-3, 2.0e-3, 6.0e-3, 9.7e-3]
    lo = [1.7e-3, 2.0e-3, 5.0e-3, 8.2e-3]
    hi = [1.7e-3, 2.0e-3, 7.0e-3, 1.12e-2]
    ax[1].errorbar(tc, mid, yerr=[np.array(mid) - np.array(lo), np.array(hi) - np.array(mid)], fmt="o-", capsize=4)
    ax[1].set_xscale("symlog", linthresh=8)
    ax[1].set_yscale("log")
    ax[1].set_xlabel("OU correlation time (ns; 0=i.i.d.)")
    ax[1].set_ylabel("reported BER range")
    ax[1].set_title("Equal variance, slower jitter is worse")
    methods = ["RZF", "DF Q0", "DF Q6", "DF Q12", "genie"]
    vals = [0.00964, 0.00972, 0.00598, 0.00481, 0]
    ax[2].bar(methods, vals, color=["#4c78a8", "#e45756", "#72b7b2", "#54a24b", "#b279a2"])
    ax[2].tick_params(axis="x", rotation=30)
    ax[2].set_ylabel("mean BER")
    ax[2].set_title("Per-symbol ICI-kernel recovery")
    finish(fig, "experiment_switch_dynamics.png")


def full_stack():
    fig, ax = plt.subplots(1, 3, figsize=(13, 3.8))
    labels = ["L0", "L1", "L2", "L3"]
    r7 = np.array([0.25544, 0.30021, 0.30183, 0.25544]) * 100
    r8 = np.array([0.00516, 0.01845, 0.01777, 0.00516]) * 100
    x = np.arange(4)
    ax[0].bar(x - 0.18, r7, 0.36, label="before timing repair")
    ax[0].bar(x + 0.18, r8, 0.36, label="after timing repair")
    ax[0].set_xticks(x, labels)
    ax[0].set_ylabel("median BER (%)")
    ax[0].set_title("Full-stack L0–L3 staircase")
    ax[0].legend(fontsize=8)
    banks = ["single\nseed1", "double\nseed1", "single\nseed2", "double\nseed2"]
    capture = [0.2617, 0.4746, 0.3527, 0.5134]
    ax[1].bar(banks, capture, color=["#4c78a8", "#54a24b", "#4c78a8", "#54a24b"])
    ax[1].axhline(0.5, color="black", ls="--", label="50% truth gate")
    ax[1].set_ylabel("truth-residual capture")
    ax[1].set_title("Kernel model ceiling")
    ax[1].legend(fontsize=8)
    seeds = ["20261001", "20261003"]
    ddce = [0.0211, 0.0805]
    received = [0.1089, 0.4065]
    z = np.arange(2)
    ax[2].bar(z - 0.18, ddce, 0.36, label="DDCE")
    ax[2].bar(z + 0.18, received, 0.36, label="DDCE + received drive")
    ax[2].axhline(0.10, color="black", ls="--", label="10 pp increment gate")
    ax[2].set_xticks(z, seeds)
    ax[2].set_ylabel("gap closure")
    ax[2].set_title("Integration boundary is seed-dependent")
    ax[2].legend(fontsize=8)
    finish(fig, "experiment_full_stack_diagnostics.png")


def ota_r15():
    fig, ax = plt.subplots(1, 2, figsize=(10, 3.8))
    gain = [25, 30, 35]
    ota = [0.2120, 1.0129, 0.7592]
    offline = [0.4936, 0.3699, 0.3199]
    x = np.arange(3)
    ax[0].bar(x - 0.18, ota, 0.36, label="OTA")
    ax[0].bar(x + 0.18, offline, 0.36, label="matched-SNR offline")
    ax[0].set_xticks(x, gain)
    ax[0].set_xlabel("RX gain setting (dB; not an SNR axis)")
    ax[0].set_ylabel("median normalized EVM² increment")
    ax[0].set_title("15 paired captures: group medians")
    ax[0].legend(fontsize=8)
    ratio = [0.430, 2.738, 2.373]
    ax[1].bar(x, ratio, color="#f58518")
    ax[1].axhline(2.0, color="black", ls="--", label="preregistered upper limit")
    ax[1].axhline(2.1120, color="#e45756", ls=":", label="overall median ratio 2.112")
    ax[1].set_xticks(x, gain)
    ax[1].set_xlabel("RX gain setting (dB)")
    ax[1].set_ylabel("OTA increment / offline increment")
    ax[1].set_title("Power-domain ratio no-go")
    ax[1].legend(fontsize=8)
    finish(fig, "experiment_ota_r15_cross_validation.png")


if __name__ == "__main__":
    plt.rcParams.update({"axes.grid": True, "grid.alpha": 0.25, "font.size": 9})
    realtime()
    phase0()
    multiuser_and_ota()
    switch_dynamics()
    full_stack()
    ota_r15()
    print(f"Wrote report figures to {OUT}")
