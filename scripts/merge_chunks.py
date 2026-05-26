#!/usr/bin/env python
"""Concatenate per-chunk HDF5s from processVcf_parallel.sh into a single
HMF-wide HDF5 with axis ordering matched to what `tensorsignatures prep`
expects.

Per-chunk schema (from processVcf.R):
    SNVR    (n_chunk, 192, 2, 4, 16, 3, 3)   int32  -- samples-first
    INDELS  (n_chunk, 62)                    int32
    MNV     (n_chunk, 91)                    int32

We concatenate along axis 0 (samples) for each dataset. Sample ordering
is the union of per-chunk_*.txt files in chunk order.

Run inside the pixi env:
    pixi run python scripts/merge_chunks.py \\
        --chunks ~/MEGA/hmf_all/chunks \\
        --out ~/MEGA/hmf_all/hmf_all.h5
"""
import argparse
import glob
import os
import sys

import h5py
import numpy as np


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chunks", required=True, help="dir containing chunk_NNN.h5")
    ap.add_argument("--out", required=True, help="consolidated HDF5 path")
    args = ap.parse_args()

    chunk_files = sorted(glob.glob(os.path.join(args.chunks, "chunk_*.h5")))
    if not chunk_files:
        sys.exit(f"no chunk_*.h5 found in {args.chunks}")
    print(f"merging {len(chunk_files)} chunks -> {args.out}")

    sample_lists = []
    for h5 in chunk_files:
        stem = os.path.splitext(os.path.basename(h5))[0]
        ids_file = os.path.join(args.chunks, f"{stem}.txt")
        with open(ids_file) as fh:
            sample_lists.append([line.strip().replace(".vcf.gz", "") for line in fh])

    snvr_parts, indels_parts, mnv_parts = [], [], []
    for h5 in chunk_files:
        with h5py.File(h5, "r") as fh:
            snvr_parts.append(fh["SNVR"][()])
            indels_parts.append(fh["INDELS"][()])
            mnv_parts.append(fh["MNV"][()])
        print(f"  loaded {os.path.basename(h5)}: SNVR shape {snvr_parts[-1].shape}")

    snvr = np.concatenate(snvr_parts, axis=0)
    indels = np.concatenate(indels_parts, axis=0)
    mnv = np.concatenate(mnv_parts, axis=0)
    all_samples = [s for sl in sample_lists for s in sl]

    print(f"\nfinal shapes: SNVR {snvr.shape}, INDELS {indels.shape}, MNV {mnv.shape}")
    print(f"n_samples: {len(all_samples)}")
    assert snvr.shape[0] == len(all_samples), "sample count mismatch"

    with h5py.File(args.out, "w") as fh:
        fh.create_dataset("SNVR", data=snvr, compression="gzip")
        fh.create_dataset("INDELS", data=indels, compression="gzip")
        fh.create_dataset("MNV", data=mnv, compression="gzip")
        fh.create_dataset(
            "SAMPLES",
            data=np.array(all_samples, dtype=h5py.string_dtype()),
        )
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
