#!/usr/bin/env python3
"""Generate English-only diagrams for the Type-A four-port experiment."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch, Rectangle


OUT = Path(__file__).resolve().parent

COLORS = {
    "idle": "#ECEFF1",
    "ssb": "#D95F59",
    "data": "#4C9BD6",
    "g0": "#F2B447",
    "g1": "#8E6CBE",
    "guard": "#B0BEC5",
    "dark": "#263238",
}


def draw_frame_overview() -> None:
    fig = plt.figure(figsize=(19, 13), constrained_layout=True)
    gs = fig.add_gridspec(3, 2, height_ratios=[0.8, 2.3, 1.4])

    ax = fig.add_subplot(gs[0, :])
    ax.set_title(
        "10 ms NR Frame: One Dedicated SSB Slot + Nineteen Type-A Data Slots",
        fontsize=18,
        weight="bold",
        pad=15,
    )
    for slot in range(20):
        color = COLORS["ssb"] if slot == 0 else COLORS["data"]
        ax.add_patch(Rectangle((slot, 0), 1, 1, facecolor=color,
                               edgecolor="white", linewidth=2))
        ax.text(slot + 0.5, 0.58, f"Slot {slot}", ha="center",
                va="center", fontsize=8 if slot > 9 else 9,
                color="white", weight="bold")
        if slot == 0:
            ax.text(slot + 0.5, 0.22, "SSB", ha="center", va="center",
                    fontsize=9, color="white")
        elif slot in (1, 10, 19):
            ax.text(slot + 0.5, 0.22, "DM-RS + DATA", ha="center",
                    va="center", fontsize=6.5, color="white")
    ax.annotate("0.5 ms per slot", xy=(7, 1.03), xytext=(7, 1.48),
                ha="center", arrowprops={"arrowstyle": "<->", "lw": 1.5})
    ax.annotate("", xy=(7, 1.28), xytext=(8, 1.28),
                arrowprops={"arrowstyle": "<->", "lw": 1.5})
    ax.set_xlim(0, 20)
    ax.set_ylim(-0.05, 1.65)
    ax.set_xticks(range(21))
    ax.set_xlabel("Slot boundary (0.5 ms spacing)")
    ax.set_yticks([])
    ax.spines[:].set_visible(False)

    # Slot 0 view.
    ax0 = fig.add_subplot(gs[1, 0])
    ssb_grid = np.zeros((612, 14), dtype=int)
    ssb_grid[186:426, 2:6] = 1
    ax0.imshow(
        ssb_grid,
        origin="lower",
        aspect="auto",
        interpolation="nearest",
        cmap=ListedColormap([COLORS["idle"], COLORS["ssb"]]),
        vmin=0,
        vmax=1,
    )
    ax0.set_title("Slot 0: Dedicated SS/PBCH Block (TX1 Only)",
                  fontsize=15, weight="bold")
    ax0.set_xlabel("OFDM symbol index in slot")
    ax0.set_ylabel("Active subcarrier index (51 RB = 612)")
    ax0.set_xticks(range(14))
    ax0.set_yticks([0, 185, 305, 425, 611])
    ax0.axhline(185.5, color="white", lw=1)
    ax0.axhline(425.5, color="white", lw=1)
    ax0.text(3.5, 305, "240 subcarriers x 4 symbols\nPSS / SSS / PBCH / PBCH DM-RS",
             ha="center", va="center", color="white", fontsize=11,
             weight="bold")
    ax0.text(9, 80, "TX2, TX3, TX4 silent\nNo custom QPSK payload",
             ha="center", va="center", color=COLORS["dark"], fontsize=11)
    ax0.grid(color="white", alpha=0.25, linewidth=0.5)

    # Representative data-slot view.
    ax1 = fig.add_subplot(gs[1, 1])
    slot_grid = np.ones((612, 14), dtype=int)
    slot_grid[0::2, 2] = 2
    slot_grid[1::2, 2] = 3
    ax1.imshow(
        slot_grid,
        origin="lower",
        aspect="auto",
        interpolation="nearest",
        cmap=ListedColormap(
            [COLORS["idle"], COLORS["data"], COLORS["g0"], COLORS["g1"]]
        ),
        vmin=0,
        vmax=3,
    )
    ax1.set_title("Slots 1...19: Strict Type-A Allocation",
                  fontsize=15, weight="bold")
    ax1.set_xlabel("OFDM symbol index in slot")
    ax1.set_ylabel("Active subcarrier index")
    ax1.set_xticks(range(14))
    ax1.set_yticks([0, 153, 305, 458, 611])
    ax1.axvline(1.5, color="white", lw=2)
    ax1.axvline(2.5, color="white", lw=2)
    ax1.text(2, 305, "TYPE-1\nDM-RS", ha="center", va="center",
             rotation=90, fontsize=12, color="white", weight="bold")
    ax1.text(7.5, 520, "13 full-band QPSK data symbols per layer",
             ha="center", va="center", fontsize=11, color="white",
             weight="bold")
    ax1.legend(
        handles=[
            Patch(facecolor=COLORS["data"], label="Four different data layers"),
            Patch(facecolor=COLORS["g0"], label="CDM group 0: ports 1000/1001"),
            Patch(facecolor=COLORS["g1"], label="CDM group 1: ports 1002/1003"),
        ],
        loc="lower right",
        fontsize=10,
        framealpha=0.95,
    )

    # Transmitter and receiver flow.
    ax2 = fig.add_subplot(gs[2, :])
    ax2.axis("off")
    stages = [
        ("Shared MAT", "bits, coded bits,\nQPSK, DM-RS"),
        ("TX grid", "Slot 0: SSB\nSlots 1-19: Type-A"),
        ("4 physical TX", "Identity mapping\nports 1000...1003"),
        ("4x4 RF channel", "122.88 MS/s RX\nfour switch phases"),
        ("Synchronization", "PSS -> CFO -> SSS\nPBCH/MIB"),
        ("Per-slot receiver", "Type-1 OCC despread\n4x4 RZF -> BER"),
    ]
    x_positions = np.linspace(0.02, 0.84, len(stages))
    for index, ((title, body), x) in enumerate(zip(stages, x_positions)):
        ax2.add_patch(Rectangle((x, 0.25), 0.14, 0.5,
                                transform=ax2.transAxes,
                                facecolor="#F7F9FA",
                                edgecolor=COLORS["dark"], linewidth=1.5))
        ax2.text(x + 0.07, 0.61, title, transform=ax2.transAxes,
                 ha="center", va="center", fontsize=11, weight="bold")
        ax2.text(x + 0.07, 0.41, body, transform=ax2.transAxes,
                 ha="center", va="center", fontsize=9)
        if index < len(stages) - 1:
            ax2.annotate(
                "",
                xy=(x_positions[index + 1], 0.5),
                xytext=(x + 0.14, 0.5),
                xycoords=ax2.transAxes,
                arrowprops={"arrowstyle": "->", "lw": 2,
                            "color": COLORS["dark"]},
            )
    ax2.text(
        0.5,
        0.08,
        "Periodic transmission: the same deterministic 10 ms package repeats",
        transform=ax2.transAxes,
        ha="center",
        fontsize=12,
        style="italic",
    )

    fig.savefig(OUT / "type1_frame_structure.png", dpi=180,
                facecolor="white")
    plt.close(fig)


def draw_dmrs_detail() -> None:
    fig = plt.figure(figsize=(18, 12), constrained_layout=True)
    gs = fig.add_gridspec(2, 2, width_ratios=[1.35, 1])

    ax = fig.add_subplot(gs[:, 0])
    ax.set_title("One-RB Resource Grid: Single-Symbol Type-1 DM-RS",
                 fontsize=17, weight="bold", pad=15)
    for k in range(12):
        for symbol in range(14):
            if symbol == 2:
                group = k % 2
                color = COLORS["g0"] if group == 0 else COLORS["g1"]
                hatch = "////" if group == 0 else "\\\\\\\\"
            else:
                color = COLORS["data"]
                hatch = None
            ax.add_patch(Rectangle((symbol, k), 1, 1, facecolor=color,
                                   edgecolor="white", linewidth=1,
                                   hatch=hatch))
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 12)
    ax.set_aspect("equal")
    ax.set_xticks(np.arange(14) + 0.5, labels=range(14))
    ax.set_yticks(np.arange(12) + 0.5, labels=range(12))
    ax.set_xlabel("OFDM symbol index")
    ax.set_ylabel("Subcarrier index within one RB")
    ax.text(2.5, 6, "FDM\nbetween\nCDM groups", rotation=90,
            ha="center", va="center", color="white", fontsize=12,
            weight="bold")
    ax.legend(
        handles=[
            Patch(facecolor=COLORS["data"],
                  label="QPSK data on all four layers"),
            Patch(facecolor=COLORS["g0"], hatch="////",
                  label="Group 0: ports 1000 and 1001"),
            Patch(facecolor=COLORS["g1"], hatch="\\\\\\\\",
                  label="Group 1: ports 1002 and 1003"),
        ],
        loc="upper center",
        bbox_to_anchor=(0.5, -0.07),
        ncol=1,
        fontsize=11,
    )

    ax_table = fig.add_subplot(gs[0, 1])
    ax_table.axis("off")
    ax_table.set_title("Port Multiplexing", fontsize=16, weight="bold")
    columns = ["3GPP port", "CDM group", "Delta", "Frequency OCC"]
    rows = [
        ["1000", "0", "0", "[+1, +1]"],
        ["1001", "0", "0", "[+1, -1]"],
        ["1002", "1", "1", "[+1, +1]"],
        ["1003", "1", "1", "[+1, -1]"],
    ]
    table = ax_table.table(cellText=rows, colLabels=columns, loc="center",
                           cellLoc="center", colLoc="center")
    table.auto_set_font_size(False)
    table.set_fontsize(11)
    table.scale(1.15, 2.0)
    for (row, _), cell in table.get_celld().items():
        if row == 0:
            cell.set_facecolor(COLORS["dark"])
            cell.set_text_props(color="white", weight="bold")
        elif row in (1, 2):
            cell.set_facecolor("#FFF3D6")
        else:
            cell.set_facecolor("#EEE7F7")
    ax_table.text(
        0.5, 0.11,
        r"$k = 4n + 2k' + \Delta,\quad k'\in\{0,1\}$",
        transform=ax_table.transAxes, ha="center", fontsize=15,
    )
    ax_table.text(
        0.5, 0.02,
        "FDM separates groups; two-chip OCC separates ports inside a group.",
        transform=ax_table.transAxes, ha="center", fontsize=10,
    )

    ax_stats = fig.add_subplot(gs[1, 1])
    ax_stats.axis("off")
    ax_stats.set_title("Resource Accounting", fontsize=16, weight="bold")
    stats = [
        ("Per DM-RS port", "6 RE / RB = 306 RE / slot"),
        ("All four ports", "Two groups fill all 12 RE / RB at symbol 2"),
        ("Per data layer", "612 x 13 = 7,956 QPSK RE / data slot"),
        ("Per 10 ms frame", "19 data slots = 151,164 QPSK RE / layer"),
        ("Coding per slot/layer", "7,950 info bits -> 15,912 coded bits"),
        ("Spatial mapping", "Layer p -> port 1000+p -> physical TX p+1"),
    ]
    y = 0.88
    for title, value in stats:
        ax_stats.add_patch(Rectangle((0.03, y - 0.09), 0.94, 0.115,
                                     transform=ax_stats.transAxes,
                                     facecolor="#F5F7F8",
                                     edgecolor="#CFD8DC"))
        ax_stats.text(0.07, y - 0.01, title, transform=ax_stats.transAxes,
                      fontsize=11, weight="bold", va="center")
        ax_stats.text(0.48, y - 0.01, value, transform=ax_stats.transAxes,
                      fontsize=10.5, va="center")
        y -= 0.14

    fig.savefig(OUT / "type1_dmrs_resource_grid.png", dpi=190,
                facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    draw_frame_overview()
    draw_dmrs_detail()
    print(OUT / "type1_frame_structure.png")
    print(OUT / "type1_dmrs_resource_grid.png")
