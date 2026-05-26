#!/usr/bin/env python
"""Load a TensorSignatures refit pickle, print exposures, save a stacked-bar PNG.

Run inside the pixi env:
    pixi run python scripts/sanity_check_refit.py <refit.pkl> [sample_ids.txt]
"""
import sys
from pathlib import Path

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from tensorsignatures.util import load_dump

pkl_path = Path(sys.argv[1])
ids_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None

fit = load_dump(str(pkl_path))
E = np.squeeze(fit.E)  # (rank, n_samples)
print(f"E shape: {E.shape}")
print(f"rank: {fit.rank}, samples: {E.shape[1]}")
print(f"per-sample total exposure (first 5): {E.sum(axis=0)[:5]}")
print("mean exposure per signature (TS01..TSn):")
for i, m in enumerate(E.mean(axis=1)):
    print(f"  TS{i + 1:02d}: {m:.1f}")

sample_ids = (
    ids_path.read_text().split() if ids_path and ids_path.exists() else
    [f"S{i}" for i in range(E.shape[1])]
)

# Stacked bar: proportions per sample
prop = E / E.sum(axis=0, keepdims=True)
fig, ax = plt.subplots(figsize=(max(8, 0.25 * E.shape[1]), 6))
bottom = np.zeros(E.shape[1])
cmap = plt.get_cmap("tab20")
for i in range(E.shape[0]):
    ax.bar(
        range(E.shape[1]), prop[i], bottom=bottom,
        color=cmap(i % 20), label=f"TS{i + 1:02d}",
    )
    bottom += prop[i]
ax.set_xticks(range(E.shape[1]))
ax.set_xticklabels(sample_ids, rotation=90, fontsize=7)
ax.set_ylabel("Exposure proportion")
ax.set_title(f"TensorSignatures refit: {pkl_path.name}")
ax.legend(ncol=4, fontsize=7, loc="upper center", bbox_to_anchor=(0.5, -0.2))
fig.tight_layout()
out = pkl_path.with_suffix(".exposures.png")
fig.savefig(out, dpi=120, bbox_inches="tight")
print(f"\nwrote {out}")
