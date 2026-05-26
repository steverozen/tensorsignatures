#!/usr/bin/env python
"""Aggregate per-run pickles from a TensorSignatures rank x seed sweep,
compute BIC per rank, plot BIC vs rank, and (for the best-BIC rank)
compute cosine similarity of discovered SNV spectra to PCAWG TS01-TS20.

Run inside the pixi env:
    pixi run python scripts/aggregate_and_bic.py \\
        --runs /cwork/sr110/hmf_tensorsig_discovery/runs \\
        --out  /cwork/sr110/hmf_tensorsig_discovery/discovery_summary
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict

import h5py
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from tensorsignatures.util import load_dump
from tensorsignatures.config import PCAWG


RANK_SEED_RX = re.compile(r"rank(\d+)_seed(\d+)\.pkl$")


def collect_runs(runs_dir):
    fits = defaultdict(list)
    for pkl in sorted(glob.glob(os.path.join(runs_dir, "rank*_seed*.pkl"))):
        m = RANK_SEED_RX.search(pkl)
        if not m:
            continue
        rank, seed = int(m.group(1)), int(m.group(2))
        fit = load_dump(pkl)
        # final log-likelihood from training: store best (least negative) of log_L
        loglik = float(np.asarray(fit.log_L).flatten()[-1])
        # n_observations from input: snv + other cell count
        # tensor_obs is determined when fit is built. Fall back to fit.observations if set.
        n_obs = int(getattr(fit, "observations", 0) or 0)
        # k = total free parameters at this rank. Approximation: rank x (96+234)
        # + rank x n_samples for exposures + small scaffolding. Refine later.
        n_samples = fit.E.shape[1] if hasattr(fit, "E") and fit.E is not None else 0
        k = rank * (96 + 234 + n_samples)
        fits[rank].append({
            "seed": seed,
            "loglik": loglik,
            "n_obs": n_obs,
            "n_samples": n_samples,
            "k": k,
            "pkl": pkl,
        })
        print(f"  rank={rank} seed={seed} loglik={loglik:.1f} k={k}")
    return fits


def bic_per_rank(fits):
    rows = []
    for rank, runs in sorted(fits.items()):
        best = max(runs, key=lambda r: r["loglik"])
        n = best["n_obs"] or 1
        bic = np.log(n) * best["k"] - 2 * best["loglik"]
        rows.append({
            "rank": rank,
            "best_loglik": best["loglik"],
            "k": best["k"],
            "n_obs": n,
            "bic": bic,
            "best_seed": best["seed"],
            "best_pkl": best["pkl"],
            "n_runs": len(runs),
        })
    return rows


def cosine_similarity_matrix(A, B):
    """rows of A, B are vectors. Returns A.shape[0] x B.shape[0] matrix."""
    An = A / (np.linalg.norm(A, axis=1, keepdims=True) + 1e-12)
    Bn = B / (np.linalg.norm(B, axis=1, keepdims=True) + 1e-12)
    return An @ Bn.T


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    print(f"scanning {args.runs}/")
    fits = collect_runs(args.runs)
    if not fits:
        sys.exit("no runs found")

    rows = bic_per_rank(fits)
    with open(os.path.join(args.out, "bic.json"), "w") as fh:
        json.dump(rows, fh, indent=2)

    ranks = [r["rank"] for r in rows]
    bics = [r["bic"] for r in rows]
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.plot(ranks, bics, "o-")
    ax.set_xlabel("rank")
    ax.set_ylabel("BIC")
    ax.set_title("Rank selection (lower BIC is better)")
    fig.tight_layout()
    fig.savefig(os.path.join(args.out, "bic_vs_rank.png"), dpi=120)
    print(f"wrote bic_vs_rank.png; best rank by BIC: {min(rows, key=lambda r: r['bic'])['rank']}")

    # Cosine similarity to PCAWG TS01-TS20 for the best-BIC rank.
    best = min(rows, key=lambda r: r["bic"])
    fit = load_dump(best["best_pkl"])
    pcawg = load_dump(PCAWG)
    # Collapse genomic-state axes by averaging to get 96-dim spectra.
    # S shape: (3,3,16,4,2,96,rank,1)
    S_disc = np.squeeze(fit.S).mean(axis=(0, 1, 2, 3, 4))  # (96, rank)
    S_pcawg = np.squeeze(pcawg.S).mean(axis=(0, 1, 2, 3, 4))  # (96, 20)
    sim = cosine_similarity_matrix(S_disc.T, S_pcawg.T)  # (rank, 20)

    fig, ax = plt.subplots(figsize=(8, 0.4 * sim.shape[0] + 1))
    im = ax.imshow(sim, vmin=0, vmax=1, cmap="viridis", aspect="auto")
    ax.set_xticks(range(20))
    ax.set_xticklabels([f"TS{i+1:02d}" for i in range(20)], rotation=90, fontsize=8)
    ax.set_yticks(range(sim.shape[0]))
    ax.set_yticklabels([f"discovered_{i+1:02d}" for i in range(sim.shape[0])], fontsize=8)
    fig.colorbar(im, ax=ax, label="cosine sim")
    ax.set_title(f"Discovered (rank {best['rank']}) vs PCAWG SNV spectra")
    fig.tight_layout()
    fig.savefig(os.path.join(args.out, "cosine_vs_pcawg.png"), dpi=120)
    print("wrote cosine_vs_pcawg.png")

    # Flag novel signatures (max cosine < 0.85 to any PCAWG)
    max_sim = sim.max(axis=1)
    best_match = sim.argmax(axis=1)
    with open(os.path.join(args.out, "novel_flags.tsv"), "w") as fh:
        fh.write("discovered_idx\tbest_pcawg_match\tcosine\tnovel\n")
        for i in range(sim.shape[0]):
            tag = "yes" if max_sim[i] < 0.85 else "no"
            fh.write(f"{i+1}\tTS{best_match[i]+1:02d}\t{max_sim[i]:.3f}\t{tag}\n")
    n_novel = int((max_sim < 0.85).sum())
    print(f"novel signatures (cosine < 0.85): {n_novel}/{sim.shape[0]}")


if __name__ == "__main__":
    main()
