"""
Plots the simulation results (results/simulation-*.json) for the report.
  python scripts/plot_results.py
"""

import json
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

local = json.load(open("results/simulation-localhost.json"))
inproc = json.load(open("results/simulation-default.json"))
n = [r["patients"] for r in local]

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9, 3.3))

ax1.plot(n, [r["totalSeconds"] for r in local], "o-", label="local node (HTTP)")
ax1.plot(n, [r["totalSeconds"] for r in inproc], "s-", label="in-process")
ax1.set_xlabel("number of patients")
ax1.set_ylabel("total time (s)")
ax1.set_title("Total simulation time")
ax1.grid(alpha=0.3)
ax1.legend()

ax2.plot(n, [r["totalGas"] / 1e6 for r in local], "o-", color="tab:green")
ax2.set_xlabel("number of patients")
ax2.set_ylabel("total gas (million)")
ax2.set_title("Total gas used")
ax2.grid(alpha=0.3)

plt.tight_layout()
plt.savefig("results/scaling.png", dpi=150)
print("saved results/scaling.png")
