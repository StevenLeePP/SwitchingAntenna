#!/usr/bin/env python3
"""Render the repository architecture figure used by README.md."""

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "images" / "system_architecture.png"


def box(ax, xy, width, height, text, color, edge, fontsize=9.5, linewidth=1.4):
    patch = FancyBboxPatch(
        xy,
        width,
        height,
        boxstyle="round,pad=0.012,rounding_size=0.015",
        facecolor=color,
        edgecolor=edge,
        linewidth=linewidth,
        zorder=3,
    )
    ax.add_patch(patch)
    ax.text(
        xy[0] + width / 2,
        xy[1] + height / 2,
        text,
        ha="center",
        va="center",
        fontsize=fontsize,
        color="#17202A",
        linespacing=1.28,
        zorder=4,
    )
    return patch


def arrow(ax, start, end, color="#34495E", style="-|>", width=1.5, dashed=False):
    patch = FancyArrowPatch(
        start,
        end,
        arrowstyle=style,
        mutation_scale=12,
        linewidth=width,
        linestyle="--" if dashed else "-",
        color=color,
        connectionstyle="arc3,rad=0",
        zorder=2,
    )
    ax.add_patch(patch)
    return patch


def lane(ax, y, height, label, color):
    ax.add_patch(
        Rectangle((0.015, y), 0.97, height, facecolor=color, edgecolor="none", zorder=0)
    )
    ax.text(
        0.027,
        y + height - 0.025,
        label,
        ha="left",
        va="top",
        fontsize=10.5,
        fontweight="bold",
        color="#34495E",
    )


def main():
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9})
    fig, ax = plt.subplots(figsize=(16, 9), dpi=180)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor("white")

    ax.text(
        0.5,
        0.965,
        "Type-A 4T4R C/MEX Real-Time Link and Offline Research Architecture",
        ha="center",
        va="center",
        fontsize=17,
        fontweight="bold",
        color="#17202A",
    )
    ax.text(
        0.5,
        0.932,
        "One shared reference, two execution paths: deterministic real-time data plane and reproducible impairment research",
        ha="center",
        va="center",
        fontsize=10,
        color="#5D6D7E",
    )

    lane(ax, 0.57, 0.33, "REAL-TIME OTA DATA PLANE", "#F4F8FB")
    lane(ax, 0.34, 0.20, "MATLAB CONTROL / DIAGNOSTICS", "#FAF7F0")
    lane(ax, 0.05, 0.26, "OFFLINE RESEARCH PLANE (PHASE 0–3)", "#F5FAF5")

    c_ref = "#E8F1FB"
    c_hw = "#EAF7F0"
    c_mex = "#FFF1D6"
    c_mat = "#F7EAF8"
    c_out = "#EBEEF1"
    e_ref = "#2874A6"
    e_hw = "#1E8449"
    e_mex = "#D68910"
    e_mat = "#7D3C98"
    e_out = "#566573"

    box(ax, (0.035, 0.665), 0.115, 0.105, "Shared 10 ms\nType-A reference\n4-layer QPSK", c_ref, e_ref)
    box(ax, (0.18, 0.665), 0.105, 0.105, "YunSDR TX\n30.72 MS/s\n4 RF ports", c_hw, e_hw)
    box(ax, (0.315, 0.665), 0.105, 0.105, "OTA channel\n3.2 GHz", c_hw, e_hw)
    box(ax, (0.45, 0.665), 0.115, 0.105, "YunSDR RX\n4 x 122.88 MS/s\nraw IQ", c_hw, e_hw)
    box(ax, (0.595, 0.645), 0.145, 0.145, "type1_yunsdr_rx_mex\nDMA pthread + native ring\ndropNew / pending / audit\n4-phase + CFO + FFT", c_mex, e_mex)
    box(ax, (0.77, 0.645), 0.125, 0.145, "frame-PHY MEX\nType-1 DM-RS\n4x4 RZF + QPSK\nBER / EVM / Hhat", c_mex, e_mex)
    box(ax, (0.92, 0.665), 0.065, 0.105, "MAT\nresults", c_out, e_out, fontsize=9)

    arrow(ax, (0.15, 0.718), (0.18, 0.718))
    arrow(ax, (0.285, 0.718), (0.315, 0.718))
    arrow(ax, (0.42, 0.718), (0.45, 0.718))
    arrow(ax, (0.565, 0.718), (0.595, 0.718))
    arrow(ax, (0.74, 0.718), (0.77, 0.718))
    arrow(ax, (0.895, 0.718), (0.92, 0.718))

    ax.text(0.6675, 0.805, "persistent native data plane", ha="center", fontsize=8.8, color=e_mex, fontweight="bold")
    ax.plot([0.585, 0.905], [0.815, 0.815], color=e_mex, linewidth=1.3)

    box(ax, (0.10, 0.385), 0.17, 0.095, "PSS / PBCH acquisition\nCP-CFO and timing lock", c_mat, e_mat)
    box(ax, (0.33, 0.385), 0.17, 0.095, "Two-stage startup\nflush + aligned arm", c_mat, e_mat)
    box(ax, (0.56, 0.385), 0.17, 0.095, "Low-rate health checks\nCFO / timing updates", c_mat, e_mat)
    box(ax, (0.79, 0.385), 0.15, 0.095, "Plots and MATLAB\nequivalence tests", c_mat, e_mat)
    arrow(ax, (0.27, 0.432), (0.33, 0.432), color=e_mat)
    arrow(ax, (0.50, 0.432), (0.56, 0.432), color=e_mat)
    arrow(ax, (0.73, 0.432), (0.79, 0.432), color=e_mat)
    arrow(ax, (0.415, 0.48), (0.64, 0.645), color=e_mat, dashed=True)
    arrow(ax, (0.645, 0.48), (0.705, 0.645), color=e_mat, dashed=True)
    arrow(ax, (0.18, 0.48), (0.50, 0.665), color=e_mat, dashed=True)
    ax.text(0.515, 0.535, "control only", fontsize=8.5, color=e_mat, rotation=29)

    box(ax, (0.035, 0.105), 0.115, 0.105, "Shared reference\nand fixed seeds", c_ref, e_ref)
    box(ax, (0.18, 0.085), 0.16, 0.145, "Controlled models\nCFO / timing / power\nM-port TDL-A + A/S\nswitch / jitter / RX-LO", c_mat, e_mat)
    box(ax, (0.37, 0.085), 0.15, 0.145, "Receiver variants\nMATLAB baseline\nICI-DF / DDCE / CPE\ngenie diagnostics", c_mat, e_mat)
    box(ax, (0.55, 0.085), 0.14, 0.145, "Paired statistics\nBER / EVM^2 / outage\nWilson / McNemar\npre-registered gates", c_mat, e_mat)
    box(ax, (0.72, 0.085), 0.12, 0.145, "MAT + PNG\nreproducible\nresearch assets", c_out, e_out)
    box(ax, (0.87, 0.105), 0.115, 0.105, "OTA raw122\npaired model\nanchor", c_hw, e_hw)
    arrow(ax, (0.15, 0.158), (0.18, 0.158))
    arrow(ax, (0.34, 0.158), (0.37, 0.158))
    arrow(ax, (0.52, 0.158), (0.55, 0.158))
    arrow(ax, (0.69, 0.158), (0.72, 0.158))
    arrow(ax, (0.87, 0.158), (0.84, 0.158), color=e_hw)
    arrow(ax, (0.507, 0.665), (0.925, 0.21), color=e_hw, dashed=True)
    ax.text(0.80, 0.27, "qualified captures", fontsize=8.5, color=e_hw, rotation=-31)

    ax.text(0.03, 0.018, "Orange: native C/MEX hot path   Purple: MATLAB algorithms/control   Green: RF/OTA   Blue: shared reference", fontsize=8.5, color="#5D6D7E")
    ax.text(0.97, 0.018, "Generated by tools/render_architecture.py", ha="right", fontsize=8, color="#7B7D7D")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUTPUT, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(OUTPUT)


if __name__ == "__main__":
    main()
