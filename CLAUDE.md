# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Environment

This is a TensorFlow 1.15 / Python 3.7 codebase. The pinned scientific stack (numpy <1.17, pandas 0.25, scipy 1.3, h5py 2.10) is fragile, do not casually upgrade.

Steve uses `pixi` to manage the environment. `pixi.toml` pins the full upstream stack plus `bcftools` and `pyarrow` for VCF preprocessing. Run Python or CLI commands through pixi:

    pixi run tensorsignatures --help    # or: pixi run ts ...
    pixi run python -m pytest tests/
    pixi run python -m pytest tests/test_tensorsignatures.py::TestTensorsignatures::test_command_line_interface

`tensorsignatures` is installed editable via pixi pypi-dependencies, so source edits take effect without reinstall.

## Common commands

- `make lint` runs `flake8 tensorsignatures tests`
- `make test` runs unit tests (prefer `pixi run python -m pytest` directly)
- `make docs` regenerates Sphinx API docs under `docs/`

## CLI architecture

Entry point: `tensorsignatures.cli:main` (registered in `setup.py` as `tensorsignatures`). Subcommands in `tensorsignatures/cli.py`:

- `prep <in.h5> <ts.h5>`, adds trinucleotide normalization to the input HDF5.
- `train <ts.h5> <out.pkl> <rank> ...`, de novo decomposition (GPU recommended).
- `refit <ts.h5> <out.pkl>`, fits exposures of pre-defined PCAWG signatures (`data/pcawg.pkl`) to new data, fast, no GPU needed.
- `boot`, bootstrap CIs for inferred parameters.
- `write`, aggregates per-run pickles into a single HDF5 (multiprocessing).
- `data`, synthesizes simulated input data.

All CLI argument names live as string constants in `tensorsignatures/config.py` (e.g. `RANK`, `SEED`, `INIT`, `OBJECTIVE`); the CLI imports them with `from tensorsignatures.config import *`. When adding or renaming options, edit `config.py` as well.

## Module layout

- `tensorsignatures/tensorsignatures.py`, core TF1 model. `TensorSignature` is the de novo extractor, `TensorSignatureRefit` is the refit variant. Uses a custom `@define_scope` decorator (memoized properties wrapped in `tf.variable_scope`) so each property builds its part of the graph exactly once.
- `tensorsignatures/bootstrap.py`, `TensorSignatureBootstrap` for percentile-based confidence intervals.
- `tensorsignatures/data.py`, `TensorSignatureData` simulator/fixture builder, also wraps trained model HDF5s for downstream inspection.
- `tensorsignatures/util.py`, `Initialization`, `load_dump`, `prepare_data` (used by `prep`).
- `tensorsignatures/writer.py`, HDF5 aggregation of pickled run dumps.
- `tensorsignatures/plot.py`, matplotlib visualizations of signatures and exposures.
- `tensorsignatures/data/`, shipped reference data: `pcawg.pkl` (reference signatures for `refit`), `norm.h5` (trinucleotide counts), `sim_sig.txt`, `other.txt`.

## Input data shape

The model expects an HDF5 containing an SNV count tensor of shape `(3, 3, t1+1, ..., tl+1, p, n)`, where dims 0/1 are transcription/replication state, middle `t_i` dims are arbitrary genomic states, `p` is SNV channels, `n` is samples, plus an `other` matrix of shape `(q, n)` for non-SNV mutation types. Trinucleotide normalization (added by `prep`) lives in the same HDF5.

## VCF preprocessing

Producing the input HDF5 from VCFs is done by the separate `sagar87/tensorsignatures-data` docker image (R 3.4 + `VariantAnnotation` + `rhdf5`), not by this repo. The image's entrypoint runs `Rscript /usr/src/app/process.R`, which expects all positional args (VCF basenames + the output HDF5 name) to be relative to `/usr/src/app/mount`, so the bind mount and the output filename must both live in the same host dir.

**Input convention — purple-only.** Use only the `*.purple.somatic.vcf.gz` files from HMF. Those already contain SNVs, indels, and MNVs in valid VCF format. The companion `*.annotated.indel.vcf.gz` files are a custom annotated-TSV variant of the same indels and would double-count if combined.

Helper scripts under `scripts/`:

- `merge_breast50_vcfs.sh` — original sequential merger (kept for reproducibility of the 50-sample refit).
- `merge_one_vcf.sh` — per-sample purple-only PASS-filter + bgzip + tabix.
- `merge_vcfs_parallel.sh` — xargs `-P` wrapper around `merge_one_vcf.sh`; parameterised by `$SAMPLE_IDS`, `$OUT_DIR`, `$NPAR`.
- `processVcf_parallel.sh` — chunks the merged VCFs and runs N concurrent docker containers, each invoking `process.R` on ~100 samples; output chunk HDF5s land in `$OUT_DIR`.
- `merge_chunks.py` — concatenates per-chunk HDF5s (`SNVR`, `INDELS`, `MNV`) along the samples axis into one consolidated HDF5 ready for `tensorsignatures prep`.
- `sanity_check_refit.py` — loads a refit pickle and writes a stacked-bar exposure PNG.
- `submit_refit.sbatch`, `submit_train_array.sbatch` — DCC SLURM templates for CPU refit and GPU de novo training (rank × seed sweep).
- `aggregate_and_bic.py` — post-hoc rank selection via BIC plus cosine similarity of discovered SNV spectra to PCAWG TS01-TS20.
- `build_dcc_sif.sh` — builds an Apptainer SIF from the upstream docker image for DCC.

Run any of these inside the pixi env (e.g. `pixi run bash scripts/merge_vcfs_parallel.sh`).

## Conventions to preserve

- Keep TF 1.x APIs (`tf.variable_scope`, `tf.placeholder`, sessions). Do not migrate to TF 2.x style.
- Python 3.7 syntax only.
- Click 7.x (not 8.x) decorator style.

## Project status (2026-05-26)

End-to-end **refit** on 50 HMF breast samples is working (see
`~/MEGA/test_50_breast_ca_extended/vcf/breast50.refit.{pkl,exposures.png}`).
Dominant signatures TS12 (APOBEC), TS19 (HRD), TS04, TS15 (MMRD), as expected for BRCA.

**Discovery pipeline (Stage F → Stage G), in progress:**

- Cohort: all 4233 HMF samples from `~/MEGA/important_mut_sig_data/fmh-unfiltered_vcfs/` (sample-ID list at `~/MEGA/hmf_all/hmf_all_ids.txt`).
- VCF merge: done. 4233 purple-only PASS VCFs at `~/MEGA/hmf_all/vcf/`. Wall time ~17 min at NPAR=8.
- processVcf.R via Docker: **18/43 chunks done** (chunks 0-17), at `~/MEGA/hmf_all/chunks/chunk_NNN.h5`. Paused. Per-chunk wall time is highly variable (6 min to 7+ h depending on per-sample mutation count); RAM-bound (each container holds ~2 GB Constants.RData). Steve asked to drop to NPAR=1 because earlier NPAR=4 was straining memory.
- Resume path: `cd ~/github/tensorsignatures && VCF_DIR=$HOME/MEGA/hmf_all/vcf OUT_DIR=$HOME/MEGA/hmf_all/chunks CHUNK_SIZE=100 NPAR=1 bash scripts/processVcf_parallel.sh`. The script's skip-if-exists check picks up the 18 done; chunks 018-042 will then run sequentially.
- After all 43 chunks land: `pixi run python scripts/merge_chunks.py --chunks ~/MEGA/hmf_all/chunks --out ~/MEGA/hmf_all/hmf_all.h5`, then `pixi run tensorsignatures prep ~/MEGA/hmf_all/hmf_all.h5 ~/MEGA/hmf_all/hmf_all.tsdata.h5`.
- DCC discovery: SLURM template `scripts/submit_train_array.sbatch` (rank sweep 10/12/14/16/18/20/22/25 × 10 seeds = 80 GPU jobs on `gpu-common`). Aggregation + BIC + PCAWG-cosine in `scripts/aggregate_and_bic.py`. Both untested on DCC; GPU access confirmed but CUDA / TF-GPU 1.15 compatibility still needs verification on a real GPU node.

**Open issues / TODO:**

- TF-GPU 1.15 needs CUDA 10.0 + cuDNN 7.4; DCC's current drivers may not provide that. Fallback is an Apptainer SIF from `nvcr.io/nvidia/tensorflow:19.12-tf1-py3`.
- Cancer-type metadata (CPCT-ID → tissue) not yet available; discovery proceeds without it. Interpretation will be by spectra + cosine similarity to PCAWG only until metadata lands.
