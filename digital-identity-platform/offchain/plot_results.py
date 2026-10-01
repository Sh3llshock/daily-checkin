"""Draws the Step 5 scaling figure (report Figure 4) from the simulation CSVs.

Left: average gas per transaction for each operation as the number of users
grows. Right: one user's log growing, writing a new entry vs reading the whole
log. Standard library only; writes an SVG, and a PNG too if `rsvg-convert` is
installed (macOS: `brew install librsvg`).

    python offchain/plot_results.py            # after simulate.py

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import argparse
import csv
import shutil
import subprocess
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "offchain" / "results"
OUT = ROOT / "docs" / "diagrams" / "5-scaling"

# Validated categorical slots (fixed order), chart chrome and ink.
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7"]
SURFACE, INK, INK_2, MUTED, GRID, AXIS = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"
FONT = 'system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif'

OP_LABELS = {
    "registerUser": "registerUser",
    "setRequesterStatus": "setRequesterStatus",
    "setConsent": "setConsent",
    "requestAccess (granted)": "requestAccess, granted",
    "revokeConsent": "revokeConsent",
    "requestAccess (denied)": "requestAccess, denied",
}


def _text(x: float, y: float, s: str, size: int = 12, fill: str = INK, anchor: str = "start", weight: str = "400") -> str:
    return (
        f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" '
        f'font-weight="{weight}" font-family=\'{FONT}\'>{escape(s)}</text>'
    )


class Panel:
    def __init__(self, x: float, y: float, w: float, h: float, xs: list[float], y_max: float, y_step: float):
        self.x, self.y, self.w, self.h = x, y, w, h
        self.x_min, self.x_max = min(xs), max(xs)
        self.xs, self.y_max, self.y_step = xs, y_max, y_step

    def px(self, v: float) -> float:
        return self.x + (v - self.x_min) / (self.x_max - self.x_min) * self.w

    def py(self, v: float) -> float:
        return self.y + self.h - v / self.y_max * self.h

    def frame(self, title: str, x_title: str, y_title: str) -> list[str]:
        parts = [_text(self.x - 52, self.y - 34, title, 15, INK, weight="600")]
        tick = 0.0
        while tick <= self.y_max + 1e-9:
            yy = self.py(tick)
            colour = AXIS if tick == 0 else GRID
            parts.append(f'<line x1="{self.x:.1f}" y1="{yy:.1f}" x2="{self.x + self.w:.1f}" y2="{yy:.1f}" stroke="{colour}" stroke-width="1"/>')
            parts.append(_text(self.x - 8, yy + 4, f"{tick / 1000:.0f}k", 11, MUTED, "end"))
            tick += self.y_step
        for v in self.xs:
            parts.append(_text(self.px(v), self.y + self.h + 18, f"{v:g}", 11, MUTED, "middle"))
        parts.append(_text(self.x + self.w / 2, self.y + self.h + 38, x_title, 12, INK_2, "middle"))
        parts.append(_text(self.x - 52, self.y - 14, y_title, 12, INK_2))
        return parts

    def line(self, values: list[float], colour: str) -> list[str]:
        points = " ".join(f"{self.px(x):.1f},{self.py(v):.1f}" for x, v in zip(self.xs, values))
        parts = [f'<polyline points="{points}" fill="none" stroke="{colour}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>']
        for x, v in zip(self.xs, values):  # >= 8px markers with a surface ring
            parts.append(f'<circle cx="{self.px(x):.1f}" cy="{self.py(v):.1f}" r="4.5" fill="{colour}" stroke="{SURFACE}" stroke-width="2"/>')
        return parts


def _spread_labels(ys: list[float], min_gap: float) -> list[float]:
    """Nudge label baselines apart so direct labels never overlap."""
    order = sorted(range(len(ys)), key=lambda i: ys[i])
    placed = list(ys)
    for a, b in zip(order, order[1:]):
        if placed[b] - placed[a] < min_gap:
            placed[b] = placed[a] + min_gap
    return placed


def build_svg(per_op: list[dict], growth: list[dict]) -> str:
    width, height = 1160, 430
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        f'<rect width="{width}" height="{height}" fill="{SURFACE}"/>',
    ]

    # Left panel: gas per transaction vs N, one line per operation.
    ns = [int(k.removeprefix("avg_gas_N")) for k in per_op[0] if k.startswith("avg_gas_N")]
    left = Panel(80, 78, 300, 290, ns, 250_000, 50_000)
    parts += left.frame("Gas per transaction stays flat as users grow", "Number of users (N)", "Average gas per transaction")
    label_ys, labels = [], []
    for slot, row in enumerate(per_op):
        values = [float(row[f"avg_gas_N{n}"]) for n in ns]
        parts += left.line(values, SERIES[slot])
        label_ys.append(left.py(values[-1]) + 4)
        labels.append((slot, f"{OP_LABELS.get(row['op'], row['op'])}  {values[-1]:,.0f}"))
    for (slot, label), yy in zip(labels, _spread_labels(label_ys, 15)):
        parts.append(f'<circle cx="{left.x + left.w + 16:.1f}" cy="{yy - 4:.1f}" r="4" fill="{SERIES[slot]}"/>')
        parts.append(_text(left.x + left.w + 26, yy, label, 12))

    # Right panel: one user's log, write vs read.
    entries = [int(g["log_entries"]) for g in growth]
    right = Panel(720, 78, 220, 290, entries, 200_000, 50_000)
    parts += right.frame("One user's log: writing stays flat, reading grows", "Entries in the user's log", "Gas")
    series = [
        (SERIES[3], "requestAccess (writes 1 entry)", [float(g["requestAccess_gas_last_write"]) for g in growth]),
        (SERIES[6], "getLogs (reads the whole log)", [float(g["getLogs_gas_estimate"]) for g in growth]),
    ]
    end_ys = []
    for colour, _, values in series:
        parts += right.line(values, colour)
        end_ys.append(right.py(values[-1]) + 4)
    for (colour, label, values), yy in zip(series, _spread_labels(end_ys, 30)):
        parts.append(f'<circle cx="{right.x + right.w + 16:.1f}" cy="{yy - 4:.1f}" r="4" fill="{colour}"/>')
        parts.append(_text(right.x + right.w + 26, yy, label.split(" (")[0], 12))
        parts.append(_text(right.x + right.w + 26, yy + 15, f"({label.split(' (')[1]}  {values[-1]:,.0f}", 11, INK_2))

    parts.append(_text(80 - 52, height - 10, "Local Hardhat node, gasUsed of each transaction (getLogs: eth_estimateGas). Source: offchain/results/automine_*.csv", 10, MUTED))
    parts.append("</svg>")
    return "\n".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(description="Draw the scaling figure from simulate.py's CSVs.")
    parser.add_argument("--prefix", default="automine", help="results prefix, e.g. automine or blocktime12s")
    args = parser.parse_args()

    per_op = list(csv.DictReader((RESULTS / f"{args.prefix}_gas_per_op.csv").open()))
    growth = list(csv.DictReader((RESULTS / "automine_log_growth.csv").open()))
    svg_path = OUT.with_suffix(".svg")
    svg_path.write_text(build_svg(per_op, growth))
    print(f"wrote {svg_path}")
    if shutil.which("rsvg-convert"):
        png_path = OUT.with_suffix(".png")
        subprocess.run(["rsvg-convert", "-z", "3", "-o", str(png_path), str(svg_path)], check=True)
        print(f"wrote {png_path}")


if __name__ == "__main__":
    main()
